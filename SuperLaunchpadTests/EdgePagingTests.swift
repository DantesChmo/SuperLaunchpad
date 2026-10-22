import CoreGraphics
import Foundation
import Testing
@testable import SuperLaunchpad

// 7×5 cells of 100×80 with 10 pt between rows on a 1000 pt page: the grid
// spans x = 150…850, the margins beside it are the edge zones.
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

struct EdgeZoneTests {

    @Test(arguments: [
        (CGFloat(-20), -1), (0, -1), (149, -1),
        (150, nil), (500, nil), (850, nil),
        (851, 1), (1000, 1), (1100, 1)
    ] as [(CGFloat, Int?)])
    func edgeDirection(x: CGFloat, expected: Int?) {
        #expect(geometry().edgeDirection(at: CGPoint(x: x, y: 200)) == expected)
    }

    @Test func zoneMatchesHorizontalPaddingOnAFullScreenPage() {
        let metrics = LayoutMetrics(screenWidth: 1920, screenHeight: 1080)
        let g = GridGeometry(metrics: metrics, pageWidth: 1920)
        #expect(g.edgeDirection(at: CGPoint(x: metrics.horizontalPadding - 1, y: 0)) == -1)
        #expect(g.edgeDirection(at: CGPoint(x: metrics.horizontalPadding + 1, y: 0)) == nil)
        #expect(g.edgeDirection(at: CGPoint(x: 1920 - metrics.horizontalPadding + 1, y: 0)) == 1)
    }
}

struct EdgeDwellTests {

    @Test func firstFlipComesAfterTheDwell() {
        var dwell = EdgeDwell()
        #expect(dwell.update(direction: 1, now: 10) == nil)
        #expect(dwell.update(direction: 1, now: 10 + Drag.edgeDwell / 2) == nil)
        #expect(dwell.update(direction: 1, now: 10 + Drag.edgeDwell) == 1)
    }

    @Test func flipsRepeatWhileThePointerStays() {
        var dwell = EdgeDwell()
        _ = dwell.update(direction: -1, now: 0)
        #expect(dwell.update(direction: -1, now: Drag.edgeDwell) == -1)
        #expect(dwell.update(direction: -1, now: Drag.edgeDwell + Drag.edgeRepeat / 2) == nil)
        #expect(dwell.update(direction: -1, now: Drag.edgeDwell + Drag.edgeRepeat) == -1)
        #expect(dwell.deadline == Drag.edgeDwell + 2 * Drag.edgeRepeat)
    }

    @Test func leavingTheZoneStartsOver() {
        var dwell = EdgeDwell()
        _ = dwell.update(direction: 1, now: 0)
        #expect(dwell.update(direction: nil, now: 0.4) == nil)
        #expect(dwell.deadline == nil)
        #expect(dwell.update(direction: 1, now: 0.45) == nil)
        #expect(dwell.update(direction: 1, now: Drag.edgeDwell + 0.1) == nil)
        #expect(dwell.update(direction: 1, now: 0.45 + Drag.edgeDwell) == 1)
    }

    @Test func switchingSidesStartsOver() {
        var dwell = EdgeDwell()
        _ = dwell.update(direction: 1, now: 0)
        #expect(dwell.update(direction: -1, now: 0.3) == nil)
        #expect(dwell.update(direction: -1, now: Drag.edgeDwell) == nil)
        #expect(dwell.update(direction: -1, now: 0.3 + Drag.edgeDwell) == -1)
    }

    @Test func outsideTheZonesNothingFires() {
        var dwell = EdgeDwell()
        #expect(dwell.update(direction: nil, now: 0) == nil)
        #expect(dwell.update(direction: nil, now: 100) == nil)
        #expect(dwell.deadline == nil)
    }

    @Test func resetForgetsTheZone() {
        var dwell = EdgeDwell()
        _ = dwell.update(direction: 1, now: 0)
        dwell.reset()
        #expect(dwell == EdgeDwell())
        #expect(dwell.update(direction: 1, now: Drag.edgeDwell) == nil)
    }
}

struct CrossPageDragSessionTests {

    private func carried(fromSlot slot: Int = 1, toPage page: Int = 1, slot target: Int) -> DragSession {
        var s = DragSession(itemID: "m", item: .app("m"), page: 0, slot: slot, grabOffset: .zero)
        s.switchPage(to: page, slot: target)
        return s
    }

