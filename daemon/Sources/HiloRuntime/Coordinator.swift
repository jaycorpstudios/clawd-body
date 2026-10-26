import Foundation
import HiloContract
import HiloCore

public protocol BuddyLink: Sendable {
    func send(_ data: Data) async
}

public protocol PresenceProbe: Sendable {
    func userIsPresent() -> Bool
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
    private let host: String
    private let mapper: HookMapper
    private let link: BuddyLink
    private let presence: PresenceProbe
    private let clock: Clock
    private let pollSeconds: Double
    private let log: @Sendable (String) -> Void
    private let recorder: StoreRecorder?
    private var registry = RequestRegistry()
    private var store = SessionStore()
    private var waiting: [String: CheckedContinuation<Resolution?, Never>] = [:]

    public init(host: String, mapper: HookMapper, link: BuddyLink, presence: PresenceProbe,
                clock: Clock = SystemClock(), pollSeconds: Double = 2, recorder: StoreRecorder? = nil,
                log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.host = host; self.mapper = mapper; self.link = link
        self.presence = presence; self.clock = clock; self.pollSeconds = pollSeconds
        self.recorder = recorder; self.log = log
    }

    /// Returns what the hook command must print to stdout.
    public func handleHook(_ input: HookInput) async -> Data {
        switch mapper.map(input, now: clock.now()) {
        case .emit(let messages):
            for m in messages { await send(m) }
            recorder?.attach(session: Text.clip(input.sessionId, 64), project: mapper.project(of: input))
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
        let result: DecisionResult
        switch envelope.body {
        case .permissionDecision(let d): result = registry.decide(d, now: clock.now())
        case .questionAnswer(let a): result = registry.answer(a, now: clock.now())
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
        guard !presence.userIsPresent() else {
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

    private func watch(id: String, expiresAt: Int) async {
        while registry.pendingRequests.contains(where: { $0.id == id }) {
            await clock.sleep(seconds: pollSeconds)
            if presence.userIsPresent() || clock.now() >= expiresAt, let released = registry.release(id) {
                log("request \(id): released to the Mac (\(clock.now() >= expiresAt ? "expired" : "user back"))")
                waiting.removeValue(forKey: id)?.resume(returning: nil)
                await send(.requestResolved(released))
                return
            }
        }
    }

    /// Full state for this host; send it whenever a buddy link comes up.
    public func sendSnapshot() async {
        if let recorder { store.setHilo(recorder.hiloState(now: clock.now())) }
        await send(.snapshot(store.snapshot(host: host)))
    }

    public func buddyLink(up: Bool) {
        recorder?.buddyLink(up: up, now: clock.now())
    }

    private func send(_ message: Outbound) async {
        store.apply(message, now: clock.now())
        recorder?.record(message, now: clock.now())
        guard let data = try? Wire.encode(message, host: host, ts: clock.now()) else { return }
        await link.send(data)
    }
}
