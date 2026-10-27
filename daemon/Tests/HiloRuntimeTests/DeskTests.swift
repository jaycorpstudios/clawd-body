import CoreGraphics
import Foundation
import Testing
import HiloContract
import HiloCore
@testable import HiloRuntime

actor DeskLink: BuddyLink {
    var raw: [Data] = []
    func send(_ data: Data) async { raw.append(data) }
    func decoded() -> [Outbound] { raw.compactMap { try? Wire.decodeOutbound($0).body } }
    func types() -> [String] { decoded().map(\.type) }
}

struct DeskAway: PresenceProbe { func userIsPresent() -> Bool { false } }

func buddyMessage(_ type: String, _ data: String) -> Data {
    Data(#"{"v":1,"id":"\#(ULID.make())","ts":1000,"type":"\#(type)","data":\#(data)}"#.utf8)
}

@Suite struct SettingsFlowTests {
    let link = DeskLink()
    let coordinator: Coordinator

    init() {
        coordinator = Coordinator(host: "work", mapper: HookMapper(repoRoot: { _ in nil }), link: link, presence: DeskAway())
    }

    @Test func changeIsSentAndOnlyTheBuddysAnswerIsReported() async throws {
        #expect(await coordinator.changeSettings(SettingsChange(sound: true, volume: 0)))
        #expect(await link.decoded() == [.settingsSet(SettingsChange(sound: true, volume: 0))])
        #expect(await coordinator.settings == nil)
        try await coordinator.handleBuddy(buddyMessage("device.settings", #"{"sound":true,"volume":0,"brightness":80}"#))
        #expect(await coordinator.settings == DeviceSettings(sound: true, volume: 0, brightness: 80))
        await coordinator.buddyLink(up: false)
        #expect(await coordinator.settings == nil)
    }

    @Test func invalidChangesAreNotSent() async {
        #expect(await coordinator.changeSettings(SettingsChange()) == false)
        #expect(await coordinator.changeSettings(SettingsChange(volume: 101)) == false)
        #expect(await coordinator.changeSettings(SettingsChange(brightness: 9)) == false)
        #expect(await link.raw.isEmpty)
    }

    @Test func settingsOpForwardsAndStatusCarriesTheReport() async throws {
        let ops = ControlOps(coordinator: coordinator, buddy: nil, configPath: "/nonexistent/config.json", tokensFromTranscripts: false)
        let rejected = String(decoding: await ops.handle(op: "settings", body: Data(#"{"volume":300}"#.utf8)) ?? Data(), as: UTF8.self)
        #expect(rejected.hasPrefix("rejected"))
        _ = await ops.handle(op: "settings", body: Data(#"{"brightness":40}"#.utf8))
        #expect(await link.decoded() == [.settingsSet(SettingsChange(brightness: 40))])
        try await coordinator.handleBuddy(buddyMessage("device.settings", #"{"sound":false,"volume":60,"brightness":40}"#))
        let status = try JSONDecoder().decode(DaemonStatus.self, from: try #require(await ops.handle(op: "status", body: Data())))
        #expect(status.settings == DeviceSettings(sound: false, volume: 60, brightness: 40))
    }
}

private func solidImage(width: Int, height: Int, rgb: (UInt8, UInt8, UInt8)) -> CGImage {
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    for i in 0..<(width * height) { (bytes[i * 4], bytes[i * 4 + 1], bytes[i * 4 + 2]) = rgb }
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                   space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}

@Suite struct FaceTests {
    @Test func rendersAFixedRGB565SquareInChunksUnderTheCap() throws {
        let face = try #require(FaceImage.render(solidImage(width: 300, height: 200, rgb: (255, 0, 0))))
        #expect(face.pixels.count == FaceImage.side * FaceImage.side * 2)
        #expect(face.pixels.prefix(2) == Data([0x00, 0xF8]))
        let chunks = face.chunks
        #expect(chunks.count == 7)
        #expect(chunks.allSatisfy { $0.data.count <= 6000 && $0.count == 7 && $0.hash == face.hash && $0.w == 120 && $0.h == 120 })
        let joined = chunks.reduce(Data()) { $0 + Data(base64Encoded: $1.data)! }
        #expect(joined == face.pixels)
        for chunk in chunks {
            let bytes = try Wire.encode(.face(chunk), host: "work")
            #expect(bytes.count < 8 * 1024)
        }
    }

    @Test func hashMatchesTheSharedFixture() throws {
        let url = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../shared/fixtures/valid/host.face.json").standardized
        guard case .face(let chunk) = try Wire.decodeOutbound(Data(contentsOf: url)).body else { Issue.record("not a face"); return }
        #expect(FaceImage(pixels: try #require(Data(base64Encoded: chunk.data))).hash == chunk.hash)
    }

    @Test func coordinatorSendsTheFaceAnswersRequestsAndClearsIt() async throws {
        let link = DeskLink()
        let coordinator = Coordinator(host: "work", mapper: HookMapper(repoRoot: { _ in nil }), link: link, presence: DeskAway())
        let face = try #require(FaceImage.render(solidImage(width: 64, height: 64, rgb: (0, 0, 255))))
        await coordinator.setFace(face)
        #expect(await link.types() == Array(repeating: "host.face", count: 7) + ["snapshot"])
        guard case .snapshot(let snap) = await link.decoded().last else { Issue.record("no snapshot"); return }
        #expect(snap.face == FaceRef(hash: face.hash))

        try await coordinator.handleBuddy(buddyMessage("device.face_request", #"{"hash":"\#(face.hash)"}"#))
        #expect(await link.types().count == 15)
        try await coordinator.handleBuddy(buddyMessage("device.face_request", #"{"hash":"0123456789abcdef"}"#))
        #expect(await link.types().count == 15)

        await coordinator.setFace(nil)
        guard case .snapshot(let cleared) = await link.decoded().last else { Issue.record("no snapshot"); return }
        #expect(cleared.face == nil)
        #expect(await coordinator.faceHash == nil)
    }
}
