import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import HiloContract
import HiloCore
import HiloRuntime
import HiloStore
import Observation
import UserNotifications

enum AppSection: String, CaseIterable, Identifiable {
    case today = "Today", focus = "Focus", sessions = "Sessions", week = "Week", agreements = "Agreements", resume = "Resume context", setup = "Setup"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .today: "calendar"
        case .focus: "timer"
        case .sessions: "terminal"
        case .week: "chart.bar"
        case .agreements: "checklist"
        case .resume: "arrow.counterclockwise"
        case .setup: "gearshape"
        }
    }
}

/// Reads the store every couple of seconds: `hilod` and the CLI write to it from other processes.
@MainActor @Observable
final class AppModel {
    var section: AppSection = .today
    var tasks: [HiloTaskRecord] = []
    var sessions: [SessionRecord] = []
    var weekSessions: [SessionRecord] = []
    var weekTasks: [HiloTaskRecord] = []
    var agreements: [Agreement] = []
    var activeToday: [String: Int] = [:]
    var activeWeek: [String: Int] = [:]
    var activePerDay: [Int: Int] = [:]
    var focusToday: (count: Int, minutes: Int) = (0, 0)
    var weekCommits: [CommitRecord] = []
    var weekSummaries: [String: WeekSummary] = [:]
    var projects: [Project] = []
    var daemonRunning = false
    var buddyConnected = false
    var daemonStatus: DaemonStatus?
    /// hilod's view, from the `music` op; `musicHere` is this app's own Automation consent.
    var musicStatus: MusicStatus?
    var musicHere: [String: AutomationAccess] = [:]
    var statusLine = StatusLineSetup.State.noStatusLine
    var hooks = HooksSetup.State.installed
    var daemonError: String?
    /// "Starting…" while a start, restart or stop waits for hilod to answer; the buttons are disabled meanwhile.
    var daemonBusy: String?
    var toast: Toast?
    var config = HiloConfig.load()
    var selectedTask: Int?
    var selectedSession: String?
    var errorMessage: String?

    private let store: HiloStore?
    private var timer: Timer?
    private var phaseAlarm = PhaseAlarm()

    init() {
        do { store = try HiloStore() } catch {
            store = nil
            errorMessage = "Cannot open the Hilo store: \(error)"
        }
        if !FileManager.default.fileExists(atPath: HiloConfig.defaultPath) { section = .setup }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    nonisolated static var now: Int { Int(Date().timeIntervalSince1970) }
    nonisolated static var startOfToday: Int { Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970) }
    nonisolated static var startOfWeek: Int { HiloStore.startOfWeek() }

    func refresh() {
        guard let store else { return }
        reading {
            let fresh = (try store.tasks(doneSince: Self.startOfToday), try store.sessions(since: Self.startOfToday),
                         try store.agreements(), try store.projects())
            if fresh.0 != tasks { tasks = fresh.0 }
            if fresh.1 != sessions { sessions = fresh.1 }
            if fresh.2 != agreements { agreements = fresh.2 }
            if fresh.3 != projects { projects = fresh.3 }
            let week = (try store.tasks(doneSince: Self.startOfWeek), try store.sessions(since: Self.startOfWeek))
            if week.0 != weekTasks { weekTasks = week.0 }
            if week.1 != weekSessions { weekSessions = week.1 }
            let capture = (try store.activeSeconds(since: Self.startOfToday), try store.activeSeconds(since: Self.startOfWeek),
                           try store.commits(since: Self.startOfWeek))
            if capture.0 != activeToday { activeToday = capture.0 }
            if capture.1 != activeWeek { activeWeek = capture.1 }
            if capture.2 != weekCommits { weekCommits = capture.2 }
            let perDay = try store.activeSecondsPerDay(since: Self.startOfWeek)
            if perDay != activePerDay { activePerDay = perDay }
            let summaries = try store.summaries(week: HiloStore.weekKey(Self.startOfWeek))
            if summaries != weekSummaries { weekSummaries = summaries }
            let focus = try store.focusCycles(since: Self.startOfToday)
            if focus != focusToday { focusToday = focus }
            let state = try store.daemonState()
            let reply = LocalSocket.request(path: LocalSocket.defaultPath, op: "status", body: Data(), timeoutSeconds: 1)
            let running = reply != nil
            if running != daemonRunning { daemonRunning = running }
            let status = reply.flatMap { try? JSONDecoder().decode(DaemonStatus.self, from: $0) }
            if status != daemonStatus { daemonStatus = status }
            let line = StatusLineSetup.detect()
            if line != statusLine { statusLine = line }
            let hooksNow = HooksSetup.detect()
            if hooksNow != hooks { hooks = hooksNow }
            if let begun = phaseAlarm.check(status?.pomodoro, now: Self.now) { PhaseNotifier.announce(begun) }
            let connected = running && (status.map { $0.buddy.link == .connected } ?? (state?.buddyConnected == true))
            if connected != buddyConnected { buddyConnected = connected }
        }
        if selectedTask == nil || !tasks.contains(where: { $0.id == selectedTask }) {
            selectedTask = tasks.first(where: { $0.status == .doing })?.id ?? tasks.first?.id
        }
    }

