import Foundation
import Testing
@testable import SuperLaunchpad

struct AppDatabaseTests {

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
        page: Int? = nil,
        order: Int? = nil,
        folderID: String? = nil,
        folderOrder: Int? = nil
    ) -> AppEntry {
        AppEntry(
            bundleIdentifier: bundleID,
            displayName: name ?? bundleID,
            appPath: "/Applications/\(bundleID).app",
            iconData: nil,
            pageIndex: page,
            orderIndex: order,
            folderID: folderID,
            folderOrderIndex: folderOrder
        )
    }

    @Test func initCreatesEmptyDatabase() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let apps = try db.fetchAllApps()
        let folders = try db.fetchAllFolders()
        #expect(apps.isEmpty)
        #expect(folders.isEmpty)
    }

    @Test func saveAndFetchAppRoundTrip() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let original = app("com.a", name: "App A", page: 0, order: 0)
        try db.saveApps([original])
        let fetched = try db.fetchAllApps()
        #expect(fetched.count == 1)
        #expect(fetched[0] == original)
    }

    @Test func fetchAllAppsSortedByPageThenOrder() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        try db.saveApps([
            app("com.p1-0", page: 1, order: 0),
            app("com.p0-1", page: 0, order: 1),
            app("com.p0-0", page: 0, order: 0)
        ])
        let fetched = try db.fetchAllApps()
        #expect(fetched.map(\.bundleIdentifier) == ["com.p0-0", "com.p0-1", "com.p1-0"])
    }

    @Test func fetchAllAppsNilPageSortedLast() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        try db.saveApps([
            app("com.nopos", page: nil, order: nil),
            app("com.pos", page: 0, order: 0)
        ])
        let fetched = try db.fetchAllApps()
        #expect(fetched.map(\.bundleIdentifier) == ["com.pos", "com.nopos"])
    }

    @Test func hasOrderingDataFalseWhenEmpty() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(try db.hasOrderingData() == false)
    }

    @Test func hasOrderingDataFalseWhenAllNilPageIndex() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        try db.saveApps([app("com.a", page: nil, order: nil)])
        #expect(try db.hasOrderingData() == false)
    }

    @Test func hasOrderingDataTrueWhenAnyAppHasPageIndex() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        try db.saveApps([
            app("com.a", page: nil, order: nil),
            app("com.b", page: 0, order: 0)
        ])
        #expect(try db.hasOrderingData() == true)
    }

    @Test func deleteStaleRemovesAppsNotInSet() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        try db.saveApps([
            app("com.keep", page: 0, order: 0),
            app("com.stale", page: 0, order: 1)
        ])
        try db.deleteStale(validIdentifiers: ["com.keep"])
        let fetched = try db.fetchAllApps()
        #expect(fetched.map(\.bundleIdentifier) == ["com.keep"])
    }

    @Test func saveAndFetchFolderRoundTrip() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = FolderEntry(id: "fld-1", title: "Utils", pageIndex: 0, orderIndex: 0)
        try db.saveFolders([folder])
        let fetched = try db.fetchAllFolders()
        #expect(fetched.count == 1)
        #expect(fetched[0] == folder)
    }

    @Test func fetchAllFoldersSortedByPageThenOrder() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        try db.saveFolders([
            FolderEntry(id: "p1-0", title: "B", pageIndex: 1, orderIndex: 0),
            FolderEntry(id: "p0-1", title: "A2", pageIndex: 0, orderIndex: 1),
            FolderEntry(id: "p0-0", title: "A1", pageIndex: 0, orderIndex: 0)
        ])
        let fetched = try db.fetchAllFolders()
        #expect(fetched.map(\.id) == ["p0-0", "p0-1", "p1-0"])
    }

    @Test func deleteStaleFoldersRemovesUnlistedIDs() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        try db.saveFolders([
            FolderEntry(id: "keep", title: "K", pageIndex: 0, orderIndex: 0),
            FolderEntry(id: "stale", title: "S", pageIndex: 0, orderIndex: 1)
        ])
        try db.deleteStaleFolders(validIDs: ["keep"])
        let fetched = try db.fetchAllFolders()
        #expect(fetched.map(\.id) == ["keep"])
    }

    @Test func saveAppUpsertDoesNotDuplicate() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        try db.saveApps([app("com.a", name: "First", page: 0, order: 0)])
        try db.saveApps([app("com.a", name: "Second", page: 1, order: 2)])
        let fetched = try db.fetchAllApps()
        #expect(fetched.count == 1)
        #expect(fetched[0].displayName == "Second")
        #expect(fetched[0].pageIndex == 1)
        #expect(fetched[0].orderIndex == 2)
    }

    @Test func folderDeletionSetsAppFolderIDToNull() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = FolderEntry(id: "fld", title: "F", pageIndex: 0, orderIndex: 0)
        try db.saveFolders([folder])
        try db.saveApps([app("com.x", folderID: "fld", folderOrder: 0)])
        // Delete the folder by passing empty valid set
        try db.deleteStaleFolders(validIDs: [])
        let fetched = try db.fetchAllApps()
        #expect(fetched.count == 1)
        #expect(fetched[0].folderID == nil)
    }
}
