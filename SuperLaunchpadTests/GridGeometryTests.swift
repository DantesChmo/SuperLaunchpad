import CoreGraphics
import Testing
@testable import SuperLaunchpad

struct GridGeometryTests {

    // 7×5 cells of 100×80 with 10 pt between rows on a 1000 pt page: the grid
    // is 700 wide, so it starts at x = 150. Hit box 50×60 centered in a cell.
    private func geometry() -> GridGeometry {
        GridGeometry(
            columns: 7,
            rows: 5,
            cellSize: CGSize(width: 100, height: 80),
            rowSpacing: 10,
            hitSize: CGSize(width: 50, height: 60),
            pageWidth: 1000
        )
    }

    // MARK: - Frames

    @Test func gridIsCenteredHorizontallyAndHugsTheTop() {
        #expect(geometry().origin == CGPoint(x: 150, y: 0))
    }

    @Test func cellFrameWrapsEveryColumnsSlots() {
        let g = geometry()
        #expect(g.cellFrame(slot: 0) == CGRect(x: 150, y: 0, width: 100, height: 80))
        #expect(g.cellFrame(slot: 6) == CGRect(x: 750, y: 0, width: 100, height: 80))
        #expect(g.cellFrame(slot: 7) == CGRect(x: 150, y: 90, width: 100, height: 80))
        #expect(g.cellFrame(slot: 34) == CGRect(x: 750, y: 360, width: 100, height: 80))
    }

    @Test func hitFrameIsCenteredInItsCell() {
        #expect(geometry().hitFrame(slot: 8) == CGRect(x: 275, y: 100, width: 50, height: 60))
    }

    @Test func metricsInitMatchesTheDrawnGrid() {
        let metrics = LayoutMetrics(screenWidth: 1920, screenHeight: 1080)
        let g = GridGeometry(metrics: metrics, pageWidth: 1920)
        #expect(g.columns == Grid.columns)
        #expect(g.rows == Grid.rows)
        #expect(g.capacity == Grid.appsPerPage)
        // The page is the screen width, so the grid starts at the padding.
        #expect(abs(g.origin.x - metrics.horizontalPadding) < 0.001)
        #expect(g.hitSize == metrics.itemHitSize)
    }

    // MARK: - Picking the dragged item

    @Test func itemAtPointInsideHitBox() {
        #expect(geometry().item(at: CGPoint(x: 300, y: 130), itemCount: 35) == 8)
    }

    @Test func itemAtPointInCellPaddingIsNil() {
        // Inside cell 8 but left of its 50 pt hit box.
        #expect(geometry().item(at: CGPoint(x: 260, y: 130), itemCount: 35) == nil)
    }

    @Test func itemAtEmptySlotIsNil() {
        #expect(geometry().item(at: CGPoint(x: 300, y: 130), itemCount: 8) == nil)
    }

    @Test func itemOutsideTheGridIsNil() {
        #expect(geometry().item(at: CGPoint(x: 20, y: 40), itemCount: 35) == nil)
        #expect(geometry().item(at: CGPoint(x: 200, y: 900), itemCount: 35) == nil)
    }

    // MARK: - Drop slot

    @Test(arguments: [
        (CGPoint(x: 160, y: 5), 0),
        (CGPoint(x: 849, y: 79), 6),
        (CGPoint(x: 300, y: 130), 8),
        (CGPoint(x: 800, y: 400), 34)
    ])
    func dropSlotIsTheCellUnderThePointer(point: CGPoint, slot: Int) {
        #expect(geometry().dropSlot(at: point, itemCount: 35) == slot)
    }

    @Test func rowSpacingIsSplitBetweenNeighbouringRows() {
        let g = geometry()
        // Row 0 ends at y = 80, row 1 starts at y = 90.
        #expect(g.dropSlot(at: CGPoint(x: 160, y: 84), itemCount: 35) == 0)
        #expect(g.dropSlot(at: CGPoint(x: 160, y: 86), itemCount: 35) == 7)
    }

    @Test func dropSlotOutsideTheGridClampsToTheNearestCell() {
        let g = geometry()
        #expect(g.dropSlot(at: CGPoint(x: 0, y: -50), itemCount: 35) == 0)
        #expect(g.dropSlot(at: CGPoint(x: 990, y: 40), itemCount: 35) == 6)
        #expect(g.dropSlot(at: CGPoint(x: 160, y: 2000), itemCount: 35) == 28)
    }

    @Test func dropSlotPastTheLastItemClampsToTheLastItem() {
        // 10 items: past slot 9 (row 1, column 2) the item stays last.
        #expect(geometry().dropSlot(at: CGPoint(x: 800, y: 400), itemCount: 10) == 9)
        #expect(geometry().dropSlot(at: CGPoint(x: 800, y: 130), itemCount: 10) == 9)
    }

    @Test func dropSlotOnEmptyPageIsZero() {
        #expect(geometry().dropSlot(at: CGPoint(x: 500, y: 200), itemCount: 0) == 0)
    }

