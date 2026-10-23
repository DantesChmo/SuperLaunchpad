import Testing
@testable import SuperLaunchpad

// Arrow-key moves over a paged grid. Every test runs on several column
// counts, the main grid's and the folder's among them, so the math doesn't
// lean on a 7×5 or 4×3 grid.
struct GridNavigationTests {

    static let columnCounts = [FolderGrid.columns, Grid.columns, 9]

    private func move(
        _ page: Int,
        _ index: Int,
        _ direction: GridNavigation.Direction,
        _ pageCounts: [Int],
        columns: Int
    ) -> GridPosition {
        GridNavigation.move(GridPosition(page: page, index: index), direction, pageCounts: pageCounts, columns: columns)
    }

    // MARK: - Within a page

    @Test(arguments: columnCounts)
    func arrowsWalkRowsAndColumns(columns: Int) {
        let pages = [columns * 3]
        #expect(move(0, 0, .right, pages, columns: columns) == GridPosition(page: 0, index: 1))
        #expect(move(0, 1, .left, pages, columns: columns) == GridPosition(page: 0, index: 0))
        #expect(move(0, 1, .down, pages, columns: columns) == GridPosition(page: 0, index: columns + 1))
        #expect(move(0, columns + 1, .up, pages, columns: columns) == GridPosition(page: 0, index: 1))
    }

    @Test(arguments: columnCounts)
    func upAndDownStopAtTheTopAndBottomRow(columns: Int) {
        let pages = [columns * 2, columns * 2]
        #expect(move(0, 1, .up, pages, columns: columns) == GridPosition(page: 0, index: 1))
        #expect(move(0, columns + 1, .down, pages, columns: columns) == GridPosition(page: 0, index: columns + 1))
    }

    @Test(arguments: columnCounts)
    func leftAndRightStopAtTheFirstAndLastPage(columns: Int) {
        let pages = [columns * 2]
        #expect(move(0, columns, .left, pages, columns: columns) == GridPosition(page: 0, index: columns))
        #expect(move(0, columns - 1, .right, pages, columns: columns) == GridPosition(page: 0, index: columns - 1))
    }

    // MARK: - Across pages

    @Test(arguments: columnCounts)
    func rightAtTheRowEndGoesToTheSameRowOfTheNextPage(columns: Int) {
        let pages = [columns * 3, columns * 3]
        #expect(move(0, columns - 1, .right, pages, columns: columns) == GridPosition(page: 1, index: 0))
        #expect(move(0, columns * 2 - 1, .right, pages, columns: columns) == GridPosition(page: 1, index: columns))
    }

    @Test(arguments: columnCounts)
    func leftAtTheRowStartGoesToTheRowEndOfThePreviousPage(columns: Int) {
        let pages = [columns * 3, columns * 3]
        #expect(move(1, 0, .left, pages, columns: columns) == GridPosition(page: 0, index: columns - 1))
        #expect(move(1, columns * 2, .left, pages, columns: columns) == GridPosition(page: 0, index: columns * 3 - 1))
    }

    // MARK: - Partial rows

    @Test(arguments: columnCounts)
    func downOverAGapLandsOnTheLastItem(columns: Int) {
        // Two full rows and a last row of two.
        let pages = [columns * 2 + 2]
        #expect(move(0, columns * 2 - 1, .down, pages, columns: columns) == GridPosition(page: 0, index: columns * 2 + 1))
        #expect(move(0, columns, .down, pages, columns: columns) == GridPosition(page: 0, index: columns * 2))
    }

    @Test(arguments: columnCounts)
    func rightFromTheLastItemOfAPartialRowCrossesThePage(columns: Int) {
        let pages = [columns + 2, columns]
        // Row 1 of a one-row page: its last item.
        #expect(move(0, columns + 1, .right, pages, columns: columns) == GridPosition(page: 1, index: columns - 1))
        #expect(move(0, 1, .right, [2, columns], columns: columns) == GridPosition(page: 1, index: 0))
        // On the last page it stays.
        #expect(move(1, columns - 1, .right, pages, columns: columns) == GridPosition(page: 1, index: columns - 1))
    }

    @Test(arguments: columnCounts)
    func crossingIntoAShorterPageLandsOnItsLastItem(columns: Int) {
        // The next page has two apps, the previous one a single row plus one.
        #expect(move(0, columns * 3 - 1, .right, [columns * 3, 2], columns: columns) == GridPosition(page: 1, index: 1))
        #expect(move(1, columns, .left, [columns + 1, columns * 2], columns: columns) == GridPosition(page: 0, index: columns))
    }

    @Test(arguments: GridNavigation.Direction.allCases)
    func nothingToMoveOverStaysPut(direction: GridNavigation.Direction) {
        let origin = GridPosition(page: 0, index: 0)
        #expect(GridNavigation.move(origin, direction, pageCounts: [], columns: Grid.columns) == origin)
        #expect(GridNavigation.move(origin, direction, pageCounts: [1], columns: Grid.columns) == origin)
        #expect(GridNavigation.move(origin, direction, pageCounts: [3], columns: 0) == origin)
    }

    // MARK: - Folder pages

    @Test(arguments: [
        (0, [Int]()),
        (FolderGrid.appsPerPage, [FolderGrid.appsPerPage]),
        (FolderGrid.appsPerPage + 1, [FolderGrid.appsPerPage, 1]),
        (FolderGrid.appsPerPage * 2 + 3, [FolderGrid.appsPerPage, FolderGrid.appsPerPage, 3])
    ])
    func folderAppsSplitIntoPages(itemCount: Int, expected: [Int]) {
        #expect(GridNavigation.pageCounts(itemCount: itemCount, perPage: FolderGrid.appsPerPage) == expected)
    }

    @Test(arguments: [0, 1, FolderGrid.appsPerPage - 1, FolderGrid.appsPerPage, FolderGrid.appsPerPage * 2 + 5])
    func flatIndexMapsToPageAndIndex(index: Int) {
        let position = GridNavigation.position(ofFlatIndex: index, perPage: FolderGrid.appsPerPage)
        #expect(position.page * FolderGrid.appsPerPage + position.index == index)
        #expect((0..<FolderGrid.appsPerPage).contains(position.index))
    }
}
