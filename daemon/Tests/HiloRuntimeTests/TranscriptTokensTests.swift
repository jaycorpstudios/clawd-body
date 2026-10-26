import Foundation
import Testing
@testable import HiloRuntime

@Suite struct TranscriptTokensTests {
    let dir = FileManager.default.temporaryDirectory.appending(path: "hilo-transcripts-\(UUID().uuidString)")
    let now = ISO8601DateFormatter().date(from: "2026-10-25T15:00:00Z")!
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    func assistant(_ id: String, at time: String, input: Int, output: Int, cacheWrite: Int = 0, cacheRead: Int = 0) -> String {
        #"{"type":"assistant","timestamp":"\#(time)","message":{"id":"\#(id)","usage":{"input_tokens":\#(input),"output_tokens":\#(output),"cache_creation_input_tokens":\#(cacheWrite),"cache_read_input_tokens":\#(cacheRead)}}}"#
    }

    func write(_ name: String, _ lines: [String], append: Bool = false) throws {
        let url = dir.appending(path: name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = lines.map { $0 + "\n" }.joined()
        if append, let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try handle.close()
        } else {
            try Data(text.utf8).write(to: url)
        }
    }

    @Test func countsTodayOncePerMessageAndSkipsCacheReads() throws {
        try write("proj-a/s1.jsonl", [
            assistant("m1", at: "2026-10-25T09:00:00.100Z", input: 10, output: 5, cacheWrite: 100, cacheRead: 9_000),
            assistant("m1", at: "2026-10-25T09:00:00.200Z", input: 10, output: 5, cacheWrite: 100, cacheRead: 9_000),
            assistant("m0", at: "2026-10-24T23:59:59.000Z", input: 1_000, output: 1_000),
            #"{"type":"user","timestamp":"2026-10-25T09:00:00.000Z","message":{"role":"user","content":"usage please"}}"#,
        ])
        try write("proj-b/sub/agent.jsonl", [assistant("m2", at: "2026-10-25T10:00:00.000Z", input: 1, output: 2)])
        let tokens = TranscriptTokens(root: dir)
        #expect(tokens.scan(now: now, calendar: calendar) == 118)
    }

    @Test func readsOnlyNewCompleteLinesOnTheNextScan() throws {
        try write("p/s.jsonl", [assistant("m1", at: "2026-10-25T09:00:00.000Z", input: 1, output: 1)])
        let tokens = TranscriptTokens(root: dir)
        #expect(tokens.scan(now: now, calendar: calendar) == 2)
        let url = dir.appending(path: "p/s.jsonl")
        let handle = try FileHandle(forWritingTo: url)
        handle.seekToEndOfFile()
        handle.write(Data((assistant("m2", at: "2026-10-25T09:01:00.000Z", input: 3, output: 3) + "\n").utf8))
        handle.write(Data(#"{"type":"assistant","timestamp":"2026-10-25T09:02:00.000Z","message":{"id":"m3","usage":{"input_tok"#.utf8))
        try handle.close()
        #expect(tokens.scan(now: now, calendar: calendar) == 8)
        try write("p/s.jsonl", [#"ens":4,"output_tokens":0}}}"#], append: true)
        #expect(tokens.scan(now: now, calendar: calendar) == 12)
    }

    @Test func aNewDayStartsFromZero() throws {
        try write("p/s.jsonl", [assistant("m1", at: "2026-10-25T09:00:00.000Z", input: 5, output: 5)])
        let tokens = TranscriptTokens(root: dir)
        #expect(tokens.scan(now: now, calendar: calendar) == 10)
        #expect(tokens.scan(now: now.addingTimeInterval(86_400), calendar: calendar) == 0)
    }
}
