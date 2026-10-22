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
    // Icons in the folder popup are a touch smaller than on the main grid.
    static let iconScale: CGFloat = 0.85
    static let rowSpacing: CGFloat = 8
    // Padding between the popup card's edge and its grid.
    static let cardHorizontalPadding: CGFloat = 30
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

enum Search {
    static let fieldWidth: CGFloat = 200
    static let fieldFontSize: CGFloat = 14
    static let fieldCornerRadius: CGFloat = 8
    // The selection highlight extends past the icon box by this share of the
    // icon size on each side.
    static let selectionOutsetRatio: CGFloat = 0.15
    static let selectionCornerRadius: CGFloat = 14
    static let selectionOpacity: Double = 0.22
    static let resultsTransition: Double = 0.12
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

    // Vertical gap between an icon and its label.
    static let iconLabelSpacing: CGFloat = 6

    // Hover / tap / drag target of a cell: the icon plus room for two label
    // lines, centered in the cell (see `GridItemContainer`).
    var itemHitSize: CGSize {
        CGSize(width: iconSize, height: iconSize + Self.iconLabelSpacing + labelFont * 3)
    }

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

// Drag-to-reorder on the main grid.
enum Drag {
    // Pointer travel (pt) before a press on an icon becomes a drag; shorter
    // movements stay a click.
    static let threshold: CGFloat = 6
    // Scale of the lifted icon that follows the pointer.
    static let liftScale: CGFloat = 1.1
    static let shadowRadius: CGFloat = 12
    static let shadowOpacity: Double = 0.4
    // The pointer must rest over a new slot this long before the neighbours
    // reflow, so sweeping across the grid doesn't shuffle every icon it passes.
    static let dwell: Double = 0.15
    // Spring used for the reflow, the lift and the drop.
    static let springDuration: Double = 0.25
    // The pointer must rest in the margin beside the grid this long before
    // the grid flips to the neighbouring page…
    static let edgeDwell: Double = 0.5
    // …and then flips again this often while it stays there.
    static let edgeRepeat: Double = 0.8
    // Merge zone: the middle of an icon, this share of its side. Dropping an
    // app there makes a folder (or adds to one); elsewhere it inserts.
    static let mergeZoneRatio: CGFloat = 0.5
    // The lifted app must rest on a merge zone this long before the target
    // is highlighted and the reflow pauses.
    static let mergeDwell: Double = 0.4
    // Highlighted merge target: scaled up, with a folder-style backplate
    // around an app's icon.
    static let mergeTargetScale: CGFloat = 1.15
    static let mergeBackplateOutset: CGFloat = 0.12
    static let mergeBackplateOpacity: Double = 0.25
    // The lifted icon shrinks into the folder it is dropped on.
    static let mergeDropScale: CGFloat = 0.4
    // Share of the label room (two lines plus slack) one label line takes;
    // used to place the icon inside its vertically centered hit box.
    static let oneLineLabelShare: CGFloat = 0.4
    // Named coordinate space of the launcher root, where the drag gesture
    // and the lifted icon live.
    static let coordinateSpace = "launchpad"
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
