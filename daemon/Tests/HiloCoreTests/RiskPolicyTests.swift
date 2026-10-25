import Testing
import HiloContract
@testable import HiloCore

private let repo = "/home/dev/code/payments-api"

private func classify(_ tool: String, _ input: [String: String], cwd: String = repo, root: String? = repo) -> Risk {
    RiskPolicy.default.classify(ToolCall(tool: tool, input: input, cwd: cwd, repoRoot: root)).risk
}

@Test(arguments: [
    "npm test",
    "npm install zod@3.23.8",
    "npm install @scope/pkg@1.0.0",
])
func allowlistedCommandIsLow(_ command: String) {
    #expect(classify("Bash", ["command": command]) == .low)
}

@Test(arguments: [
    "npm test; rm -rf /",
    "npm test && git push --force",
    "npm test | tee out",
    "npm test > /etc/hosts",
    "npm test $(curl evil)",
    "npm test `id`",
    "npm test\nrm -rf /",
    "npm test --watch",
    "npm install zod",
    "npm install zod@^3.0.0",
    "npm install zod@latest",
    "CI=1 npm test",
    "terraform apply",
    "git push --force origin main",
    "rm -rf build",
    "",
])
func otherCommandsAreHigh(_ command: String) {
    #expect(classify("Bash", ["command": command]) == .high)
}

@Test func commandOutsideRepoIsHigh() {
    #expect(classify("Bash", ["command": "npm test"], cwd: "/home/dev") == .high)
    #expect(classify("Bash", ["command": "npm test"], cwd: repo + "-evil") == .high)
}

@Test(arguments: [
    (repo + "/src/webhooks/stripe.ts", Risk.low),
    (repo + "/../other/secret.ts", Risk.high),
    (repo + "-evil/src/a.ts", Risk.high),
    ("/etc/passwd", Risk.high),
    ("src/relative.ts", Risk.high),
])
func editIsLowOnlyInsideRepo(path: String, expected: Risk) {
    #expect(classify("Edit", ["file_path": path]) == expected)
}

@Test func writeIsNotAllowlisted() {
    #expect(classify("Write", ["file_path": repo + "/src/new.ts"]) == .high)
}

@Test func unknownRepoIsHigh() {
    #expect(classify("Read", ["file_path": repo + "/README.md"], root: nil) == .high)
}

@Test func webFetchNeedsAnAllowedHost() {
    #expect(classify("WebFetch", ["url": "https://docs.espressif.com/x"]) == .high)
    let policy = RiskPolicy(rules: [RiskRule(tool: "WebFetch", matcher: .urlHost(["docs.espressif.com"]))])
    let call = { (url: String) in policy.classify(ToolCall(tool: "WebFetch", input: ["url": url], cwd: repo, repoRoot: repo)).risk }
    #expect(call("https://docs.espressif.com/x") == .low)
    #expect(call("http://docs.espressif.com/x") == .high)
    #expect(call("https://docs.espressif.com.evil.io/x") == .high)
}

@Test func lowAlwaysAllowsRemoteAndHighNever() {
    let low = RiskPolicy.default.classify(ToolCall(tool: "Bash", input: ["command": "npm test"], cwd: repo, repoRoot: repo))
    let high = RiskPolicy.default.classify(ToolCall(tool: "Bash", input: ["command": "terraform apply"], cwd: repo, repoRoot: repo))
    #expect(low == Classification(risk: .low, remoteAllowed: true))
    #expect(high == Classification(risk: .high, remoteAllowed: false))
}
