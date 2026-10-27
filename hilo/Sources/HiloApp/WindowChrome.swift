import AppKit
import SwiftUI

/// Makes the custom top bar behave like a title bar: drag moves the window, a double click does what
/// System Settings › Desktop & Dock asks (`AppleActionOnDoubleClick`: zoom, minimize or nothing).
struct TitleBarArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { TitleBarView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    static func doubleClickAction(_ defaults: UserDefaults = .standard) -> String {
        if let action = defaults.string(forKey: "AppleActionOnDoubleClick") { return action }
        return defaults.bool(forKey: "AppleMiniaturizeOnDoubleClick") ? "Minimize" : "Maximize"
    }

    final class TitleBarView: NSView {
        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                switch TitleBarArea.doubleClickAction() {
                case "Minimize": window.performMiniaturize(nil)
                case "None": break
                default: window.performZoom(nil)
                }
            } else {
                window.performDrag(with: event)
            }
        }
    }
}

/// Remembers the window's size and position across launches and keeps full screen available.
struct WindowSetup: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { AutosaveView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class AutosaveView: NSView {
        override func viewDidMoveToWindow() {
            guard let window else { return }
            window.collectionBehavior.insert(.fullScreenPrimary)
            window.setFrameAutosaveName("HiloMain")
        }
    }
}

extension View {
    /// Liquid Glass on macOS 26, the system material before; snapshots get the flat color, as `cacheDisplay` draws neither.
    @ViewBuilder func barGlass() -> some View {
        if Snapshots.requested {
            background(Theme.topBar)
        } else if #available(macOS 26, *) {
            glassEffect(.regular.tint(Theme.topBar.opacity(0.55)), in: .rect)
        } else {
            background(.ultraThinMaterial)
        }
    }
}

/// A material that fades out downwards: content scrolling under the bar blurs progressively instead of at a hard edge.
struct ProgressiveBlur: View {
    var height: CGFloat = 28

    var body: some View {
        Rectangle().fill(.ultraThinMaterial)
            .mask(LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom))
            .frame(height: height)
            .allowsHitTesting(false)
    }
}
