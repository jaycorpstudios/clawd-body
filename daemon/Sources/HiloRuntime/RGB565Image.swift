import CoreGraphics
import Foundation
import HiloContract
import ImageIO

/// A square picture as the buddy draws it: RGB565 pixels sent in chunks (see the contract's faces and covers sections).
public struct RGB565Image: Equatable, Sendable {
    public static let faceSide = 120
    public static let coverSide = 96
    static let maxChunkChars = 6000

    public let side: Int
    public let pixels: Data
    public let hash: String

    public init(pixels: Data, side: Int) {
        self.side = side
        self.pixels = pixels
        self.hash = String(format: "%016llx", Self.fnv1a64(pixels))
    }

    /// Scales any image ImageIO reads to `side`×`side` (the app already cropped it square; anything else is center-cropped).
    public static func load(_ url: URL, side: Int = faceSide) -> RGB565Image? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return render(source, side: side)
    }

    public static func decode(_ data: Data, side: Int) -> RGB565Image? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return render(source, side: side)
    }

    /// Decodes at most a few times `side` so a huge picture never lands in memory at full size.
    static func render(_ source: CGImageSource, side: Int) -> RGB565Image? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: side * 4,
            kCGImageSourceShouldCache: false,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return render(image, side: side)
    }

    public static func render(_ image: CGImage, side: Int = faceSide) -> RGB565Image? {
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        else { return nil }
        let crop = min(image.width, image.height)
        guard let square = image.cropping(to: CGRect(x: (image.width - crop) / 2, y: (image.height - crop) / 2, width: crop, height: crop))
        else { return nil }
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        ctx.interpolationQuality = .high
        ctx.draw(square, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let base = ctx.data else { return nil }
        let rgba = base.bindMemory(to: UInt8.self, capacity: side * side * 4)
        var out = Data(count: side * side * 2)
        out.withUnsafeMutableBytes { raw in
            let dst = raw.bindMemory(to: UInt8.self)
            for i in 0..<(side * side) {
                let r = UInt16(rgba[i * 4]), g = UInt16(rgba[i * 4 + 1]), b = UInt16(rgba[i * 4 + 2])
                let v = (r >> 3) << 11 | (g >> 2) << 5 | (b >> 3)
                dst[i * 2] = UInt8(v & 0xff)
                dst[i * 2 + 1] = UInt8(v >> 8)
            }
        }
        return RGB565Image(pixels: out, side: side)
    }

    public var chunks: [ImageChunk] {
        let bytesPerChunk = Self.maxChunkChars / 4 * 3
        let parts = stride(from: 0, to: pixels.count, by: bytesPerChunk).map { pixels[$0..<min($0 + bytesPerChunk, pixels.count)] }
        return parts.enumerated().map { i, part in
            ImageChunk(hash: hash, w: side, h: side, index: i, count: parts.count, data: Data(part).base64EncodedString())
        }
    }

    static func fnv1a64(_ data: Data) -> UInt64 {
        data.reduce(0xcbf2_9ce4_8422_2325) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 }
    }
}
