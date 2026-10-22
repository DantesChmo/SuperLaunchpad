import Foundation
import Testing
@testable import SuperLaunchpad

@MainActor
struct LaunchpadViewModelRemovalTests {

    private enum TestError: Error {
        case diskFull
    }

    // Records what the view model asked of the Trash.
    private final class TrashLog {
        var running: Set<String> = []
        var protected: Set<String> = []
        var failure: Error?
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

    // Page a, b, folder F(x), mail — stored in the DB, in edit mode, with a
    // fake Trash.
    private func makeViewModel(_ db: AppDatabase, log: TrashLog) throws -> LaunchpadViewModel {
        let folders = [FolderEntry(id: "F", title: "Tools", pageIndex: 0, orderIndex: 2)]
        let apps = [
            app("a", page: 0, order: 0),
            app("b", page: 0, order: 1),
            app("mail", path: "/System/Applications/Mail.app", page: 0, order: 3),
            app("x", folderID: "F", folderOrder: 0)
        ]
        try db.saveFolders(folders)
        try db.saveApps(apps)
        let vm = LaunchpadViewModel(database: db)
        vm.folders = folders
        vm.apps = apps
        vm.trash = AppTrash.Operations(
            isRunning: { log.running.contains($0) },
            needsAuthorization: { path in log.protected.contains(path) },
            moveToTrash: { path in
                if let failure = log.failure { throw failure }
                log.trashed.append(path)
            },
            moveToTrashWithFinder: { path in
                if let failure = log.failure { throw failure }
                log.trashedWithFinder.append(path)
            }
        )
        vm.show()
        vm.enterEditMode()
        return vm
    }

    private func pageIDs(_ vm: LaunchpadViewModel) -> [[String]] {
        vm.pages.map { $0.map(\.id) }
    }

    private func entry(_ vm: LaunchpadViewModel, _ id: String) throws -> AppEntry {
        try #require(vm.apps.first { $0.bundleIdentifier == id })
    }

    // MARK: - Asking

    @Test func requestAsksForConfirmation() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db, log: TrashLog())

        vm.requestRemoval(of: try entry(vm, "a"))

