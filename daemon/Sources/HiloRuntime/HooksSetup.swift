import Foundation

/// Whether Claude Code's user settings send every hook `hilod` needs to `hilo hook`, and the prompt that makes it so.
/// Like `StatusLineSetup`, Hilo only reads `settings.json`; the change is left to a Claude Code session the user watches.
public enum HooksSetup {
    public enum State: Equatable, Sendable {
        case installed, missing([String]), unreadable
    }

    /// The blocking ones need a timeout above hilod's 600 s request expiry.
    static let events: [(name: String, matcher: String?, timeout: Int?)] = [
        ("SessionStart", nil, nil), ("SessionEnd", nil, nil), ("UserPromptSubmit", nil, nil),
        ("PostToolUse", nil, nil), ("PostToolUseFailure", nil, nil), ("Stop", nil, nil), ("StopFailure", nil, nil),
        ("PermissionRequest", nil, 660), ("PreToolUse", "AskUserQuestion", 660),
    ]

    public static func detect(path: String = StatusLineSetup.settingsPath) -> State {
        guard let data = FileManager.default.contents(atPath: path) else { return .missing(events.map(\.name)) }
        return detect(data)
    }

    public static func detect(_ settings: Data) -> State {
        guard let root = try? JSONSerialization.jsonObject(with: settings) as? [String: Any] else { return .unreadable }
        let hooks = root["hooks"] as? [String: Any] ?? [:]
        let missing = events.filter { event in
            let groups = hooks[event.name] as? [[String: Any]] ?? []
            return !groups.contains { group in
                covers(group["matcher"] as? String, event.matcher)
                    && (group["hooks"] as? [[String: Any]] ?? []).contains { isHiloHook($0["command"] as? String ?? "") }
            }
        }.map(\.name)
        return missing.isEmpty ? .installed : .missing(missing)
    }

    static func covers(_ matcher: String?, _ needed: String?) -> Bool {
        guard let needed, let matcher, !matcher.isEmpty, matcher != "*" else { return true }
        return matcher.range(of: #"(^|\|)\#(needed)($|\|)"#, options: .regularExpression) != nil
    }

    static func isHiloHook(_ command: String) -> Bool {
        command.trimmingCharacters(in: .whitespaces)
            .range(of: #"^(?:(['"])(?:[^'"]*/)?hilo\1|(?:\S*/)?hilo)\s+hook\s*$"#, options: .regularExpression) != nil
    }

    public static func prompt(hilo: String) -> String {
        let command = "\(StatusLineSetup.quoted(hilo)) hook"
        let list = events.map { event in
            var entry = "   - \(event.name)"
            if let matcher = event.matcher { entry += " (matcher \"\(matcher)\")" }
            if let timeout = event.timeout { entry += ", timeout \(timeout)" }
            return entry
        }.joined(separator: "\n")
        return """
        Please send my Claude Code hooks to Hilo, so the Hilo buddy can show my sessions and answer low-risk prompts. Edit only ~/.claude/settings.json (or settings.json in $CLAUDE_CONFIG_DIR if that is set).

        1. Copy the file to settings.json.bak-hilo next to it before changing anything (if that name is taken, add a timestamp).
        2. Under "hooks", make sure each of these events has a command hook running `\(command)`:
        \(list)
           Each one is {"matcher": <matcher, only where given>, "hooks": [{"type": "command", "command": "\(command)", "timeout": <timeout, only where given>}]}, appended to that event's list.
           If an event already has a hook running `hilo hook` (any path to hilo), change it only to point at the path above. Keep every other hook and setting as it is. Never add it twice.
        3. Show me the diff and wait for my OK before saving. End that reply by saying nothing is saved yet and asking me to answer "ok" to save it.
        4. Once it is saved, tell me how to check it: hooks load when a Claude Code session starts, so I open a new session, and it shows up in Hilo › Sessions and on the buddy; Hilo › Setup › Claude Code hooks says every hook goes to hilo hook.
        """
    }
}
