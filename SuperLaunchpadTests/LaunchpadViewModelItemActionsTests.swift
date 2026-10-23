import AppKit
import Testing
@testable import SuperLaunchpad

@MainActor
struct LaunchpadViewModelItemActionsTests {

    // Records what the view model asked to open or show in Finder.
    private final class OpenerLog {
        var opened: [(path: String, activates: Bool)] = []
        var shownInFinder: [String] = []
    }

    private func makeTempDB() throws -> (AppDatabase, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("slp-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("test.db").path
        return (try AppDatabase(path: path), dir)
    }

    private func app(
        _ bundleID: String,
        name: String? = nil,
        path: String? = nil,
        page: Int? = nil,
        order: Int? = nil,
        folderID: String? = nil,
        folderOrder: Int? = nil
    ) -> AppEntry {
        AppEntry(
            bundleIdentifier: bundleID,
            displayName: name ?? bundleID,
            appPath: path ?? "/Applications/\(bundleID).app",
            pageIndex: page,
            orderIndex: order,
            folderID: folderID,
            folderOrderIndex: folderOrder
        )
    }

    // Page: a, folder F(zed, Émile, bob), mail (system app), b.
    private func makeViewModel(_ db: AppDatabase?, log: OpenerLog = OpenerLog()) throws -> LaunchpadViewModel {
        let folders = [FolderEntry(id: "F", title: "Tools", pageIndex: 0, orderIndex: 1)]
        let apps = [
            app("a", page: 0, order: 0),
            app("mail", path: "/System/Applications/Mail.app", page: 0, order: 2),
            app("b", page: 0, order: 3),
            app("z", name: "zed", folderID: "F", folderOrder: 0),
            app("e", name: "Émile", folderID: "F", folderOrder: 1),
            app("o", name: "bob", folderID: "F", folderOrder: 2)
        ]
        try db?.saveFolders(folders)
        try db?.saveApps(apps)
        let vm = LaunchpadViewModel(database: db)
        vm.folders = folders
        vm.apps = apps
        vm.opener = AppOpener.Operations(
            open: { path, activates in log.opened.append((path, activates)) },
            showInFinder: { path in log.shownInFinder.append(path) }
        )
        vm.show()
        return vm
    }

    private func entry(_ vm: LaunchpadViewModel, _ id: String) throws -> AppEntry {
        try #require(vm.apps.first { $0.bundleIdentifier == id })
    }

    private func folder(_ vm: LaunchpadViewModel, _ id: String) throws -> FolderEntry {
        try #require(vm.folders.first { $0.id == id })
    }

    private func pageIDs(_ vm: LaunchpadViewModel) -> [[String]] {
        vm.pages.map { $0.map(\.id) }
    }

    private func isEnabled(_ action: ItemMenu.Action, in sections: ItemMenu.Sections) -> Bool? {
        sections.joined().first { $0.action == action }?.isEnabled
    }

    // MARK: - Disband

    @Test func disbandPutsAppsInFolderPlaceAndPersists() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)

        #expect(vm.disbandFolder("F"))

