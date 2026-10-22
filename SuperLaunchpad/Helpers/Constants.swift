import Foundation

// `enum` with only `static` members is the canonical Swift "namespace" pattern.
// Unlike a `struct`, an empty `enum` cannot be instantiated — `Grid()` is a
// compile error — which makes the intent ("this is a bag of constants, not a
// type") explicit and prevents accidental misuse.
enum Grid {
    static let columns = 7
    static let rows = 5
    static let appsPerPage = columns * rows
}

enum FolderGrid {
    static let columns = 4
    static let rows = 3
    static let appsPerPage = columns * rows
}

enum Rescan {
    // Directory events closer together than this collapse into one rescan.
    static let debounceInterval: Double = 0.5
}

enum AnimationDuration {
    static let show: Double = 0.25
    static let hide: Double = 0.2
    // Extra wait after the hide animation before `orderOut`, so the window is
    // not removed while the tail of the spring is still on screen.
    static let orderOutSlack: Double = 0.1
}

enum SettingsWindow {
    static let width: CGFloat = 420
}

enum HotKey {
    // Four-char code 'SLPd' identifying our Carbon hotkey events.
    static let signature: UInt32 = 0x534C_5064
    static let identifier: UInt32 = 1
    static let maxKeyNameLength = 4
    static let noKeyCode = -1
}

// Snapshot of layout numbers derived from the current screen size.
// Built from a SwiftUI `GeometryReader` — recompute on resize rather than caching,
// because external display changes or stage-manager resizes invalidate the values.
struct LayoutMetrics {
    let iconSize: CGFloat
    let labelWidth: CGFloat
    let labelFont: CGFloat
    let itemWidth: CGFloat
    let itemHeight: CGFloat
    let horizontalPadding: CGFloat
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let rowSpacing: CGFloat

    init(screenWidth: CGFloat, screenHeight: CGFloat) {
        // All numbers are screen-relative so the grid looks proportionally the
        // same on a 13" MacBook and a 6K Pro Display. Hard-coded pixel sizes
        // would look cramped or sparse depending on the display.
        horizontalPadding = screenWidth * 0.06
        let availableWidth = screenWidth - horizontalPadding * 2
        itemWidth = availableWidth / CGFloat(Grid.columns)
        iconSize = itemWidth * 0.5
        labelWidth = itemWidth * 0.8
        // Floor at 11pt so labels stay legible on small screens where the
        // proportional value (screenHeight * 0.012) would round down too far.
        labelFont = max(11, screenHeight * 0.012)

        topPadding = screenHeight * 0.06
        bottomPadding = screenHeight * 0.04
        // Reserve ~10% of screen height for the search bar + page indicator
        // chrome that sits above and below the grid.
        let availableHeight = screenHeight - topPadding - bottomPadding - screenHeight * 0.1
        itemHeight = availableHeight / CGFloat(Grid.rows)
        rowSpacing = itemHeight * 0.05
    }
}

// Tuning for the main-grid pager. Positions and velocities are in "pages"
// (1.0 = one screen width), so the numbers are independent of display size.
enum Paging {
    // Response of the critically damped settle spring, like
    // `.spring(duration:bounce: 0)`.
    static let springResponse: Double = 0.3
    // Release velocity (pages/s) above which a swipe counts as a flick and
    // moves to the neighbouring page regardless of how far it was dragged.
    static let flickVelocity: Double = 0.5
    // Classic UIScrollView rubber-band coefficient.
    static let rubberBandCoefficient: Double = 0.55
    // The banded overshoot approaches one page asymptotically; clamp before
    // inverting so the inverse stays finite.
    static let rubberBandInverseLimit: Double = 0.999
    // Weight of the newest sample in the exponentially smoothed drag velocity.
    static let velocitySmoothing: Double = 0.5
    // If the fingers rested this long before lifting, the release is not a flick.
    static let velocityStaleInterval: Double = 0.08
    static let settleDistance: Double = 0.0005
    static let settleVelocity: Double = 0.005
    // Accumulated wheel delta (lines) needed to turn a burst into a page step.
    static let wheelThreshold: Double = 0.5
    // Wheel ticks closer together than this belong to the same burst.
    static let wheelBurstGap: Double = 0.15
}
