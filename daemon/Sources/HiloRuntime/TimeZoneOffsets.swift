import Foundation
import HiloContract

/// The offsets Hilo › Setup offers for the buddy's clock. No DST: a region with DST picks again or uses this Mac's.
public enum TimeZoneOffsets {
    /// Every whole hour plus the half and quarter hours in use somewhere.
    public static let choices: [Int] = (Array(stride(from: -720, through: 840, by: 60))
        + [-570, -210, 210, 270, 330, 345, 390, 525, 570, 630, 765]).sorted()

    public static func label(_ minutes: Int) -> String {
        let sign = minutes < 0 ? "−" : "+"
        let m = abs(minutes)
        return String(format: "UTC%@%02d:%02d", sign, m / 60, m % 60)
    }

    /// This Mac's offset right now, or nil when it is not one the buddy accepts.
    public static func current(_ zone: TimeZone = .current, at date: Date = Date()) -> Int? {
        let minutes = zone.secondsFromGMT(for: date) / 60
        return DeviceSettings.validTz(minutes) ? minutes : nil
    }
}
