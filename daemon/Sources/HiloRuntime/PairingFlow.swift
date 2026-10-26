import Foundation

public enum PairingState: String, Codable, Sendable {
    case idle, scanning, connecting, paired, failed
    case timedOut = "timed_out"
}

/// Pairing as the Hilo app sees it: scan for a buddy in pairing mode, connect, wait for the passkey, done.
/// The buddy leaves pairing mode after 60 s, so each phase gets the same budget.
public struct PairingFlow: Sendable {
    public static let phaseSeconds = 60

    public private(set) var state: PairingState = .idle
    public private(set) var buddyName: String?
    private var deadline = 0

    public init() {}

    public var active: Bool { state == .scanning || state == .connecting }

    public mutating func start(now: Int) -> Bool {
        guard !active else { return false }
        state = .scanning
        buddyName = nil
        deadline = now + Self.phaseSeconds
        return true
    }

    public mutating func found(name: String, now: Int) {
        guard state == .scanning else { return }
        state = .connecting
        buddyName = name
        deadline = now + Self.phaseSeconds
    }

    public mutating func secured() {
        if state == .connecting { state = .paired }
    }

    public mutating func linkLost() {
        if state == .connecting { state = .failed }
    }

    public mutating func cancel() {
        if active { state = .idle }
    }

    /// True when the current phase just ran out; the caller stops scanning or drops the half-made link.
    public mutating func expire(now: Int) -> Bool {
        guard active, now >= deadline else { return false }
        state = .timedOut
        return true
    }
}
