import CoreGraphics
import Foundation
import Testing
@testable import SuperLaunchpad

// 7×5 cells of 100×80 with 10 pt between rows on a 1000 pt page: slot 0 is
// x 150…250, its 50×60 hit box x 175…225 / y 10…70. With a one-line label the
// icon is y 11.2…61.2, so its merge zone is x 187.5…212.5 / y 23.7…48.7.
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

struct MergeZoneTests {

    @Test(arguments: [
        (CGPoint(x: 200, y: 36), GridGeometry.Zone.center),
        (CGPoint(x: 188, y: 24), .center),
        (CGPoint(x: 212, y: 48), .center),
        (CGPoint(x: 185, y: 36), .gap),
        (CGPoint(x: 215, y: 36), .gap),
        (CGPoint(x: 200, y: 20), .gap),
        (CGPoint(x: 200, y: 60), .gap),
        (CGPoint(x: 160, y: 36), .gap)
    ])
    func zoneIsTheMiddleOfTheIcon(point: CGPoint, expected: GridGeometry.Zone) {
        #expect(geometry().zone(at: point, slot: 0) == expected)
    }

    @Test func iconSitsAboveTheMiddleOfItsHitBox() {
        let icon = geometry().iconFrame(slot: 0)
        #expect(icon.width == 50)
        #expect(icon.height == 50)
        #expect(icon.minX == 175)
        #expect(abs(icon.minY - 11.2) < 0.001)
    }

    @Test func mergeSlotNeedsAnOccupiedCellAndTheCenter() {
        let g = geometry()
        // Slot 1's icon middle.
        let middle = CGPoint(x: 300, y: 36)
        #expect(g.mergeSlot(at: middle, itemCount: 2) == 1)
        #expect(g.mergeSlot(at: middle, itemCount: 1) == nil)
        #expect(g.mergeSlot(at: CGPoint(x: 260, y: 36), itemCount: 2) == nil)
        // Second row, slot 7.
        #expect(g.mergeSlot(at: CGPoint(x: 200, y: 126), itemCount: 8) == 7)
    }

    @Test func zoneScalesWithRealMetrics() {
        let metrics = LayoutMetrics(screenWidth: 1920, screenHeight: 1080)
        let g = GridGeometry(metrics: metrics, pageWidth: 1920)
        let icon = g.iconFrame(slot: 3)
        #expect(icon.width == metrics.iconSize)
        #expect(g.zone(at: CGPoint(x: icon.midX, y: icon.midY), slot: 3) == .center)
        #expect(g.zone(at: CGPoint(x: icon.minX + 1, y: icon.midY), slot: 3) == .gap)
    }

    @Test func folderGeometryMatchesThePopupGrid() {
        let metrics = LayoutMetrics(screenWidth: 1920, screenHeight: 1080)
        let g = GridGeometry.folder(metrics: metrics)
        #expect(g.columns == FolderGrid.columns)
        #expect(g.rows == FolderGrid.rows)
        #expect(g.origin == .zero)
        #expect(g.gridSize.width == metrics.itemWidth * CGFloat(FolderGrid.columns))
        #expect(g.hitSize.width == metrics.iconSize * FolderGrid.iconScale)
        let itemHeight = metrics.iconSize * FolderGrid.iconScale + LayoutMetrics.iconLabelSpacing + metrics.labelFont * 3
        #expect(g.gridSize.height == itemHeight * 3 + FolderGrid.rowSpacing * 2)
    }
}

struct AppCategoryTitleTests {

    @Test(arguments: [
        ("public.app-category.developer-tools", "Developer Tools"),
        ("public.app-category.graphics-design", "Graphics & Design"),
        ("public.app-category.healthcare-fitness", "Health & Fitness"),
        ("public.app-category.social-networking", "Social Networking"),
        ("public.app-category.productivity", "Productivity"),
        ("public.app-category.music", "Music"),
        ("public.app-category.action-games", "Games"),
        ("public.app-category.games", "Games"),
        ("public.app-category.Utilities", "Utilities")
    ])
    func readableTitle(type: String, expected: String) {
        #expect(AppCategoryTitle.title(forCategoryType: type) == expected)
    }

    @Test(arguments: [nil, "", "com.example.thing", "public.app-category."] as [String?])
    func noTitleForMissingOrMalformedTypes(type: String?) {
        #expect(AppCategoryTitle.title(forCategoryType: type) == nil)
    }

