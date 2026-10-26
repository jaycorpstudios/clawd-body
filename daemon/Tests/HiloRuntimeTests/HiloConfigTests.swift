import Foundation
import Testing
@testable import HiloRuntime

@Suite struct HiloConfigTests {
    @Test func displayNamesBecomeContractHosts() {
        #expect(HiloConfig.hostName(from: "Work") == "work")
        #expect(HiloConfig.hostName(from: "  Home Mac ") == "home-mac")
        #expect(HiloConfig.hostName(from: "Café_Studio #2") == "cafe-studio-2")
        #expect(HiloConfig.hostName(from: "a very long laptop name") == "a-very-long-lapt")
        #expect(HiloConfig.hostName(from: "abcdefghijklmno pq") == "abcdefghijklmno")
        #expect(HiloConfig.hostName(from: "!!!") == nil)
        #expect(HiloConfig.hostName(from: "") == nil)
    }

    @Test func savesAndLoadsWithSnakeCaseKeys() throws {
        let path = FileManager.default.temporaryDirectory.appending(path: "hilo-config-\(UUID().uuidString)/config.json")
            .path(percentEncoded: false)
        #expect(HiloConfig.load(path: path) == HiloConfig())
        try HiloConfig(host: "home", tokensFromTranscripts: true).save(path: path)
        #expect(HiloConfig.load(path: path) == HiloConfig(host: "home", tokensFromTranscripts: true))
        let text = String(decoding: FileManager.default.contents(atPath: path) ?? Data(), as: UTF8.self)
        #expect(text.contains("tokens_from_transcripts"))
    }
}