        #expect(pageIDs(vm) == [["a", "z", "e", "o", "mail", "b"]])
        #expect(vm.folders.isEmpty)
        #expect(try db.fetchAllFolders().isEmpty)
        let stored = try db.fetchAllApps()
        #expect(stored.allSatisfy { $0.folderID == nil && $0.pageIndex == 0 })
        #expect(stored.first { $0.bundleIdentifier == "e" }?.orderIndex == 2)
    }

    @Test func disbandOpenFolderClosesIt() throws {
        let vm = try makeViewModel(nil)
        vm.openFolder(try folder(vm, "F"))

        #expect(vm.disbandFolder("F"))

        #expect(vm.openFolderID == nil)
    }

    @Test func disbandUnknownFolderChangesNothing() throws {
        let vm = try makeViewModel(nil)
        let before = pageIDs(vm)

        #expect(!vm.disbandFolder("missing"))

        #expect(pageIDs(vm) == before)
    }

    // MARK: - Sort by name

    @Test func sortByNameUsesLocalizedCaseInsensitiveOrderAndPersists() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)

        #expect(vm.sortFolderByName("F"))

        #expect(vm.folderApps("F").map(\.displayName) == ["bob", "Émile", "zed"])
        #expect(pageIDs(vm) == [["a", "F", "mail", "b"]])
        let stored = try db.fetchAllApps().filter { $0.folderID == "F" }
            .sorted { ($0.folderOrderIndex ?? 0) < ($1.folderOrderIndex ?? 0) }
        #expect(stored.map(\.bundleIdentifier) == ["o", "e", "z"])
    }

    @Test func sortByNameBreaksTiesByBundleID() throws {
        let vm = LaunchpadViewModel(database: nil)
        vm.folders = [FolderEntry(id: "F", title: "Tools", pageIndex: 0, orderIndex: 0)]
        vm.apps = [
            app("com.b", name: "Notes", folderID: "F", folderOrder: 0),
            app("com.a", name: "notes", folderID: "F", folderOrder: 1)
        ]

        #expect(vm.sortFolderByName("F"))

        #expect(vm.folderApps("F").map(\.bundleIdentifier) == ["com.a", "com.b"])
    }

    // MARK: - Menu items

    @Test func appMenuDisablesTrashForSystemApps() throws {
        let vm = try makeViewModel(nil)
        #expect(isEnabled(.moveToTrash, in: vm.menuItems(for: try entry(vm, "a"))) == true)
        #expect(isEnabled(.moveToTrash, in: vm.menuItems(for: try entry(vm, "mail"))) == false)
    }

    @Test func editLayoutIsDisabledWhileEditingOrSearching() throws {
        let vm = try makeViewModel(nil)
        let a = try entry(vm, "a")
        #expect(isEnabled(.editLayout, in: vm.menuItems(for: a)) == true)

        vm.enterEditMode()
        #expect(isEnabled(.editLayout, in: vm.menuItems(for: a)) == false)
        #expect(isEnabled(.editLayout, in: vm.menuItems(for: try folder(vm, "F"))) == false)

        vm.exitEditMode()
        vm.searchText = "a"
        #expect(isEnabled(.editLayout, in: vm.menuItems(for: a)) == false)
    }

    @Test func folderMenuCountsItsApps() throws {
        let vm = try makeViewModel(nil)
        #expect(isEnabled(.sortByName, in: vm.menuItems(for: try folder(vm, "F"))) == true)

        vm.folders.append(FolderEntry(id: "G", title: "One", pageIndex: 0, orderIndex: 4))
        vm.apps.append(app("solo", folderID: "G", folderOrder: 0))
        #expect(isEnabled(.sortByName, in: vm.menuItems(for: try folder(vm, "G"))) == false)
    }

    // MARK: - App menu actions

    @Test func openLaunchesInFrontAndHidesLauncher() throws {
        let log = OpenerLog()
        let vm = try makeViewModel(nil, log: log)
        vm.enterEditMode()

        #expect(vm.perform(.open, on: try entry(vm, "a")))

        #expect(log.opened.map(\.path) == ["/Applications/a.app"])
        #expect(log.opened.map(\.activates) == [true])
    }

    @Test func showInFinderRevealsAndHidesLauncher() throws {
        let log = OpenerLog()
        let vm = try makeViewModel(nil, log: log)

        #expect(vm.perform(.showInFinder, on: try entry(vm, "a")))

        #expect(log.shownInFinder == ["/Applications/a.app"])
        #expect(log.opened.isEmpty)
    }

    @Test func moveToTrashAsksOutsideEditModeButNotForSystemApps() throws {
        let vm = try makeViewModel(nil)
        vm.runningApps = RunningApps(source: FakeWorkspace().source)
        vm.trash = AppTrash.Operations(
            needsAuthorization: { _ in false },
            moveToTrash: { _ in },
            moveToTrashWithFinder: { _ in }
        )

        #expect(!vm.perform(.moveToTrash, on: try entry(vm, "mail")))
        #expect(vm.pendingRemoval == nil)

        #expect(!vm.perform(.moveToTrash, on: try entry(vm, "a")))
        #expect(vm.pendingRemoval?.app.bundleIdentifier == "a")
        #expect(vm.pendingRemoval?.stage == .confirm)
        #expect(!vm.isEditing)
    }

    // MARK: - Quit

    @Test func menuOffersQuitOnlyWhileTheAppRuns() throws {
        let workspace = FakeWorkspace()
        let vm = try makeViewModel(nil)
        vm.runningApps = RunningApps(source: workspace.source)
        let a = try entry(vm, "a")
        #expect(isEnabled(.quit, in: vm.menuItems(for: a)) == nil)

        let process = workspace.launch("a")
        #expect(isEnabled(.quit, in: vm.menuItems(for: a)) == true)
        #expect(isEnabled(.quit, in: vm.menuItems(for: try entry(vm, "b"))) == nil)

        workspace.terminate(process)
        #expect(isEnabled(.quit, in: vm.menuItems(for: a)) == nil)
    }

    @Test(arguments: [(ItemMenu.Action.quit, false), (.forceQuit, true)])
    func quitAndForceQuitAskTheAppAndKeepTheLauncher(action: ItemMenu.Action, forced: Bool) throws {
        let workspace = FakeWorkspace()
        workspace.quitsOnRequest = false
        let vm = try makeViewModel(nil)
        vm.runningApps = RunningApps(source: workspace.source)
        let process = workspace.launch("a")

        #expect(!vm.perform(action, on: try entry(vm, "a")))

        #expect(workspace.terminateRequests.map(\.id) == [process.id])
        #expect(workspace.terminateRequests.map(\.force) == [forced])
        #expect(vm.isVisible)
    }

    @Test func editLayoutEntersEditMode() throws {
        let vm = try makeViewModel(nil)
        #expect(!vm.perform(.editLayout, on: try entry(vm, "a")))
        #expect(vm.isEditing)

        vm.exitEditMode()
        vm.perform(.editLayout, on: try folder(vm, "F"))
        #expect(vm.isEditing)
    }

    // MARK: - Folder menu actions

    @Test func openAndRenameAskTheViewToOpenTheFolder() throws {
        let vm = try makeViewModel(nil)
        let f = try folder(vm, "F")

        vm.perform(.open, on: f)
        let open = try #require(vm.folderOpenRequest)
        #expect(open.folderID == "F")
        #expect(!open.renaming)

        vm.perform(.rename, on: f)
        let rename = try #require(vm.folderOpenRequest)
        #expect(rename.renaming)

        // A repeat of the same request is still a change the view sees.
        vm.perform(.rename, on: f)
        #expect(vm.folderOpenRequest != rename)
    }

    @Test func folderSortAndDisbandActionsEditTheLayout() throws {
        let vm = try makeViewModel(nil)

        vm.perform(.sortByName, on: try folder(vm, "F"))
        #expect(vm.folderApps("F").map(\.bundleIdentifier) == ["o", "e", "z"])

        vm.perform(.disband, on: try folder(vm, "F"))
        #expect(pageIDs(vm) == [["a", "o", "e", "z", "mail", "b"]])
    }

    // MARK: - Clicks

    @Test func plainClickLaunchesAndHides() throws {
        let log = OpenerLog()
        let vm = try makeViewModel(nil, log: log)

        #expect(vm.click(try entry(vm, "a"), modifiers: []))

        #expect(log.opened.map(\.activates) == [true])
    }

    @Test func commandClickLaunchesInBackgroundAndKeepsLauncher() throws {
        let log = OpenerLog()
        let vm = try makeViewModel(nil, log: log)

        #expect(!vm.click(try entry(vm, "a"), modifiers: .command))
        #expect(!vm.click(try entry(vm, "b"), modifiers: .command))

        #expect(log.opened.map(\.path) == ["/Applications/a.app", "/Applications/b.app"])
        #expect(log.opened.map(\.activates) == [false, false])
        #expect(vm.isVisible)
    }

    @Test func optionCommandClickShowsInFinder() throws {
        let log = OpenerLog()
        let vm = try makeViewModel(nil, log: log)

        #expect(vm.click(try entry(vm, "a"), modifiers: [.option, .command]))

        #expect(log.shownInFinder == ["/Applications/a.app"])
        #expect(log.opened.isEmpty)
    }

    @Test func clicksDoNothingInEditMode() throws {
        let log = OpenerLog()
        let vm = try makeViewModel(nil, log: log)
        vm.enterEditMode()

        #expect(!vm.click(try entry(vm, "a"), modifiers: []))
        #expect(!vm.click(try entry(vm, "a"), modifiers: [.option, .command]))

        #expect(log.opened.isEmpty)
        #expect(log.shownInFinder.isEmpty)
    }
}
