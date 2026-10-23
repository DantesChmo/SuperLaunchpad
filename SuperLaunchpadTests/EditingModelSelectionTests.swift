import AppKit
import Foundation
import Testing
@testable import SuperLaunchpad

@MainActor
struct EditingModelSelectionTests {

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
        isHidden: Bool = false
    ) -> AppEntry {
        var entry = AppEntry(
            bundleIdentifier: bundleID,
            displayName: bundleID,
            appPath: "/Applications/\(bundleID).app",
            pageIndex: page,
            orderIndex: order,
            folderID: folderID,
            folderOrderIndex: folderOrder
        )
        entry.isHidden = isHidden
        return entry
    }

    // Page 0: a b F(x y) c — page 1: d e — hidden h. Stored in the DB, shown,
    // in edit mode.
    private func makeViewModel(_ db: AppDatabase) throws -> LaunchpadViewModel {
        let folders = [FolderEntry(id: "F", title: "Tools", pageIndex: 0, orderIndex: 2)]
        let apps = [
            app("a", page: 0, order: 0),
            app("b", page: 0, order: 1),
            app("c", page: 0, order: 3),
            app("x", folderID: "F", folderOrder: 0),
            app("y", folderID: "F", folderOrder: 1),
            app("d", page: 1, order: 0),
            app("e", page: 1, order: 1),
            app("h", isHidden: true)
        ]
        return try load(apps: apps, folders: folders, db: db)
    }

    private func load(apps: [AppEntry], folders: [FolderEntry], db: AppDatabase) throws -> LaunchpadViewModel {
        try db.saveFolders(folders)
        try db.saveApps(apps)
        let vm = LaunchpadViewModel(database: db)
        vm.folders = folders
        vm.apps = apps
        vm.show()
        vm.editing.enterEditMode()
        return vm
    }

    private func pageIDs(_ vm: LaunchpadViewModel) -> [[String]] {
        vm.pages.map { $0.map(\.id) }
    }

    private func entry(_ vm: LaunchpadViewModel, _ id: String) throws -> AppEntry {
        try #require(vm.apps.first { $0.bundleIdentifier == id })
    }

    private func select(_ vm: LaunchpadViewModel, _ ids: String...) {
        for id in ids {
            vm.editing.toggleSelection(id)
        }
    }

    // The DB holds exactly what the view model shows.
    private func expectPersisted(_ vm: LaunchpadViewModel, _ db: AppDatabase) throws {
        let stored = GridLayout(apps: try db.fetchAllApps(), folders: try db.fetchAllFolders())
        #expect(stored == GridLayout(apps: vm.apps, folders: vm.folders))
    }

    // MARK: - Toggling

    @Test func toggleChecksAndUnchecks() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)

        #expect(vm.editing.toggleSelection("a"))
        #expect(vm.editing.toggleSelection("x"))
        #expect(vm.editing.selection == ["a", "x"])
        #expect(vm.editing.toggleSelection("a"))
        #expect(vm.editing.selection == ["x"])
    }

    @Test func onlyVisibleAppsInEditModeAreSelectable() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)

        #expect(!vm.editing.toggleSelection("h"))
        #expect(!vm.editing.toggleSelection("F"))
        #expect(!vm.editing.toggleSelection("gone"))
        vm.editing.exitEditMode()
        #expect(!vm.editing.toggleSelection("a"))
        #expect(vm.editing.selection.isEmpty)
    }

    @Test(arguments: [false, true])
    func clickInEditModeTogglesInsteadOfLaunching(withCommand: Bool) throws {
        let modifiers: NSEvent.ModifierFlags = withCommand ? .command : []
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        var opened: [String] = []
        vm.itemActions.opener = AppOpener.Operations(
            open: { path, _ in opened.append(path) },
            showInFinder: { opened.append($0) }
        )

        #expect(!vm.itemActions.click(try entry(vm, "b"), modifiers: modifiers))
        #expect(vm.editing.selection == ["b"])
        #expect(!vm.itemActions.click(try entry(vm, "b"), modifiers: modifiers))
        #expect(vm.editing.selection.isEmpty)
        #expect(opened.isEmpty)
    }

    // MARK: - Clearing

    @Test func leavingEditModeClearsTheSelection() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        select(vm, "a", "b")

        vm.editing.exitEditMode()
        #expect(vm.editing.selection.isEmpty)
    }

    @Test func hidingTheLauncherClearsTheSelection() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        select(vm, "a")

        vm.hide()
        #expect(vm.editing.selection.isEmpty)
    }

    @Test func escapeClearsTheSelectionBeforeLeavingEditMode() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        select(vm, "a", "x")

        #expect(vm.handleEscape() == .clearedSelection)
        #expect(vm.editing.selection.isEmpty)
        #expect(vm.editing.isEditing)
        #expect(vm.handleEscape() == .exitedEditMode)
    }

    @Test func selectionSurvivesOpeningAndClosingFolders() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        select(vm, "a")
        let folder = try #require(vm.folders.first)

        vm.openFolder(folder)
        select(vm, "y")
        vm.closeFolder()
        #expect(vm.editing.selection == ["a", "y"])
    }

    @Test func appsThatLeaveTheLayoutLeaveTheSelection() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        select(vm, "a", "b", "d")

        #expect(vm.editing.hideApp("a"))
        #expect(vm.removal.dropUninstalledApp("d"))
        #expect(vm.editing.selection == ["b"])
    }

    // MARK: - Marquee

    @Test func marqueeAddsToTheSelectionItStartedFrom() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        select(vm, "d")

        vm.editing.updateMarquee(hits: ["a"], toggling: false)
        vm.editing.updateMarquee(hits: ["a", "b"], toggling: false)
        #expect(vm.editing.selection == ["a", "b", "d"])
        // Shrinking the band gives back what it no longer covers.
        vm.editing.updateMarquee(hits: ["b"], toggling: false)
        #expect(vm.editing.selection == ["b", "d"])
        vm.editing.endMarquee()

        // A new band starts from the current selection.
        vm.editing.updateMarquee(hits: ["c"], toggling: false)
        #expect(vm.editing.selection == ["b", "c", "d"])
    }

    @Test func togglingMarqueeFlipsWhatItCovers() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        select(vm, "a", "b")

        vm.editing.updateMarquee(hits: ["b", "c"], toggling: true)
        #expect(vm.editing.selection == ["a", "c"])
    }

    @Test func marqueeIgnoresHiddenAppsAndNeedsEditMode() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)

        vm.editing.updateMarquee(hits: ["a", "h"], toggling: false)
        #expect(vm.editing.selection == ["a"])
        vm.editing.exitEditMode()
        vm.editing.updateMarquee(hits: ["b"], toggling: false)
        #expect(vm.editing.selection.isEmpty)
    }

    // MARK: - Order and companions

    @Test func orderedSelectionFollowsTheLayout() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        select(vm, "e", "y", "a", "c")

        #expect(vm.editing.orderedSelection == ["a", "y", "c", "e"])
        #expect(vm.editing.dragCompanions(for: "c").map(\.id) == ["a", "y", "e"])
    }

    @Test func noCompanionsForAnUnselectedOrLoneApp() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        select(vm, "a")

        #expect(vm.editing.dragCompanions(for: "a").isEmpty)
        select(vm, "b")
        #expect(vm.editing.dragCompanions(for: "c").isEmpty)
    }

    // MARK: - Group drop

    @Test func groupDropOnTheSamePageLandsConsecutively() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        select(vm, "c", "a")
        let revision = vm.layoutRevision

        // c lifted with a: b F c, c at 2 → dropped at 1.
        var session = DragSession(itemID: "c", item: .app("c"), page: 0, slot: 2, grabOffset: .zero, companionIDs: vm.editing.dragCompanions(for: "c").map(\.id))
        session.retarget(1)
        let outcome = try #require(vm.editing.commitDrop(session))

        #expect(pageIDs(vm) == [["b", "c", "a", "F"], ["d", "e"]])
        #expect(outcome == .init(page: 0, slot: 1))
        #expect(vm.layoutRevision == revision + 1)
        #expect(vm.editing.selection.isEmpty)
        try expectPersisted(vm, db)
    }

    @Test func groupDropOnAnotherPageGathersFromFoldersToo() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        select(vm, "a", "x")

        var session = DragSession(itemID: "a", item: .app("a"), page: 0, slot: 0, grabOffset: .zero, companionIDs: ["x"])
        session.switchPage(to: 1, slot: 1)
        let outcome = try #require(vm.editing.commitDrop(session))

        #expect(pageIDs(vm) == [["b", "F", "c"], ["d", "a", "x", "e"]])
        #expect(vm.folderApps("F").map(\.id) == ["y"])
        #expect(outcome == .init(page: 1, slot: 1))
        try expectPersisted(vm, db)
    }

    @Test func groupDropOnAFullPageSpillsOntoTheNextOne() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let full = (0..<Grid.appsPerPage).map { app("p\($0)", page: 0, order: $0) }
        let vm = try load(apps: full + [app("q", page: 1, order: 0), app("r", page: 1, order: 1)], folders: [], db: db)
        select(vm, "q", "r")

        var session = DragSession(itemID: "q", item: .app("q"), page: 1, slot: 0, grabOffset: .zero, companionIDs: ["r"])
        session.switchPage(to: 0, slot: 0)
        #expect(vm.editing.commitDrop(session) == .init(page: 0, slot: 0))

        let last = Grid.appsPerPage - 1
        #expect(pageIDs(vm).first.map { Array($0.prefix(3)) } == ["q", "r", "p0"])
        #expect(pageIDs(vm).count == 2)
        #expect(pageIDs(vm).last == ["p\(last - 1)", "p\(last)"])
        try expectPersisted(vm, db)
    }

    @Test func groupDropOnTheTrailingPageOpensIt() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        select(vm, "b", "y")

        var session = DragSession(itemID: "b", item: .app("b"), page: 0, slot: 1, grabOffset: .zero, companionIDs: ["y"])
        session.switchPage(to: 2, slot: 0)
        #expect(vm.editing.commitDrop(session) == .init(page: 2, slot: 0))
        #expect(pageIDs(vm).last == ["b", "y"])
    }

    @Test func groupDropOntoAFolderAddsThemAll() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        select(vm, "e", "a")

        var session = DragSession(itemID: "e", item: .app("e"), page: 1, slot: 1, grabOffset: .zero, companionIDs: ["a"])
        session.setMergeTarget("F")
        let outcome = try #require(vm.editing.commitDrop(session))

        #expect(vm.folderApps("F").map(\.id) == ["x", "y", "e", "a"])
        #expect(pageIDs(vm) == [["b", "F", "c"], ["d"]])
        #expect(outcome == .init(page: 0, slot: 1))
        try expectPersisted(vm, db)
    }

    @Test func groupDropOntoAnAppMakesANewFolder() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        select(vm, "a", "d")

        var session = DragSession(itemID: "d", item: .app("d"), page: 1, slot: 0, grabOffset: .zero, companionIDs: ["a"])
        session.setMergeTarget("c")
        let outcome = try #require(vm.editing.commitDrop(session))
        let folderID = try #require(outcome.createdFolderID)

        #expect(vm.folderApps(folderID).map(\.id) == ["c", "d", "a"])
        #expect(pageIDs(vm) == [["b", "F", folderID], ["e"]])
        #expect(outcome.page == 0 && outcome.slot == 2)
        try expectPersisted(vm, db)
    }

    @Test func groupDropInsideTheOpenFolderJoinsIt() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        select(vm, "y", "c")

        var session = DragSession(appID: "y", folderID: "F", index: 1, grabOffset: .zero, companionIDs: ["c"])
        session.retarget(0)
        #expect(vm.editing.commitDrop(session) == .init(page: 0, slot: 0))

        #expect(vm.folderApps("F").map(\.id) == ["y", "c", "x"])
        #expect(pageIDs(vm) == [["a", "b", "F"], ["d", "e"]])
        try expectPersisted(vm, db)
    }

    @Test func refusedGroupDropKeepsLayoutAndSelection() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        select(vm, "a", "b")

        var session = DragSession(itemID: "a", item: .app("a"), page: 0, slot: 0, grabOffset: .zero, companionIDs: ["b"])
        session.switchPage(to: 5, slot: 0)
        #expect(vm.editing.commitDrop(session) == nil)
        #expect(pageIDs(vm) == [["a", "b", "F", "c"], ["d", "e"]])
        #expect(vm.editing.selection == ["a", "b"])
    }

    @Test func groupDropSurvivesAReload() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        select(vm, "a", "x")
        var session = DragSession(itemID: "a", item: .app("a"), page: 0, slot: 0, grabOffset: .zero, companionIDs: ["x"])
        session.switchPage(to: 1, slot: 2)
        _ = try #require(vm.editing.commitDrop(session))

        let reloaded = LaunchpadViewModel(database: db)
        reloaded.folders = try db.fetchAllFolders()
        reloaded.apps = try db.fetchAllApps()
        #expect(pageIDs(reloaded) == [["b", "F", "c"], ["d", "e", "a", "x"]])
    }

    // MARK: - Group actions

    @Test func newFolderFromSelectionTakesTheFirstSlotAndOpensForRenaming() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        select(vm, "e", "b", "y")
        let revision = vm.layoutRevision

        let folderID = try #require(vm.editing.makeFolderFromSelection())

        #expect(pageIDs(vm) == [["a", folderID, "F", "c"], ["d"]])
        #expect(vm.folderApps(folderID).map(\.id) == ["b", "y", "e"])
        #expect(vm.folderApps("F").map(\.id) == ["x"])
        #expect(vm.folderOpenRequest?.folderID == folderID)
        #expect(vm.folderOpenRequest?.renaming == true)
        #expect(vm.editing.selection.isEmpty)
        #expect(vm.layoutRevision == revision + 1)
        try expectPersisted(vm, db)
    }

    @Test func newFolderFromAWholeFolderReplacesIt() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        select(vm, "x", "y")

        let folderID = try #require(vm.editing.makeFolderFromSelection())
        #expect(pageIDs(vm) == [["a", "b", folderID, "c"], ["d", "e"]])
        #expect(!vm.folders.contains { $0.id == "F" })
        try expectPersisted(vm, db)
    }

    @Test func newFolderNeedsASelection() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)

        #expect(vm.editing.makeFolderFromSelection() == nil)
        #expect(pageIDs(vm) == [["a", "b", "F", "c"], ["d", "e"]])
    }

    @Test func hideSelectionHidesThemAllInOneEdit() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        select(vm, "a", "x", "y", "e")
        let revision = vm.layoutRevision

        #expect(vm.editing.hideSelection())

        // F lost both apps and is dissolved.
        #expect(pageIDs(vm) == [["b", "c"], ["d"]])
        #expect(Set(vm.editing.hiddenApps.map(\.id)) == ["a", "e", "h", "x", "y"])
        #expect(vm.editing.selection.isEmpty)
        #expect(vm.layoutRevision == revision + 1)
        let stored = try db.fetchAllApps().filter(\.isHidden).map(\.bundleIdentifier)
        #expect(Set(stored) == ["a", "e", "h", "x", "y"])
        try expectPersisted(vm, db)
    }
}
