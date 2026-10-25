import Testing
import HiloContract
@testable import HiloCore

private let now = 1_000
private let id = "01K8F3Z9QW4Y6R2M7N5P8T0V1X"

private func permission(risk: Risk = .low, remoteAllowed: Bool = true) -> PendingRequest {
    PendingRequest(id: id, session: "s1", body: .permission(risk: risk, remoteAllowed: remoteAllowed), expiresAt: now + 600)
}

private func question() -> PendingRequest {
    PendingRequest(id: id, session: "s1", body: .question(options: ["Local SQLite", "Markdown files"]), expiresAt: now + 600)
}

private func registry(_ request: PendingRequest) -> RequestRegistry {
    var r = RequestRegistry()
    r.register(request)
    return r
}

@Test func lowRiskApprovalIsAccepted() {
    var r = registry(permission())
    let result = r.decide(PermissionDecision(requestId: id, decision: .approve), now: now)
    #expect(result == .accepted(.allow, resolved: RequestResolved(requestId: id, session: "s1", kind: .permission, outcome: .approved, via: .buddy)))
}

@Test(arguments: [(Risk.high, false), (Risk.low, false), (Risk.high, true)])
func approvalIsRejectedUnlessLowAndRemoteAllowed(risk: Risk, remoteAllowed: Bool) {
    var r = registry(permission(risk: risk, remoteAllowed: remoteAllowed))
    #expect(r.decide(PermissionDecision(requestId: id, decision: .approve), now: now) == .rejected(.approvalNotAllowed, reply: nil))
    #expect(r.pendingRequests.count == 1)
}

@Test func highRiskDenyIsHonored() {
    var r = registry(permission(risk: .high, remoteAllowed: false))
    let result = r.decide(PermissionDecision(requestId: id, decision: .deny), now: now)
    #expect(result == .accepted(.deny, resolved: RequestResolved(requestId: id, session: "s1", kind: .permission, outcome: .denied, via: .buddy)))
}

@Test func decisionIsSingleUse() {
    var r = registry(permission())
    _ = r.decide(PermissionDecision(requestId: id, decision: .approve), now: now)
    let replay = r.decide(PermissionDecision(requestId: id, decision: .approve), now: now)
    #expect(replay == .rejected(.alreadyResolved, reply: RequestResolved(requestId: id, session: "s1", kind: .permission, outcome: .approved, via: .buddy)))
}

@Test func expiredRequestIsRejectedAndClosed() {
    var r = registry(permission())
    let result = r.decide(PermissionDecision(requestId: id, decision: .approve), now: now + 600)
    #expect(result == .rejected(.expired, reply: RequestResolved(requestId: id, session: "s1", kind: .permission, outcome: .expired, via: .timeout)))
    #expect(r.pendingRequests.isEmpty)
}

@Test func unknownRequestIsDropped() {
    var r = RequestRegistry()
    #expect(r.decide(PermissionDecision(requestId: id, decision: .deny), now: now) == .rejected(.unknownRequest, reply: nil))
}

@Test func releasedRequestIgnoresLateBuddyDecision() {
    var r = registry(permission())
    #expect(r.release(id)?.outcome == .expired)
    if case .rejected(.alreadyResolved, let reply) = r.decide(PermissionDecision(requestId: id, decision: .approve), now: now) {
        #expect(reply?.outcome == .expired)
    } else {
        Issue.record("late decision was not rejected")
    }
}

@Test func sweepExpiresOnlyDueRequests() {
    var r = RequestRegistry()
    r.register(PendingRequest(id: "01K8F3Z9QW4Y6R2M7N5P8T0V1A", session: "s1", body: .question(options: ["a", "b"]), expiresAt: now))
    r.register(PendingRequest(id: "01K8F3Z9QW4Y6R2M7N5P8T0V1B", session: "s2", body: .question(options: ["a", "b"]), expiresAt: now + 1))
    #expect(r.expire(now: now).map(\.session) == ["s1"])
    #expect(r.pendingRequests.map(\.session) == ["s2"])
}

@Test func validAnswerIsAccepted() {
    var r = registry(question())
    let result = r.answer(QuestionAnswer(requestId: id, choiceIndex: 1, choice: "Markdown files"), now: now)
    #expect(result == .accepted(.answer(index: 1, label: "Markdown files"),
                                resolved: RequestResolved(requestId: id, session: "s1", kind: .question, outcome: .answered, via: .buddy, choiceIndex: 1)))
}

@Test(arguments: [(2, "Decide later"), (0, "Markdown files")])
func answerMustMatchOfferedOption(index: Int, label: String) {
    var r = registry(question())
    #expect(r.answer(QuestionAnswer(requestId: id, choiceIndex: index, choice: label), now: now) == .rejected(.choiceMismatch, reply: nil))
}

@Test func decisionKindMustMatchRequest() {
    var q = registry(question())
    #expect(q.decide(PermissionDecision(requestId: id, decision: .approve), now: now) == .rejected(.wrongKind, reply: nil))
    var p = registry(permission())
    #expect(p.answer(QuestionAnswer(requestId: id, choiceIndex: 0, choice: "Local SQLite"), now: now) == .rejected(.wrongKind, reply: nil))
}
