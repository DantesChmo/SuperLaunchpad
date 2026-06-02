import Foundation

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
        horizontalPadding = screenWidth * 0.06
        let availableWidth = screenWidth - horizontalPadding * 2
        itemWidth = availableWidth / CGFloat(Grid.columns)
        iconSize = itemWidth * 0.5
        labelWidth = itemWidth * 0.8
        labelFont = max(11, screenHeight * 0.012)

        topPadding = screenHeight * 0.06
        bottomPadding = screenHeight * 0.04
        let availableHeight = screenHeight - topPadding - bottomPadding - screenHeight * 0.1
        itemHeight = availableHeight / CGFloat(Grid.rows)
        rowSpacing = itemHeight * 0.05
    }
}