    @Test func carryingToAnotherPageCountsAsAMove() {
        var s = DragSession(itemID: "m", item: .app("m"), page: 0, slot: 1, grabOffset: .zero)
        s.switchPage(to: 1, slot: 1)
        #expect(s.hasMoved)
        #expect(s.sourcePage == 0)
        #expect(s.sourceSlot == 1)
    }

    @Test func sourcePageKeepsItsOrderWhileTheItemIsAway() {
        let s = carried(slot: 0)
        #expect(s.preview(["a", "m", "b"], page: 0, moved: "m", capacity: 35) == ["a", "m", "b"])
        #expect(s.hidesItem(onPage: 0))
    }

    @Test func destinationPageMakesRoomAtTheTarget() {
        let s = carried(slot: 1)
        #expect(s.preview(["x", "y", "z"], page: 1, moved: "m", capacity: 35) == ["x", "m", "y", "z"])
        #expect(s.hidesItem(onPage: 1))
        #expect(!s.hidesItem(onPage: 2))
    }

    @Test func targetPastTheEndAppends() {
        let s = carried(slot: 9)
        #expect(s.preview(["x", "y"], page: 1, moved: "m", capacity: 35) == ["x", "y", "m"])
    }

    @Test func emptyTrailingPageShowsJustTheItem() {
        let s = carried(toPage: 2, slot: 0)
        #expect(s.preview([String](), page: 2, moved: "m", capacity: 35) == ["m"])
    }

    @Test func fullPageHidesItsOverflow() {
        let s = carried(slot: 0)
        #expect(s.preview(["x", "y", "z"], page: 1, moved: "m", capacity: 3) == ["m", "x", "y"])
    }

    @Test func otherPagesAreUntouched() {
        let s = carried(slot: 0)
        #expect(s.preview(["p", "q"], page: 2, moved: "m", capacity: 35) == ["p", "q"])
    }

    @Test func samePagePreviewMatchesTheSingleArgumentForm() {
        var s = DragSession(itemID: "c", item: .app("c"), page: 0, slot: 2, grabOffset: .zero)
        s.retarget(0)
        #expect(s.preview(["a", "b", "c"], page: 0, moved: "c", capacity: 35) == ["c", "a", "b"])
    }

    @Test func revertGoesBackToTheSourcePage() {
        var s = carried(slot: 0)
        s.revert()
        #expect(!s.hasMoved)
        #expect(s.page == 0)
        #expect(s.targetSlot == 1)
    }

    @Test func committedLocationEndsThePreview() {
        var s = carried(slot: 3)
        s.markCommitted(page: 0, slot: 3)
        #expect(!s.hasMoved)
        #expect(s.page == 0)
        #expect(s.preview(["x", "y", "z", "m"], page: 0, moved: "m", capacity: 35) == ["x", "y", "z", "m"])
    }

    @Test func noPageSwitchWhileDropping() {
        var s = DragSession(itemID: "m", item: .app("m"), page: 0, slot: 1, grabOffset: .zero)
        s.beginDrop()
        s.switchPage(to: 1, slot: 0)
        #expect(s.page == 0)
        #expect(!s.hasMoved)
    }
}

@MainActor
struct GridDragControllerEdgeTests {

    private func app(_ id: String, page: Int, order: Int) -> LaunchpadItem {
        .app(AppEntry(bundleIdentifier: id, displayName: id, appPath: "/Applications/\(id).app", pageIndex: page, orderIndex: order))
    }

    // Page 0: a, b — page 1: c. Slot 0's cell center is (200, 40).
    private var pages: [[LaunchpadItem]] {
        [[app("a", page: 0, order: 0), app("b", page: 0, order: 1)], [app("c", page: 1, order: 0)]]
    }

    private final class Clock {
        var now: TimeInterval = 100
    }

    private func drag(
        _ controller: GridDragController,
        to pointer: CGPoint,
        page: Int = 0,
        flipPage: @escaping (Int) -> Int?
    ) -> Bool {
        controller.update(
            start: CGPoint(x: 200, y: 40),
            pointer: pointer,
            pages: pages,
            page: page,
            geometry: geometry(),
            pagerPosition: Double(page),
            pageWidth: 1000,
            flipPage: flipPage
        )
    }

