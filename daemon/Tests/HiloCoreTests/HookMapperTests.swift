import Foundation
import Testing
import HiloContract
@testable import HiloCore

private let repo = "/home/dev/code/payments-api"
private let mapper = HookMapper(repoRoot: { $0.hasPrefix(repo) ? repo : nil })
private let rid = "01K8F3Z9QW4Y6R2M7N5P8T0V1X"

private func hook(_ json: String) throws -> HookInput {
    try HookInput.decode(Data(json.utf8))
}

private func map(_ json: String) throws -> HookAction {
    mapper.map(try hook(json), now: 1_000, requestId: rid)
}

@Test func sessionStartUsesRepoName() throws {
    let action = try map(#"{"hook_event_name":"SessionStart","session_id":"abc","cwd":"\#(repo)/src","source":"startup"}"#)
    #expect(action == .emit([.sessionStart(SessionStart(session: "abc", project: "payments-api", task: ""))]))
}

@Test func lowRiskPermissionRequest() throws {
    let action = try map(#"""
    {"hook_event_name":"PermissionRequest","session_id":"abc","cwd":"\#(repo)","tool_name":"Bash",
     "tool_input":{"command":"npm test","description":"Run the unit tests"}}
    """#)
    #expect(action == .awaitPermission(PermissionRequest(
        requestId: rid, session: "abc", project: "payments-api", tool: "Bash", detail: "npm test", why: "Run the unit tests",
        cwd: repo, risk: .low, remoteAllowed: true, expiresAt: 1_600)))
}

@Test func editPermissionCarriesRelativePathAndDiff() throws {
    let action = try map(#"""
    {"hook_event_name":"PermissionRequest","session_id":"abc","cwd":"\#(repo)","tool_name":"Edit",
     "tool_input":{"file_path":"\#(repo)/src/a.ts","old_string":"  if (x) {","new_string":"  verify();\n  if (x) {"}}
    """#)
    guard case .awaitPermission(let p) = action else { Issue.record("expected permission"); return }
    #expect(p.detail == "src/a.ts")
    #expect(p.risk == .low)
    #expect(p.diff == [DiffLine(.removed, "  if (x) {"), DiffLine(.added, "  verify();"), DiffLine(.added, "  if (x) {")])
}

@Test func unknownToolInputIsNotForwarded() throws {
    let action = try map(#"""
    {"hook_event_name":"PermissionRequest","session_id":"abc","cwd":"\#(repo)","tool_name":"mcp__jira__create",
     "tool_input":{"token":"secret-value","summary":"x"}}
    """#)
    guard case .awaitPermission(let p) = action else { Issue.record("expected permission"); return }
    #expect(p.detail == "mcp__jira__create")
    #expect(p.risk == .high)
}

@Test func aCommandTooLongToShowWholeIsMacOnly() throws {
    func request(_ command: String) throws -> PermissionRequest? {
        let json = #"{"hook_event_name":"PermissionRequest","session_id":"abc","cwd":"\#(repo)","tool_name":"Bash","tool_input":{"command":"\#(command)"}}"#
        guard case .awaitPermission(let p) = try map(json) else { return nil }
        return p
    }
    let words = "echo " + Array(repeating: "word", count: 59).joined(separator: " ")
    let fits = try #require(try request(words + "s"))
    let cut = try #require(try request(words + "ss"))
    #expect(fits.remoteAllowed && fits.detail.count == 300)
    #expect(!cut.remoteAllowed && cut.detail.hasSuffix("…"))
}

@Test func singleSelectQuestionIsForwarded() throws {
    let action = try map(#"""
    {"hook_event_name":"PreToolUse","session_id":"abc","cwd":"\#(repo)","tool_name":"AskUserQuestion",
     "tool_input":{"questions":[{"question":"Where should I store Hilo history?","header":"Storage","multiSelect":false,
       "options":[{"label":"Local SQLite","description":""},{"label":"Markdown files","description":""}]}]}}
    """#)
    guard case .awaitQuestion(let q, _) = action else { Issue.record("expected question"); return }
    #expect(q.options == ["Local SQLite", "Markdown files"])
    #expect(q.detail == "Where should I store Hilo history?")
}

@Test(arguments: [
    #"{"questions":[{"question":"Pick","multiSelect":true,"options":[{"label":"a"},{"label":"b"}]}]}"#,
    #"{"questions":[{"question":"A","options":[{"label":"a"},{"label":"b"}]},{"question":"B","options":[{"label":"a"},{"label":"b"}]}]}"#,
    #"{"questions":[{"question":"Pick","options":[{"label":"a"}]}]}"#,
])
func otherQuestionsStayOnTheMac(_ input: String) throws {
    let action = try map(#"{"hook_event_name":"PreToolUse","session_id":"abc","cwd":"\#(repo)","tool_name":"AskUserQuestion","tool_input":\#(input)}"#)
    #expect(action == .emit([.agentStep(AgentStep(session: "abc", kind: .ask, text: "Asked a question on the Mac"))]))
}

@Test func postToolUseBecomesStep() throws {
    let action = try map(#"{"hook_event_name":"PostToolUse","session_id":"abc","cwd":"\#(repo)","tool_name":"Bash","tool_input":{"command":"npm run build"}}"#)
    #expect(action == .emit([.agentStep(AgentStep(session: "abc", kind: .run, text: "Ran npm run build"))]))
}

@Test func stopBecomesTaskDoneWithClippedSummary() throws {
    let long = String(repeating: "x", count: 400)
    let action = try map(#"{"hook_event_name":"Stop","session_id":"abc","cwd":"\#(repo)","last_assistant_message":"\#(long)"}"#)
    guard case .emit(let messages) = action, case .taskDone(let done)? = messages.first else { Issue.record("expected task_done"); return }
    #expect(done.summary.count == 300)
}

@Test func otherToolsPreToolUseIsIgnored() throws {
    #expect(try map(#"{"hook_event_name":"PreToolUse","session_id":"abc","cwd":"\#(repo)","tool_name":"Bash","tool_input":{}}"#) == .emit([]))
}

@Test func permissionResponses() throws {
    let allow = String(decoding: HookResponse.permission(.allow), as: UTF8.self)
    #expect(allow == #"{"hookSpecificOutput":{"decision":{"behavior":"allow"},"hookEventName":"PermissionRequest"}}"#)
    #expect(HookResponse.permission(.answer(index: 0, label: "x")).isEmpty)
}

@Test func questionResponseEchoesQuestionsAndAddsAnswer() throws {
    let input = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"questions":[{"question":"Which?","options":[{"label":"A"},{"label":"B"}]}]}"#.utf8))
    let out = try JSONDecoder().decode(JSONValue.self, from: HookResponse.question(.answer(index: 1, label: "B"), toolInput: input))
    #expect(out["hookSpecificOutput"]?["permissionDecision"]?.string == "allow")
    #expect(out["hookSpecificOutput"]?["updatedInput"]?["answers"]?["Which?"]?.string == "B")
    #expect(out["hookSpecificOutput"]?["updatedInput"]?["questions"] == input["questions"])
}

@Test func clippingCountsUnicodeScalarsLikeTheSchema() {
    let combining = String(repeating: "e\u{301}", count: 100)
    let clipped = Text.clip(combining, 120)
    #expect(clipped.unicodeScalars.count == 120)
    #expect(clipped.hasSuffix("…"))
    #expect(Text.clipLeft(combining, 120).unicodeScalars.count == 120)
    #expect(Text.clip("short", 120) == "short")
}
