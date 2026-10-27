import CoreGraphics
import Foundation
import ImageIO
import Testing
import HiloContract
import HiloCore
@testable import HiloRuntime

private func png(width: Int, height: Int, rgb: (UInt8, UInt8, UInt8)) -> Data {
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    for i in 0..<(width * height) { (bytes[i * 4], bytes[i * 4 + 1], bytes[i * 4 + 2]) = rgb }
    let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                        provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    let out = NSMutableData()
    let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    return out as Data
}

private let song = Media(title: "Low Tide", artist: "The Pixels", lengthS: 214, positionS: 10, playing: true)

@Suite struct CoverImageTests {
    @Test func aCoverIs96SquareInFiveChunksUnderTheCap() throws {
        let cover = try #require(RGB565Image.decode(png(width: 640, height: 640, rgb: (255, 0, 0)), side: RGB565Image.coverSide))
        #expect(cover.pixels.count == 96 * 96 * 2)
        #expect(cover.pixels.prefix(2) == Data([0x00, 0xF8]))
        let chunks = cover.chunks
        #expect(chunks.count == 5)
        #expect(chunks.allSatisfy { $0.w == 96 && $0.h == 96 && $0.count == 5 && $0.data.count <= 6000 })
        #expect(chunks.reduce(Data()) { $0 + Data(base64Encoded: $1.data)! } == cover.pixels)
        for chunk in chunks { #expect(try Wire.encode(.cover(chunk), host: "work").count < 8 * 1024) }
    }

    @Test func garbageIsNoCover() {
        #expect(RGB565Image.decode(Data("not an image".utf8), side: RGB565Image.coverSide) == nil)
    }

    @Test func hashMatchesTheSharedFixture() throws {
        let url = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../shared/fixtures/valid/media.cover.json").standardized
        guard case .cover(let chunk) = try Wire.decodeOutbound(Data(contentsOf: url)).body else { Issue.record("not a cover"); return }
        #expect(RGB565Image(pixels: try #require(Data(base64Encoded: chunk.data)), side: chunk.w).hash == chunk.hash)
    }
}

@Suite struct CoverFlowTests {
    let link = DeskLink()
    let clock = DeskClock(10_000)
    let player = FakePlayer()
    let coordinator: Coordinator

    init() {
        coordinator = Coordinator(host: "work", mapper: HookMapper(repoRoot: { _ in nil }), link: link, presence: DeskAway(), clock: clock)
    }

    func nowPlaying() async -> [Media] {
        await link.decoded().compactMap { if case .nowPlaying(let m) = $0 { m } else { nil } }
    }

