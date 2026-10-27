import Foundation
import HiloContract
import HiloCore

public protocol BuddyLink: Sendable {
    func send(_ data: Data) async
}

public protocol PresenceProbe: Sendable {
    func userIsPresent() -> Bool
    /// No input for `seconds`, or the screen is locked.
    func quiet(for seconds: Double) -> Bool
}

extension PresenceProbe {
    public func quiet(for seconds: Double) -> Bool { !userIsPresent() }
}

public protocol Clock: Sendable {
    func now() -> Int
    func sleep(seconds: Double) async
}

public struct SystemClock: Clock {
    public init() {}
    public func now() -> Int { Int(Date().timeIntervalSince1970) }
    public func sleep(seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }
}

public actor Coordinator {
    private var host: String
    private let mapper: HookMapper
    private let link: BuddyLink
    private let presence: PresenceProbe
    private let clock: Clock
    private let pollSeconds: Double
    private let presenceGrace: Int
    private let log: @Sendable (String) -> Void
    private let recorder: StoreRecorder?
    private var registry = RequestRegistry()
    private var store = SessionStore()
    private var usage = UsageTracker()
    private var waiting: [String: CheckedContinuation<Resolution?, Never>] = [:]
    /// When the buddy last acked each held request, i.e. showed it on screen.
    private var shownOnBuddy: [String: Int] = [:]
    static let shownWithin = 30, handBackAfter = 10
    static let activeWithin: Double = 3
    /// Buddy messages more than this far from the Mac clock are dropped; ids outlive the ±window, so a replay inside it is caught.
    static let replayWindow = 120, seenFor = 600
    private var seenIds: [String: Int] = [:]
    private var buddySettings: DeviceSettings?
    private var face: RGB565Image?
    private var pomodoro: PomodoroState?
    private var media: (value: Media, at: Int)?
    private var player: MediaPlayer?
    private let mediaCommands = DispatchQueue(label: "hilod.media")
    private var cover: (track: String, image: RGB565Image?)?
    private let coverFetches = DispatchQueue(label: "hilod.cover")

    public init(host: String, mapper: HookMapper, link: BuddyLink, presence: PresenceProbe,
                clock: Clock = SystemClock(), pollSeconds: Double = 2, presenceGrace: Int = 10, recorder: StoreRecorder? = nil,
                log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.host = host; self.mapper = mapper; self.link = link
        self.presence = presence; self.clock = clock; self.pollSeconds = pollSeconds; self.presenceGrace = presenceGrace
        self.recorder = recorder; self.log = log
        pomodoro = recorder?.savedFocus()
        store.setPomodoro(pomodoro)
    }

    /// Returns what the hook command must print to stdout.
    public func handleHook(_ input: HookInput) async -> Data {
        switch mapper.map(input, now: clock.now()) {
        case .emit(let messages):
            for m in messages { await send(m) }
            recorder?.attach(session: Text.clip(input.sessionId, 64), project: mapper.project(of: input),
                            repo: mapper.repoRoot(input.cwd))
            return HookResponse.passThrough
        case .awaitPermission(let request):
            guard let resolution = await hold(id: request.requestId, session: request.session, expiresAt: request.expiresAt,
                                              body: .permission(risk: request.risk, remoteAllowed: request.remoteAllowed),
                                              message: .needsPermission(request), onMac: "Waiting on the Mac: \(request.tool)")
            else { return HookResponse.passThrough }
            return HookResponse.permission(resolution)
        case .awaitQuestion(let request, let toolInput):
            guard let resolution = await hold(id: request.requestId, session: request.session, expiresAt: request.expiresAt,
                                              body: .question(options: request.options),
                                              message: .question(request), onMac: "Asked a question on the Mac")
            else { return HookResponse.passThrough }
            return HookResponse.question(resolution, toolInput: toolInput)
        }
    }

    public func handleBuddy(_ bytes: Data) async throws(ContractError) {
        let envelope = try Wire.decodeInbound(bytes)
        let now = clock.now()
        guard abs(envelope.ts - now) <= Self.replayWindow else {
            throw .replayed("ts \(envelope.ts) is \(envelope.ts - now) s from the Mac clock")
        }
        seenIds = seenIds.filter { now - $0.value < Self.seenFor }
        guard seenIds.updateValue(now, forKey: envelope.id) == nil else { throw .replayed("id \(envelope.id) already seen") }
        let result: DecisionResult
        switch envelope.body {
        case .permissionDecision(let d): result = registry.decide(d, now: clock.now())
        case .questionAnswer(let a): result = registry.answer(a, now: clock.now())
        case .settings(let s):
            buddySettings = s
            log("buddy settings: sound \(s.sound ? "on" : "off"), volume \(s.volume), brightness \(s.brightness)%\(s.tzOffsetMin.map { ", UTC offset \($0) min" } ?? "")")
            return
        case .pomodoro(let p):
            if let mine = pomodoro, p.updatedAt < mine.updatedAt { return await send(.pomodoro(mine)) }
            log("buddy pomodoro: \(p.state.rawValue) \(p.phase.rawValue), cycle \(p.cycle)")
            adopt(p)
            return
        case .mediaControl(let c):
            guard let player else { return log("buddy media control ignored: no player") }
            log("buddy media control: \(c.action.rawValue)")
            mediaCommands.async { [self] in
                player.control(c.action)
                let now = player.current()
                Task { await updateMedia(now) }
            }
            return
        case .faceRequest(let ref):
            guard let face, face.hash == ref.hash else { return log("buddy asked for face \(ref.hash), which this Mac no longer has") }
            log("buddy asked for this Mac's face")
            for chunk in face.chunks { await send(.face(chunk)) }
            return
        case .coverRequest(let ref):
            guard let image = cover?.image, image.hash == ref.hash else { return log("buddy asked for cover \(ref.hash), which is not playing") }
            for chunk in image.chunks { await send(.cover(chunk)) }
            return
        case .sessionLook(let change):
            if await changeLook(change) == nil { log("buddy picked a look for unknown session \(change.session)") }
            return
        case .ack(let ack):
            if registry.pendingRequests.contains(where: { $0.id == ack.requestId }) { shownOnBuddy[ack.requestId] = clock.now() }
            return
        default: return
        }
        switch result {
        case .accepted(let resolution, let resolved):
            log("request \(resolved.requestId): \(resolved.outcome.rawValue) on the buddy")
            waiting.removeValue(forKey: resolved.requestId)?.resume(returning: resolution)
            await send(.requestResolved(resolved))
        case .rejected(let rejection, let reply):
            log("buddy decision rejected: \(rejection)")
            if let reply {
                waiting.removeValue(forKey: reply.requestId)?.resume(returning: nil)
                await send(.requestResolved(reply))
            }
        }
    }

    private func hold(id: String, session: String, expiresAt: Int, body: PendingRequest.Body,
                      message: Outbound, onMac: String) async -> Resolution? {
        guard await awayWithinGrace() else {
            log("request \(id): user at the Mac, prompt stays in the terminal")
            await send(.agentStep(AgentStep(session: session, kind: .ask, text: String(onMac.prefix(120)))))
            return nil
        }
        log("request \(id): user away, holding for the buddy")
        registry.register(PendingRequest(id: id, session: session, body: body, expiresAt: expiresAt))
        return await withCheckedContinuation { continuation in
            waiting[id] = continuation
            Task {
                await send(message)
                await watch(id: id, expiresAt: expiresAt)
            }
        }
    }

    /// Right after typing the user always counts as present, so a request waits up to `presenceGrace` seconds for the
    /// Mac to go quiet (no input for that long, or the screen locked) before it goes to the terminal instead.
    private func awayWithinGrace() async -> Bool {
        guard presence.userIsPresent() else { return true }
        for _ in 0..<presenceGrace {
            if presence.quiet(for: Double(presenceGrace)) { return true }
            await clock.sleep(seconds: 1)
        }
        return presence.quiet(for: Double(presenceGrace))
    }

    /// Any input on the Mac takes a held request back to the terminal; while the buddy shows it, only
    /// `handBackAfter` seconds of continuous input do, so a nudged mouse does not take it away mid-reach.
    private func watch(id: String, expiresAt: Int) async {
        defer { shownOnBuddy[id] = nil }
        var activeSince: Int?
        while registry.pendingRequests.contains(where: { $0.id == id }) {
            await clock.sleep(seconds: pollSeconds)
            let now = clock.now(), expired = now >= expiresAt
            let shown = shownOnBuddy[id].map { now - $0 < Self.shownWithin } ?? false
            activeSince = presence.quiet(for: Self.activeWithin) ? nil : activeSince ?? now
            let back = activeSince.map { !shown || now - $0 >= Self.handBackAfter } ?? false
            if back || expired, let released = registry.release(id) {
                log("request \(id): released to the Mac (\(expired ? "expired" : "user back"))")
                waiting.removeValue(forKey: id)?.resume(returning: nil)
                await send(.requestResolved(released))
                return
            }
        }
    }

    public var currentHost: String { host }

    /// The buddy binds a link to one host, so the caller must also drop the link.
    public func setHost(_ name: String) {
        host = name
    }

    public func updateUsage(_ limits: RateLimits) async {
        await sendUsage(usage.update(limits, now: clock.now()))
    }

    public func updateUsage(tokensToday: Int) async {
        await sendUsage(usage.update(tokensToday: tokensToday, now: clock.now()))
    }

    private func sendUsage(_ messages: [Outbound]) async {
        for message in messages {
            if case .usageUpdate(let u) = message {
                log("usage: 5 h \(u.sessionPct)% (reset in \(u.resetInMin) min), week \(u.weeklyPct)%, tokens today \(u.tokensToday.map(String.init) ?? "-")")
            }
            await send(message)
        }
    }

    /// Full state for this host; send it whenever a buddy link comes up.
    public func sendSnapshot() async {
        if let recorder { store.setHilo(recorder.hiloState(now: clock.now())) }
        store.setUsage(usage.usage(now: clock.now()))
        await send(.snapshot(store.snapshot(host: host)))
    }

    public func buddyLink(up: Bool) {
        recorder?.buddyLink(up: up, now: clock.now())
        if !up { buddySettings = nil }
    }

    /// What the buddy last reported; nil until it does (or while the link is down).
    public var settings: DeviceSettings? { buddySettings }

    public var faceHash: String? { face?.hash }

    /// A new picture goes out at once; the next snapshot names it (or, with nil, tells the buddy to drop it).
    public func setFace(_ image: RGB565Image?) async {
        guard image != face else { return }
        face = image
        store.setFace(image.map { ImageRef(hash: $0.hash) })
        log(image.map { "face \($0.hash)" } ?? "no face")
        if let image { for chunk in image.chunks { await send(.face(chunk)) } }
        await sendSnapshot()
    }

    public var focus: PomodoroState? { pomodoro }

    public func setPlayer(_ player: MediaPlayer) { self.player = player }

    private var music = (spotify: true, app: true)

    /// With both off the buddy drops what was playing and may hide its Music view.
    public func followMusic(spotify: Bool, app: Bool) async {
        player?.follow(spotify: spotify, music: app)
        let wasOn = music.spotify || music.app
        music = (spotify, app)
        guard wasOn != (spotify || app) else { return }
        log("music: \(spotify || app ? "following \([spotify ? "Spotify" : nil, app ? "Music" : nil].compactMap { $0 }.joined(separator: " and "))" : "off")")
        if !(spotify || app) { media = nil; cover = nil }
        store.setMediaEnabled(spotify || app)
        await sendSnapshot()
    }

    public var followedMusic: (spotify: Bool, app: Bool) { music }

    /// AppleScript can block for seconds (a pending Automation prompt, a hung app), so it runs off the actor.
    public nonisolated func pollMedia() async {
        guard let player = await player else { return }
        await updateMedia(player.current())
    }

    /// Sends `media.now_playing` when the track, play state or a seek changes what the buddy extrapolates; a snapshot
    /// without `media` when playback stops.
    public func updateMedia(_ playing: Media?) async {
        let now = clock.now()
        guard var next = playing, music.spotify || music.app else {
            cover = nil
            guard media != nil else { return }
            media = nil
            store.setMedia(nil)
            return await sendSnapshot()
        }
        let track = Self.track(next)
        if cover?.track != track {
            cover = (track, nil)
            fetchCover(for: track)
        }
        next.cover = cover?.image.map { ImageRef(hash: $0.hash) }
        if let (last, at) = media, Self.track(last) == track, last.playing == next.playing, last.cover == next.cover {
            let expected = last.positionS + (last.playing == false ? 0 : now - at)
            if abs(expected - next.positionS) <= 3 { return }
        }
        media = (next, now)
        await send(.nowPlaying(next))
    }

    public var coverHash: String? { cover?.image?.hash }

    private static func track(_ m: Media) -> String { "\(m.title)\t\(m.artist)\t\(m.lengthS)" }

    /// Reading the cover can mean a download, so it runs off the actor; a cover that arrives after the track changed is dropped.
    private func fetchCover(for track: String) {
        guard let player else { return }
        coverFetches.async { [self] in
            let image = player.artwork().flatMap { RGB565Image.decode($0, side: RGB565Image.coverSide) }
            Task { await coverFetched(image, for: track) }
        }
    }

    private func coverFetched(_ image: RGB565Image?, for track: String) async {
        guard let image, cover?.track == track, let (last, at) = media, Self.track(last) == track else { return }
        cover = (track, image)
        log("cover \(image.hash)")
        let now = clock.now()
        var next = last
        if last.playing != false { next.positionS = min(last.lengthS, last.positionS + now - at) }
        next.cover = ImageRef(hash: image.hash)
        media = (next, now)
        await send(.nowPlaying(next))
    }

    static let idleAfter = 600

    public func tickSessions() async {
        let now = clock.now()
        recorder?.markIdle(before: now - Self.idleAfter)
        let stale = store.idleStale(now: now, after: Self.idleAfter)
        guard !stale.isEmpty else { return }
        log("idle after \(Self.idleAfter / 60) min without events: \(stale.joined(separator: ", "))")
        await sendSnapshot()
    }

    /// Runs on the Mac's clock too, so finished work phases are recorded even with the buddy away.
    public func tickPomodoro() {
        guard var p = pomodoro else { return }
        p.advance(to: clock.now())
        adopt(p)
    }

    public func changePomodoro(_ command: PomodoroCommand) async -> Bool {
        let now = clock.now()
        var p = pomodoro ?? .stopped(now: now)
        p.advance(to: now)
        switch command {
        case .toggle: p.toggle(now: now)
        case .reset: p.reset(now: now)
        case .durations(let work, let rest): guard p.setDurations(work: work, rest: rest, now: now) else { return false }
        case .autoContinue(let on): p.setAutoContinue(on, now: now)
        }
        adopt(p)
        await send(.pomodoro(p))
        return true
    }

    private func adopt(_ next: PomodoroState) {
        var p = next
        p.advance(to: clock.now())
        if p != pomodoro {
            let finished = pomodoro.map { max(0, p.cycle - $0.cycle) } ?? 0
            recorder?.saveFocus(p, finishedCycles: finished, now: clock.now())
        }
        pomodoro = p
        store.setPomodoro(p)
    }

    /// The buddy applies it and answers with `device.settings`, which is what Hilo then shows.
    public func changeSettings(_ change: SettingsChange) async -> Bool {
        guard change.isValid else { return false }
        await send(.settingsSet(change))
        return true
    }

    /// The buddy and Hilo both pick from here; the Mac's snapshot is what both then show. nil for a session this Mac does not know.
    public func changeLook(_ change: SessionLookChange) async -> SessionLook? {
        guard let project = store.project(of: change.session),
              let look = store.setLook(session: change.session, acc: change.acc, hue: PetLook.of(project: project).hue) else {
            guard var ended = recorder?.look(session: change.session) else { return nil }
            ended.acc = change.acc
            recorder?.saveLook(session: change.session, look: ended)
            return ended
        }
        log("session \(change.session): \(change.acc.rawValue)")
        recorder?.saveLook(session: change.session, look: look)
        await sendSnapshot()
        return look
    }

    private func send(_ outbound: Outbound) async {
        var message = outbound
        if case .sessionStart(var s) = outbound, s.look == nil {
            s.look = recorder?.look(session: s.session)
                ?? PetLook.forSession(project: s.project, others: store.looks(project: s.project, except: s.session))
            message = .sessionStart(s)
        }
        store.apply(message, now: clock.now())
        recorder?.record(message, now: clock.now())
        guard let data = try? Wire.encode(message, host: host, ts: clock.now()) else { return }
        await link.send(data)
    }
}
