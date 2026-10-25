import Foundation

/// JSON a hook prints to stdout. An empty body leaves Claude Code's normal flow untouched.
public enum HookResponse {
    public static let passThrough = Data()

    public static func permission(_ resolution: Resolution) -> Data {
        let behavior: String
        switch resolution {
        case .allow: behavior = "allow"
        case .deny: behavior = "deny"
        case .answer: return passThrough
        }
        return encode(.object(["hookSpecificOutput": .object([
            "hookEventName": .string("PermissionRequest"),
            "decision": .object(["behavior": .string(behavior)]),
        ])]))
    }

    public static func question(_ resolution: Resolution, toolInput: JSONValue) -> Data {
        guard case .answer(_, let label) = resolution,
              case .object(var input) = toolInput,
              let question = toolInput["questions"]?.array?.first?["question"]?.string else { return passThrough }
        input["answers"] = .object([question: .string(label)])
        return encode(.object(["hookSpecificOutput": .object([
            "hookEventName": .string("PreToolUse"),
            "permissionDecision": .string("allow"),
            "updatedInput": .object(input),
        ])]))
    }

    private static func encode(_ value: JSONValue) -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? e.encode(value)) ?? passThrough
    }
}
