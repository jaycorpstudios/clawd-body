import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import HiloRuntime

/// Picks this Mac's picture, crops it square and saves it next to `config.json`; `hilod` scales it down for the buddy.
struct ProfileCard: View {
    @Environment(AppModel.self) private var model
    @State private var picked: CGImage?
    @State private var zoom = 1.0
    @State private var offset = CGSize.zero
    @State private var dragStart = CGSize.zero
    @State private var saved: NSImage?

    private let frame: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("While the buddy rests, it rotates the clock with a card per Mac: this picture, the Mac's name and when it was last connected. It stays on this Mac and on the buddy, which drops it when it forgets this Mac.")
                .foregroundStyle(Theme.secondary)
            HStack(alignment: .top, spacing: 18) {
                if let picked { cropper(picked) } else { current }
                VStack(alignment: .leading, spacing: 10) {
                    Button(picked == nil ? "Choose picture…" : "Choose another…") { choose() }.buttonStyle(SecondaryButtonStyle())
                    if picked != nil {
                        HStack(spacing: 8) {
                            Image(systemName: "minus.magnifyingglass").foregroundStyle(Theme.secondary)
                            Slider(value: $zoom, in: 1...4).frame(width: 140)
                            Image(systemName: "plus.magnifyingglass").foregroundStyle(Theme.secondary)
                        }
                        Text("Drag to move it inside the square.").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        HStack(spacing: 8) {
                            Button("Use picture") { save() }.buttonStyle(PrimaryButtonStyle())
                            Button("Cancel") { picked = nil }.buttonStyle(SecondaryButtonStyle())
                        }
                    } else if saved != nil {
                        Button("Remove picture") { remove() }.buttonStyle(SecondaryButtonStyle())
                    }
                    if let hash = model.daemonStatus?.face {
                        HStack(spacing: 0) {
                            Text("hilod sends it as ")
                            Text(hash).font(Theme.mono)
                        }
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    }
                }
            }
        }
        .onAppear { saved = NSImage(contentsOfFile: model.facePath) }
    }

    private var current: some View {
        Group {
            if let saved {
                Image(nsImage: saved).resizable().interpolation(.high).scaledToFill()
            } else {
                Image(systemName: "person.crop.square").font(.system(size: 54)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.softPanel)
            }
        }
        .frame(width: 110, height: 110).clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
    }

    private func cropper(_ image: CGImage) -> some View {
        let size = displaySize(image)
        return Image(decorative: image, scale: 1).resizable().interpolation(.high)
            .frame(width: size.width, height: size.height)
            .offset(offset)
            .frame(width: frame, height: frame).clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.lineStrong, lineWidth: 2))
            .contentShape(Rectangle())
            .gesture(DragGesture()
                .onChanged { g in offset = clamp(CGSize(width: dragStart.width + g.translation.width, height: dragStart.height + g.translation.height), image) }
                .onEnded { _ in dragStart = offset })
            .onChange(of: zoom) { offset = clamp(offset, image); dragStart = offset }
    }

    private func displaySize(_ image: CGImage) -> CGSize {
        let scale = frame / CGFloat(min(image.width, image.height)) * zoom
        return CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
    }

    private func clamp(_ o: CGSize, _ image: CGImage) -> CGSize {
        let size = displaySize(image)
        let mx = (size.width - frame) / 2, my = (size.height - frame) / 2
        return CGSize(width: min(max(o.width, -mx), mx), height: min(max(o.height, -my), my))
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 2048,
              ] as CFDictionary)
        else { return }
        picked = image
        zoom = 1
        offset = .zero
        dragStart = .zero
    }

    private func save() {
        guard let image = picked else { return }
        let size = displaySize(image)
        let scale = size.width / CGFloat(image.width)
        let side = frame / scale
        let x = ((size.width - frame) / 2 - offset.width) / scale, y = ((size.height - frame) / 2 - offset.height) / scale
        guard let square = image.cropping(to: CGRect(x: x, y: y, width: side, height: side).integral) else { return }
        model.saveFace(square)
        saved = NSImage(contentsOfFile: model.facePath)
        picked = nil
    }

    private func remove() {
        model.saveFace(nil)
        saved = nil
    }
}
