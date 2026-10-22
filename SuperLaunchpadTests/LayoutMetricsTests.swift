import Foundation
import Testing
@testable import SuperLaunchpad

struct LayoutMetricsTests {

    // MARK: - Grid constants

    @Test func gridAppsPerPageIsColumnsTimesRows() {
        #expect(Grid.appsPerPage == Grid.columns * Grid.rows)
        #expect(Grid.appsPerPage == 35)
    }

    @Test func folderGridAppsPerPageIsColumnsTimesRows() {
        #expect(FolderGrid.appsPerPage == FolderGrid.columns * FolderGrid.rows)
        #expect(FolderGrid.appsPerPage == 12)
    }

    @Test func animationDurations() {
        #expect(AnimationDuration.show == 0.25)
        #expect(AnimationDuration.hide == 0.2)
    }

    // MARK: - LayoutMetrics

    @Test func layoutMetricsStandardScreen() {
        let m = LayoutMetrics(screenWidth: 1920, screenHeight: 1080)
        #expect(m.horizontalPadding == 1920 * 0.06)
        let availableWidth: CGFloat = 1920 - (1920 * 0.06) * 2
        #expect(m.itemWidth == availableWidth / 7)
        #expect(m.iconSize == m.itemWidth * 0.5)
        #expect(m.labelWidth == m.itemWidth * 0.8)
        #expect(m.topPadding == 1080 * 0.06)
        #expect(m.bottomPadding == 1080 * 0.04)
    }

    @Test func layoutMetricsLabelFontMinClamped() {
        // 800 * 0.012 = 9.6, but min clamp is 11
        let m = LayoutMetrics(screenWidth: 1280, screenHeight: 800)
        #expect(m.labelFont == 11)
    }

    @Test func layoutMetricsLabelFontScalesWithHeight() {
        // 2000 * 0.012 = 24, above the 11 floor
        let m = LayoutMetrics(screenWidth: 3840, screenHeight: 2000)
        #expect(m.labelFont == 2000 * 0.012)
    }

    @Test func layoutMetricsRowSpacingProportional() {
        let m = LayoutMetrics(screenWidth: 1920, screenHeight: 1080)
        #expect(m.rowSpacing == m.itemHeight * 0.05)
    }

    // The rows plus the gaps between them fill the height left for the grid,
    // so the last row stays clear of the page indicator.
    @Test func rowsAndGapsFitAvailableHeight() {
        let m = LayoutMetrics(screenWidth: 1920, screenHeight: 1080)
        let availableHeight: CGFloat = 1080 - (1080 * 0.06) - (1080 * 0.04) - (1080 * 0.1)
        let gridHeight = m.itemHeight * CGFloat(Grid.rows) + m.rowSpacing * CGFloat(Grid.rows - 1)
        #expect(abs(gridHeight - availableHeight) < 0.001)
    }

    @Test func layoutMetricsScalesWithLargerScreen() {
        let small = LayoutMetrics(screenWidth: 1920, screenHeight: 1080)
        let large = LayoutMetrics(screenWidth: 3840, screenHeight: 2160)
        // Doubling screen doubles itemWidth
        #expect(large.itemWidth == small.itemWidth * 2)
        #expect(large.horizontalPadding == small.horizontalPadding * 2)
        #expect(large.iconSize == small.iconSize * 2)
    }
}