    @Test func holdingInTheRightMarginFlipsToTheNextPageAfterTheDwell() {
        let clock = Clock()
        let controller = GridDragController(clock: { clock.now })
        var flips: [Int] = []
        let flipPage: (Int) -> Int? = { direction in
            flips.append(direction)
            return 1
        }

        #expect(drag(controller, to: CGPoint(x: 950, y: 40), flipPage: flipPage))
        #expect(flips.isEmpty)

        clock.now += Drag.edgeDwell
        _ = drag(controller, to: CGPoint(x: 951, y: 40), flipPage: flipPage)
        #expect(flips == [1])
        #expect(controller.session?.page == 1)
        // Past the last item of the page it was carried to.
        #expect(controller.session?.targetSlot == 1)

        var committed: DragSession?
        let landed = controller.end { session in
            committed = session
            return (session.page, session.targetSlot)
        }
        #expect(committed?.page == 1)
        #expect(committed?.targetSlot == 1)
        #expect(committed?.item == .app("a"))
        #expect(landed == 1)
    }

    @Test func noFlipBeforeTheDwellOrOutsideTheMargins() {
        let clock = Clock()
        let controller = GridDragController(clock: { clock.now })
        var flips = 0
        let flipPage: (Int) -> Int? = { _ in
            flips += 1
            return 1
        }

        _ = drag(controller, to: CGPoint(x: 950, y: 40), flipPage: flipPage)
        clock.now += Drag.edgeDwell / 2
        _ = drag(controller, to: CGPoint(x: 950, y: 40), flipPage: flipPage)
        // Back over the grid: the timer starts over.
        _ = drag(controller, to: CGPoint(x: 500, y: 40), flipPage: flipPage)
        clock.now += Drag.edgeDwell
        _ = drag(controller, to: CGPoint(x: 500, y: 40), flipPage: flipPage)
        _ = drag(controller, to: CGPoint(x: 950, y: 40), flipPage: flipPage)

        #expect(flips == 0)
        #expect(controller.session?.page == 0)
        controller.cancel()
    }

    @Test func pressOutsideAnIconNeverFlips() {
        let clock = Clock()
        let controller = GridDragController(clock: { clock.now })
        var flips = 0
        let flipPage: (Int) -> Int? = { _ in
            flips += 1
            return 1
        }
        let lifted = controller.update(
            start: CGPoint(x: 50, y: 40),
            pointer: CGPoint(x: 950, y: 40),
            pages: pages,
            page: 0,
            geometry: geometry(),
            pagerPosition: 0,
            pageWidth: 1000,
            flipPage: flipPage
        )
        clock.now += Drag.edgeDwell * 4
        _ = drag(controller, to: CGPoint(x: 951, y: 40), flipPage: flipPage)

        #expect(!lifted)
        #expect(flips == 0)
        #expect(!controller.isActive)
        controller.cancel()
    }

    @Test func cancelDropRevertsToTheSourcePageWithoutCommitting() {
        let clock = Clock()
        let controller = GridDragController(clock: { clock.now })
        let flipPage: (Int) -> Int? = { _ in 1 }

        _ = drag(controller, to: CGPoint(x: 950, y: 40), flipPage: flipPage)
        clock.now += Drag.edgeDwell
        _ = drag(controller, to: CGPoint(x: 950, y: 40), flipPage: flipPage)
        #expect(controller.session?.page == 1)

        // Outside a view the landing animation completes at once, so only
        // the returned source page is left to check.
        #expect(controller.cancelDrop() == 0)

        // The rest of the gesture is ignored, and the release commits nothing.
        clock.now += Drag.edgeDwell * 4
        #expect(drag(controller, to: CGPoint(x: 50, y: 40), flipPage: flipPage) == false)
        var commits = 0
        #expect(controller.end { _ in
            commits += 1
            return (0, 0)
        } == nil)
        #expect(commits == 0)
        #expect(controller.cancelDrop() == nil)
    }

    @Test func refusedCrossPageDropFliesBackToTheSourcePage() {
        let clock = Clock()
        let controller = GridDragController(clock: { clock.now })
        let flipPage: (Int) -> Int? = { _ in 1 }

        _ = drag(controller, to: CGPoint(x: 950, y: 40), flipPage: flipPage)
        clock.now += Drag.edgeDwell
        _ = drag(controller, to: CGPoint(x: 950, y: 40), flipPage: flipPage)

        #expect(controller.end { _ in nil } == 0)
    }
}

