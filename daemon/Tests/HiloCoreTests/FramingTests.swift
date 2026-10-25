import Foundation
import Testing
@testable import HiloCore

private func message(_ n: Int) -> Data { Data((0..<n).map { UInt8(truncatingIfNeeded: $0) }) }

@Test(arguments: [(1, 20), (17, 20), (18, 20), (100, 20), (8 * 1024, 185), (8 * 1024, 512)])
func framesRoundTrip(size: Int, frameSize: Int) throws {
    let original = message(size)
    let frames = try Framing.frames(original, seq: 7, frameSize: frameSize)
    #expect(frames.allSatisfy { $0.count <= frameSize })
    var r = Framing.Reassembler()
    let outputs = frames.map { r.push($0) }
    #expect(outputs.dropLast().allSatisfy { $0 == nil })
    #expect(outputs.last! == original)
}

@Test func rejectsOversizedAndDegenerateInput() {
    #expect(throws: Framing.FramingError.tooLarge) { try Framing.frames(message(8 * 1024 + 1), seq: 0, frameSize: 244) }
    #expect(throws: Framing.FramingError.tooLarge) { try Framing.frames(Data(), seq: 0, frameSize: 244) }
    #expect(throws: Framing.FramingError.tooLarge) { try Framing.frames(message(300), seq: 0, frameSize: 4) }
    #expect(throws: Framing.FramingError.tooLarge) { try Framing.frames(message(8 * 1024), seq: 0, frameSize: 20) }
    #expect(throws: Framing.FramingError.frameTooSmall) { try Framing.frames(message(10), seq: 0, frameSize: 3) }
}

@Test func missingFrameDropsMessage() throws {
    let frames = try Framing.frames(message(50), seq: 1, frameSize: 20)
    var r = Framing.Reassembler()
    #expect(r.push(frames[0]) == nil)
    #expect(r.push(frames[2]) == nil)
    #expect(r.push(frames[1]) == nil)
}

@Test func newMessageReplacesPartialOne() throws {
    let first = try Framing.frames(message(50), seq: 1, frameSize: 20)
    let second = try Framing.frames(message(10), seq: 2, frameSize: 20)
    var r = Framing.Reassembler()
    _ = r.push(first[0])
    #expect(r.push(second[0]) == message(10))
    #expect(r.push(first[1]) == nil)
}

@Test func mixedSequenceIsRejected() throws {
    let a = try Framing.frames(message(50), seq: 1, frameSize: 20)
    let b = try Framing.frames(message(50), seq: 2, frameSize: 20)
    var r = Framing.Reassembler()
    _ = r.push(a[0])
    #expect(r.push(b[1]) == nil)
    #expect(r.push(a[1]) == nil)
}

@Test func malformedHeaderIsRejected() {
    var r = Framing.Reassembler()
    #expect(r.push(Data([0, 0])) == nil)
    #expect(r.push(Data([0, 2, 2, 65])) == nil)
    #expect(r.push(Data([0, 0, 0, 65])) == nil)
}