    @Test func titleComesFromTheBundlesInfoPlist() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("slp-cat-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = try makeBundle(in: dir, category: "public.app-category.developer-tools")

        #expect(AppCategoryTitle.folderTitle(forAppAt: path, fallback: "Folder") == "Developer Tools")
        #expect(AppCategoryTitle.folderTitle(forAppAt: try makeBundle(in: dir, name: "Plain", category: nil), fallback: "Folder") == "Folder")
        #expect(AppCategoryTitle.folderTitle(forAppAt: dir.appendingPathComponent("Missing.app").path, fallback: "Folder") == "Folder")
    }
}

// Writes `<dir>/<name>.app/Contents/Info.plist` and returns the bundle path.
func makeBundle(in dir: URL, name: String = "Target", category: String?) throws -> String {
    let bundle = dir.appendingPathComponent("\(name).app")
    let contents = bundle.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    var info: [String: Any] = ["CFBundleIdentifier": "com.test.\(name)", "CFBundlePackageType": "APPL"]
    if let category {
        info[AppCategoryTitle.typeKey] = category
    }
    let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try data.write(to: contents.appendingPathComponent("Info.plist"))
    return bundle.path
}

struct FolderDragSessionTests {

    private func inFolder(index: Int = 0) -> DragSession {
        DragSession(appID: "x", folderID: "F", index: index, grabOffset: .zero)
    }

    @Test func liftedInAFolderReordersTheFolderOnly() {
        var session = inFolder(index: 0)
        session.retarget(2)
        #expect(session.isInFolder)
        #expect(session.hasMoved)
        #expect(session.preview(["x", "y", "z"]) == ["y", "z", "x"])
        // The grid pages are left alone.
        #expect(session.preview(["a", "b"], page: 0, moved: "x", capacity: 35) == ["a", "b"])
        #expect(!session.hidesItem(onPage: 0))
    }

    @Test func leavingTheFolderCarriesTheAppOverTheGrid() {
        var session = inFolder()
        session.leaveFolder(tilePage: 0, tileSlot: 2, page: 0, slot: 1)
        #expect(!session.isInFolder)
        #expect(session.isOutOfFolder)
        #expect(session.insertsItem)
        #expect(session.hasMoved)
        #expect(session.sourceFolderID == "F")
        // Inserted, the folder tile is not moved.
        #expect(session.preview(["a", "b", "F"], page: 0, moved: "x", capacity: 35) == ["a", "x", "b", "F"])
    }

    @Test func refusedDropReturnsToTheFolderTileWithoutInserting() {
        var session = inFolder()
        session.leaveFolder(tilePage: 0, tileSlot: 2, page: 1, slot: 0)
        session.setMergeTarget("c")
        session.revert()
        #expect(session.isReturningToFolder)
        #expect(session.mergeTargetID == nil)
        #expect(session.page == 0)
        #expect(session.targetSlot == 2)
        #expect(!session.insertsItem)
        #expect(session.preview(["a", "b", "F"], page: 0, moved: "x", capacity: 35) == ["a", "b", "F"])
    }

    @Test func committedDropOutOfTheFolderEndsThePreview() {
        var session = inFolder()
        session.leaveFolder(tilePage: 0, tileSlot: 2, page: 0, slot: 0)
        session.markCommitted(page: 0, slot: 0)
        #expect(session.sourceFolderID == nil)
        #expect(!session.hasMoved)
        #expect(session.preview(["x", "a", "b", "F"], page: 0, moved: "x", capacity: 35) == ["x", "a", "b", "F"])
    }

    @Test func mergeTargetNeverTheItemItselfAndClearedByPaging() {
        var session = DragSession(itemID: "a", item: .app("a"), page: 0, slot: 0, grabOffset: .zero)
        session.setMergeTarget("a")
        #expect(session.mergeTargetID == nil)
        session.setMergeTarget("b")
        #expect(session.mergeTargetID == "b")
        #expect(!session.isMerging)
        session.switchPage(to: 1, slot: 0)
        #expect(session.mergeTargetID == nil)
    }

    @Test func mergingDropShrinksIntoTheTarget() {
        var session = DragSession(itemID: "a", item: .app("a"), page: 0, slot: 0, grabOffset: .zero)
        session.setMergeTarget("b")
        session.beginDrop()
        #expect(session.isMerging)
        session.setMergeTarget(nil)
        #expect(session.mergeTargetID == "b")
    }
}

@MainActor
struct GridDragControllerMergeTests {

    private func app(_ id: String, order: Int) -> LaunchpadItem {
        .app(AppEntry(bundleIdentifier: id, displayName: id, appPath: "/Applications/\(id).app", pageIndex: 0, orderIndex: order))
    }

