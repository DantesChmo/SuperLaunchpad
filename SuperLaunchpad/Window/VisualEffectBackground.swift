import SwiftUI

// Bridges the AppKit `NSVisualEffectView` (the "blur the desktop behind me"
// view used in Spotlight, Notification Center, etc.) into SwiftUI.
//
// `NSViewRepresentable` is the macOS counterpart of `UIViewRepresentable`:
//   • `makeNSView`  — construct once.
//   • `updateNSView` — re-applied whenever SwiftUI re-renders the parent.
//                      Empty here because we never change the configuration
//                      after creation.
//
// Why not SwiftUI's `.background(.ultraThinMaterial)`? At fullscreen this view
// gives a better, darker frosted look (`.fullScreenUI`) that mirrors the system
// Launchpad more closely, and `blendingMode = .behindWindow` samples the actual
// desktop wallpaper, not just other views inside our window.
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .fullScreenUI
        view.blendingMode = .behindWindow
        // `.active` keeps the blur "on" even when our window is not key —
        // without this the effect flickers off briefly during focus changes.
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