        #expect(vm.pendingRemoval?.app.bundleIdentifier == "a")
        #expect(vm.pendingRemoval?.stage == .confirm)
    }

    @Test func requestForRunningAppSaysItIsOpen() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = TrashLog()
        log.running = ["a"]
        let vm = try makeViewModel(db, log: log)

        vm.requestRemoval(of: try entry(vm, "a"))

        #expect(vm.pendingRemoval?.stage == .appIsOpen)
    }

    @Test func requestIgnoresSystemAppsAndWorksOnlyInEditMode() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db, log: TrashLog())

        vm.requestRemoval(of: try entry(vm, "mail"))
        #expect(vm.pendingRemoval == nil)

        vm.exitEditMode()
        vm.requestRemoval(of: try entry(vm, "a"))
        #expect(vm.pendingRemoval == nil)
    }

    @Test func escapeAndHideCloseTheDialogFirst() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db, log: TrashLog())

        vm.requestRemoval(of: try entry(vm, "a"))
        #expect(vm.handleEscape() == .cancelledRemoval)
        #expect(vm.pendingRemoval == nil)
        #expect(vm.isEditing)

        vm.requestRemoval(of: try entry(vm, "a"))
        vm.hide()
        #expect(vm.pendingRemoval == nil)
    }

    // MARK: - Confirming

    @Test func confirmTrashesAppAndDropsItFromLayoutAndDB() async throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = TrashLog()
        let vm = try makeViewModel(db, log: log)

        vm.requestRemoval(of: try entry(vm, "a"))
        var hidden = false
        await vm.confirmRemoval { hidden = true }

        #expect(log.trashed == ["/Applications/a.app"])
        #expect(!hidden)
        #expect(vm.pendingRemoval == nil)
        #expect(pageIDs(vm) == [["b", "F", "mail"]])
        #expect(try db.fetchAllApps().map(\.bundleIdentifier).contains("a") == false)
        #expect(vm.isEditing)
    }

    @Test func confirmLastAppOfFolderDissolvesIt() async throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db, log: TrashLog())
        vm.openFolderID = "F"

        vm.requestRemoval(of: try entry(vm, "x"))
        await vm.confirmRemoval {}

        #expect(pageIDs(vm) == [["a", "b", "mail"]])
        #expect(vm.openFolderID == nil)
        #expect(try db.fetchAllFolders().isEmpty)
    }

    @Test func protectedAppGoesThroughFinderAfterHidingLauncher() async throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = TrashLog()
        log.protected = ["/Applications/a.app"]
        let vm = try makeViewModel(db, log: log)

        vm.requestRemoval(of: try entry(vm, "a"))
        var hidden = false
        await vm.confirmRemoval { hidden = true }

        #expect(hidden)
        #expect(log.trashed.isEmpty)
        #expect(log.trashedWithFinder == ["/Applications/a.app"])
        #expect(!vm.apps.contains { $0.bundleIdentifier == "a" })
    }

    @Test func cancelledPasswordPromptKeepsAppQuietly() async throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = TrashLog()
        log.protected = ["/Applications/a.app"]
        log.failure = AppTrash.Failure.cancelled
        let vm = try makeViewModel(db, log: log)

        vm.requestRemoval(of: try entry(vm, "a"))
        await vm.confirmRemoval {}

        #expect(vm.pendingRemoval == nil)
        #expect(vm.apps.contains { $0.bundleIdentifier == "a" })
    }

    @Test(arguments: [
        (AppTrash.Failure.finderNotPermitted as Error, AppTrash.Failure.finderNotPermitted),
        (AppTrash.Failure.other("Disk error") as Error, AppTrash.Failure.other("Disk error")),
        (TestError.diskFull as Error, AppTrash.Failure.other(TestError.diskFull.localizedDescription))
    ])
    func failureKeepsAppAndShowsWhy(thrown: Error, shown: AppTrash.Failure) async throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = TrashLog()
        log.failure = thrown
        let vm = try makeViewModel(db, log: log)

        vm.requestRemoval(of: try entry(vm, "a"))
        await vm.confirmRemoval {}

        #expect(vm.pendingRemoval?.stage == .failed(shown))
        #expect(vm.apps.contains { $0.bundleIdentifier == "a" })
        #expect(try db.fetchAllApps().contains { $0.bundleIdentifier == "a" })
    }

    @Test func confirmOnOpenAppDialogOnlyClosesIt() async throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = TrashLog()
        log.running = ["a"]
        let vm = try makeViewModel(db, log: log)

        vm.requestRemoval(of: try entry(vm, "a"))
        await vm.confirmRemoval {}

        #expect(vm.pendingRemoval == nil)
        #expect(log.trashed.isEmpty)
        #expect(vm.apps.contains { $0.bundleIdentifier == "a" })
    }

    @Test func dropUnknownAppChangesNothing() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db, log: TrashLog())
        let before = vm.apps

        #expect(!vm.dropUninstalledApp("missing"))
        #expect(vm.apps == before)
    }
}

struct AppTrashTests {
    @Test(arguments: [
        ("/Applications/Telegram.app", true),
        ("/Applications/Utilities/Tool.app", true),
        ("/System/Applications/Mail.app", false),
        ("/System/Applications/Utilities/Terminal.app", false)
    ])
    func isRemovable(path: String, expected: Bool) {
        #expect(AppTrash.isRemovable(appPath: path) == expected)
    }

    // Like /Applications/Safari.app, which links into the system cryptex.
    @Test func linkIntoSystemIsNotRemovable() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("slp-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let link = dir.appendingPathComponent("Linked.app")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/System/Applications")

        #expect(!AppTrash.isRemovable(appPath: link.path))
    }

    @Test func userOwnedBundleNeedsNoAuthorization() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("slp-tests-\(UUID().uuidString)", isDirectory: true)
        let bundle = dir.appendingPathComponent("Mine.app", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(!AppTrash.needsAuthorization(appPath: bundle.path))

        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: bundle.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundle.path) }
        #expect(AppTrash.needsAuthorization(appPath: bundle.path))
    }
}
