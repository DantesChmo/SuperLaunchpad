import Foundation
import GRDB

final class AppDatabase {
    private let dbQueue: DatabaseQueue

    init(path: String? = nil) throws {
        let dbPath: String
        if let path {
            dbPath = path
        } else {
            let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("com.dantes.SuperLaunchpad", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            dbPath = folder.appendingPathComponent("apps.db").path
        }
        dbQueue = try DatabaseQueue(path: dbPath)
        try migrate()
    }

    private func migrate() throws {
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
                t.add(column: "folderID", .text).references("folderEntry", onDelete: .setNull)
            }
            try db.alter(table: "appEntry") { t in
                t.add(column: "folderOrderIndex", .integer)
            }
        }
        try migrator.migrate(dbQueue)
    }

    func saveApps(_ apps: [AppEntry]) throws {
        try dbQueue.write { db in
            for app in apps {
                try app.save(db)
            }
        }
    }

    func fetchAllApps() throws -> [AppEntry] {
        try dbQueue.read { db in
            try AppEntry
                .order(
                    AppEntry.Columns.pageIndex.ascNullsLast,
                    AppEntry.Columns.orderIndex.ascNullsLast,
                    AppEntry.Columns.displayName.collating(.localizedCaseInsensitiveCompare)
                )
                .fetchAll(db)
        }
    }

    func hasOrderingData() throws -> Bool {
        try dbQueue.read { db in
            let count = try AppEntry
                .filter(AppEntry.Columns.pageIndex != nil)
                .fetchCount(db)
            return count > 0
        }
    }

    func deleteStale(validIdentifiers: Set<String>) throws {
        try dbQueue.write { db in
            try AppEntry.filter(!validIdentifiers.contains(AppEntry.Columns.bundleIdentifier)).deleteAll(db)
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
}