@MainActor
struct TrailingDragPageTests {

    private func makeTempDB() throws -> (AppDatabase, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("slp-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("test.db").path
        return (try AppDatabase(path: path), dir)
    }

    private func app(_ bundleID: String, page: Int, order: Int) -> AppEntry {
        AppEntry(
            bundleIdentifier: bundleID,
            displayName: bundleID,
            appPath: "/Applications/\(bundleID).app",
            pageIndex: page,
            orderIndex: order
        )
    }

    // `layout[page]` lists the app IDs on that page.
    private func makeViewModel(_ db: AppDatabase, _ layout: [[String]]) throws -> LaunchpadViewModel {
        let apps = layout.enumerated().flatMap { page, ids in
            ids.enumerated().map { order, id in app(id, page: page, order: order) }
        }
        try db.saveApps(apps)
        let vm = LaunchpadViewModel(database: db)
        vm.apps = apps
        return vm
    }

    private func pageIDs(_ vm: LaunchpadViewModel) -> [[String]] {
        vm.pages.map { $0.map(\.id) }
    }

    private func storedPageIDs(_ db: AppDatabase) throws -> [[String]] {
        GridLayout(apps: try db.fetchAllApps(), folders: try db.fetchAllFolders()).pages.map { page in
            page.map { item in
                switch item {
                case .app(let id), .folder(let id): id
                }
            }
        }
    }

    @Test func trailingPageNeedsADrag() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db, [["a", "b"]])

        #expect(vm.openTrailingDragPage() == false)
        #expect(!vm.hasTrailingDragPage)
        #expect(vm.displayedPageCount == 1)
    }

    @Test func trailingPageIsShownOnceAndRemovedWhenTheDragEnds() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db, [["a", "b"]])

        vm.beginDragSession()
        #expect(vm.openTrailingDragPage())
        #expect(vm.openTrailingDragPage() == false)
        #expect(vm.displayedPageCount == 2)
        #expect(pageIDs(vm) == [["a", "b"]])

        // Cancelled: nothing was dropped there.
        vm.endDragSession()
        #expect(!vm.hasTrailingDragPage)
        #expect(vm.displayedPageCount == 1)
        #expect(try storedPageIDs(db) == [["a", "b"]])
    }

    @Test func dropOnTheTrailingPageCreatesIt() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db, [["a", "b"]])

        vm.beginDragSession()
        vm.openTrailingDragPage()
        #expect(vm.moveItem(.app("a"), toPage: 1, slot: 0))
        vm.endDragSession()

        #expect(pageIDs(vm) == [["b"], ["a"]])
        #expect(vm.displayedPageCount == 2)
        #expect(try storedPageIDs(db) == [["b"], ["a"]])
    }

    @Test func movingTheOnlyItemOfAPageClosesItUp() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db, [["a"], ["b", "c"]])

        vm.beginDragSession()
        #expect(vm.moveItem(.app("a"), toPage: 1, slot: 2))
        vm.endDragSession()

        #expect(pageIDs(vm) == [["b", "c", "a"]])
        #expect(try storedPageIDs(db) == [["b", "c", "a"]])
    }

    @Test func crossPageDropOntoAFullPageSpills() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let full = (0..<Grid.appsPerPage).map { "p\($0)" }
        let vm = try makeViewModel(db, [["m", "n"], full])

        vm.beginDragSession()
        #expect(vm.moveItem(.app("m"), toPage: 1, slot: 0))
        vm.endDragSession()

        let expected = [["n"], ["m"] + full.dropLast(), [full[full.count - 1]]]
        #expect(pageIDs(vm) == expected)
        #expect(try storedPageIDs(db) == expected)
    }

    @Test func cancelDragNeedsADrag() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db, [["a", "b"]])

        #expect(vm.cancelDrag() == false)
        #expect(vm.dragCancelRequest == 0)

        vm.beginDragSession()
        #expect(vm.cancelDrag())
        #expect(vm.dragCancelRequest == 1)
        vm.endDragSession()
        #expect(vm.cancelDrag() == false)
        #expect(try storedPageIDs(db) == [["a", "b"]])
    }
}
