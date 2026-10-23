import Foundation
import Testing
@testable import SuperLaunchpad

// The arrow-key focus over the grid and the open folder. Sizes come from
// `Grid` and `FolderGrid`, so the fixture follows a different grid size.
@MainActor
struct KeyboardFocusModelTests {

    // Page 0 is full, with folder F at `folderSlot`; F holds a folder page
    // and two more apps. Page 1 is one row and one app.
    private static let folderSlot = 2
    private static let folderAppCount = FolderGrid.appsPerPage + 2
    private static let secondPageCount = Grid.columns + 1

    private func makeTempDB() throws -> (AppDatabase, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("slp-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("test.db").path
        return (try AppDatabase(path: path), dir)
    }

    private func app(_ bundleID: String, page: Int? = nil, order: Int? = nil, folderOrder: Int? = nil) -> AppEntry {
        AppEntry(
            bundleIdentifier: bundleID,
            displayName: bundleID,
            appPath: "/Applications/\(bundleID).app",
            pageIndex: page,
            orderIndex: order,
            folderID: folderOrder == nil ? nil : "F",
            folderOrderIndex: folderOrder
        )
    }

    private func makeViewModel(_ db: AppDatabase) throws -> LaunchpadViewModel {
        let folders = [FolderEntry(id: "F", title: "Tools", pageIndex: 0, orderIndex: Self.folderSlot)]
        var apps: [AppEntry] = []
        for slot in 0..<Grid.appsPerPage where slot != Self.folderSlot {
            apps.append(app("p0-\(slot)", page: 0, order: slot))
        }
        for slot in 0..<Self.secondPageCount {
            apps.append(app("p1-\(slot)", page: 1, order: slot))
        }
        for index in 0..<Self.folderAppCount {
            apps.append(app("f-\(index)", folderOrder: index))
        }
        try db.saveFolders(folders)
        try db.saveApps(apps)
        let vm = LaunchpadViewModel(database: db)
        vm.folders = folders
        vm.apps = apps
        vm.show()
        return vm
    }

    private func folder(_ vm: LaunchpadViewModel) throws -> FolderEntry {
        try #require(vm.folders.first { $0.id == "F" })
    }

    // Focus on `slot` of page 0: the first arrow shows the focus on slot 0,
    // then it walks down to the row and right to the column (right past a
    // row end would cross the page).
    private func focus(_ vm: LaunchpadViewModel, slot: Int) {
        _ = vm.keyboardFocus.move(.right)
        for _ in 0..<(slot / Grid.columns) {
            _ = vm.keyboardFocus.move(.down)
        }
        for _ in 0..<(slot % Grid.columns) {
            _ = vm.keyboardFocus.move(.right)
        }
    }

    // What `LaunchpadView` does with a folder open request.
    private func openRequestedFolder(_ vm: LaunchpadViewModel) throws {
        let request = try #require(vm.folderOpenRequest)
        let folder = try #require(vm.folders.first { $0.id == request.folderID })
        vm.openFolder(folder)
    }

    // MARK: - Showing the focus

    @Test(arguments: GridNavigation.Direction.allCases)
    func firstArrowOnlyShowsTheFocus(direction: GridNavigation.Direction) throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)

        #expect(vm.keyboardFocus.focusedGridItemID == nil)
        #expect(vm.keyboardFocus.focusedItem == nil)