    private func context(_ pages: [[LaunchpadItem]]) -> GridDragController.GridContext {
        GridDragController.GridContext(
            pages: pages,
            page: 0,
            geometry: geometry(),
            frame: CGRect(x: 0, y: 0, width: 1000, height: 600),
            pagerPosition: 0
        )
    }

    // Lifts slot 0 (grabbed at its cell center) and moves it to `pointer`.
    private func drag(_ controller: GridDragController, _ pages: [[LaunchpadItem]], to pointer: CGPoint) {
        controller.update(start: CGPoint(x: 200, y: 40), pointer: pointer, grid: context(pages), flipPage: { _ in nil })
    }

    @Test func appRestingOnAnotherAppsMiddleWaitsToMerge() {
        let controller = GridDragController()
        let pages = [[app("a", order: 0), app("b", order: 1)]]
        drag(controller, pages, to: CGPoint(x: 210, y: 40))
        drag(controller, pages, to: CGPoint(x: 300, y: 36))

        #expect(controller.pendingMerge == "b")
        #expect(controller.session?.targetSlot == 0)
        controller.cancel()
    }

    @Test func gapOfTheCellDoesNotMerge() {
        let controller = GridDragController()
        let pages = [[app("a", order: 0), app("b", order: 1)]]
        drag(controller, pages, to: CGPoint(x: 210, y: 40))
        drag(controller, pages, to: CGPoint(x: 265, y: 36))

        #expect(controller.pendingMerge == nil)
        controller.cancel()
    }

    @Test func liftedFolderNeverMerges() {
        let controller = GridDragController()
        let folder = LaunchpadItem.folder(FolderEntry(id: "F", title: "F", pageIndex: 0, orderIndex: 0), apps: [])
        let pages = [[folder, app("b", order: 1)]]
        drag(controller, pages, to: CGPoint(x: 210, y: 40))
        drag(controller, pages, to: CGPoint(x: 300, y: 36))

        #expect(controller.session?.item == .folder("F"))
        #expect(controller.pendingMerge == nil)
        controller.cancel()
    }
}

@MainActor
struct FolderDragViewModelTests {

    private func makeTempDB() throws -> (AppDatabase, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("slp-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("test.db").path
        return (try AppDatabase(path: path), dir)
    }

    private func app(
        _ bundleID: String,
        page: Int? = nil,
        order: Int? = nil,
        folderID: String? = nil,
        folderOrder: Int? = nil,
        path: String? = nil
    ) -> AppEntry {
        AppEntry(
            bundleIdentifier: bundleID,
            displayName: bundleID,
            appPath: path ?? "/nonexistent/\(bundleID).app",
            pageIndex: page,
            orderIndex: order,
            folderID: folderID,
            folderOrderIndex: folderOrder
        )
    }

    // Page a, b, folder F(x, y), c.
    private func makeViewModel(_ db: AppDatabase, bPath: String? = nil, folderApps: [String] = ["x", "y"]) throws -> LaunchpadViewModel {
        let folders = [FolderEntry(id: "F", title: "Tools", pageIndex: 0, orderIndex: 2)]
        var apps = [
            app("a", page: 0, order: 0),
            app("b", page: 0, order: 1, path: bPath),
            app("c", page: 0, order: 3)
        ]
        for (index, id) in folderApps.enumerated() {
            apps.append(app(id, folderID: "F", folderOrder: index))
        }
        try db.saveFolders(folders)
        try db.saveApps(apps)
        let vm = LaunchpadViewModel(database: db)
        vm.folders = folders
        vm.apps = apps
        return vm
    }

    private func pageIDs(_ vm: LaunchpadViewModel) -> [[String]] {
        vm.pages.map { $0.map(\.id) }
    }

    private func storedLayout(_ db: AppDatabase) throws -> GridLayout {
        GridLayout(apps: try db.fetchAllApps(), folders: try db.fetchAllFolders())
    }

    private func gridSession(_ id: String, slot: Int, target: Int, mergeInto: String? = nil) -> DragSession {
        var session = DragSession(itemID: id, item: .app(id), page: 0, slot: slot, grabOffset: .zero)
        session.retarget(target)
        session.setMergeTarget(mergeInto)
        return session
    }

    @Test func appOnAppMakesAFolderTitledByTheTargetsCategory() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let bPath = try makeBundle(in: dir, name: "B", category: "public.app-category.developer-tools")
        let vm = try makeViewModel(db, bPath: bPath)

        let outcome = try #require(vm.editing.commitDrop(gridSession("a", slot: 0, target: 0, mergeInto: "b")))
        let folderID = try #require(outcome.createdFolderID)

        #expect(pageIDs(vm) == [[folderID, "F", "c"]])
        #expect(outcome.page == 0)
        #expect(outcome.slot == 0)
        #expect(vm.folders.first { $0.id == folderID }?.title == "Developer Tools")
        #expect(vm.folderApps(folderID).map(\.id) == ["b", "a"])
        #expect(try storedLayout(db) == GridLayout(apps: vm.apps, folders: vm.folders))
    }

