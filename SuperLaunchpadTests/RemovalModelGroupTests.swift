import Foundation
import Testing
@testable import SuperLaunchpad

// Move to Trash on a selection: one dialog for the group.
@MainActor
struct RemovalModelGroupTests {

    // Records what the view model asked of the Trash.
    private final class TrashLog {
        var protected: Set<String> = []
        var failing: Set<String> = []
        var cancelling: Set<String> = []
        var trashed: [String] = []
        var trashedWithFinder: [String] = []
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
        path: String? = nil,
        page: Int? = nil,
        order: Int? = nil,
        folderID: String? = nil,
        folderOrder: Int? = nil
    ) -> AppEntry {
        AppEntry(
            bundleIdentifier: bundleID,
            displayName: bundleID,
            appPath: path ?? "/Applications/\(bundleID).app",
            pageIndex: page,
            orderIndex: order,
            folderID: folderID,
            folderOrderIndex: folderOrder
        )
    }

    // Page a, b, folder F(x), mail, c — stored in the DB, in edit mode, with a
    // fake Trash and fake running apps.
    private func makeViewModel(
        _ db: AppDatabase,
        log: TrashLog,
        workspace: FakeWorkspace? = nil
    ) throws -> LaunchpadViewModel {
        let folders = [FolderEntry(id: "F", title: "Tools", pageIndex: 0, orderIndex: 2)]
        let apps = [
            app("a", page: 0, order: 0),
            app("b", page: 0, order: 1),
            app("mail", path: "/System/Applications/Mail.app", page: 0, order: 3),
            app("c", page: 0, order: 4),
            app("x", folderID: "F", folderOrder: 0)
        ]
        try db.saveFolders(folders)
        try db.saveApps(apps)
        let vm = LaunchpadViewModel(database: db)
        vm.folders = folders
        vm.apps = apps
        vm.runningApps = RunningApps(source: (workspace ?? FakeWorkspace()).source)
        vm.removal.trash = AppTrash.Operations(
            needsAuthorization: { path in log.protected.contains(path) },
            moveToTrash: { path in
                if log.cancelling.contains(path) { throw AppTrash.Failure.cancelled }
                if log.failing.contains(path) { throw AppTrash.Failure.other("disk full") }
                log.trashed.append(path)
            },
            moveToTrashWithFinder: { path in
                if log.cancelling.contains(path) { throw AppTrash.Failure.cancelled }
                log.trashedWithFinder.append(path)
            }
        )
        vm.show()
        vm.editing.enterEditMode()
        return vm
    }

    private func entries(_ vm: LaunchpadViewModel, _ ids: String...) -> [AppEntry] {
        ids.compactMap { id in vm.apps.first { $0.bundleIdentifier == id } }
    }

    private func pageIDs(_ vm: LaunchpadViewModel) -> [[String]] {
        vm.pages.map { $0.map(\.id) }
    }

    // MARK: - Request