    @Test func degenerateGeometryDropsAtZero() {
        let g = GridGeometry(columns: 7, rows: 5, cellSize: .zero, rowSpacing: 0, hitSize: .zero, pageWidth: 0)
        #expect(g.dropSlot(at: CGPoint(x: 10, y: 10), itemCount: 5) == 0)
        #expect(g.item(at: CGPoint(x: 10, y: 10), itemCount: 5) == nil)
    }

    // MARK: - Pager coordinates

    @Test func pageLocalAccountsForPagerPosition() {
        // Pager resting on page 2 of 1000 pt pages: the container shows page 2.
        let local = GridGeometry.pageLocal(CGPoint(x: 300, y: 40), page: 2, pagerPosition: 2, pageWidth: 1000)
        #expect(local == CGPoint(x: 300, y: 40))
        // Mid-swipe at 1.5: the left half of the container shows page 1's right half.
        let mid = GridGeometry.pageLocal(CGPoint(x: 300, y: 40), page: 1, pagerPosition: 1.5, pageWidth: 1000)
        #expect(mid == CGPoint(x: 800, y: 40))
    }

    @Test func containerPointInvertsPageLocal() {
        let point = CGPoint(x: 123, y: 45)
        let local = GridGeometry.pageLocal(point, page: 3, pagerPosition: 2.25, pageWidth: 800)
        #expect(GridGeometry.containerPoint(local, page: 3, pagerPosition: 2.25, pageWidth: 800) == point)
    }
}

struct DragSessionTests {

    private func session(slot: Int) -> DragSession {
        DragSession(itemID: "c", item: .app("c"), page: 0, slot: slot, grabOffset: .zero)
    }

    @Test func newSessionShowsTheStoredOrder() {
        let s = session(slot: 2)
        #expect(!s.hasMoved)
        #expect(s.preview(["a", "b", "c", "d"]) == ["a", "b", "c", "d"])
    }

    @Test func previewMovesItemForward() {
        var s = session(slot: 2)
        s.retarget(0)
        #expect(s.hasMoved)
        #expect(s.preview(["a", "b", "c", "d"]) == ["c", "a", "b", "d"])
    }

    @Test func previewMovesItemBackward() {
        var s = session(slot: 0)
        s.retarget(3)
        #expect(s.preview(["c", "a", "b", "d"]) == ["a", "b", "d", "c"])
    }

    // The preview must be what `GridLayout.move` stores on drop, or the icons
    // would jump when the drop commits.
    @Test(arguments: [(0, 4), (4, 0), (2, 3), (5, 5), (1, 5)])
    func previewMatchesGridLayoutMove(from source: Int, to target: Int) throws {
        let ids = ["a", "b", "c", "d", "e", "f"]
        let apps = ids.enumerated().map { index, id in
            AppEntry(
                bundleIdentifier: id,
                displayName: id,
                appPath: "/Applications/\(id).app",
                pageIndex: 0,
                orderIndex: index
            )
        }
        var layout = GridLayout(apps: apps, folders: [])
        let moved = layout.move(.app(ids[source]), toPage: 0, slot: target)
        #expect(moved)

        var s = DragSession(itemID: ids[source], item: .app(ids[source]), page: 0, slot: source, grabOffset: .zero)
        s.retarget(target)
        #expect(s.preview(ids).map { GridLayout.Item.app($0) } == layout.pages[0])
    }

    @Test func outOfRangeSlotsLeaveOrderAlone() {
        var s = session(slot: 5)
        s.retarget(1)
        #expect(s.preview(["a", "b", "c"]) == ["a", "b", "c"])
    }

    @Test func markCommittedStopsMovingTheItem() {
        var s = session(slot: 2)
        s.retarget(0)
        s.markCommitted()
        #expect(!s.hasMoved)
        #expect(s.targetSlot == 0)
        // The view model now holds the moved order; the preview leaves it be.
        #expect(s.preview(["c", "a", "b"]) == ["c", "a", "b"])
    }

    @Test func revertReturnsToSourceSlot() {
        var s = session(slot: 2)
        s.retarget(0)
        s.revert()
        #expect(!s.hasMoved)
        #expect(s.targetSlot == 2)
    }

    @Test func droppingSessionIgnoresRetarget() {
        var s = session(slot: 2)
        s.retarget(1)
        s.beginDrop()
        s.retarget(3)
        #expect(s.isDropping)
        #expect(s.targetSlot == 1)
    }

    @Test func layoutItemMapsAppsAndFolders() {
        let app = AppEntry(bundleIdentifier: "com.a", displayName: "A", appPath: "/Applications/A.app", pageIndex: 0, orderIndex: 0)
        let folder = FolderEntry(id: "F", title: "Tools", pageIndex: 0, orderIndex: 1)
        #expect(LaunchpadItem.app(app).layoutItem == .app("com.a"))
        #expect(LaunchpadItem.folder(folder, apps: []).layoutItem == .folder("F"))
    }
}