    @Test func appOnAppWithoutACategoryFallsBackToFolder() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)

        let outcome = try #require(vm.editing.commitDrop(gridSession("c", slot: 3, target: 3, mergeInto: "a")))
        let folderID = try #require(outcome.createdFolderID)
        #expect(vm.folders.first { $0.id == folderID }?.title == EditingModel.defaultFolderTitle)
        #expect(pageIDs(vm) == [[folderID, "b", "F"]])
    }

    @Test func appOnFolderAddsItAtTheEnd() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)

        let outcome = try #require(vm.editing.commitDrop(gridSession("a", slot: 0, target: 0, mergeInto: "F")))
        #expect(outcome.createdFolderID == nil)
        #expect(pageIDs(vm) == [["b", "F", "c"]])
        #expect(outcome.slot == 1)
        #expect(vm.folderApps("F").map(\.id) == ["x", "y", "a"])
        #expect(try storedLayout(db) == GridLayout(apps: vm.apps, folders: vm.folders))
    }

    @Test func folderIsNeverMergedIntoAnything() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        var session = DragSession(itemID: "F", item: .folder("F"), page: 0, slot: 2, grabOffset: .zero)
        session.setMergeTarget("a")

        #expect(vm.editing.commitDrop(session) == nil)
        #expect(pageIDs(vm) == [["a", "b", "F", "c"]])
    }

    @Test func reorderInsideTheFolder() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db, folderApps: ["x", "y", "z"])
        var session = DragSession(appID: "x", folderID: "F", index: 0, grabOffset: .zero)
        session.retarget(2)

        let outcome = try #require(vm.editing.commitDrop(session))
        #expect(outcome.slot == 2)
        #expect(vm.folderApps("F").map(\.id) == ["y", "z", "x"])
        #expect(pageIDs(vm) == [["a", "b", "F", "c"]])
        #expect(try storedLayout(db) == GridLayout(apps: vm.apps, folders: vm.folders))
    }

    @Test func dropOutOfTheFolderPutsTheAppOnTheGrid() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        var session = DragSession(appID: "x", folderID: "F", index: 0, grabOffset: .zero)
        session.leaveFolder(tilePage: 0, tileSlot: 2, page: 0, slot: 1)

        let outcome = try #require(vm.editing.commitDrop(session))
        #expect(pageIDs(vm) == [["a", "x", "b", "F", "c"]])
        #expect(outcome.page == 0)
        #expect(outcome.slot == 1)
        #expect(vm.folderApps("F").map(\.id) == ["y"])
        #expect(try storedLayout(db) == GridLayout(apps: vm.apps, folders: vm.folders))
    }

    @Test func folderLeftEmptyDissolves() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db, folderApps: ["x"])
        vm.openFolder(try #require(vm.folders.first))
        var session = DragSession(appID: "x", folderID: "F", index: 0, grabOffset: .zero)
        session.leaveFolder(tilePage: 0, tileSlot: 2, page: 0, slot: 4)

        #expect(vm.editing.commitDrop(session) != nil)
        #expect(pageIDs(vm) == [["a", "b", "c", "x"]])
        #expect(vm.folders.isEmpty)
        #expect(vm.openFolderID == nil)
        #expect(try db.fetchAllFolders().isEmpty)
    }

    @Test func oneAppFolderStays() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        var session = DragSession(appID: "y", folderID: "F", index: 1, grabOffset: .zero)
        session.leaveFolder(tilePage: 0, tileSlot: 2, page: 0, slot: 0)

        #expect(vm.editing.commitDrop(session) != nil)
        #expect(vm.folderApps("F").map(\.id) == ["x"])
        #expect(pageIDs(vm) == [["y", "a", "b", "F", "c"]])
    }

    @Test func droppedBackOnItsOwnFolderChangesNothing() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        var session = DragSession(appID: "x", folderID: "F", index: 0, grabOffset: .zero)
        session.leaveFolder(tilePage: 0, tileSlot: 2, page: 0, slot: 2)
        session.setMergeTarget("F")

        let outcome = try #require(vm.editing.commitDrop(session))
        #expect(outcome.page == 0)
        #expect(outcome.slot == 2)
        #expect(vm.folderApps("F").map(\.id) == ["x", "y"])
    }

    @Test func appTakenOutOfAFolderMergesIntoAnotherApp() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db, folderApps: ["x"])
        var session = DragSession(appID: "x", folderID: "F", index: 0, grabOffset: .zero)
        session.leaveFolder(tilePage: 0, tileSlot: 2, page: 0, slot: 0)
        session.setMergeTarget("c")

        let outcome = try #require(vm.editing.commitDrop(session))
        let folderID = try #require(outcome.createdFolderID)
        // F emptied and dissolved; c became the new folder.
        #expect(pageIDs(vm) == [["a", "b", folderID]])
        #expect(vm.folderApps(folderID).map(\.id) == ["c", "x"])
    }

    // The whole path: lift in the open folder, leave its card (the folder
    // closes), drop on the grid, persist.
    @Test func dragOutOfTheFolderContinuesOnTheGridAndPersists() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        let folder = try #require(vm.folders.first)
        vm.openFolder(folder)

        let controller = GridDragController()
        var closed = 0
        let card = CGRect(x: 300, y: 100, width: 400, height: 300)
        let folderGrid = CGRect(x: 300, y: 150, width: 400, height: 260)
        let folderGeometry = GridGeometry(
            columns: 4,
            rows: 3,
            cellSize: CGSize(width: 100, height: 80),
            rowSpacing: 10,
            hitSize: CGSize(width: 50, height: 60),
            origin: .zero
        )
        func update(_ pointer: CGPoint) -> Bool {
            let grid = GridDragController.GridContext(
                pages: vm.pages,
                page: 0,
                geometry: geometry(),
                frame: CGRect(x: 0, y: 0, width: 1000, height: 600),
                pagerPosition: 0
            )
            let open = vm.openFolderID.map {
                GridDragController.FolderContext(
                    folderID: $0,
                    apps: vm.folderApps($0),
                    page: 0,
                    geometry: folderGeometry,
                    frames: .init(card: card, grid: folderGrid, page: 0)
                )
            }
            return controller.update(
                start: CGPoint(x: 350, y: 190),
                pointer: pointer,
                grid: grid,
                folder: open,
                flipPage: { _ in nil },
                leaveFolder: {
                    closed += 1
                    vm.closeFolder()
                }
            )
        }

        // x is folder slot 0 (cell center 350, 190).
        #expect(update(CGPoint(x: 360, y: 190)))
        #expect(controller.session?.isInFolder == true)
        #expect(controller.session?.itemID == "x")

        // Out of the card, over the grid's last row: the end of page 0.
        _ = update(CGPoint(x: 800, y: 500))
        #expect(closed == 1)
        #expect(vm.openFolderID == nil)
        #expect(controller.session?.isOutOfFolder == true)
        #expect(controller.session?.targetSlot == 4)

        let landed = controller.end { session in
            vm.editing.commitDrop(session).map { ($0.page, $0.slot) }
        }
        #expect(landed == 0)
        #expect(pageIDs(vm) == [["a", "b", "F", "c", "x"]])
        #expect(vm.folderApps("F").map(\.id) == ["y"])
        #expect(try storedLayout(db) == GridLayout(apps: vm.apps, folders: vm.folders))
    }

    @Test func pressOutsideTheOpenFolderCardLiftsNothing() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        let controller = GridDragController()
        let grid = GridDragController.GridContext(
            pages: vm.pages,
            page: 0,
            geometry: geometry(),
            frame: CGRect(x: 0, y: 0, width: 1000, height: 600),
            pagerPosition: 0
        )
        let open = GridDragController.FolderContext(
            folderID: "F",
            apps: vm.folderApps("F"),
            page: 0,
            geometry: .folder(metrics: LayoutMetrics(screenWidth: 1000, screenHeight: 600)),
            frames: .init(card: CGRect(x: 300, y: 100, width: 400, height: 300), grid: CGRect(x: 300, y: 150, width: 400, height: 260), page: 0)
        )
        // Over grid icon `a`, but behind the open folder's backdrop.
        let lifted = controller.update(start: CGPoint(x: 200, y: 40), pointer: CGPoint(x: 260, y: 40), grid: grid, folder: open, flipPage: { _ in nil })
        #expect(!lifted)
        #expect(!controller.isActive)
    }
}
