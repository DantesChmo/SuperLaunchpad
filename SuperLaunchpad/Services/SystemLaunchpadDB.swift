import Foundation
import GRDB

struct FolderInfo {
    let title: String
    let pageIndex: Int
    let orderIndex: Int
    let appBundleIDs: [(bundleID: String, orderIndex: Int)]
}

struct LaunchpadOrdering {
    let appPositions: [String: (pageIndex: Int, orderIndex: Int)]
    let folders: [FolderInfo]
}

final class SystemLaunchpadDB {

    static func readOrdering() -> LaunchpadOrdering? {
        guard let dbPath = systemDBPath(),
              FileManager.default.fileExists(atPath: dbPath) else {
            return nil
        }

        do {
            var config = Configuration()
            config.readonly = true
            let dbQueue = try DatabaseQueue(path: dbPath, configuration: config)

            return try dbQueue.read { db in
                // Find the Launchpad root (type=1, parent_id=0)
                guard let rootRow = try Row.fetchOne(db, sql: """
                    SELECT rowid FROM items WHERE type = 1 AND parent_id = 0 ORDER BY rowid LIMIT 1
                """) else {
                    return nil
                }
                let rootID: Int64 = rootRow["rowid"]

                // Get top-level pages under root
                let pageRows = try Row.fetchAll(db, sql: """
                    SELECT rowid, ordering FROM items
                    WHERE type = 3 AND parent_id = ?
                    ORDER BY ordering ASC
                """, arguments: [rootID])

                // Build page map, skipping empty pages
                var pageRowIDs: [Int64] = []
                for row in pageRows {
                    let rowid: Int64 = row["rowid"]
                    let hasItems = try Row.fetchOne(db, sql: """
                        SELECT 1 FROM items WHERE parent_id = ? AND type IN (2, 4, 5) LIMIT 1
                    """, arguments: [rowid]) != nil
                    if hasItems {
                        pageRowIDs.append(rowid)
                    }
                }

                guard !pageRowIDs.isEmpty else { return nil }

                var pageIndexMap: [Int64: Int] = [:]
                for (index, rowid) in pageRowIDs.enumerated() {
                    pageIndexMap[rowid] = index
                }

                // Read folders (type=2) with titles from groups table
                // Hierarchy: Root → Page → Folder → FolderPage → App
                let folderRows = try Row.fetchAll(db, sql: """
                    SELECT i.rowid, i.parent_id, i.ordering, g.title
                    FROM items i
                    LEFT JOIN groups g ON g.item_id = i.rowid
                    WHERE i.type = 2
                """)

                struct FolderMeta {
                    let rowid: Int64
                    let title: String
                    let pageIndex: Int
                    let orderIndex: Int
                }

                var folderMetas: [FolderMeta] = []
                var folderRowIDs: Set<Int64> = []

                for row in folderRows {
                    let rowid: Int64 = row["rowid"]
                    let parentID: Int64 = row["parent_id"]
                    let ordering: Int = row["ordering"]
                    let title: String = row["title"] ?? "Folder"

                    guard let pageIdx = pageIndexMap[parentID] else { continue }
                    folderMetas.append(FolderMeta(rowid: rowid, title: title, pageIndex: pageIdx, orderIndex: ordering))
                    folderRowIDs.insert(rowid)
                }

                // Get folder-pages (type=3 children of folders)
                // Map folder-page rowid → folder rowid
                var folderPageToFolder: [Int64: Int64] = [:]
                if !folderRowIDs.isEmpty {
                    let placeholders = folderRowIDs.map { _ in "?" }.joined(separator: ",")
                    let folderPageRows = try Row.fetchAll(db, sql: """
                        SELECT rowid, parent_id FROM items
                        WHERE type = 3 AND parent_id IN (\(placeholders))
                    """, arguments: StatementArguments(folderRowIDs.sorted()))
                    for row in folderPageRows {
                        let fpRowid: Int64 = row["rowid"]
                        let fpParent: Int64 = row["parent_id"]
                        folderPageToFolder[fpRowid] = fpParent
                    }
                }

                // Get all apps with parent info
                let appRows = try Row.fetchAll(db, sql: """
                    SELECT
                        a.bundleid,
                        i.parent_id,
                        i.ordering AS app_ordering
                    FROM apps a
                    JOIN items i ON a.item_id = i.rowid
                    WHERE i.type IN (4, 5)
                """)

                var positions: [String: (pageIndex: Int, orderIndex: Int)] = [:]
                // Collect folder apps: folder rowid → [(bundleID, orderIndex)]
                var folderAppsMap: [Int64: [(bundleID: String, orderIndex: Int)]] = [:]

                for row in appRows {
                    guard let bundleID: String = row["bundleid"] else { continue }
                    let parentID: Int64 = row["parent_id"]
                    let appOrdering: Int = row["app_ordering"]

                    if let folderRowid = folderPageToFolder[parentID] {
                        // App is inside a folder (parent is a folder-page)
                        folderAppsMap[folderRowid, default: []].append((bundleID: bundleID, orderIndex: appOrdering))
                    } else if folderRowIDs.contains(parentID) {
                        // App is directly under a folder (no intermediate folder-page)
                        folderAppsMap[parentID, default: []].append((bundleID: bundleID, orderIndex: appOrdering))
                    } else if pageIndexMap[parentID] != nil {
                        // App is directly on a top-level page
                        positions[bundleID] = (pageIndex: pageIndexMap[parentID]!, orderIndex: appOrdering)
                    }
                }

                // Build FolderInfo array
                let folders: [FolderInfo] = folderMetas.map { meta in
                    let apps = (folderAppsMap[meta.rowid] ?? []).sorted { $0.orderIndex < $1.orderIndex }
                    return FolderInfo(
                        title: meta.title,
                        pageIndex: meta.pageIndex,
                        orderIndex: meta.orderIndex,
                        appBundleIDs: apps
                    )
                }

                guard !positions.isEmpty || !folders.isEmpty else { return nil }
                return LaunchpadOrdering(appPositions: positions, folders: folders)
            }
        } catch {
            print("Failed to read system Launchpad DB: \(error)")
            return nil
        }
    }

    private static func systemDBPath() -> String? {
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        let result = confstr(_CS_DARWIN_USER_DIR, &buf, buf.count)
        guard result > 0 else { return nil }
        let darwinUserDir = String(cString: buf)
        return darwinUserDir + "com.apple.dock.launchpad/db/db"
    }
}