    @Test func theCoverFollowsTheTrackAndIsSentOnlyWhenAsked() async throws {
        player.cover = png(width: 300, height: 300, rgb: (0, 0, 255))
        await coordinator.setPlayer(player)
        await coordinator.updateMedia(song)
        try await until { await nowPlaying().count == 2 }
        let first = await nowPlaying()
        #expect(first[0].cover == nil)
        let hash = try #require(first[1].cover?.hash)
        #expect(first[1].title == song.title)
        #expect(await coordinator.coverHash == hash)
        #expect(!(await link.types()).contains("media.cover"))

        try await coordinator.handleBuddy(buddyMessage("device.cover_request", #"{"hash":"\#(hash)"}"#, ts: clock.now()))
        let chunks = await link.decoded().compactMap { if case .cover(let c) = $0 { c } else { nil } }
        #expect(chunks.count == 5 && chunks.allSatisfy { $0.hash == hash })
        try await coordinator.handleBuddy(buddyMessage("device.cover_request", #"{"hash":"0123456789abcdef"}"#, ts: clock.now()))
        #expect(await link.types().filter { $0 == "media.cover" }.count == 5)

        await coordinator.sendSnapshot()
        guard case .snapshot(let snap) = await link.decoded().last else { Issue.record("no snapshot"); return }
        #expect(snap.media?.cover == ImageRef(hash: hash))

        clock.set(10_005)
        await coordinator.updateMedia(Media(title: "Low Tide", artist: "The Pixels", lengthS: 214, positionS: 15, playing: true))
        #expect(await nowPlaying().count == 2)

        player.cover = nil
        await coordinator.updateMedia(Media(title: "Fan Noise", artist: "Tabstop", lengthS: 180, positionS: 0, playing: true))
        #expect(await nowPlaying().last?.cover == nil)
        #expect(await coordinator.coverHash == nil)
        try await coordinator.handleBuddy(buddyMessage("device.cover_request", #"{"hash":"\#(hash)"}"#, ts: clock.now()))
        #expect(await link.types().filter { $0 == "media.cover" }.count == 5)
    }

    @Test func aCoverThatArrivesAfterTheTrackChangedIsDropped() async throws {
        let gate = DispatchSemaphore(value: 0), entered = Flag()
        let slow = SlowCoverPlayer(cover: png(width: 64, height: 64, rgb: (0, 200, 0)), gate: gate, entered: entered)
        await coordinator.setPlayer(slow)
        await coordinator.updateMedia(song)
        try await until { entered.isSet }
        await coordinator.updateMedia(Media(title: "Fan Noise", artist: "Tabstop", lengthS: 180, positionS: 0, playing: true))
        gate.signal()
        gate.signal()
        try await until { await coordinator.coverHash != nil }
        let sent = await nowPlaying()
        #expect(sent.allSatisfy { $0.title == "Fan Noise" || $0.cover == nil })
        #expect(sent.last?.title == "Fan Noise" && sent.last?.cover != nil)
    }

    @Test func playbackStoppingForgetsTheCover() async throws {
        player.cover = png(width: 64, height: 64, rgb: (9, 9, 9))
        await coordinator.setPlayer(player)
        await coordinator.updateMedia(song)
        try await until { await coordinator.coverHash != nil }
        await coordinator.updateMedia(nil)
        #expect(await coordinator.coverHash == nil)
    }
}

final class SlowCoverPlayer: MediaPlayer, @unchecked Sendable {
    let cover: Data, gate: DispatchSemaphore, entered: Flag
    init(cover: Data, gate: DispatchSemaphore, entered: Flag) { self.cover = cover; self.gate = gate; self.entered = entered }
    func current() -> Media? { nil }
    func control(_ action: MediaAction) {}
    func artwork() -> Data? {
        entered.set()
        gate.wait()
        return cover
    }
}

@Suite struct ArtworkSourceTests {
    let spotify = "com.spotify.client", music = "com.apple.Music"

    final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []
        func add(_ url: URL) { lock.withLock { urls.append(url) } }
        var all: [URL] { lock.withLock { urls } }
    }

    func player(app: String, artworkURL: String, downloads: Calls, data: Data? = nil) -> AppleScriptPlayer {
        AppleScriptPlayer(
            isRunning: { $0 == app },
            script: { source in
                if source.contains("artwork url") { return (artworkURL, nil) }
                return ("Low Tide\tThe Pixels\t214000\t61\tplaying", nil)
            },
            dataScript: { source in source.contains("raw data of artwork 1") ? (data, nil) : (nil, -1728) },
            download: { url in downloads.add(url); return Data([1, 2, 3]) },
            now: { 0 })
    }

    @Test func spotifyCoversComeOnlyFromItsImageCDNOverHTTPS() {
        let ok = Calls()
        let p = player(app: spotify, artworkURL: "https://i.scdn.co/image/ab67616d0000b273\n", downloads: ok)
        _ = p.current()
        #expect(p.artwork() == Data([1, 2, 3]))
        #expect(ok.all.map(\.absoluteString) == ["https://i.scdn.co/image/ab67616d0000b273"])

        for bad in ["http://i.scdn.co/image/x", "https://example.com/image/x", "https://i.scdn.co.example.com/x",
                    "https://user:pw@i.scdn.co/x", "https://i.scdn.co:8443/x", "file:///etc/hosts", "", "missing value"] {
            let calls = Calls()
            let q = player(app: spotify, artworkURL: bad, downloads: calls)
            _ = q.current()
            #expect(q.artwork() == nil, "\(bad)")
            #expect(calls.all.isEmpty, "\(bad)")
        }
    }

    @Test func musicAppHandsOverTheRawArtworkWithoutDownloading() {
        let calls = Calls()
        let p = player(app: music, artworkURL: "https://i.scdn.co/x", downloads: calls, data: Data([9, 9]))
        _ = p.current()
        #expect(p.artwork() == Data([9, 9]))
        #expect(calls.all.isEmpty)
    }

    @Test func noAppNoArtwork() {
        let calls = Calls()
        let p = player(app: "none", artworkURL: "https://i.scdn.co/x", downloads: calls)
        #expect(p.current() == nil)
        #expect(p.artwork() == nil)
        #expect(calls.all.isEmpty)
    }
}
