import Foundation
import Testing
import HiloContract
@testable import HiloCore

@Test(arguments: [
    (#"curl -H "Authorization: Bearer abc.def" https://api.example.com"#, #"curl -H "Authorization: [redacted]" https://api.example.com"#),
    (#"curl -H 'Cookie: sid=42; theme=dark' https://example.com"#, #"curl -H 'Cookie: [redacted]' https://example.com"#),
    (#"curl -H "X-Api-Key: k123" https://example.com"#, #"curl -H "X-Api-Key: [redacted]" https://example.com"#),
    ("export GITHUB_TOKEN=gh_short && make", "export GITHUB_TOKEN=[redacted] && make"),
    (#"DB_PASSWORD="hunter 2" npm start"#, "DB_PASSWORD=[redacted] npm start"),
    ("mysql --password=hunter2 -u root", "mysql --password=[redacted] -u root"),
    ("gh auth login --with-token abc", "gh auth login --with-token [redacted]"),
    ("git clone https://dev:p4ss@git.example.com/repo.git", "git clone https://dev:[redacted]@git.example.com/repo.git"),
    ("curl 'https://example.com/v1?api_key=abc123&page=2'", "curl 'https://example.com/v1?api_key=[redacted]&page=2'"),
    (#"  "client_secret": "s3cr3t","#, #"  "client_secret": "[redacted]","#),
    ("password: hunter2", "password: [redacted]"),
    ("echo AKIAIOSFODNN7EXAMPLE", "echo [redacted]"),
    ("git show 3f2b6810c4e5d6a7b8c9d0e1f2a3b4c5d6e7f809", "git show [redacted]"),
    ("echo ghp_R4nd0mT0k3nV4lu3Xy9Zq8Wp7Vn6Mb5Lk4J3h", "echo [redacted]"),
    ("curl -d eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.e30.x", "curl -d [redacted].e30.x"),
])
func secretsAreMasked(_ input: String, _ expected: String) {
    #expect(Redactor.redact(input) == expected)
}

@Test(arguments: [
    "npm test",
    "npm install left-pad@1.3.0",
    "Sources/HiloRuntime/CoordinatorTests.swift",
    "pnpm -F @hilo-buddy/shared emit permission-low --host work --interval 1500",
    "swift test --filter CoordinatorPhase4Tests",
    "https://docs.example.com/reference/api/authentication-overview",
    "xcrun simctl boot 'iPhone 16 Pro'",
])
func ordinaryTextIsLeftAlone(_ input: String) {
    #expect(Redactor.redact(input) == input)
}

@Test func permissionDetailStepAndDiffAreRedacted() throws {
    let repo = "/home/dev/code/payments-api"
    let mapper = HookMapper(repoRoot: { _ in repo })
    let bash = try HookInput.decode(Data(#"""
    {"hook_event_name":"PermissionRequest","session_id":"s","cwd":"\#(repo)","tool_name":"Bash",
     "tool_input":{"command":"curl -H \"Authorization: Bearer xyz\" https://api.example.com","description":"Call with STRIPE_KEY=sk_live_1"}}
    """#.utf8))
    guard case .awaitPermission(let p) = mapper.map(bash, now: 0) else { Issue.record("expected permission"); return }
    #expect(p.detail == #"curl -H "Authorization: [redacted]" https://api.example.com"#)
    #expect(p.why == "Call with STRIPE_KEY=[redacted]")
    #expect(p.risk == .high)

    let ran = try HookInput.decode(Data(#"""
    {"hook_event_name":"PostToolUse","session_id":"s","cwd":"\#(repo)","tool_name":"Bash","tool_input":{"command":"export API_TOKEN=abc && make"}}
    """#.utf8))
    #expect(mapper.map(ran, now: 0) == .emit([.agentStep(AgentStep(session: "s", kind: .run, text: "Ran export API_TOKEN=[redacted] && make"))]))

    let edit = try HookInput.decode(Data(#"""
    {"hook_event_name":"PermissionRequest","session_id":"s","cwd":"\#(repo)","tool_name":"Edit",
     "tool_input":{"file_path":"\#(repo)/.env","old_string":"DB_PASSWORD=old","new_string":"DB_PASSWORD=new"}}
    """#.utf8))
    guard case .awaitPermission(let e) = mapper.map(edit, now: 0) else { Issue.record("expected permission"); return }
    #expect(e.diff == [DiffLine(.removed, "DB_PASSWORD=[redacted]"), DiffLine(.added, "DB_PASSWORD=[redacted]")])
}

@Test func redactedFixtureMatchesTheMapperOutput() throws {
    let url = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "../../../shared/fixtures/valid/agent.needs_permission.redacted.json").standardized
    let fixture = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let data = try #require(fixture["data"] as? [String: Any])
    let raw = #"curl -sS -H "Authorization: Bearer 9f8e7d6c" -H "X-Api-Key: live_42" "https://api.example.com/v1/charges?limit=5""#
    #expect(Redactor.redact(raw) == data["detail"] as? String)
}
