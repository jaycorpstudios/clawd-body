import Foundation

/// Splits contract messages into GATT-sized frames: `[seq, index, count] + chunk`.
public enum Framing {
    public static let headerSize = 3
    public static let maxMessageSize = 8 * 1024

    public enum FramingError: Error, Equatable { case tooLarge, frameTooSmall }

    public static func frames(_ message: Data, seq: UInt8, frameSize: Int) throws(FramingError) -> [Data] {
        let chunk = frameSize - headerSize
        guard chunk > 0 else { throw .frameTooSmall }
        guard !message.isEmpty, message.count <= maxMessageSize else { throw .tooLarge }
        let count = (message.count + chunk - 1) / chunk
        guard count <= Int(UInt8.max) else { throw .tooLarge }
        return (0..<count).map { i in
            let start = message.startIndex + i * chunk
            let body = message[start..<min(start + chunk, message.endIndex)]
            return Data([seq, UInt8(i), UInt8(count)]) + body
        }
    }

    public struct Reassembler: Sendable {
        private var seq: UInt8?
        private var expected = 0
        private var buffer = Data()

        public init() {}

        /// Returns a complete message on its last frame; out-of-order or malformed frames drop the partial message.
        public mutating func push(_ frame: Data) -> Data? {
            guard frame.count > headerSize else { reset(); return nil }
            let bytes = [UInt8](frame.prefix(headerSize))
            let (seq, index, count) = (bytes[0], Int(bytes[1]), Int(bytes[2]))
            let body = frame.dropFirst(headerSize)
            guard count > 0, index < count else { reset(); return nil }

            if index == 0 {
                self.seq = seq
                expected = 0
                buffer = Data()
            }
            guard self.seq == seq, index == expected else { reset(); return nil }
            buffer.append(body)
            expected += 1
            guard buffer.count <= maxMessageSize else { reset(); return nil }
            guard expected == count else { return nil }
            defer { reset() }
            return buffer
        }

        private mutating func reset() {
            seq = nil
            expected = 0
            buffer = Data()
        }
    }
}
