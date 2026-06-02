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

enum AnimationDuration {
    static let show: Double = 0.25
    static let hide: Double = 0.2
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
