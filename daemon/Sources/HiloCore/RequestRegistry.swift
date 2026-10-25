import HiloContract

public struct PendingRequest: Equatable, Sendable {
    public enum Body: Equatable, Sendable {
        case permission(risk: Risk, remoteAllowed: Bool)
        case question(options: [String])
    }

    public var id: String
    public var session: String
    public var body: Body
    public var expiresAt: Int

    public init(id: String, session: String, body: Body, expiresAt: Int) {
        self.id = id; self.session = session; self.body = body; self.expiresAt = expiresAt
    }

    var kind: RequestKind {
        if case .question = body { return .question }
        return .permission
    }
}

public enum Resolution: Equatable, Sendable {
    case allow
    case deny
    case answer(index: Int, label: String)
}

public enum Rejection: Equatable, Sendable {
    case unknownRequest
    case alreadyResolved
    case expired
    case approvalNotAllowed
    case wrongKind
    case choiceMismatch
}

public enum DecisionResult: Equatable, Sendable {
    /// Hand `resolution` to the waiting hook and send `resolved` to the buddy.
    case accepted(Resolution, resolved: RequestResolved)
    /// Drop the decision; send `reply` to the buddy when present so it shows the real state.
    case rejected(Rejection, reply: RequestResolved?)
}

public struct RequestRegistry: Sendable {
    private var pending: [String: PendingRequest] = [:]
    private var resolved: [String: RequestResolved] = [:]
    private var resolvedOrder: [String] = []
    private let historyLimit: Int

    public init(historyLimit: Int = 256) {
        self.historyLimit = historyLimit
    }

    public var pendingRequests: [PendingRequest] { Array(pending.values) }

    public mutating func register(_ request: PendingRequest) {
        pending[request.id] = request
    }

    public mutating func decide(_ decision: PermissionDecision, now: Int) -> DecisionResult {
        let request: PendingRequest
        switch lookup(decision.requestId, now: now) {
        case .failure(let failure): return failure
        case .success(let r): request = r
        }
        guard case .permission(let risk, let remoteAllowed) = request.body else {
            return .rejected(.wrongKind, reply: nil)
        }
        switch decision.decision {
        case .deny:
            return .accepted(.deny, resolved: close(request, outcome: .denied, via: .buddy))
        case .approve:
            guard risk == .low, remoteAllowed else { return .rejected(.approvalNotAllowed, reply: nil) }
            return .accepted(.allow, resolved: close(request, outcome: .approved, via: .buddy))
        }
    }

    public mutating func answer(_ answer: QuestionAnswer, now: Int) -> DecisionResult {
        let request: PendingRequest
        switch lookup(answer.requestId, now: now) {
        case .failure(let failure): return failure
        case .success(let r): request = r
        }
        guard case .question(let options) = request.body else { return .rejected(.wrongKind, reply: nil) }
        guard options.indices.contains(answer.choiceIndex), options[answer.choiceIndex] == answer.choice else {
            return .rejected(.choiceMismatch, reply: nil)
        }
        let resolved = close(request, outcome: .answered, via: .buddy, choiceIndex: answer.choiceIndex)
        return .accepted(.answer(index: answer.choiceIndex, label: answer.choice), resolved: resolved)
    }

    /// The user is back at the Mac or the hook gave up: the terminal prompt takes over.
    public mutating func release(_ id: String) -> RequestResolved? {
        guard let request = pending[id] else { return nil }
        return close(request, outcome: .expired, via: .timeout)
    }

    public mutating func expire(now: Int) -> [RequestResolved] {
        pending.values.filter { $0.expiresAt <= now }.sorted { $0.id < $1.id }.map { close($0, outcome: .expired, via: .timeout) }
    }

    private enum Lookup { case success(PendingRequest), failure(DecisionResult) }

    private mutating func lookup(_ id: String, now: Int) -> Lookup {
        guard let request = pending[id] else {
            if let earlier = resolved[id] { return .failure(.rejected(.alreadyResolved, reply: earlier)) }
            return .failure(.rejected(.unknownRequest, reply: nil))
        }
        if request.expiresAt <= now {
            return .failure(.rejected(.expired, reply: close(request, outcome: .expired, via: .timeout)))
        }
        return .success(request)
    }

    private mutating func close(_ request: PendingRequest, outcome: Outcome, via: Via, choiceIndex: Int? = nil) -> RequestResolved {
        pending[request.id] = nil
        let result = RequestResolved(requestId: request.id, session: request.session, kind: request.kind,
                                     outcome: outcome, via: via, choiceIndex: choiceIndex)
        resolved[request.id] = result
        resolvedOrder.append(request.id)
        if resolvedOrder.count > historyLimit {
            resolved[resolvedOrder.removeFirst()] = nil
        }
        return result
    }
}
