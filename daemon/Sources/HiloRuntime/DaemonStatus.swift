import Foundation
import HiloContract

public struct BuddyStatus: Codable, Equatable, Sendable {
    public enum Link: String, Codable, Sendable {
        case connected, disconnected, unauthorized
        case notPaired = "not_paired", bluetoothOff = "bluetooth_off", noBluetooth = "no_bluetooth"
    }

    public var link: Link
    public var pairing: PairingState
    public var buddyName: String?

    public init(link: Link, pairing: PairingState = .idle, buddyName: String? = nil) {
        self.link = link; self.pairing = pairing; self.buddyName = buddyName
    }

    enum CodingKeys: String, CodingKey { case link, pairing, buddyName = "buddy_name" }
}

/// Reply to the socket op `status`, read by the Hilo app.
public struct DaemonStatus: Codable, Equatable, Sendable {
    public var host: String
    public var buddy: BuddyStatus
    public var tokensFromTranscripts: Bool
    public var settings: DeviceSettings?

    public init(host: String, buddy: BuddyStatus, tokensFromTranscripts: Bool, settings: DeviceSettings? = nil) {
        self.host = host; self.buddy = buddy; self.tokensFromTranscripts = tokensFromTranscripts; self.settings = settings
    }

    enum CodingKeys: String, CodingKey { case host, buddy, tokensFromTranscripts = "tokens_from_transcripts", settings }
}
