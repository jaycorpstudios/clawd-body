import Foundation

public enum ULID {
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    public static func make(now: Date = Date()) -> String {
        var time = UInt64(max(0, now.timeIntervalSince1970 * 1000))
        var head = [Character](repeating: "0", count: 10)
        for i in stride(from: 9, through: 0, by: -1) {
            head[i] = alphabet[Int(time % 32)]
            time /= 32
        }
        var rng = SystemRandomNumberGenerator()
        let tail = (0..<16).map { _ in alphabet[Int(rng.next(upperBound: UInt8(32)))] }
        return String(head + tail)
    }

    public static func isValid(_ s: String) -> Bool {
        s.count == 26 && s.allSatisfy { alphabet.contains($0) }
    }
}
