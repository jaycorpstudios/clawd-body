import AppKit
import Foundation
import HiloContract
import HiloRuntime
import HiloStore
import Observation

enum AppSection: String, CaseIterable, Identifiable {
    case today = "Today", sessions = "Sessions", week = "Week", agreements = "Agreements", resume = "Resume context", setup = "Setup"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .today: "calendar"
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
    var weekCommits: [CommitRecord] = []
    var projects: [Project] = []
    var daemonRunning = false
    var buddyConnected = false
    var daemonStatus: DaemonStatus?
    var daemonError: String?
    var config = HiloConfig.load()
    var selectedTask: Int?
    var selectedSession: String?
    var errorMessage: String?

    private let store: HiloStore?
    private var timer: Timer?

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
    nonisolated static var startOfWeek: Int {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return Int(start.timeIntervalSince1970)
    }

    func refresh() {
        guard let store else { return }
        attempt {
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
            let state = try store.daemonState()
            let reply = LocalSocket.request(path: LocalSocket.defaultPath, op: "status", body: Data(), timeoutSeconds: 1)
            let running = reply != nil
            if running != daemonRunning { daemonRunning = running }
            let status = reply.flatMap { try? JSONDecoder().decode(DaemonStatus.self, from: $0) }
            if status != daemonStatus { daemonStatus = status }
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
        attempt { try store?.deleteTask(id) }
        changed()
    }

    func link(session: String, task: Int?) {
        attempt { try store?.link(session: session, task: task) }
        refresh()
    }

    func addAgreement(_ text: String, project: String?, task: Int?) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        attempt { try store?.addAgreement(text, project: project, task: task, now: Self.now) }
        changed()
    }

    func confirm(_ agreement: Agreement) {
        attempt { try store?.confirmAgreement(agreement.id) }
        changed()
    }

    func discard(_ agreement: Agreement) {
        attempt { try store?.deleteAgreement(agreement.id) }
        changed()
    }

    static let statusLineCommand = "hilo statusline -- <your status line command>"

    /// `HILO_HILOD` overrides it; otherwise the copy bundled next to the app's executable.
    var hilodPath: String? {
        if let path = ProcessInfo.processInfo.environment["HILO_HILOD"] { return path }
        let bundled = Bundle.main.bundleURL.appending(path: "Contents/MacOS/hilod").path(percentEncoded: false)
        return FileManager.default.isExecutableFile(atPath: bundled) ? bundled : nil
    }

    func saveHost(_ display: String) {
        guard let host = HiloConfig.hostName(from: display) else { return }
        if daemonRunning, let reply = LocalSocket.request(path: LocalSocket.defaultPath, op: "host", body: Data(display.utf8), timeoutSeconds: 2),
           (try? JSONDecoder().decode(DaemonStatus.self, from: reply)) != nil {
            daemonError = nil
        } else {
            var updated = HiloConfig.load()
            updated.host = host
            do { try updated.save() } catch { daemonError = "Cannot save the name: \(error)" }
        }
        config = HiloConfig.load()
        refresh()
    }

    func setTokensFromTranscripts(_ on: Bool) {
        var updated = HiloConfig.load()
        updated.tokensFromTranscripts = on
        do { try updated.save() } catch { daemonError = "Cannot save the setting: \(error)" }
        config = HiloConfig.load()
    }

    /// Installs the LaunchAgent, so hilod also starts at every login; replaces a job started with `launchctl submit`.
    func startDaemon() {
        guard let hilodPath else { return }
        launchAgent { try $0.install(hilod: hilodPath) }
    }

    func stopDaemon() {
        launchAgent { try $0.uninstall() }
    }

    func restartDaemon() { startDaemon() }

    func startPairing() { control("pair") }
    func cancelPairing() { control("pair-cancel") }

    private func control(_ op: String) {
        let reply = LocalSocket.request(path: LocalSocket.defaultPath, op: op, body: Data(), timeoutSeconds: 2)
        if let status = reply.flatMap({ try? JSONDecoder().decode(DaemonStatus.self, from: $0) }) { daemonStatus = status }
    }

    private func launchAgent(_ action: (LaunchAgent) throws -> Void) {
        do {
            try action(LaunchAgent())
            daemonError = nil
        } catch {
            daemonError = "\(error)"
        }
        refreshSoon()
    }

    private func refreshSoon() {
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            refresh()
        }
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Refreshes the window and lets `hilod` push the new Hilo state to the buddy.
    private func changed() {
        refresh()
        Task.detached {
            _ = LocalSocket.request(path: LocalSocket.defaultPath, op: "hilo", body: Data(), timeoutSeconds: 2)
        }
    }

    private func attempt(_ body: () throws -> Void) {
        do {
            try body()
            if errorMessage != nil, store != nil { errorMessage = nil }
        } catch {
            errorMessage = "\(error)"
        }
    }
}

enum Format {
    static func duration(_ seconds: Int) -> String {
        let m = max(0, seconds) / 60
        return m < 60 ? "\(m) min" : String(format: "%d h %02d min", m / 60, m % 60)
    }

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

    static func sessionTime(_ s: SessionRecord) -> Int {
        (s.endedAt ?? (s.status == .working || s.status == .waiting ? AppModel.now : s.updatedAt)) - s.startedAt
    }
}
