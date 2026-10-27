import CoreGraphics
import Foundation
import IOKit

public struct SystemPresence: PresenceProbe {
    public var idleThresholdSeconds: Double

    public init(idleThresholdSeconds: Double) {
        self.idleThresholdSeconds = idleThresholdSeconds
    }

    public func userIsPresent() -> Bool {
        !Self.screenIsLocked() && (Self.idleSeconds() ?? .infinity) < idleThresholdSeconds
    }

    public func quiet(for seconds: Double) -> Bool {
        Self.screenIsLocked() || (Self.idleSeconds() ?? .infinity) >= seconds
    }

    static func screenIsLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return true }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    static func idleSeconds() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let value = IORegistryEntryCreateCFProperty(service, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? NSNumber else { return nil }
        return value.doubleValue / 1_000_000_000
    }
}
