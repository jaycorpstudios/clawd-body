import Foundation
import HiloContract

public struct ToolCall: Sendable {
    public var tool: String
    public var input: [String: String]
    public var cwd: String
    public var repoRoot: String?

    public init(tool: String, input: [String: String], cwd: String, repoRoot: String?) {
        self.tool = tool; self.input = input; self.cwd = cwd; self.repoRoot = repoRoot
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

    public init(rules: [RiskRule]) { self.rules = rules }

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
        return matches ? .low : .high
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
