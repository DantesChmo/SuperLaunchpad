import CoreGraphics

// Room the Dock takes at the edges of a screen. Pure: `LaunchpadPanel` passes
// `NSScreen.frame` and `visibleFrame` (global coordinates, origin
// bottom-left), so this is testable without real displays.
//
// The top difference is the menu bar, which the launcher covers like the
// system Launchpad, so only the left, bottom and right edges count. An
// auto-hidden Dock is not excluded from `visibleFrame`, so it gives no insets
// and still slides over the content when shown.
struct DockInsets: Equatable {
    let left: CGFloat
    let bottom: CGFloat
    let right: CGFloat

    static let zero = DockInsets(frame: .zero, visibleFrame: .zero)

    init(frame: CGRect, visibleFrame: CGRect) {
        left = max(visibleFrame.minX - frame.minX, 0)
        bottom = max(visibleFrame.minY - frame.minY, 0)
        right = max(frame.maxX - visibleFrame.maxX, 0)
    }
}
