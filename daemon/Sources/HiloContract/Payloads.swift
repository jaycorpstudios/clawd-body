import Foundation

public enum Risk: String, Codable, Sendable { case low, high }
public enum RequestKind: String, Codable, Sendable { case permission, question }
public enum Outcome: String, Codable, Sendable { case approved, denied, answered, expired }
public enum Via: String, Codable, Sendable { case mac, buddy, timeout }
public enum StepKind: String, Codable, Sendable { case plan, read, edit, run, ask, ok, deny, err }
public enum SessionStatus: String, Codable, Sendable { case working, waiting, done, error, idle }
public enum Decision: String, Codable, Sendable { case approve, deny }
public enum WakeSource: String, Codable, Sendable { case touch, button, longPress = "long_press", idle }
public enum Accessory: String, Codable, Sendable { case none, wizard, shades, headphones, crown, party, band, heart }

public struct DiffLine: Codable, Equatable, Sendable {
    public enum Change: String, Codable, Sendable { case added = "a", removed = "r" }
    public var change: Change
    public var text: String

    public init(_ change: Change, _ text: String) {
        self.change = change
        self.text = text
    }

    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        change = try c.decode(Change.self)
        text = try c.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(change)
        try c.encode(text)
    }
}

public struct SessionStart: Codable, Equatable, Sendable {
    public var session: String
    public var project: String
    public var task: String
    public init(session: String, project: String, task: String) {
        self.session = session; self.project = project; self.task = task
    }
}

public struct SessionRef: Codable, Equatable, Sendable {
    public var session: String
    public init(session: String) { self.session = session }
}

public struct PermissionRequest: Codable, Equatable, Sendable {
    public var requestId: String
    public var session: String
    public var project: String
    public var tool: String
    public var detail: String
    public var why: String?
    public var diff: [DiffLine]?
    public var cwd: String
    public var risk: Risk
    public var remoteAllowed: Bool
    public var expiresAt: Int

    public init(requestId: String, session: String, project: String, tool: String, detail: String, why: String? = nil,
                diff: [DiffLine]? = nil, cwd: String, risk: Risk, remoteAllowed: Bool, expiresAt: Int) {
        self.requestId = requestId; self.session = session; self.project = project; self.tool = tool
        self.detail = detail; self.why = why; self.diff = diff; self.cwd = cwd
        self.risk = risk; self.remoteAllowed = remoteAllowed; self.expiresAt = expiresAt
    }
}

public struct QuestionRequest: Codable, Equatable, Sendable {
    public var requestId: String
    public var session: String
    public var project: String
    public var detail: String
    public var options: [String]
    public var expiresAt: Int

    public init(requestId: String, session: String, project: String, detail: String, options: [String], expiresAt: Int) {
        self.requestId = requestId; self.session = session; self.project = project
        self.detail = detail; self.options = options; self.expiresAt = expiresAt
    }
}

public struct RequestResolved: Codable, Equatable, Sendable {
    public var requestId: String
    public var session: String
    public var kind: RequestKind
    public var outcome: Outcome
    public var via: Via
    public var choiceIndex: Int?

    public init(requestId: String, session: String, kind: RequestKind, outcome: Outcome, via: Via, choiceIndex: Int? = nil) {
        self.requestId = requestId; self.session = session; self.kind = kind
        self.outcome = outcome; self.via = via; self.choiceIndex = choiceIndex
    }
}

public struct TaskDone: Codable, Equatable, Sendable {
    public var session: String
    public var summary: String
    public init(session: String, summary: String) { self.session = session; self.summary = summary }
}

public struct AgentError: Codable, Equatable, Sendable {
    public var session: String
    public var detail: String
    public init(session: String, detail: String) { self.session = session; self.detail = detail }
}

public struct AgentStep: Codable, Equatable, Sendable {
    public var session: String
    public var kind: StepKind
    public var text: String
    public init(session: String, kind: StepKind, text: String) { self.session = session; self.kind = kind; self.text = text }
}

public struct Usage: Codable, Equatable, Sendable {
    public var sessionPct: Double
    public var weeklyPct: Double
    public var resetInMin: Int
    public var tokensToday: Int?
    public init(sessionPct: Double, weeklyPct: Double, resetInMin: Int, tokensToday: Int? = nil) {
        self.sessionPct = sessionPct; self.weeklyPct = weeklyPct; self.resetInMin = resetInMin; self.tokensToday = tokensToday
    }
}

