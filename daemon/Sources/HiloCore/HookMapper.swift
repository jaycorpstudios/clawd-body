import Foundation
import HiloContract

public struct HookInput: Decodable, Sendable {
    public var hookEventName: String
    public var sessionId: String
    public var cwd: String
    public var toolName: String?
    public var toolInput: JSONValue?
    public var lastAssistantMessage: String?
    public var error: String?

    public static func decode(_ data: Data) throws -> HookInput {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(HookInput.self, from: data)
    }
}

public enum HookAction: Equatable, Sendable {
    case emit([Outbound])
    case awaitPermission(PermissionRequest)
    case awaitQuestion(QuestionRequest, toolInput: JSONValue)
}

public struct HookMapper: Sendable {
    public static let expirySeconds = 600

    public var policy: RiskPolicy
    public var repoRoot: @Sendable (String) -> String?

    public init(policy: RiskPolicy = .default, repoRoot: @escaping @Sendable (String) -> String?) {
        self.policy = policy
        self.repoRoot = repoRoot
    }

    public func project(of hook: HookInput) -> String {
        Self.project(root: repoRoot(hook.cwd), cwd: hook.cwd)
    }

    public func map(_ hook: HookInput, now: Int, requestId: String = ULID.make()) -> HookAction {
        let root = repoRoot(hook.cwd)
        let project = Self.project(root: root, cwd: hook.cwd)
        let session = Text.clip(hook.sessionId, 64)
        let tool = hook.toolName ?? ""
        let input = hook.toolInput ?? .object([:])

        switch hook.hookEventName {
        case "SessionStart":
            return .emit([.sessionStart(SessionStart(session: session, project: project, task: ""))])
        case "SessionEnd":
            return .emit([.sessionEnd(SessionRef(session: session))])
        case "UserPromptSubmit":
            return .emit([.agentStep(AgentStep(session: session, kind: .plan, text: "New prompt"))])
        case "PostToolUse":
            return .emit([.agentStep(Self.step(session: session, tool: tool, input: input, root: root))])
        case "PostToolUseFailure":
            return .emit([.agentStep(AgentStep(session: session, kind: .err, text: Text.clip("\(tool) failed", 120)))])
        case "Stop":
            let summary = Text.clip(hook.lastAssistantMessage ?? "", 300)
            return .emit([.taskDone(TaskDone(session: session, summary: summary.isEmpty ? "Finished" : summary))])
        case "StopFailure":
            return .emit([.agentError(AgentError(session: session, detail: Text.clip(hook.error ?? "Turn failed", 300)))])
        case "PermissionRequest":
            let call = ToolCall(tool: tool, input: Self.flatStrings(input), cwd: hook.cwd, repoRoot: root)
            let c = policy.classify(call)
            return .awaitPermission(PermissionRequest(
                requestId: requestId, session: session, project: project, tool: Text.clip(tool.isEmpty ? "Tool" : tool, 32),
                detail: Self.detail(tool: tool, input: input, root: root), why: input["description"]?.string.map { Text.clip($0, 300) },
                diff: Self.diff(input), cwd: Text.clipLeft(hook.cwd, 120), risk: c.risk, remoteAllowed: c.remoteAllowed,
                expiresAt: now + Self.expirySeconds))
        case "PreToolUse" where tool == "AskUserQuestion":
            guard let q = Self.singleQuestion(input) else {
                return .emit([.agentStep(AgentStep(session: session, kind: .ask, text: "Asked a question on the Mac"))])
            }
            return .awaitQuestion(QuestionRequest(requestId: requestId, session: session, project: project,
                                                  detail: Text.clip(q.text, 300), options: q.options, expiresAt: now + Self.expirySeconds),
                                  toolInput: input)
        default:
            return .emit([])
        }
    }

    static func project(root: String?, cwd: String) -> String {
        let name = URL(filePath: root ?? cwd).lastPathComponent
        return Text.clip(name.isEmpty || name == "/" ? "unknown" : name, 64)
    }

    static func relative(_ path: String, root: String?) -> String {
        guard let root, path.hasPrefix(root + "/") else { return path }
        return String(path.dropFirst(root.count + 1))
    }

    static func detail(tool: String, input: JSONValue, root: String?) -> String {
        let text: String
        if let command = input["command"]?.string { text = command }
        else if let path = input["file_path"]?.string { text = relative(path, root: root) }
        else if let url = input["url"]?.string { text = url }
        else { text = tool }
        return Text.clip(text.isEmpty ? tool : text, 300)
    }

    static func diff(_ input: JSONValue) -> [DiffLine]? {
        guard let old = input["old_string"]?.string, let new = input["new_string"]?.string else { return nil }
        let removed = old.split(separator: "\n", omittingEmptySubsequences: false).map { DiffLine(.removed, Text.clipLine(String($0), 120)) }
        let added = new.split(separator: "\n", omittingEmptySubsequences: false).map { DiffLine(.added, Text.clipLine(String($0), 120)) }
        return Array((removed + added).prefix(12))
    }

    static func step(session: String, tool: String, input: JSONValue, root: String?) -> AgentStep {
        let target = detail(tool: tool, input: input, root: root)
        let (kind, verb): (StepKind, String) = switch tool {
        case "Read", "Glob", "Grep": (.read, "Read")
        case "Edit", "Write", "NotebookEdit": (.edit, "Edited")
        case "Bash": (.run, "Ran")
        default: (.plan, tool.isEmpty ? "Used a tool" : "Used \(tool)")
        }
        let text = ["Read", "Edited", "Ran"].contains(verb) ? "\(verb) \(target)" : verb
        return AgentStep(session: session, kind: kind, text: Text.clip(text, 120))
    }

    static func singleQuestion(_ input: JSONValue) -> (text: String, options: [String])? {
        guard let questions = input["questions"]?.array, questions.count == 1, let q = questions.first,
              q["multiSelect"]?.bool != true, let text = q["question"]?.string, !text.isEmpty,
              let options = q["options"]?.array?.compactMap({ $0["label"]?.string }),
              (2...4).contains(options.count), options.allSatisfy({ (1...40).contains($0.count) }) else { return nil }
        return (text, options)
    }

    static func flatStrings(_ input: JSONValue) -> [String: String] {
        guard case .object(let o) = input else { return [:] }
        return o.compactMapValues(\.string)
    }
}

/// Limits count Unicode scalars, as JSON Schema's maxLength does.
public enum Text {
    public static func clip(_ s: String, _ max: Int) -> String {
        clipLine(s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces), max)
    }

    public static func clipLine(_ s: String, _ max: Int) -> String {
        let u = s.unicodeScalars
        return u.count <= max ? s : String(String.UnicodeScalarView(u.prefix(max - 1))) + "…"
    }

    public static func clipLeft(_ s: String, _ max: Int) -> String {
        let u = s.unicodeScalars
        return u.count <= max ? s : "…" + String(String.UnicodeScalarView(u.suffix(max - 1)))
    }
}
