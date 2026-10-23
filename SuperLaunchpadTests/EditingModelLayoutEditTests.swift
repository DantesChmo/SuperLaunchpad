import Foundation
import Testing
@testable import SuperLaunchpad

@MainActor
struct EditingModelLayoutEditTests {

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
        folderOrder: Int? = nil
    ) -> AppEntry {
        AppEntry(
            bundleIdentifier: bundleID,
            displayName: bundleID,
            appPath: "/Applications/\(bundleID).app",
            pageIndex: page,
            orderIndex: order,
            folderID: folderID,
            folderOrderIndex: folderOrder
        )
    }

    // Page a, b, folder F(x, y), c — stored in the DB and loaded into a view
    // model without a rescan.
    private func makeViewModel(_ db: AppDatabase) throws -> LaunchpadViewModel {
        let folders = [FolderEntry(id: "F", title: "Tools", pageIndex: 0, orderIndex: 2)]
        let apps = [
            app("a", page: 0, order: 0),
            app("b", page: 0, order: 1),
            app("c", page: 0, order: 3),
            app("x", folderID: "F", folderOrder: 0),
            app("y", folderID: "F", folderOrder: 1)
        ]
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

    @Test func moveItemUpdatesPagesAndPersists() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)

        #expect(vm.editing.moveItem(.app("c"), toPage: 0, slot: 0))
        #expect(pageIDs(vm) == [["c", "a", "b", "F"]])
        #expect(try storedLayout(db) == GridLayout(apps: vm.apps, folders: vm.folders))
        #expect(try db.fetchAllApps().first { $0.id == "c" }?.orderIndex == 0)
        #expect(try db.setting(.folderImportDone) == "1")
    }

    @Test func mergeAppsCreatesFolderAndPersists() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)

        let folderID = try #require(vm.editing.mergeApps("c", onto: "a"))
        #expect(pageIDs(vm) == [[folderID, "b", "F"]])
        let folder = try #require(try db.fetchAllFolders().first { $0.id == folderID })
        #expect(folder.title == EditingModel.defaultFolderTitle)
        #expect(folder.pageIndex == 0 && folder.orderIndex == 0)
        let stored = try db.fetchAllApps().filter { $0.folderID == folderID }
        #expect(stored.map(\.id) == ["a", "c"] || stored.map(\.id) == ["c", "a"])
        #expect(stored.allSatisfy { $0.pageIndex == nil && $0.orderIndex == nil })
    }

    @Test func addAppToFolderPersists() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)

        #expect(vm.editing.addApp("b", toFolder: "F", at: 0))
        #expect(pageIDs(vm) == [["a", "F", "c"]])
        vm.openFolder(try #require(vm.folders.first))
        #expect(vm.openFolderApps.map(\.id) == ["b", "x", "y"])
        #expect(try storedLayout(db).folders["F"]?.appIDs == ["b", "x", "y"])
    }

    @Test func removingLastAppDissolvesFolderAndClosesIt() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        vm.openFolder(try #require(vm.folders.first))

        #expect(vm.editing.removeApp("x", fromFolder: "F", toPage: 0, slot: 0))
        #expect(vm.openFolderID == "F")
        #expect(vm.editing.removeApp("y", fromFolder: "F", toPage: 0, slot: 0))

        #expect(vm.folders.isEmpty)
        #expect(vm.openFolderID == nil)
        #expect(pageIDs(vm) == [["y", "x", "a", "b", "c"]])
        #expect(try db.fetchAllFolders().isEmpty)
        #expect(try db.fetchAllApps().allSatisfy { $0.folderID == nil && $0.pageIndex == 0 })
    }

    @Test func invalidEditChangesNothing() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        let apps = vm.apps

        #expect(vm.editing.moveItem(.app("missing"), toPage: 0, slot: 0) == false)
        #expect(vm.editing.mergeApps("a", onto: "x") == nil)
        #expect(vm.editing.addApp("F", toFolder: "F") == false)
        #expect(vm.apps == apps)
        #expect(try db.setting(.folderImportDone) == nil)
    }

    @Test func renameFolderTrimsAndPersists() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)

        #expect(vm.editing.renameFolder("F", to: "  Work "))
        #expect(vm.folders.first?.title == "Work")
        #expect(try db.fetchAllFolders().first?.title == "Work")
        #expect(vm.editing.renameFolder("F", to: "   ") == false)
        #expect(vm.folders.first?.title == "Work")
    }

    // The folder-resurrection bug: once the user dissolved the last folder,
    // the next rescan must not import the system Launchpad folders again.
    @Test func dissolvedFoldersStayGoneAfterRescanMerge() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        #expect(vm.editing.removeApp("x", fromFolder: "F", toPage: 0, slot: 0))
        #expect(vm.editing.removeApp("y", fromFolder: "F", toPage: 0, slot: 0))

        let systemOrdering = LaunchpadOrdering(
            appPositions: [:],
            folders: [FolderInfo(title: "System", pageIndex: 0, orderIndex: 0, appBundleIDs: [(bundleID: "x", orderIndex: 0)])]
        )
        let (apps, folders) = LaunchpadViewModel.mergeNewApps(
            try db.fetchAllApps(),
            existingApps: try db.fetchAllApps(),
            existingFolders: try db.fetchAllFolders(),
            systemOrdering: systemOrdering,
            folderImportDone: try db.setting(.folderImportDone) != nil
        )
        #expect(folders.isEmpty)
        #expect(apps.allSatisfy { $0.folderID == nil })
    }
}
