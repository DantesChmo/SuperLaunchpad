import Foundation
import Testing
@testable import SuperLaunchpad

struct SystemLaunchpadDBTests {

    // MARK: - Fixture helpers

    // type values in the system Launchpad schema:
    // 1 = root, 2 = folder, 3 = page (top-level or folder-page), 4/5 = app.
    private enum ItemType: Int {
        case root = 1
        case folder = 2
        case page = 3
        case app = 4
        case systemApp = 5
    }

    private struct FixtureItem {
        let rowid: Int64
        let parentID: Int64
        let ordering: Int
        let type: ItemType
        var bundleID: String? = nil
        var title: String? = nil
    }

    // We construct the fixture DB by piping SQL into `/usr/bin/sqlite3`.
    // This avoids linking GRDB into the test target while still producing
    // a real SQLite file that SystemLaunchpadDB opens via GRDB at runtime.
    private func makeFixtureDB(_ items: [FixtureItem]) throws -> (String, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("slp-syslp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("db").path

        var sql = """
        CREATE TABLE items (rowid INTEGER PRIMARY KEY, parent_id INTEGER NOT NULL, ordering INTEGER NOT NULL, type INTEGER NOT NULL);
        CREATE TABLE apps (item_id INTEGER PRIMARY KEY, bundleid TEXT);
        CREATE TABLE groups (item_id INTEGER PRIMARY KEY, title TEXT);
        """
        for item in items {
            sql += "\nINSERT INTO items VALUES (\(item.rowid), \(item.parentID), \(item.ordering), \(item.type.rawValue));"
            if let bundleID = item.bundleID {
                sql += "\nINSERT INTO apps VALUES (\(item.rowid), '\(bundleID)');"
            }
            if let title = item.title {
                sql += "\nINSERT INTO groups VALUES (\(item.rowid), '\(title)');"
            }
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        proc.arguments = [path]
        let stdin = Pipe()
        proc.standardInput = stdin
        try proc.run()
        try stdin.fileHandleForWriting.write(contentsOf: Data(sql.utf8))
        try stdin.fileHandleForWriting.close()
        proc.waitUntilExit()
        return (path, dir)
    }

    // MARK: - Missing / empty DB

    @Test func returnsNilWhenDBFileMissing() {
        let bogus = "/tmp/does-not-exist-\(UUID().uuidString)/db"
        #expect(SystemLaunchpadDB.readOrdering(dbPath: bogus) == nil)
    }

    @Test func returnsNilWhenNoRootRow() throws {
        let (path, dir) = try makeFixtureDB([])
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(SystemLaunchpadDB.readOrdering(dbPath: path) == nil)
    }

    @Test func returnsNilWhenAllPagesEmpty() throws {
        // Root + a page that contains no apps/folders — must be filtered out,
        // and since there are no other pages we return nil.
        let (path, dir) = try makeFixtureDB([
            FixtureItem(rowid: 1, parentID: 0, ordering: 0, type: .root),
            FixtureItem(rowid: 2, parentID: 1, ordering: 0, type: .page)
        ])
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(SystemLaunchpadDB.readOrdering(dbPath: path) == nil)
    }

    @Test func returnsNilWhenRootHasNoPages() throws {
        let (path, dir) = try makeFixtureDB([
            FixtureItem(rowid: 1, parentID: 0, ordering: 0, type: .root)
        ])
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(SystemLaunchpadDB.readOrdering(dbPath: path) == nil)
    }

    // MARK: - Top-level apps

    @Test func readsTopLevelAppsWithPageAndOrder() throws {
        let (path, dir) = try makeFixtureDB([
            FixtureItem(rowid: 1, parentID: 0, ordering: 0, type: .root),
            FixtureItem(rowid: 10, parentID: 1, ordering: 0, type: .page),
            FixtureItem(rowid: 11, parentID: 1, ordering: 1, type: .page),
            FixtureItem(rowid: 100, parentID: 10, ordering: 0, type: .app, bundleID: "com.a"),
            FixtureItem(rowid: 101, parentID: 10, ordering: 1, type: .systemApp, bundleID: "com.b"),
            FixtureItem(rowid: 102, parentID: 11, ordering: 0, type: .app, bundleID: "com.c")
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let ordering = try #require(SystemLaunchpadDB.readOrdering(dbPath: path))

        #expect(ordering.appPositions.count == 3)
        #expect(ordering.appPositions["com.a"]?.pageIndex == 0)
        #expect(ordering.appPositions["com.a"]?.orderIndex == 0)
        #expect(ordering.appPositions["com.b"]?.pageIndex == 0)
        #expect(ordering.appPositions["com.b"]?.orderIndex == 1)
        #expect(ordering.appPositions["com.c"]?.pageIndex == 1)
        #expect(ordering.folders.isEmpty)
    }

    @Test func emptyPagesAreFilteredAndIndicesCompacted() throws {
        // Page rowid=20 is empty and must be dropped — apps on page rowid=21
        // should land on dense index 1, not 2.
        let (path, dir) = try makeFixtureDB([
            FixtureItem(rowid: 1, parentID: 0, ordering: 0, type: .root),
            FixtureItem(rowid: 10, parentID: 1, ordering: 0, type: .page),
            FixtureItem(rowid: 20, parentID: 1, ordering: 1, type: .page),
            FixtureItem(rowid: 21, parentID: 1, ordering: 2, type: .page),
            FixtureItem(rowid: 100, parentID: 10, ordering: 0, type: .app, bundleID: "com.a"),
            FixtureItem(rowid: 101, parentID: 21, ordering: 0, type: .app, bundleID: "com.b")
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let ordering = try #require(SystemLaunchpadDB.readOrdering(dbPath: path))
        #expect(ordering.appPositions["com.a"]?.pageIndex == 0)
        #expect(ordering.appPositions["com.b"]?.pageIndex == 1)
    }

    @Test func pagesAreOrderedByOrderingColumnNotRowid() throws {
        // rowid 20 has ordering=0, rowid 10 has ordering=1 — the page with
        // smaller ordering must become page index 0.
        let (path, dir) = try makeFixtureDB([
            FixtureItem(rowid: 1, parentID: 0, ordering: 0, type: .root),
            FixtureItem(rowid: 10, parentID: 1, ordering: 1, type: .page),
            FixtureItem(rowid: 20, parentID: 1, ordering: 0, type: .page),
            FixtureItem(rowid: 100, parentID: 10, ordering: 0, type: .app, bundleID: "com.a"),
            FixtureItem(rowid: 101, parentID: 20, ordering: 0, type: .app, bundleID: "com.b")
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let ordering = try #require(SystemLaunchpadDB.readOrdering(dbPath: path))
        #expect(ordering.appPositions["com.b"]?.pageIndex == 0)
        #expect(ordering.appPositions["com.a"]?.pageIndex == 1)
    }

    // MARK: - Folders

    @Test func readsFolderWithAppsViaFolderPage() throws {
        // Standard hierarchy: root → page → folder → folder-page → app.
        let (path, dir) = try makeFixtureDB([
            FixtureItem(rowid: 1, parentID: 0, ordering: 0, type: .root),
            FixtureItem(rowid: 10, parentID: 1, ordering: 0, type: .page),
            FixtureItem(rowid: 50, parentID: 10, ordering: 2, type: .folder, title: "Utilities"),
            FixtureItem(rowid: 60, parentID: 50, ordering: 0, type: .page),
            FixtureItem(rowid: 200, parentID: 60, ordering: 1, type: .app, bundleID: "com.tool.b"),
            FixtureItem(rowid: 201, parentID: 60, ordering: 0, type: .app, bundleID: "com.tool.a")
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let ordering = try #require(SystemLaunchpadDB.readOrdering(dbPath: path))
        #expect(ordering.folders.count == 1)
        let folder = try #require(ordering.folders.first)
        #expect(folder.title == "Utilities")
        #expect(folder.pageIndex == 0)
        #expect(folder.orderIndex == 2)
        #expect(folder.appBundleIDs.map(\.bundleID) == ["com.tool.a", "com.tool.b"])
    }

    @Test func readsFolderWithAppsDirectlyUnderFolder() throws {
        // Some folders skip the folder-page level — apps sit directly under
        // the folder rowid.
        let (path, dir) = try makeFixtureDB([
            FixtureItem(rowid: 1, parentID: 0, ordering: 0, type: .root),
            FixtureItem(rowid: 10, parentID: 1, ordering: 0, type: .page),
            FixtureItem(rowid: 50, parentID: 10, ordering: 0, type: .folder, title: "Direct"),
            FixtureItem(rowid: 200, parentID: 50, ordering: 0, type: .app, bundleID: "com.x")
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let ordering = try #require(SystemLaunchpadDB.readOrdering(dbPath: path))
        let folder = try #require(ordering.folders.first)
        #expect(folder.appBundleIDs.map(\.bundleID) == ["com.x"])
    }

    @Test func folderWithoutTitleFallsBackToDefault() throws {
        let (path, dir) = try makeFixtureDB([
            FixtureItem(rowid: 1, parentID: 0, ordering: 0, type: .root),
            FixtureItem(rowid: 10, parentID: 1, ordering: 0, type: .page),
            FixtureItem(rowid: 50, parentID: 10, ordering: 0, type: .folder),
            FixtureItem(rowid: 200, parentID: 50, ordering: 0, type: .app, bundleID: "com.x")
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let ordering = try #require(SystemLaunchpadDB.readOrdering(dbPath: path))
        #expect(ordering.folders.first?.title == "Folder")
    }

    @Test func mixedTopLevelAppsAndFolders() throws {
        let (path, dir) = try makeFixtureDB([
            FixtureItem(rowid: 1, parentID: 0, ordering: 0, type: .root),
            FixtureItem(rowid: 10, parentID: 1, ordering: 0, type: .page),
            FixtureItem(rowid: 100, parentID: 10, ordering: 0, type: .app, bundleID: "com.solo"),
            FixtureItem(rowid: 50, parentID: 10, ordering: 1, type: .folder, title: "Group"),
            FixtureItem(rowid: 60, parentID: 50, ordering: 0, type: .page),
            FixtureItem(rowid: 200, parentID: 60, ordering: 0, type: .app, bundleID: "com.inside")
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let ordering = try #require(SystemLaunchpadDB.readOrdering(dbPath: path))
        #expect(ordering.appPositions["com.solo"]?.pageIndex == 0)
        #expect(ordering.appPositions["com.inside"] == nil)
        #expect(ordering.folders.first?.appBundleIDs.map(\.bundleID) == ["com.inside"])
    }

    @Test func appOrderIndexPreservedAcrossFolderPages() throws {
        // A folder with two folder-pages — each folder-page restarts its
        // child ordering at 0. The current implementation flattens them
        // by orderIndex regardless of folder-page, so the second-page
        // entries with ordering=0,1 will interleave with the first.
        // We pin the observed behaviour: all apps end up in the folder,
        // sorted by ordering ascending.
        let (path, dir) = try makeFixtureDB([
            FixtureItem(rowid: 1, parentID: 0, ordering: 0, type: .root),
            FixtureItem(rowid: 10, parentID: 1, ordering: 0, type: .page),
            FixtureItem(rowid: 50, parentID: 10, ordering: 0, type: .folder, title: "Many"),
            FixtureItem(rowid: 60, parentID: 50, ordering: 0, type: .page),
            FixtureItem(rowid: 61, parentID: 50, ordering: 1, type: .page),
            FixtureItem(rowid: 200, parentID: 60, ordering: 5, type: .app, bundleID: "com.fifth"),
            FixtureItem(rowid: 201, parentID: 61, ordering: 2, type: .app, bundleID: "com.second")
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let ordering = try #require(SystemLaunchpadDB.readOrdering(dbPath: path))
        let folder = try #require(ordering.folders.first)
        #expect(folder.appBundleIDs.map(\.bundleID) == ["com.second", "com.fifth"])
    }
}