    @Test func requestSkipsSystemAppsAndCountsThem() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db, log: TrashLog())

        vm.removal.requestRemoval(of: entries(vm, "a", "mail", "x"))

        let removal = try #require(vm.removal.pendingRemoval)
        #expect(removal.apps.map(\.id) == ["a", "x"])
        #expect(removal.stage == .confirm)
        #expect(removal.skippedCount == 1)
        #expect(removal.isGroup)
    }

    @Test func onlySystemAppsAskNothing() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db, log: TrashLog())

        vm.removal.requestRemoval(of: entries(vm, "mail"))
        #expect(vm.removal.pendingRemoval == nil)
    }

    @Test func oneRemovableAppIsTheSingleDialog() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db, log: TrashLog())

        vm.removal.requestRemoval(of: entries(vm, "mail", "b"))
        let removal = try #require(vm.removal.pendingRemoval)
        #expect(!removal.isGroup)
        #expect(removal.app.id == "b")
    }

    @Test func anOpenAppMakesTheGroupAskToQuit() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let workspace = FakeWorkspace()
        workspace.launch("b")
        let vm = try makeViewModel(db, log: TrashLog(), workspace: workspace)

        vm.removal.requestRemoval(of: entries(vm, "a", "b"))
        #expect(vm.removal.pendingRemoval?.stage == .appIsOpen)
    }

    // MARK: - Confirm

    @Test func confirmTrashesTheGroupInOneEdit() async throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = TrashLog()
        let vm = try makeViewModel(db, log: log)
        vm.editing.toggleSelection("a")
        vm.editing.toggleSelection("x")
        let revision = vm.layoutRevision

        vm.removal.requestRemoval(of: entries(vm, "a", "x", "mail"))
        var hidden = false
        await vm.removal.confirmRemoval { hidden = true }

        #expect(log.trashed == ["/Applications/a.app", "/Applications/x.app"])
        #expect(!hidden)
        #expect(vm.removal.pendingRemoval == nil)
        // F lost its only app and is dissolved; Mail stays.
        #expect(pageIDs(vm) == [["b", "mail", "c"]])
        #expect(vm.layoutRevision == revision + 1)
        #expect(vm.editing.selection.isEmpty)
        let stored = try db.fetchAllApps().map(\.bundleIdentifier)
        #expect(!stored.contains("a") && !stored.contains("x"))
    }

    @Test func protectedAppsGoThroughFinderAfterOneHide() async throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = TrashLog()
        log.protected = ["/Applications/b.app", "/Applications/c.app"]
        let vm = try makeViewModel(db, log: log)

        vm.removal.requestRemoval(of: entries(vm, "a", "b", "c"))
        var hides = 0
        await vm.removal.confirmRemoval { hides += 1 }

        #expect(hides == 1)
        #expect(log.trashed == ["/Applications/a.app"])
        #expect(log.trashedWithFinder == ["/Applications/b.app", "/Applications/c.app"])
        #expect(pageIDs(vm) == [["F", "mail"]])
    }

    @Test func failureStopsTheGroupAndNamesTheApp() async throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = TrashLog()
        log.failing = ["/Applications/b.app"]
        let vm = try makeViewModel(db, log: log)

        vm.removal.requestRemoval(of: entries(vm, "a", "b", "c"))
        await vm.removal.confirmRemoval {}

        #expect(log.trashed == ["/Applications/a.app"])
        #expect(vm.removal.pendingRemoval?.app.id == "b")
        #expect(vm.removal.pendingRemoval?.stage == .failed(.other("disk full")))
        // Only the app that made it to the Trash leaves the layout.
        #expect(pageIDs(vm) == [["b", "F", "mail", "c"]])
    }

    @Test func cancelledPasswordPromptStopsQuietly() async throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = TrashLog()
        log.protected = ["/Applications/b.app"]
        log.cancelling = ["/Applications/b.app"]
        let vm = try makeViewModel(db, log: log)

        vm.removal.requestRemoval(of: entries(vm, "a", "b", "c"))
        await vm.removal.confirmRemoval {}

        #expect(log.trashed == ["/Applications/a.app"])
        #expect(vm.removal.pendingRemoval == nil)
        #expect(pageIDs(vm) == [["b", "F", "mail", "c"]])
    }

    @Test func confirmQuitsEveryOpenAppFirst() async throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = TrashLog()
        let workspace = FakeWorkspace()
        let first = workspace.launch("a")
        let second = workspace.launch("c")
        let vm = try makeViewModel(db, log: log, workspace: workspace)

        vm.removal.requestRemoval(of: entries(vm, "a", "b", "c"))
        await vm.removal.confirmRemoval {}

        #expect(Set(workspace.terminateRequests.map(\.id)) == [first.id, second.id])
        #expect(log.trashed == ["/Applications/a.app", "/Applications/b.app", "/Applications/c.app"])
        #expect(vm.removal.pendingRemoval == nil)
    }

    @Test func oneAppThatDoesNotQuitKeepsTheWholeGroup() async throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = TrashLog()
        let workspace = FakeWorkspace()
        workspace.quitsOnRequest = false
        workspace.launch("c")
        let vm = try makeViewModel(db, log: log, workspace: workspace)
        vm.removal.quitTimeout = .milliseconds(20)

        vm.removal.requestRemoval(of: entries(vm, "a", "c"))
        await vm.removal.confirmRemoval {}

        let removal = try #require(vm.removal.pendingRemoval)
        #expect(removal.stage == .didNotQuit)
        #expect(removal.apps.map(\.id) == ["a", "c"])
        #expect(log.trashed.isEmpty)
        #expect(pageIDs(vm) == [["a", "b", "F", "mail", "c"]])
    }
}
