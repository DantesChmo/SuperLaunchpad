import Foundation
import GRDB
import Testing
@testable import SuperLaunchpad

@MainActor
struct NewAppsTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("slp-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeTempDB() throws -> (AppDatabase, URL) {
        let dir = try makeTempDir()
        return (try AppDatabase(path: dir.appendingPathComponent("test.db").path), dir)
    }

    private func app(
        _ bundleID: String,
        page: Int? = nil,
        order: Int? = nil,
        folderID: String? = nil,
        folderOrder: Int? = nil,
        isNew: Bool = false
    ) -> AppEntry {
        AppEntry(
            bundleIdentifier: bundleID,
            displayName: bundleID,
            appPath: "/Applications/\(bundleID).app",
            pageIndex: page,
            orderIndex: order,
            folderID: folderID,
            folderOrderIndex: folderOrder,
            isNew: isNew
        )
    }

    // Page 0: a, b, folder F (x, y).
    private let existingApps = [
        AppEntry(bundleIdentifier: "com.a", displayName: "a", appPath: "/Applications/com.a.app", pageIndex: 0, orderIndex: 0),
        AppEntry(bundleIdentifier: "com.b", displayName: "b", appPath: "/Applications/com.b.app", pageIndex: 0, orderIndex: 1),
        AppEntry(bundleIdentifier: "com.x", displayName: "x", appPath: "/Applications/com.x.app", folderID: "F", folderOrderIndex: 0),
        AppEntry(bundleIdentifier: "com.y", displayName: "y", appPath: "/Applications/com.y.app", folderID: "F", folderOrderIndex: 1),
    ]
    private let existingFolders = [FolderEntry(id: "F", title: "Games", pageIndex: 0, orderIndex: 2)]

    private func merge(
        _ newIDs: [String],
        folders: [FolderEntry]? = nil,
        markNew: Bool = true,
        placement: NewAppPlacement = .end,
        categoryTitles: @escaping (AppEntry) -> [String] = { _ in [] }
    ) -> (apps: [String: AppEntry], folders: [FolderEntry]) {
        let enumerated = existingApps.map { app($0.bundleIdentifier) } + newIDs.map { app($0) }
        let (apps, folders) = LaunchpadViewModel.mergeNewApps(
            enumerated,
            existingApps: existingApps,
            existingFolders: folders ?? existingFolders,
            systemOrdering: nil,
            folderImportDone: true,
            markNew: markNew,
            placement: placement,
            categoryTitles: categoryTitles
        )
        return (Dictionary(uniqueKeysWithValues: apps.map { ($0.bundleIdentifier, $0) }), folders)
    }

    private func scan(_ ids: [String], in db: AppDatabase, systemOrdering: LaunchpadOrdering? = nil) -> [String: AppEntry] {
        let (apps, _) = LaunchpadViewModel.syncScan(
            ids.map { app($0) },
            systemOrdering: systemOrdering,
            placement: .end,
            database: db
        )
        return Dictionary(uniqueKeysWithValues: apps.map { ($0.bundleIdentifier, $0) })
    }

    // MARK: - Migration

    @Test func freshDatabaseDoesNotTrackNewApps() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(try db.setting(.newAppTracking) == nil)
    }

    // A v4 database is filled, then opened by `AppDatabase`, which runs v5 and v6.
    @Test(arguments: [true, false])
    func v6MarksNothingNewAndTracksOnlyAnExistingLayout(hasLayout: Bool) throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("test.db").path

        let queue = try DatabaseQueue(path: path)
        try AppDatabase.migrator.migrate(queue, upTo: "v4")
        try queue.write { db in
            for (index, id) in ["com.a", "com.b"].enumerated() {
                try db.execute(
                    sql: "INSERT INTO appEntry (bundleIdentifier, displayName, appPath, pageIndex, orderIndex) VALUES (?, ?, ?, ?, ?)",
                    arguments: [id, id, "/Applications/\(id).app", hasLayout ? 0 : nil, hasLayout ? index : nil]
                )
            }
        }
        try queue.close()

        let db = try AppDatabase(path: path)
        let apps = try db.fetchAllApps()
        #expect(apps.count == 2)
        #expect(apps.allSatisfy { !$0.isNew })
        #expect(try db.setting(.newAppTracking) == (hasLayout ? "1" : nil))
    }

    @Test func isNewRoundTripsThroughDatabase() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        try db.saveApps([app("com.a", page: 0, order: 0, isNew: true), app("com.b", page: 0, order: 1)])
        let byID = Dictionary(uniqueKeysWithValues: try db.fetchAllApps().map { ($0.bundleIdentifier, $0.isNew) })
        #expect(byID == ["com.a": true, "com.b": false])
    }

    // MARK: - Marking on scan

    @Test func firstRunMarksNothingNew() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }

        let apps = scan(["com.a", "com.b"], in: db)

        #expect(apps.count == 2)
        #expect(apps.values.allSatisfy { !$0.isNew })
        #expect(try db.setting(.newAppTracking) == "1")
    }

    @Test func appInstalledAfterFirstRunIsNew() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = scan(["com.a", "com.b"], in: db)

        let apps = scan(["com.a", "com.b", "com.c"], in: db)

        #expect(apps["com.c"]?.isNew == true)
        #expect(apps["com.a"]?.isNew == false)
        #expect(apps["com.b"]?.isNew == false)
    }

    @Test func laterRescanKeepsTheMark() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = scan(["com.a"], in: db)
        _ = scan(["com.a", "com.c"], in: db)

        let apps = scan(["com.a", "com.c"], in: db)

        #expect(apps["com.c"]?.isNew == true)
    }

    // The system layout leaves out apps it doesn't know; the next rescan adds
    // them, but they were there before SuperLaunchpad, so they are not new.
    @Test func appsSkippedByFirstImportAreNotNew() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let ordering = LaunchpadOrdering(appPositions: ["com.a": (pageIndex: 0, orderIndex: 0)], folders: [])

        let first = scan(["com.a", "com.unknown"], in: db, systemOrdering: ordering)
        #expect(first["com.unknown"] == nil)
        #expect(try db.setting(.newAppTracking) == nil)

        let second = scan(["com.a", "com.unknown"], in: db, systemOrdering: ordering)
        #expect(second["com.unknown"]?.isNew == false)
        #expect(try db.setting(.newAppTracking) == "1")

        let third = scan(["com.a", "com.unknown", "com.c"], in: db, systemOrdering: ordering)
        #expect(third["com.c"]?.isNew == true)
        #expect(third["com.unknown"]?.isNew == false)
    }

    @Test func mergeMarksOnlyAppsWithoutRow() {
        let (apps, _) = merge(["com.c"])
        #expect(apps["com.c"]?.isNew == true)
        #expect(existingApps.allSatisfy { apps[$0.bundleIdentifier]?.isNew == false })
    }

    @Test func mergeWithoutTrackingMarksNothing() {
        let (apps, _) = merge(["com.c"], markNew: false)
        #expect(apps["com.c"]?.isNew == false)
    }

    // MARK: - Placement

    @Test func endPlacementAppendsAfterLastItem() {
        let (apps, folders) = merge(["com.c"], placement: .end)
        #expect(apps["com.c"]?.pageIndex == 0)
        #expect(apps["com.c"]?.orderIndex == 3)
        #expect(apps["com.c"]?.folderID == nil)
        #expect(folders == existingFolders)
    }

    @Test func categoryPlacementPutsAppAfterFolderLastApp() {
        let (apps, folders) = merge(["com.c"], placement: .categoryFolder) { _ in ["Utilities", "games"] }
        #expect(apps["com.c"]?.folderID == "F")
        #expect(apps["com.c"]?.folderOrderIndex == 2)
        #expect(apps["com.c"]?.pageIndex == nil)
        #expect(apps["com.c"]?.orderIndex == nil)
        #expect(folders == existingFolders)
    }

    @Test func categoryPlacementWithoutMatchingFolderAppendsAtEnd() {
        let (apps, folders) = merge(["com.c"], placement: .categoryFolder) { _ in ["Productivity"] }
        #expect(apps["com.c"]?.folderID == nil)
        #expect(apps["com.c"]?.pageIndex == 0)
        #expect(apps["com.c"]?.orderIndex == 3)
        #expect(folders == existingFolders)
    }

    @Test func newFolderPlacementMakesOneFolderAtEnd() throws {
        let (apps, folders) = merge(["com.c", "com.d"], placement: .newFolder)

        #expect(folders.count == 2)
        let newFolder = try #require(folders.first { $0.title == NewAppPlacement.newFolderTitle })
        #expect(newFolder.pageIndex == 0)
        #expect(newFolder.orderIndex == 3)
        #expect(apps["com.c"]?.folderID == newFolder.id)
        #expect(apps["com.c"]?.folderOrderIndex == 0)
        #expect(apps["com.d"]?.folderID == newFolder.id)
        #expect(apps["com.d"]?.folderOrderIndex == 1)
        #expect(apps["com.c"]?.pageIndex == nil)
    }

    @Test func newFolderPlacementReusesExistingNewFolder() {
        let folders = [FolderEntry(id: "F", title: NewAppPlacement.newFolderTitle, pageIndex: 0, orderIndex: 2)]
        let (apps, result) = merge(["com.c"], folders: folders, placement: .newFolder)
        #expect(result == folders)
        #expect(apps["com.c"]?.folderID == "F")
        #expect(apps["com.c"]?.folderOrderIndex == 2)
    }

    // Apps added without the mark (see `appsSkippedByFirstImportAreNotNew`)
    // go at the end whatever the setting.
    @Test(arguments: [NewAppPlacement.categoryFolder, .newFolder])
    func placementNeedsTracking(placement: NewAppPlacement) {
        let (apps, folders) = merge(["com.c"], markNew: false, placement: placement) { _ in ["Games"] }
        #expect(apps["com.c"]?.folderID == nil)
        #expect(apps["com.c"]?.orderIndex == 3)
        #expect(folders == existingFolders)
    }

    // MARK: - Launch

    @Test func launchDropsTheMarkInMemoryAndOnDisk() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        try db.saveApps([app("com.a", page: 0, order: 0, isNew: true), app("com.b", page: 0, order: 1, isNew: true)])
        let vm = LaunchpadViewModel(database: db)
        vm.apps = try db.fetchAllApps()

        vm.recordLaunch("com.a")

        #expect(vm.apps.first { $0.bundleIdentifier == "com.a" }?.isNew == false)
        #expect(vm.apps.first { $0.bundleIdentifier == "com.b" }?.isNew == true)
        let stored = Dictionary(uniqueKeysWithValues: try db.fetchAllApps().map { ($0.bundleIdentifier, $0.isNew) })
        #expect(stored == ["com.a": false, "com.b": true])
    }

    // In edit mode a click doesn't launch, so the app stays new.
    @Test func clickInEditModeKeepsTheMark() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        try db.saveApps([app("com.a", page: 0, order: 0, isNew: true)])
        let vm = LaunchpadViewModel(database: db)
        vm.apps = try db.fetchAllApps()
        vm.editing.enterEditMode()

        let launched = vm.itemActions.launchApp(try #require(vm.apps.first))

        #expect(launched == false)
        #expect(vm.apps.first?.isNew == true)
        #expect(try db.fetchAllApps().first?.isNew == true)
    }
}
