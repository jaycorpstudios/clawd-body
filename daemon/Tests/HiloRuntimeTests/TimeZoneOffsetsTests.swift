import Foundation
import Testing
import HiloContract
@testable import HiloRuntime

@Suite struct TimeZoneOffsetsTests {
    @Test func choicesAreValidSortedAndIncludeTheDefault() {
        #expect(TimeZoneOffsets.choices.allSatisfy(DeviceSettings.validTz))
        #expect(TimeZoneOffsets.choices == TimeZoneOffsets.choices.sorted())
        #expect(Set(TimeZoneOffsets.choices).count == TimeZoneOffsets.choices.count)
        #expect(TimeZoneOffsets.choices.contains(DeviceSettings.defaultTzOffsetMin))
        #expect(TimeZoneOffsets.choices.first == -720 && TimeZoneOffsets.choices.last == 840)
    }

    @Test func labelsReadLikeUTCOffsets() {
        #expect(TimeZoneOffsets.label(-360) == "UTC−06:00")
        #expect(TimeZoneOffsets.label(345) == "UTC+05:45")
        #expect(TimeZoneOffsets.label(0) == "UTC+00:00")
    }

    @Test func thisMacsOffsetFollowsItsZoneAndDST() throws {
        let mexico = try #require(TimeZone(identifier: "America/Mexico_City"))
        #expect(TimeZoneOffsets.current(mexico, at: Date(timeIntervalSince1970: 1_792_900_000)) == -360)
        let madrid = try #require(TimeZone(identifier: "Europe/Madrid"))
        let july = Date(timeIntervalSince1970: 1_783_000_000)
        #expect(TimeZoneOffsets.current(madrid, at: july) == 120)
        let kathmandu = try #require(TimeZone(identifier: "Asia/Kathmandu"))
        #expect(TimeZoneOffsets.current(kathmandu) == 345)
    }
}
