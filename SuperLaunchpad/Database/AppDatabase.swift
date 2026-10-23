import Foundation
import GRDB

// SQLite persistence layer (GRDB).
//
// One instance per app session. `DatabaseQueue` serialises all access through
// a single background queue, so reads/writes from any thread are safe — no
// manual locking required at call sites.
final class AppDatabase {
    private let dbQueue: DatabaseQueue

    // `path: nil` resolves to the standard Application Support location:
    //   ~/Library/Application Support/com.dantes.SuperLaunchpad/apps.db
    // Tests pass an explicit temp path via `makeTempDB()` so each test gets a
    // fresh DB (see SuperLaunchpadTests/AppDatabaseTests.swift).
    init(path: String? = nil) throws {
        let dbPath: String
        if let path {
            dbPath = path
        } else {
            // `.applicationSupportDirectory` resolves to the per-user directory
            // sandboxed apps are allowed to write to without extra entitlements.
            let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("com.dantes.SuperLaunchpad", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            dbPath = folder.appendingPathComponent("apps.db").path
        }
        dbQueue = try DatabaseQueue(path: dbPath)
        try migrate()
    }

    // GRDB's `DatabaseMigrator` runs each named migration exactly once per DB.
    // SQLite tracks applied migrations in an internal table, so on every launch
    // we only execute newly added "vN" blocks.
    //
    // RULE: migrations are append-only. Never edit "v1"/"v2"/"v3" — users with
    // existing DBs won't re-run them. To change schema, add a new "vN+1" block.
    // See Database/CLAUDE.md.
    private func migrate() throws {
        try Self.migrator.migrate(dbQueue)
    }

    // Exposed so tests can stop at an older version (`migrate(_:upTo:)`) and
    // check what a later migration does to existing rows.
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "appEntry") { t in
                t.primaryKey("bundleIdentifier", .text)
                t.column("displayName", .text).notNull()
                t.column("appPath", .text).notNull()
                t.column("iconData", .blob)
            }
        }
        migrator.registerMigration("v2") { db in
            // SQLite only supports one ADD COLUMN per ALTER TABLE statement,
            // so two columns require two `alter(table:)` blocks.
            try db.alter(table: "appEntry") { t in
                t.add(column: "pageIndex", .integer)
            }
            try db.alter(table: "appEntry") { t in
                t.add(column: "orderIndex", .integer)
            }
        }
        migrator.registerMigration("v3") { db in
            try db.create(table: "folderEntry") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("pageIndex", .integer).notNull()
                t.column("orderIndex", .integer).notNull()
            }
            try db.alter(table: "appEntry") { t in
                // `.setNull` on delete: removing a folder nulls out the FK in its
                // apps rather than cascading and deleting the apps with it.
                t.add(column: "folderID", .text).references("folderEntry", onDelete: .setNull)
            }
            try db.alter(table: "appEntry") { t in
                t.add(column: "folderOrderIndex", .integer)
            }
        }
        migrator.registerMigration("v4") { db in
            try db.create(table: "appSetting") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }
            // A DB that already has apps in folders has done its system import.
            // Without folder apps the flag stays unset, so the recovery import in
            // `mergeNewApps` still runs once for DBs that never imported folders.
            let hasFolderApps = try AppEntry.filter(AppEntry.Columns.folderID != nil).fetchCount(db) > 0
            if hasFolderApps {
                try AppSetting(key: AppSetting.Key.folderImportDone.rawValue, value: "1").insert(db)
            }
        }
        migrator.registerMigration("v5") { db in
            try db.alter(table: "appEntry") { t in
                t.add(column: "isHidden", .boolean).notNull().defaults(to: false)
            }
        }
        return migrator
    }

    // `dbQueue.write { db in ... }` wraps the closure in a single transaction.
    // Batching writes inside one closure is dramatically faster than calling
    // `write` per row because each call commits to disk.
    func saveApps(_ apps: [AppEntry]) throws {
        try dbQueue.write { db in
            for app in apps {
                // `save(db)` is GRDB's upsert: INSERT or UPDATE keyed on PK.
                try app.save(db)
            }
        }
    }

    func fetchAllApps() throws -> [AppEntry] {
        try dbQueue.read { db in
            try AppEntry
                .order(
                    // `ascNullsLast` keeps NULL `pageIndex` rows at the bottom.
                    // Without it, SQLite would sort NULLs first.
                    AppEntry.Columns.pageIndex.ascNullsLast,
                    AppEntry.Columns.orderIndex.ascNullsLast,
                    // Locale-aware case-insensitive sort. Plain `<` would order
                    // "Évernote" after "Zoom" because of Unicode codepoints —
                    // this collation matches user expectations across locales.
                    AppEntry.Columns.displayName.collating(.localizedCaseInsensitiveCompare)
                )
                .fetchAll(db)
        }
    }

    // Used to decide whether to apply ordering from the system Launchpad DB
    // (first launch) or merge new apps into an existing layout (subsequent runs).
    // A hidden app has no page but counts: the first-launch import would
    // overwrite it as a visible app.
    func hasOrderingData() throws -> Bool {
        try dbQueue.read { db in
            let count = try AppEntry
                .filter(AppEntry.Columns.pageIndex != nil || AppEntry.Columns.isHidden == true)
                .fetchCount(db)
            return count > 0
        }
    }

    // Drop rows for apps that no longer exist on disk (uninstalled).
    // GRDB's expression DSL turns the Swift `!set.contains(column)` into a
    // `column NOT IN (?, ?, ...)` SQL clause.
    func deleteStale(validIdentifiers: Set<String>) throws {
        try dbQueue.write { db in
            try AppEntry.filter(!validIdentifiers.contains(AppEntry.Columns.bundleIdentifier)).deleteAll(db)
        }
    }

    func deleteApp(bundleIdentifier: String) throws {
        try dbQueue.write { db in
            _ = try AppEntry.deleteOne(db, key: bundleIdentifier)
        }
    }

    // MARK: - Folders

    func fetchAllFolders() throws -> [FolderEntry] {
        try dbQueue.read { db in
            try FolderEntry
                .order(
                    FolderEntry.Columns.pageIndex.asc,
                    FolderEntry.Columns.orderIndex.asc
                )
                .fetchAll(db)
        }
    }

    func saveFolders(_ folders: [FolderEntry]) throws {
        try dbQueue.write { db in
            for folder in folders {
                try folder.save(db)
            }
        }
    }

    func deleteStaleFolders(validIDs: Set<String>) throws {
        try dbQueue.write { db in
            try FolderEntry.filter(!validIDs.contains(FolderEntry.Columns.id)).deleteAll(db)
        }
    }

    // MARK: - Layout edits

    // Persists a whole layout after an edit, in one transaction: upserts every
    // folder and app passed in and deletes folders that are not in `folders`.
    // Rewriting everything (not just the rows the edit touched) also repairs a
    // layout that a concurrent rescan overwrote with rows read before the edit.
    func saveLayout(apps: [AppEntry], folders: [FolderEntry]) throws {
        try dbQueue.write { db in
            // Folders first: apps reference them through the folderID FK.
            for folder in folders {
                try folder.save(db)
            }
            for app in apps {
                try app.save(db)
            }
            let folderIDs = Set(folders.map(\.id))
            try FolderEntry.filter(!folderIDs.contains(FolderEntry.Columns.id)).deleteAll(db)
            try AppSetting(key: AppSetting.Key.folderImportDone.rawValue, value: "1").save(db)
        }
    }

    func renameFolder(id: String, title: String) throws {
        try dbQueue.write { db in
            _ = try FolderEntry
                .filter(FolderEntry.Columns.id == id)
                .updateAll(db, FolderEntry.Columns.title.set(to: title))
        }
    }

    // MARK: - Settings

    func setting(_ key: AppSetting.Key) throws -> String? {
        try dbQueue.read { db in
            try AppSetting.fetchOne(db, key: key.rawValue)?.value
        }
    }

    func setSetting(_ key: AppSetting.Key, _ value: String) throws {
        try dbQueue.write { db in
            try AppSetting(key: key.rawValue, value: value).save(db)
        }
    }
}
