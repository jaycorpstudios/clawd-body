import Foundation
import HiloContract

public struct ToolCall: Sendable {
    public var tool: String
    public var input: [String: String]
    public var cwd: String
    public var repoRoot: String?
    public var project: String?

    public init(tool: String, input: [String: String], cwd: String, repoRoot: String?, project: String? = nil) {
        self.tool = tool; self.input = input; self.cwd = cwd; self.repoRoot = repoRoot; self.project = project
    }
}

public struct Classification: Equatable, Sendable {
    public var risk: Risk
    public var remoteAllowed: Bool

    static let high = Classification(risk: .high, remoteAllowed: false)
    static let low = Classification(risk: .low, remoteAllowed: true)
}

public enum CommandToken: Equatable, Sendable {
    case literal(String)
    case exactPackage
}

public struct RiskRule: Sendable {
    public enum Matcher: Sendable {
        case fileInsideRepo
        case command([CommandToken])
        case urlHost(Set<String>)
    }

    public var tool: String
    public var matcher: Matcher

    public init(tool: String, matcher: Matcher) {
        self.tool = tool; self.matcher = matcher
    }
}

public struct RiskPolicy: Sendable {
    public var rules: [RiskRule]
    public var file: PolicyFile?

    public init(rules: [RiskRule], file: PolicyFile? = nil) { self.rules = rules; self.file = file }

    public static let `default` = RiskPolicy(rules: [
        RiskRule(tool: "Read", matcher: .fileInsideRepo),
        RiskRule(tool: "Edit", matcher: .fileInsideRepo),
        RiskRule(tool: "Bash", matcher: .command([.literal("npm"), .literal("test")])),
        RiskRule(tool: "Bash", matcher: .command([.literal("npm"), .literal("install"), .exactPackage])),
        RiskRule(tool: "WebFetch", matcher: .urlHost([])),
    ])

    public func classify(_ call: ToolCall) -> Classification {
        guard let root = call.repoRoot.flatMap(Self.normalized) else { return .high }
        let matches = rules.contains { rule in
            rule.tool == call.tool && Self.matches(rule.matcher, call, root: root)
        }
        guard matches else { return .high }
        if let file, file.tightens(call, tokens: call.input["command"].flatMap(Self.plainTokens) ?? []) { return .high }
        return .low
    }

    private static func matches(_ matcher: RiskRule.Matcher, _ call: ToolCall, root: String) -> Bool {
        switch matcher {
        case .fileInsideRepo:
            guard let path = call.input["file_path"].flatMap(normalized) else { return false }
            return isInside(path, root)
        case .command(let pattern):
            guard let cwd = normalized(call.cwd), isInside(cwd, root),
                  let command = call.input["command"], let tokens = plainTokens(command) else { return false }
            return tokens.count == pattern.count && zip(tokens, pattern).allSatisfy(tokenMatches)
        case .urlHost(let hosts):
            guard let url = call.input["url"].flatMap(URL.init(string:)), url.scheme == "https",
                  let host = url.host()?.lowercased() else { return false }
            return hosts.contains(host)
        }
    }

    private static let shellMeta = CharacterSet(charactersIn: ";&|<>$`\\(){}[]*?~!#'\"\n\r=")

    /// nil when the command uses any shell syntax beyond plain words.
    private static func plainTokens(_ command: String) -> [String]? {
        guard command.rangeOfCharacter(from: shellMeta) == nil else { return nil }
        let tokens = command.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        return tokens.isEmpty ? nil : tokens
    }

    private static func tokenMatches(_ token: String, _ pattern: CommandToken) -> Bool {
        switch pattern {
        case .literal(let literal): token == literal
        case .exactPackage: token.wholeMatch(of: /^(@[a-z0-9][a-z0-9._-]*\/)?[a-z0-9][a-z0-9._-]*@\d+\.\d+\.\d+$/) != nil
        }
    }

    private static func normalized(_ path: String) -> String? {
        guard path.hasPrefix("/") else { return nil }
        return URL(filePath: path).standardized.path(percentEncoded: false)
    }

    private static func isInside(_ path: String, _ root: String) -> Bool {
        let base = root.hasSuffix("/") ? root : root + "/"
        return path == root || path.hasPrefix(base)
    }
}

/// `policy.json`: it can only turn low-risk calls into high, never the reverse. Unknown keys are an error, so a typo cannot silently do nothing.
public struct PolicyFile: Equatable, Sendable {
    public struct Rules: Equatable, Sendable {
        public var remoteApproval = true
        public var highTools: Set<String> = []
        public var highCommands: [[String]] = []
    }

    public var all = Rules()
    public var projects: [String: Rules] = [:]

    public static func parse(_ data: Data) throws -> PolicyFile {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw PolicyError("not a JSON object") }
        var file = PolicyFile(all: try rules(json, extra: ["projects"]))
        if let projects = json["projects"] {
            guard let projects = projects as? [String: Any] else { throw PolicyError("projects must be an object") }
            for (name, value) in projects {
                guard let value = value as? [String: Any] else { throw PolicyError("projects.\(name) must be an object") }
                file.projects[name] = try rules(value, extra: [])
            }
        }
        return file
    }

    private static func rules(_ json: [String: Any], extra: Set<String>) throws -> Rules {
        let known: Set<String> = ["remote_approval", "high_tools", "high_commands"]
        if let unknown = Set(json.keys).subtracting(known).subtracting(extra).sorted().first { throw PolicyError("unknown key \(unknown)") }
        var r = Rules()
        if let v = json["remote_approval"] {
            guard let v = v as? Bool else { throw PolicyError("remote_approval must be true or false") }
            r.remoteApproval = v
        }
        if let v = json["high_tools"] {
            guard let v = v as? [String] else { throw PolicyError("high_tools must be a list of tool names") }
            r.highTools = Set(v)
        }
        if let v = json["high_commands"] {
            guard let v = v as? [[String]], v.allSatisfy({ !$0.isEmpty }) else { throw PolicyError("high_commands must be a list of non-empty word lists") }
            r.highCommands = v
        }
        return r
    }

    /// `tokens` are the Bash command's words; a high command matches as a prefix.
    func tightens(_ call: ToolCall, tokens: [String]) -> Bool {
        [all, call.project.flatMap { projects[$0] }].compactMap { $0 }.contains { r in
            !r.remoteApproval || r.highTools.contains(call.tool)
                || (call.tool == "Bash" && r.highCommands.contains { tokens.starts(with: $0) })
        }
    }
}

public struct PolicyError: Error, CustomStringConvertible, Sendable {
    public let description: String
    init(_ description: String) { self.description = description }
}

extension RiskPolicy {
    /// A missing file is the defaults; a broken one is the defaults plus the error to show.
    public static func load(path: String) -> (policy: RiskPolicy, error: String?) {
        guard let data = FileManager.default.contents(atPath: path) else { return (.default, nil) }
        do { return (RiskPolicy(rules: Self.default.rules, file: try PolicyFile.parse(data)), nil) }
        catch { return (.default, "\(URL(filePath: path).lastPathComponent): \(error)") }
    }
}