    var needsYou: [SessionRecord] { sessions.filter { $0.status == .waiting } }
    var working: [SessionRecord] { sessions.filter { $0.status == .working } }
    var pendingAgreements: [Agreement] { agreements.filter { $0.status == .pending } }

    func tasks(_ status: TaskStatus) -> [HiloTaskRecord] {
        tasks.filter { $0.status == status }.sorted {
            status == .done ? ($0.doneAt ?? 0) > ($1.doneAt ?? 0) : $0.createdAt < $1.createdAt
        }
    }

    func task(_ id: Int?) -> HiloTaskRecord? { tasks.first { $0.id == id } }

    func steps(_ session: String) -> [StepRecord] {
        (try? store?.steps(session: session)) ?? []
    }

    func commits(forTask id: Int) -> [CommitRecord] {
        (try? store?.commits(task: id)) ?? []
    }

    func commits(project name: String) -> [CommitRecord] {
        (try? store?.commits(project: name, limit: 6)) ?? []
    }

    func sessions(forTask id: Int) -> [SessionRecord] {
        (try? store?.sessions(task: id)) ?? []
    }

    func addTask(_ title: String, project: String?, start: Bool) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let store else { return }
        attempt {
            let t = try store.addTask(title, project: project, status: start ? .doing : .todo, now: Self.now)
            selectedTask = t.id
        }
        changed()
    }

    func editSummary(weekStart: Int, project: Int, text: String) {
        attempt(done: "Summary saved") { try store?.editSummary(week: HiloStore.weekKey(weekStart), projectId: project, text: text, now: Self.now) }
        changed()
    }

    func setStatus(_ id: Int, _ status: TaskStatus) {
        attempt { try store?.setStatus(task: id, status, now: Self.now) }
        changed()
    }

    func toggleDone(_ t: HiloTaskRecord) {
        setStatus(t.id, t.status == .done ? .todo : .done)
    }

    func save(_ id: Int, title: String, notes: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        attempt { try store?.update(task: id, title: title, notes: notes) }
        changed()
    }

    func delete(_ id: Int) {
        attempt(done: "Task deleted") { try store?.deleteTask(id) }
        changed()
    }

    func link(session: String, task: Int?) {
        attempt { try store?.link(session: session, task: task) }
        refresh()
    }

    /// Through `hilod`, so the buddy follows; straight into the store when `hilod` is off or no longer holds the session.
    func setLook(_ session: SessionRecord, acc: Accessory) {
        let reply = (try? JSONEncoder().encode(SessionLookChange(session: session.id, acc: acc))).flatMap {
            LocalSocket.request(path: LocalSocket.defaultPath, op: "session-look", body: $0, timeoutSeconds: 2)
        }
        if reply.flatMap({ try? JSONDecoder().decode(DaemonStatus.self, from: $0) }) == nil {
            let hue = session.look?.hue ?? PetView.look(of: session.project).hue
            attempt { try store?.setLook(session: session.id, look: SessionLook(hue: hue, acc: acc)) }
        }
        refresh()
    }

    func addAgreement(_ text: String, project: String?, task: Int?) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        attempt { try store?.addAgreement(text, project: project, task: task, now: Self.now) }
        changed()
    }

    func confirm(_ agreement: Agreement) {
        attempt(done: "Agreement confirmed") { try store?.confirmAgreement(agreement.id) }
        changed()
    }

    func discard(_ agreement: Agreement) {
        attempt(done: "Agreement discarded") { try store?.deleteAgreement(agreement.id) }
        changed()
    }

    static let statusLineCommand = "hilo statusline -- <your status line command>"

    /// `HILO_HILOD` overrides it; otherwise the copy in the app's `Contents/Helpers`.
    var hilodPath: String? {
        if let path = ProcessInfo.processInfo.environment["HILO_HILOD"] { return path }
        let bundled = Bundle.main.bundleURL.appending(path: "Contents/Helpers/hilod").path(percentEncoded: false)
        return FileManager.default.isExecutableFile(atPath: bundled) ? bundled : nil
    }

    /// The `hilo` CLI next to the app's executable, or next to the build `HILO_HILOD` points at.
    var hiloPath: String? {
        let env = ProcessInfo.processInfo.environment["HILO_HILOD"].map { URL(filePath: $0).deletingLastPathComponent() }
        let path = (env ?? Bundle.main.bundleURL.appending(path: "Contents/MacOS")).appending(path: "hilo").path(percentEncoded: false)
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    func saveHost(_ display: String) {
        guard let host = HiloConfig.hostName(from: display) else { return }
        if daemonRunning, let reply = LocalSocket.request(path: LocalSocket.defaultPath, op: "host", body: Data(display.utf8), timeoutSeconds: 2),
           (try? JSONDecoder().decode(DaemonStatus.self, from: reply)) != nil {
            daemonError = nil
            notify("Saved: the buddy now shows \(host)")
        } else {
            var updated = HiloConfig.load()
            updated.host = host
            do {
                try updated.save()
                notify(daemonRunning ? "Saved; hilod did not answer, it applies on its next start" : "Saved; it applies when hilod starts")
            } catch {
                fail("Cannot save the name: \(error)")
            }
        }
        config = HiloConfig.load()
        refresh()
    }

    func setTokensFromTranscripts(_ on: Bool) {
        var updated = HiloConfig.load()
        updated.tokensFromTranscripts = on
        do { try updated.save() } catch { fail("Cannot save the setting: \(error)") }
        config = HiloConfig.load()
    }

    /// Installs the LaunchAgent, so hilod also starts at every login; replaces a job started with `launchctl submit`.
    func startDaemon() { launchDaemon(busy: "Starting…", done: "hilod is running") }

    func restartDaemon() { launchDaemon(busy: "Restarting…", done: "hilod restarted") }

    func stopDaemon() {
        guard daemonBusy == nil else { return }
        daemonBusy = "Stopping…"
        Task {
            let failure = await Task.detached { () -> String? in
                do { try LaunchAgent().uninstall() } catch { return "\(error)" }
                return nil
            }.value
            daemonBusy = nil
            if let failure { fail(failure) } else { daemonError = nil; notify("hilod stopped") }
            refresh()
        }
    }

    /// A bootstrap that works says nothing about hilod itself (macOS may kill it at once), so it waits for the socket to answer twice.
    private func launchDaemon(busy: String, done: String) {
        guard daemonBusy == nil else { return }
        guard let hilodPath else {
            fail("hilod was not found next to Hilo. Build it with scripts/build-hilod.sh, then rebuild the app.")
            return
        }
        daemonBusy = busy
        Task {
            let failure = await Task.detached { () -> String? in
                let agent = LaunchAgent()
                do { try agent.install(hilod: hilodPath) } catch { return "\(error)" }
                var answers = 0
                for _ in 0..<20 {
                    usleep(500_000)
                    let up = LocalSocket.request(path: LocalSocket.defaultPath, op: "status", body: Data(), timeoutSeconds: 1) != nil
                    answers = up ? answers + 1 : 0
                    if answers == 3 { return nil }
                }
                return agent.whyNotRunning(print: agent.printed())
                    ?? "hilod did not answer within 10 s. Log in ~/Library/Logs/Hilo."
            }.value
            daemonBusy = nil
            if let failure { fail(failure) } else { daemonError = nil; notify(done) }
            refresh()
        }
    }

    func startPairing() { control("pair", done: "Pairing started") }
    func cancelPairing() { control("pair-cancel", done: "Pairing cancelled") }

    var facePath: String { HiloConfig.facePath() }

    /// Writes the cropped square (at most 480 px) next to `config.json`, or deletes it, and lets `hilod` pick it up.
    func saveFace(_ square: CGImage?) {
        let url = URL(filePath: facePath)
        do {
            if let square {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let side = min(square.width, 480)
                guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fail("Cannot save the picture"); return }
                ctx.interpolationQuality = .high
                ctx.draw(square, in: CGRect(x: 0, y: 0, width: side, height: side))
                guard let scaled = ctx.makeImage(),
                      let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { fail("Cannot save the picture"); return }
                CGImageDestinationAddImage(dest, scaled, nil)
                guard CGImageDestinationFinalize(dest) else { fail("Cannot save the picture"); return }
            } else if FileManager.default.fileExists(atPath: facePath) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            fail("Cannot save the picture: \(error)")
            return
        }
        control("face", done: square == nil ? "Picture removed" : "Picture saved; the buddy picks it up next time it asks")
        refreshSoon()
    }

    /// The buddy applies it and reports back; the controls follow `daemonStatus.settings`, never this request.
    func changeSettings(_ change: SettingsChange) {
        guard let body = try? JSONEncoder().encode(change) else { return }
        control("settings", body: body)
        refreshSoon()
    }

    func pomodoro(_ command: [String: Any]) {
        guard let body = try? JSONSerialization.data(withJSONObject: command) else { return }
        control("pomodoro", body: body)
    }

    private func control(_ op: String, body: Data = Data(), done: String? = nil) {
        let reply = LocalSocket.request(path: LocalSocket.defaultPath, op: op, body: body, timeoutSeconds: 2)
        guard let status = reply.flatMap({ try? JSONDecoder().decode(DaemonStatus.self, from: $0) }) else {
            notify(reply == nil ? "hilod did not answer. Start it in Setup." : "hilod could not do that; its log is in ~/Library/Logs/Hilo.", .error)
            return
        }
        daemonStatus = status
        if let done { notify(done) }
    }

    /// Daemon errors also stay in the Setup card, where the fix usually is.
    private func fail(_ message: String) {
        daemonError = message
        notify(message, .error)
    }

    private func refreshSoon() {
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            refresh()
        }
    }

    /// A finished week read straight from the store; the current week comes from the refreshed fields instead.
    func week(start: Int, end: Int) -> (report: WeekReport, perDay: [Int: Int])? {
        guard let store else { return nil }
        do {
            return (try store.weekReport(start: start, end: end, now: Self.now), try store.activeSecondsPerDay(since: start, until: end))
        } catch {
            errorMessage = "\(error)"
            return nil
        }
    }

    func export(_ markdown: String, name: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = name
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(markdown.utf8).write(to: url, options: .atomic)
            notify("Saved \(url.lastPathComponent)")
        } catch {
            notify("Cannot save \(url.lastPathComponent): \(error)", .error)
        }
    }

    /// Refreshes the window and lets `hilod` push the new Hilo state to the buddy.
    private func changed() {
        refresh()
        Task.detached {
            _ = LocalSocket.request(path: LocalSocket.defaultPath, op: "hilo", body: Data(), timeoutSeconds: 2)
        }
    }

    /// A background read: its error stays on the page until a later read works, instead of a toast every 2 s.
    private func reading(_ body: () throws -> Void) {
        do {
            try body()
            if errorMessage != nil, store != nil { errorMessage = nil }
        } catch {
            errorMessage = "\(error)"
        }
    }

    private func attempt(done: String? = nil, _ body: () throws -> Void) {
        do {
            try body()
            if let done { notify(done) }
        } catch {
            notify("\(error)", .error)
        }
    }

    func notify(_ text: String, _ kind: Toast.Kind = .done) {
        toast = Toast(kind: kind, text: text)
    }
}

enum Format {
    static func duration(_ seconds: Int) -> String { WeekReport.duration(seconds) }

    /// As the prototype writes them: "41 k", "1.2 M".
    static func tokens(_ n: Int) -> String {
        n < 1_000 ? "\(n)" : n < 1_000_000 ? "\(n / 1_000) k" : String(format: "%.1f M", Double(n) / 1_000_000)
    }

    static func clock(_ ts: Int) -> String {
        Date(timeIntervalSince1970: TimeInterval(ts)).formatted(date: .omitted, time: .shortened)
    }

    static func day(_ ts: Int) -> String {
        Date(timeIntervalSince1970: TimeInterval(ts)).formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    static func sessionTime(_ s: SessionRecord) -> Int { WeekReport.sessionSeconds(s, now: AppModel.now) }
}
