import Foundation
import GRDB
import Testing
@testable import SuperLaunchpad

struct AppDatabaseLayoutTests {

    private func makeTempDB() throws -> (AppDatabase, URL) {
        let dir = try makeTempDir()
        return (try AppDatabase(path: dir.appendingPathComponent("test.db").path), dir)
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("slp-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
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

    // MARK: - Migration v4

    @Test func freshDatabaseHasNoFolderImportFlag() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(try db.setting(.folderImportDone) == nil)
    }

    // A v3 database is filled, then opened by `AppDatabase`, which runs v4.
    @Test(arguments: [true, false])
    func v4BackfillsFlagOnlyWhenAppsAreInFolders(hasFolderApps: Bool) throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("test.db").path

        let queue = try DatabaseQueue(path: path)
        try AppDatabase.migrator.migrate(queue, upTo: "v3")
        try queue.write { db in
            try FolderEntry(id: "F", title: "F", pageIndex: 0, orderIndex: 0).insert(db)
            let member = hasFolderApps
                ? app("com.in", folderID: "F", folderOrder: 0)
                : app("com.in", page: 0, order: 1)
            try member.insert(db)
            try app("com.top", page: 0, order: 2).insert(db)
        }
        try queue.close()

        let db = try AppDatabase(path: path)
        #expect(try db.setting(.folderImportDone) == (hasFolderApps ? "1" : nil))
        #expect(try db.fetchAllApps().count == 2)
        #expect(try db.fetchAllFolders().count == 1)
    }

    @Test func settingRoundTripAndOverwrite() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        try db.setSetting(.folderImportDone, "1")
        #expect(try db.setting(.folderImportDone) == "1")
        try db.setSetting(.folderImportDone, "2")
        #expect(try db.setting(.folderImportDone) == "2")
    }

    // MARK: - Layout writes

    @Test func saveLayoutUpsertsRowsDeletesMissingFoldersAndSetsFlag() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        try db.saveFolders([
            FolderEntry(id: "Keep", title: "Keep", pageIndex: 0, orderIndex: 0),
            FolderEntry(id: "Drop", title: "Drop", pageIndex: 0, orderIndex: 1)
        ])
        try db.saveApps([
            app("com.k", folderID: "Keep", folderOrder: 0),
            app("com.d", folderID: "Drop", folderOrder: 0)
        ])

        let folders = [
            FolderEntry(id: "Keep", title: "Keep", pageIndex: 0, orderIndex: 1),
            FolderEntry(id: "New", title: "New", pageIndex: 0, orderIndex: 2)
        ]
        let apps = [
            app("com.k", folderID: "Keep", folderOrder: 0),
            app("com.d", page: 0, order: 0),
            app("com.n", folderID: "New", folderOrder: 0)
        ]
        try db.saveLayout(apps: apps, folders: folders)

        #expect(try db.fetchAllFolders() == folders)
        #expect(Set(try db.fetchAllApps().map(\.id)) == ["com.k", "com.d", "com.n"])
        #expect(try db.fetchAllApps().first { $0.id == "com.d" } == apps[1])
        #expect(try db.setting(.folderImportDone) == "1")
    }

    @Test func renameFolderUpdatesOnlyTitle() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        try db.saveFolders([FolderEntry(id: "F", title: "Old", pageIndex: 1, orderIndex: 3)])
        try db.renameFolder(id: "F", title: "New")
        #expect(try db.fetchAllFolders() == [FolderEntry(id: "F", title: "New", pageIndex: 1, orderIndex: 3)])
    }
}