public struct HiloTask: Codable, Equatable, Sendable {
    public var title: String
    public var project: String
    public var jira: String?
    public var startedAt: Int
    public init(title: String, project: String, jira: String? = nil, startedAt: Int) {
        self.title = title; self.project = project; self.jira = jira; self.startedAt = startedAt
    }
}

public struct HiloNext: Codable, Equatable, Sendable {
    public var title: String
    public var project: String
    public var jira: String?
    public init(title: String, project: String, jira: String? = nil) { self.title = title; self.project = project; self.jira = jira }
}

public struct Media: Codable, Equatable, Sendable {
    public var title: String
    public var artist: String
    public var lengthS: Int
    public var positionS: Int
    public init(title: String, artist: String, lengthS: Int, positionS: Int) {
        self.title = title; self.artist = artist; self.lengthS = lengthS; self.positionS = positionS
    }
}

public struct Step: Codable, Equatable, Sendable {
    public var ts: Int
    public var kind: StepKind
    public var text: String
    public init(ts: Int, kind: StepKind, text: String) { self.ts = ts; self.kind = kind; self.text = text }
}

public struct SessionState: Codable, Equatable, Sendable {
    public var session: String
    public var project: String
    public var task: String
    public var status: SessionStatus
    public var since: Int
    public var tokens: Int?
    public var summary: String?
    public var error: String?
    public var steps: [Step]?
    public var pendingPermission: PermissionRequest?
    public var pendingQuestion: QuestionRequest?

    public init(session: String, project: String, task: String, status: SessionStatus, since: Int, tokens: Int? = nil,
                summary: String? = nil, error: String? = nil, steps: [Step]? = nil,
                pendingPermission: PermissionRequest? = nil, pendingQuestion: QuestionRequest? = nil) {
        self.session = session; self.project = project; self.task = task; self.status = status; self.since = since
        self.tokens = tokens; self.summary = summary; self.error = error; self.steps = steps
        self.pendingPermission = pendingPermission; self.pendingQuestion = pendingQuestion
    }
}

public struct HiloState: Codable, Equatable, Sendable {
    public var current: HiloTask?
    public var next: [HiloNext]
    public var agreementsToday: [String]

    public init(current: HiloTask?, next: [HiloNext], agreementsToday: [String]) {
        self.current = current; self.next = next; self.agreementsToday = agreementsToday
    }

    private enum CodingKeys: String, CodingKey { case current, next, agreementsToday }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(current, forKey: .current)
        try c.encode(next, forKey: .next)
        try c.encode(agreementsToday, forKey: .agreementsToday)
    }
}

public struct Snapshot: Codable, Equatable, Sendable {
    public var sessions: [SessionState]
    public var usage: Usage
    public var hilo: HiloState
    public var media: Media?
    public init(sessions: [SessionState], usage: Usage, hilo: HiloState, media: Media? = nil) {
        self.sessions = sessions; self.usage = usage; self.hilo = hilo; self.media = media
    }
}

public struct Empty: Codable, Equatable, Sendable { public init() {} }

public struct PermissionDecision: Codable, Equatable, Sendable {
    public var requestId: String
    public var decision: Decision
    public init(requestId: String, decision: Decision) { self.requestId = requestId; self.decision = decision }
}

public struct QuestionAnswer: Codable, Equatable, Sendable {
    public var requestId: String
    public var choiceIndex: Int
    public var choice: String
    public init(requestId: String, choiceIndex: Int, choice: String) {
        self.requestId = requestId; self.choiceIndex = choiceIndex; self.choice = choice
    }
}

public struct DeviceAck: Codable, Equatable, Sendable {
    public var requestId: String
    public var seen: Bool
    public init(requestId: String) { self.requestId = requestId; self.seen = true }
}

public struct RequestRef: Codable, Equatable, Sendable {
    public var requestId: String
    public init(requestId: String) { self.requestId = requestId }
}

public struct Battery: Codable, Equatable, Sendable {
    public var pct: Int
    public var charging: Bool
    public init(pct: Int, charging: Bool) { self.pct = pct; self.charging = charging }
}

public struct SleepWake: Codable, Equatable, Sendable {
    public var by: WakeSource
    public init(by: WakeSource) { self.by = by }
}

public struct PetAccessory: Codable, Equatable, Sendable {
    public var acc: Accessory
    public init(acc: Accessory) { self.acc = acc }
}
