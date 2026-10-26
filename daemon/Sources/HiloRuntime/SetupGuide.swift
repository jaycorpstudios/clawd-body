import Foundation

/// How the Hilo app runs `hilod`: a per-user launchd job, so macOS ties the Bluetooth permission to `hilod` itself.
public struct LaunchAgent: Sendable {
    public static let label = "dev.hilo.hilod"

    public let logPath: String

    public static var defaultLogPath: String {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/Hilo/hilod.log").path(percentEncoded: false)
    }

    public init(logPath: String = LaunchAgent.defaultLogPath) { self.logPath = logPath }

    public func submitArguments(hilod: String) -> [String] {
        ["submit", "-l", Self.label, "-o", logPath, "-e", logPath, "--", hilod]
    }

    public var removeArguments: [String] { ["remove", Self.label] }
}

public struct PairingGuide: Equatable, Sendable {
    public var title: String
    public var detail: String
    public var active: Bool

    public init(title: String, detail: String, active: Bool) { self.title = title; self.detail = detail; self.active = active }

    public static func describe(_ buddy: BuddyStatus) -> PairingGuide {
        let name = buddy.buddyName ?? "the buddy"
        switch buddy.pairing {
        case .scanning:
            return .init(title: "Looking for the buddy…", detail: "Keep the pairing screen open on the buddy.", active: true)
        case .connecting:
            return .init(title: "Found \(name)", detail: "macOS asks for a code: type the 6 digits shown on the buddy.", active: true)
        case .paired:
            return .init(title: "Paired with \(name)", detail: "From now on hilod reconnects by itself.", active: false)
        case .failed:
            return .init(title: "Pairing did not finish", detail: "The code was wrong or the dialog was closed. Open the pairing screen again and retry.", active: false)
        case .timedOut:
            return .init(title: "No buddy answered", detail: "Hold the side button 5 s on Home until the pairing screen shows, then retry.", active: false)
        case .idle:
            switch buddy.link {
            case .connected: return .init(title: "Buddy connected", detail: "This Mac is paired and the link is up.", active: false)
            case .disconnected: return .init(title: "Buddy paired, not in range", detail: "hilod reconnects when the buddy is on and nearby.", active: false)
            case .notPaired: return .init(title: "No buddy paired yet", detail: "Hold the side button 5 s on the buddy's Home view, then start pairing.", active: false)
            case .bluetoothOff: return .init(title: "Bluetooth is off", detail: "Turn Bluetooth on to reach the buddy.", active: false)
            case .unauthorized: return .init(title: "hilod has no Bluetooth permission", detail: "Allow it in System Settings › Privacy & Security › Bluetooth.", active: false)
            case .noBluetooth: return .init(title: "hilod runs without Bluetooth", detail: "It was started with --stdout.", active: false)
            }
        }
    }
}
