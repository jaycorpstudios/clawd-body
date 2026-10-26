import Foundation
import HiloContract

/// The `rate_limits` object Claude Code hands its status line command.
public struct RateLimits: Codable, Equatable, Sendable {
    public struct Window: Codable, Equatable, Sendable {
        public var usedPercentage: Double
        public var resetsAt: Int
        public init(usedPercentage: Double, resetsAt: Int) { self.usedPercentage = usedPercentage; self.resetsAt = resetsAt }
        enum CodingKeys: String, CodingKey { case usedPercentage = "used_percentage", resetsAt = "resets_at" }
    }

    public var fiveHour: Window?
    public var sevenDay: Window?
    public init(fiveHour: Window? = nil, sevenDay: Window? = nil) { self.fiveHour = fiveHour; self.sevenDay = sevenDay }
    enum CodingKeys: String, CodingKey { case fiveHour = "five_hour", sevenDay = "seven_day" }

    /// Picks `rate_limits` out of a full status line payload; nil when it carries none.
    public static func fromStatusLine(_ data: Data) -> RateLimits? {
        struct Payload: Decodable { var rate_limits: RateLimits? }
        guard let limits = (try? JSONDecoder().decode(Payload.self, from: data))?.rate_limits,
              limits.fiveHour != nil || limits.sevenDay != nil else { return nil }
        return limits
    }
}

public struct UsageTracker: Sendable {
    public static let windowMinutes = 300

    private var limits = RateLimits()
    private var tokensToday: Int?
    private var lastSent: Usage?

    public init() {}

    public func usage(now: Int) -> Usage {
        let five = limits.fiveHour.flatMap { $0.resetsAt > now ? $0 : nil }
        let week = limits.sevenDay.flatMap { $0.resetsAt > now ? $0 : nil }
        let reset = five.map { min(Self.windowMinutes, max(0, ($0.resetsAt - now + 59) / 60)) } ?? 0
        return Usage(sessionPct: Self.pct(five?.usedPercentage), weeklyPct: Self.pct(week?.usedPercentage),
                     resetInMin: reset, tokensToday: tokensToday)
    }

    public mutating func update(_ new: RateLimits, now: Int) -> [Outbound] {
        let previous = limits.fiveHour
        if new.fiveHour != nil { limits.fiveHour = new.fiveHour }
        if new.sevenDay != nil { limits.sevenDay = new.sevenDay }
        var out: [Outbound] = []
        if let previous, let next = new.fiveHour, next.resetsAt > previous.resetsAt + 60 {
            out.append(.usageWindowReset)
        }
        return out + changed(now: now)
    }

    public mutating func update(tokensToday: Int, now: Int) -> [Outbound] {
        self.tokensToday = tokensToday
        return changed(now: now)
    }

    /// Only percent, window or token changes are sent: the buddy counts the reset down by itself.
    private mutating func changed(now: Int) -> [Outbound] {
        let current = usage(now: now)
        let rounded = { (u: Usage?) in u.map { [Int($0.sessionPct), Int($0.weeklyPct), $0.tokensToday ?? -1] } }
        let windowMoved = abs((lastSent?.resetInMin ?? -10) - current.resetInMin) > 2
        guard rounded(current) != rounded(lastSent) || windowMoved else { return [] }
        lastSent = current
        return [.usageUpdate(current)]
    }

    private static func pct(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return 0 }
        return min(100, max(0, (value * 10).rounded() / 10))
    }
}
