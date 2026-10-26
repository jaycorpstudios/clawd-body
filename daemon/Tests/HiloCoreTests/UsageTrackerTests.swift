import Foundation
import Testing
import HiloContract
@testable import HiloCore

@Suite struct UsageTrackerTests {
    let now = 1_792_900_000

    @Test func statusLinePayloadYieldsOnlyRateLimits() throws {
        let json = #"""
        {"session_id":"x","cwd":"/tmp","model":{"display_name":"Opus"},
         "rate_limits":{"five_hour":{"used_percentage":41.27,"resets_at":1792903600},"seven_day":{"used_percentage":12,"resets_at":1793400000}}}
        """#
        let limits = try #require(RateLimits.fromStatusLine(Data(json.utf8)))
        #expect(limits.fiveHour == .init(usedPercentage: 41.27, resetsAt: 1_792_903_600))
        #expect(limits.sevenDay?.usedPercentage == 12)
        #expect(RateLimits.fromStatusLine(Data(#"{"cwd":"/tmp"}"#.utf8)) == nil)
        #expect(RateLimits.fromStatusLine(Data("not json".utf8)) == nil)
    }

    @Test func usageFollowsTheLimitsAndClampsToTheSchema() {
        var tracker = UsageTracker()
        let out = tracker.update(RateLimits(fiveHour: .init(usedPercentage: 104.4, resetsAt: now + 3_601),
                                            sevenDay: .init(usedPercentage: 38.26, resetsAt: now + 86_400)), now: now)
        #expect(out == [.usageUpdate(Usage(sessionPct: 100, weeklyPct: 38.3, resetInMin: 61))])
        #expect(tracker.usage(now: now + 3_601).sessionPct == 0)
        #expect(tracker.usage(now: now + 3_601).resetInMin == 0)
    }

    @Test func repeatedStatusLinesDoNotResendTheSameUsage() {
        var tracker = UsageTracker()
        let limits = RateLimits(fiveHour: .init(usedPercentage: 20.1, resetsAt: now + 7_200))
        #expect(tracker.update(limits, now: now).count == 1)
        #expect(tracker.update(limits, now: now + 30).isEmpty)
        #expect(tracker.update(RateLimits(fiveHour: .init(usedPercentage: 20.6, resetsAt: now + 7_200)), now: now + 60).isEmpty)
        #expect(tracker.update(RateLimits(fiveHour: .init(usedPercentage: 21.0, resetsAt: now + 7_200)), now: now + 90).count == 1)
    }

    @Test func aNewFiveHourWindowSendsWindowResetFirst() {
        var tracker = UsageTracker()
        _ = tracker.update(RateLimits(fiveHour: .init(usedPercentage: 90, resetsAt: now + 60)), now: now)
        let out = tracker.update(RateLimits(fiveHour: .init(usedPercentage: 2, resetsAt: now + 18_000)), now: now + 120)
        #expect(out.first == .usageWindowReset)
        #expect(out.last == .usageUpdate(Usage(sessionPct: 2, weeklyPct: 0, resetInMin: 298)))
    }

    @Test func tokensAloneAreSentAndKeptAcrossLimitUpdates() {
        var tracker = UsageTracker()
        #expect(tracker.update(tokensToday: 1_200, now: now) == [.usageUpdate(Usage(sessionPct: 0, weeklyPct: 0, resetInMin: 0, tokensToday: 1_200))])
        #expect(tracker.update(tokensToday: 1_200, now: now + 60).isEmpty)
        let out = tracker.update(RateLimits(sevenDay: .init(usedPercentage: 5, resetsAt: now + 9_000)), now: now + 60)
        #expect(out == [.usageUpdate(Usage(sessionPct: 0, weeklyPct: 5, resetInMin: 0, tokensToday: 1_200))])
    }
}
