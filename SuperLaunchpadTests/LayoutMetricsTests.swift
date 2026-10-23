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

    // MARK: - Frequently Used row

    @Test(arguments: [(1440.0, 900.0), (1920.0, 1080.0), (1280.0, 800.0), (3440.0, 1440.0)])
    func extraRowSharesTheGridHeightAndCellsFitTheirIcons(width: Double, height: Double) {
        let m = LayoutMetrics(screenWidth: width, screenHeight: height, extraRows: 1)
        let availableHeight = height - height * 0.06 - height * 0.04 - height * 0.1
        let rows = CGFloat(Grid.rows + 1)
        let totalHeight = m.itemHeight * rows + m.rowSpacing * (rows - 1)
        #expect(abs(totalHeight - availableHeight) < 0.001)
        #expect(m.itemHitSize.height <= m.itemHeight + 0.001)
        #expect(m.iconSize <= m.itemWidth * 0.5)
    }

    @Test func noExtraRowsKeepsTheStandardMetrics() {
        let standard = LayoutMetrics(screenWidth: 1440, screenHeight: 900)
        let explicit = LayoutMetrics(screenWidth: 1440, screenHeight: 900, extraRows: 0)
        #expect(explicit.iconSize == standard.iconSize)
        #expect(explicit.itemHeight == standard.itemHeight)
        #expect(standard.iconSize == standard.itemWidth * 0.5)
    }

    @Test func extraRowMakesRowsShorterOnly() {
        let standard = LayoutMetrics(screenWidth: 1440, screenHeight: 900)
        let withRow = LayoutMetrics(screenWidth: 1440, screenHeight: 900, extraRows: 1)
        #expect(withRow.itemHeight < standard.itemHeight)
        #expect(withRow.itemWidth == standard.itemWidth)
        #expect(withRow.labelFont == standard.labelFont)
    }

    // MARK: - Appearance: label size and hidden labels

    @Test(arguments: [(1440.0, 900.0), (1920.0, 1080.0), (3440.0, 1440.0)])
    func defaultLabelSettingsKeepTheOriginalMetrics(width: Double, height: Double) {
        let standard = LayoutMetrics(screenWidth: width, screenHeight: height)
        let explicit = LayoutMetrics(screenWidth: width, screenHeight: height, labelSize: .medium, showsLabels: true)
        #expect(explicit.iconSize == standard.iconSize)
        #expect(explicit.labelFont == standard.labelFont)
        #expect(explicit.itemHitSize == standard.itemHitSize)
        #expect(standard.iconSize == standard.itemWidth * 0.5)
        #expect(abs(standard.labelFont - max(11, height * 0.012)) < 0.001)
        #expect(abs(standard.itemHitSize.height - (standard.iconSize + 6 + standard.labelFont * 3)) < 0.001)
    }

    @Test(arguments: LabelSize.allCases)
    func labelSizeScalesTheFont(size: LabelSize) {
        let standard = LayoutMetrics(screenWidth: 1920, screenHeight: 1080)
        let m = LayoutMetrics(screenWidth: 1920, screenHeight: 1080, labelSize: size)
        #expect(abs(m.labelFont - standard.labelFont * size.scale) < 0.001)
        #expect(m.itemHeight == standard.itemHeight)
        #expect(m.itemWidth == standard.itemWidth)
    }

    @Test func labelSizesGrowInOrder() {
        let scales = LabelSize.allCases.map(\.scale)
        #expect(scales == scales.sorted())
        #expect(LabelSize.medium.scale == 1)
    }

    @Test func smallLabelsKeepTheIconSize() {
        let standard = LayoutMetrics(screenWidth: 1920, screenHeight: 1080)
        let small = LayoutMetrics(screenWidth: 1920, screenHeight: 1080, labelSize: .small)
        #expect(small.iconSize == standard.iconSize)
    }

    // Bigger labels need more room under the icon; where the cell can't give
    // it, the icon shrinks so icon and label still fit the cell.
    @Test(arguments: [(1920.0, 1080.0), (1440.0, 900.0), (2560.0, 1080.0)])
    func largeLabelsFitTheirCells(width: Double, height: Double) {
        for size in [LabelSize.large, .extraLarge] {
            let m = LayoutMetrics(screenWidth: width, screenHeight: height, labelSize: size)
            #expect(m.itemHitSize.height <= m.itemHeight + 0.001)
            #expect(m.iconSize <= m.itemWidth * 0.5)
        }
    }

    @Test func extraLargeLabelsShrinkTheIconOnA1080pScreen() {
        let standard = LayoutMetrics(screenWidth: 1920, screenHeight: 1080)
        let m = LayoutMetrics(screenWidth: 1920, screenHeight: 1080, labelSize: .extraLarge)
        #expect(m.iconSize < standard.iconSize)
    }

    @Test func hiddenLabelsLeaveJustTheIcon() {
        let m = LayoutMetrics(screenWidth: 1920, screenHeight: 1080, showsLabels: false)
        #expect(m.showsLabels == false)
        #expect(m.labelRoom == 0)
        #expect(m.itemHitSize == CGSize(width: m.iconSize, height: m.iconSize))
    }

    @Test func hiddenLabelsKeepTheGridAndIconSize() {
        let standard = LayoutMetrics(screenWidth: 1920, screenHeight: 1080)
        let hidden = LayoutMetrics(screenWidth: 1920, screenHeight: 1080, showsLabels: false)
        #expect(hidden.iconSize == standard.iconSize)
        #expect(hidden.itemHeight == standard.itemHeight)
        #expect(hidden.rowSpacing == standard.rowSpacing)
    }

    // With the Frequently Used row the icon gives way to the label; without
    // labels it gets that room back.
    @Test func hiddenLabelsGiveTheShorterCellsBigIcons() {
        let labelled = LayoutMetrics(screenWidth: 1920, screenHeight: 1080, extraRows: 1)
        let hidden = LayoutMetrics(screenWidth: 1920, screenHeight: 1080, extraRows: 1, showsLabels: false)
        #expect(labelled.iconSize < labelled.itemWidth * 0.5)
        #expect(hidden.iconSize > labelled.iconSize)
        #expect(hidden.iconSize <= hidden.itemHeight)
        #expect(hidden.iconSize <= hidden.itemWidth * 0.5)
    }

    @Test func hiddenLabelsIgnoreTheLabelSize() {
        let small = LayoutMetrics(screenWidth: 1920, screenHeight: 1080, labelSize: .small, showsLabels: false)
        let extraLarge = LayoutMetrics(screenWidth: 1920, screenHeight: 1080, labelSize: .extraLarge, showsLabels: false)
        #expect(small.iconSize == extraLarge.iconSize)
        #expect(small.itemHitSize == extraLarge.itemHitSize)
    }

    // MARK: - Appearance: dimming

    @Test func dimmingIsTheSettingWithNormalContrast() {
        #expect(BackgroundDimming.opacity(0.1, increasedContrast: false) == 0.1)
        #expect(BackgroundDimming.opacity(LabelContrast.dimOpacity, increasedContrast: false) == LabelContrast.dimOpacity)
    }

    @Test func increasedContrastDimsAtLeastTheReadableMinimum() {
        // The default reproduces the original Increase Contrast dimming.
        #expect(BackgroundDimming.opacity(LabelContrast.dimOpacity, increasedContrast: true) == LabelContrast.increasedDimOpacity)
        #expect(BackgroundDimming.opacity(0, increasedContrast: true) == LabelContrast.increasedDimOpacity)
        #expect(BackgroundDimming.opacity(0.7, increasedContrast: true) == 0.7)
    }
}
