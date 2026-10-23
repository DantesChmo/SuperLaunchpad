import CoreGraphics
import Foundation
import Testing
@testable import SuperLaunchpad

// 7×5 cells of 100×80 with 10 pt between rows on a 1000 pt page: the grid
// spans x = 150…850. Slot s is centered at (200 + 100·(s % 7), 40 + 90·(s / 7));
// its icon + label box is 50×60 around that center.
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

private func appItem(_ id: String) -> LaunchpadItem {
    .app(entry(id))
}

private func entry(_ id: String) -> AppEntry {
    AppEntry(bundleIdentifier: id, displayName: id, appPath: "/Applications/\(id).app", pageIndex: 0, orderIndex: 0)
}

struct MarqueeGeometryTests {

    @Test func rectSpansBothCornersInEitherDirection() {
        let rect = GridGeometry.marqueeRect(from: CGPoint(x: 300, y: 100), to: CGPoint(x: 100, y: 40))
        #expect(rect == CGRect(x: 100, y: 40, width: 200, height: 60))
    }

    @Test func slotsWhoseHitBoxTouchesTheBand() {
        // x 210…310 touches slot 0 (175…225) and slot 1 (275…325).
        let band = CGRect(x: 210, y: 20, width: 100, height: 10)
        #expect(geometry().slots(intersecting: band, itemCount: 10) == [0, 1])
    }

    @Test func bandSpanningRowsSelectsTheBlock() {
        // From slot 1's box to slot 9's (row 1, column 2).
        let band = CGRect(x: 290, y: 50, width: 120, height: 80)
        #expect(geometry().slots(intersecting: band, itemCount: 20) == [1, 2, 8, 9])
    }

    @Test func gapBetweenBoxesSelectsNothing() {
        let band = CGRect(x: 230, y: 20, width: 40, height: 40)
        #expect(geometry().slots(intersecting: band, itemCount: 10).isEmpty)
    }

    @Test func flatBandStillCounts() {
        let band = GridGeometry.marqueeRect(from: CGPoint(x: 100, y: 40), to: CGPoint(x: 380, y: 40))
        #expect(geometry().slots(intersecting: band, itemCount: 10) == [0, 1, 2])
    }

    @Test func emptyCellsAreNotSlots() {
        let band = CGRect(x: 0, y: 0, width: 1000, height: 600)
        #expect(geometry().slots(intersecting: band, itemCount: 3) == [0, 1, 2])
    }
}

struct DragSessionGroupTests {

    @Test func liftingLeavesTheCompanionsOut() {
        let session = DragSession(itemID: "c", item: .app("c"), page: 0, slot: 1, grabOffset: .zero, companionIDs: ["a", "d"])
        #expect(session.lifting([entry("a"), entry("b"), entry("c"), entry("d")]).map(\.id) == ["b", "c"])
        #expect(session.isGroup)
    }

    @Test func singleDragLiftsNothingElse() {
        let session = DragSession(itemID: "c", item: .app("c"), page: 0, slot: 2, grabOffset: .zero)
        #expect(session.lifting([entry("a"), entry("c")]).map(\.id) == ["a", "c"])
        #expect(!session.isGroup)
        #expect(!session.hasMoved)
    }

    @Test func groupDropAlwaysChangesTheLayout() {
        let session = DragSession(itemID: "c", item: .app("c"), page: 0, slot: 1, grabOffset: .zero, companionIDs: ["a"])
        #expect(session.hasMoved)
    }

    @Test func previewOfTheLiftedPageClosesUpBehindTheCompanions() {
        var session = DragSession(itemID: "c", item: .app("c"), page: 0, slot: 1, grabOffset: .zero, companionIDs: ["a"])
        session.retarget(0)
        let items = [entry("a"), entry("b"), entry("c"), entry("d")]
        #expect(session.preview(session.lifting(items)).map(\.id) == ["c", "b", "d"])
    }
}

@MainActor
struct GridDragControllerGroupTests {

    private func context(_ pages: [[LaunchpadItem]]) -> GridDragController.GridContext {
        GridDragController.GridContext(
            pages: pages,
            page: 0,
            geometry: geometry(),
            frame: CGRect(x: 0, y: 0, width: 1000, height: 600),
            pagerPosition: 0
        )
    }

    @Test func liftingASelectedAppCarriesTheOthersAndCountsWithoutThem() {
        let controller = GridDragController()
        let pages = [["a", "b", "c", "d"].map(appItem)]
        // Grab c (slot 2) with a selected too.
        controller.update(
            start: CGPoint(x: 400, y: 40),
            pointer: CGPoint(x: 410, y: 40),
            grid: context(pages),
            flipPage: { _ in nil },
            companions: { $0 == "c" ? [entry("a")] : [] }
        )

        #expect(controller.session?.itemID == "c")
        #expect(controller.session?.companionIDs == ["a"])
        // b c d: c is at 1 once a is lifted with it.
        #expect(controller.session?.sourceSlot == 1)
        #expect(controller.liftedCompanions.map(\.id) == ["a"])
        controller.cancel()
        #expect(controller.liftedCompanions.isEmpty)
    }

    @Test func groupDropCommitsEvenWithoutMoving() {
        let controller = GridDragController()
        let pages = [["a", "b", "c"].map(appItem)]
        controller.update(
            start: CGPoint(x: 200, y: 40),
            pointer: CGPoint(x: 207, y: 40),
            grid: context(pages),
            flipPage: { _ in nil },
            companions: { _ in [entry("c")] }
        )
        var committed: DragSession?
        controller.end { session in
            committed = session
            return (session.page, session.targetSlot)
        }
        #expect(committed?.itemID == "a")
        #expect(committed?.companionIDs == ["c"])
        #expect(committed?.targetSlot == 0)
    }

    @Test func pressOnAnEmptySpotDrawsAMarqueeAndReportsTheAppsUnderIt() {
        let controller = GridDragController()
        let folder = LaunchpadItem.folder(FolderEntry(id: "F", title: "F", pageIndex: 0, orderIndex: 2), apps: [])
        let pages = [[appItem("a"), appItem("b"), folder]]
        var reported: [Set<String>] = []
        // Slot 3 is empty: from there back over a, b and the folder.
        let lifted = controller.update(
            start: CGPoint(x: 500, y: 40),
            pointer: CGPoint(x: 150, y: 75),
            grid: context(pages),
            flipPage: { _ in nil },
            marquee: { reported.append($0) }
        )

        #expect(!lifted)
        #expect(controller.session == nil)
        #expect(controller.marquee == CGRect(x: 150, y: 40, width: 350, height: 35))
        // Folders are never selected.
        #expect(reported == [["a", "b"]])
        #expect(controller.isTapSuppressed)

        controller.update(
            start: CGPoint(x: 500, y: 40),
            pointer: CGPoint(x: 290, y: 75),
            grid: context(pages),
            flipPage: { _ in nil },
            marquee: { reported.append($0) }
        )
        #expect(reported.last == ["b"])

        #expect(controller.end { _ in nil } == nil)
        #expect(controller.marquee == nil)
    }

    @Test func noMarqueeOutsideEditMode() {
        let controller = GridDragController()
        let pages = [[appItem("a")]]
        controller.update(start: CGPoint(x: 500, y: 40), pointer: CGPoint(x: 150, y: 75), grid: context(pages), flipPage: { _ in nil })
        #expect(controller.marquee == nil)
        #expect(!controller.isTapSuppressed)
        controller.cancel()
    }
}