        #expect(vm.keyboardFocus.move(direction) == nil)
        #expect(vm.keyboardFocus.focusedGridItemID == vm.pages[0][0].id)
    }

    @Test func showingTheLauncherAgainHidesTheFocus() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        focus(vm, slot: 3)

        vm.hide()
        vm.show()

        #expect(vm.keyboardFocus.focusedGridItemID == nil)
        _ = vm.keyboardFocus.move(.down)
        #expect(vm.keyboardFocus.focusedGridItemID == vm.pages[0][0].id)
    }

    @Test func searchResultsHideTheGridFocus() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        focus(vm, slot: 1)

        vm.search.searchText = "p1"
        #expect(vm.keyboardFocus.focusedGridItemID == nil)

        vm.search.searchText = ""
        #expect(vm.keyboardFocus.focusedGridItemID == vm.pages[0][1].id)
    }

    // MARK: - Moving on a page and across pages

    @Test(arguments: [
        (GridNavigation.Direction.right, 4),
        (.left, 2),
        (.down, 3 + Grid.columns),
        (.up, 3)
    ])
    func arrowsMoveOnTheShownPage(direction: GridNavigation.Direction, expectedSlot: Int) throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        focus(vm, slot: 3)

        #expect(vm.keyboardFocus.move(direction) == nil)
        #expect(vm.keyboardFocus.focusedGridItemID == vm.pages[0][expectedSlot].id)
    }

    @Test func rightAtTheRowEndPagesToTheNextPage() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        focus(vm, slot: Grid.columns - 1)

        #expect(vm.keyboardFocus.move(.right) == 1)
        // The panel pages the grid.
        vm.currentPage = 1
        #expect(vm.keyboardFocus.focusedGridItemID == vm.pages[1][0].id)

        #expect(vm.keyboardFocus.move(.left) == 0)
        vm.currentPage = 0
        #expect(vm.keyboardFocus.focusedGridItemID == vm.pages[0][Grid.columns - 1].id)
    }

    @Test func downIntoThePartialLastRowLandsOnItsLastItem() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        focus(vm, slot: Grid.columns - 1)
        #expect(vm.keyboardFocus.move(.right) == 1)
        vm.currentPage = 1

        // Page 1: one full row, then a row with one app.
        _ = vm.keyboardFocus.move(.right)
        _ = vm.keyboardFocus.move(.down)

        #expect(vm.keyboardFocus.focusedGridItemID == vm.pages[1][Self.secondPageCount - 1].id)
    }

    @Test func aSwipeAwayBringsTheFocusBackOnTheShownPage() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        focus(vm, slot: Grid.columns + 3)

        vm.currentPage = 1
        #expect(vm.keyboardFocus.focusedGridItemID == nil)

        // The next arrow puts it at the same place, clamped to the short page.
        #expect(vm.keyboardFocus.move(.right) == nil)
        #expect(vm.keyboardFocus.focusedGridItemID == vm.pages[1][min(Grid.columns + 3, Self.secondPageCount - 1)].id)
    }

    @Test func aFocusedAppThatLeavesTheGridHandsTheFocusToItsSlot() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        focus(vm, slot: 4)
        let hidden = try #require(vm.keyboardFocus.focusedGridItemID)

        #expect(vm.editing.hideApp(hidden))

        #expect(vm.keyboardFocus.focusedGridItemID == vm.pages[0][4].id)
        #expect(vm.keyboardFocus.focusedGridItemID != hidden)
    }

    // MARK: - Return

    @Test func returnTargetIsTheFocusedItem() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)

        focus(vm, slot: 1)
        #expect(vm.keyboardFocus.focusedItem?.id == "p0-1")

        _ = vm.keyboardFocus.move(.right)
        guard case .folder(let folder, _) = vm.keyboardFocus.focusedItem else {
            Issue.record("expected the folder")
            return
        }
        #expect(folder.id == "F")
    }

    @Test func returnOnAFolderOpensItWithTheFocusOnItsFirstApp() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        focus(vm, slot: Self.folderSlot)

        vm.keyboardFocus.openFolder(try folder(vm))
        try openRequestedFolder(vm)

        #expect(vm.openFolderID == "F")
        #expect(vm.keyboardFocus.focusedFolderAppID == "f-0")
        #expect(vm.keyboardFocus.focusedItem?.id == "f-0")
        // Only one ring at a time: the tile behind the open folder has none.
        #expect(vm.keyboardFocus.focusedGridItemID == nil)
    }

    @Test func closingTheFolderLeavesTheFocusOnItsTile() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        focus(vm, slot: Self.folderSlot)
        vm.keyboardFocus.openFolder(try folder(vm))
        try openRequestedFolder(vm)

        #expect(vm.handleEscape() == .closedFolder)

        #expect(vm.keyboardFocus.focusedFolderAppID == nil)
        #expect(vm.keyboardFocus.focusedGridItemID == "F")
        // Reopened with the mouse, it has no focus until an arrow.
        vm.openFolder(try folder(vm))
        #expect(vm.keyboardFocus.focusedFolderAppID == nil)
    }

    // MARK: - Folder grid

    @Test func aFolderOpenedWithTheMouseGetsTheFocusOnTheFirstArrow() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        vm.openFolder(try folder(vm))
        #expect(vm.keyboardFocus.focusedItem == nil)

        #expect(vm.keyboardFocus.move(.down) == nil)

        #expect(vm.keyboardFocus.focusedFolderAppID == "f-0")
        // The grid keeps no focus of its own meanwhile.
        #expect(vm.keyboardFocus.focusedGridItemID == nil)
    }

    @Test(arguments: [
        // From f-1, the second app of the first row.
        (GridNavigation.Direction.right, 2),
        (.down, 1 + FolderGrid.columns),
        (.left, 0),
        (.up, 1)
    ])
    func arrowsMoveOverTheFolderGrid(direction: GridNavigation.Direction, expectedIndex: Int) throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        vm.openFolder(try folder(vm))
        _ = vm.keyboardFocus.move(.right)
        _ = vm.keyboardFocus.move(.right)
        #expect(vm.keyboardFocus.focusedFolderAppID == "f-1")

        // Folder moves never page the main grid.
        #expect(vm.keyboardFocus.move(direction) == nil)
        #expect(vm.keyboardFocus.focusedFolderAppID == "f-\(expectedIndex)")
    }

    @Test func rightAtAFolderRowEndGoesToItsNextPage() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        vm.openFolder(try folder(vm))
        _ = vm.keyboardFocus.move(.right)
        for _ in 0..<(FolderGrid.columns - 1) {
            _ = vm.keyboardFocus.move(.right)
        }
        #expect(vm.keyboardFocus.focusedFolderAppID == "f-\(FolderGrid.columns - 1)")

        // Past the last column of row 0: row 0 of the second folder page.
        #expect(vm.keyboardFocus.move(.right) == nil)
        #expect(vm.keyboardFocus.focusedFolderAppID == "f-\(FolderGrid.appsPerPage)")
        // And back.
        _ = vm.keyboardFocus.move(.left)
        #expect(vm.keyboardFocus.focusedFolderAppID == "f-\(FolderGrid.columns - 1)")
    }

    // MARK: - Space in edit mode

    @Test func spaceTogglesTheFocusedAppInEditMode() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        vm.editing.enterEditMode()
        focus(vm, slot: 1)

        #expect(vm.keyboardFocus.toggleSelection())
        #expect(vm.editing.selection == ["p0-1"])

        #expect(vm.keyboardFocus.toggleSelection())
        #expect(vm.editing.selection.isEmpty)
    }

    @Test func spaceTogglesTheFocusedAppInAFolder() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        vm.editing.enterEditMode()
        vm.openFolder(try folder(vm))
        _ = vm.keyboardFocus.move(.right)
        _ = vm.keyboardFocus.move(.right)

        #expect(vm.keyboardFocus.toggleSelection())
        #expect(vm.editing.selection == ["f-1"])
    }

    @Test func spaceDoesNothingOnAFolderWithoutFocusOrOutsideEditMode() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)

        // No focus yet.
        vm.editing.enterEditMode()
        #expect(!vm.keyboardFocus.toggleSelection())
        // A folder can't be selected.
        focus(vm, slot: Self.folderSlot)
        #expect(!vm.keyboardFocus.toggleSelection())
        // Outside edit mode Space is the search field's.
        vm.editing.exitEditMode()
        _ = vm.keyboardFocus.move(.left)
        #expect(!vm.keyboardFocus.toggleSelection())
        #expect(vm.editing.selection.isEmpty)
    }

    // MARK: - Ring

    @Test func increaseContrastMakesTheRingWiderAndOpaque() {
        let normal = KeyboardFocusRingStyle(increasedContrast: false)
        let increased = KeyboardFocusRingStyle(increasedContrast: true)
        #expect(increased.lineWidth > normal.lineWidth)
        #expect(increased.opacity == 1)
        #expect(increased.edgeOpacity > normal.edgeOpacity)
    }
}
