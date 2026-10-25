import Foundation
import HiloCore

public enum LinkEvent: Sendable, Equatable {
    case up(frameSize: Int)
    case down
    case frame(Data)
}

public protocol FrameWriter: Sendable {
    /// Writes one frame and waits for the buddy to acknowledge it.
    func write(_ frame: Data) async -> Bool
}

/// Contract messages over one buddy link: framing, one message on the air at a time, snapshot on every link up.
public actor BuddySession: BuddyLink {
    public typealias Handler = @Sendable (Data) async -> Void

    private let writer: FrameWriter
    private var frameSize: Int?
    private var seq: UInt8 = 0
    private var reassembler = Framing.Reassembler()
    private var tail: Task<Void, Never>?
    private var onUp: @Sendable () async -> Void = {}
    private var onMessage: Handler = { _ in }

    public init(writer: FrameWriter) {
        self.writer = writer
    }

    public func setHandlers(onUp: @escaping @Sendable () async -> Void, onMessage: @escaping Handler) {
        self.onUp = onUp
        self.onMessage = onMessage
    }

    public var isUp: Bool { frameSize != nil }

    public func handle(_ event: LinkEvent) async {
        switch event {
        case .up(let size):
            frameSize = size
            reassembler = Framing.Reassembler()
            await onUp()
        case .down:
            frameSize = nil
            reassembler = Framing.Reassembler()
        case .frame(let frame):
            if let message = reassembler.push(frame) { await onMessage(message) }
        }
    }

    /// Dropped while the link is down: the next link up sends a full snapshot.
    public func send(_ data: Data) async {
        guard let frameSize, let frames = try? Framing.frames(data, seq: seq, frameSize: frameSize) else { return }
        seq &+= 1
        let previous = tail
        let writer = writer
        let task = Task {
            await previous?.value
            for frame in frames {
                guard await writer.write(frame) else { return }
            }
        }
        tail = task
        await task.value
    }
}
