import Foundation
import GRDB

// Imports ordering and folder structure from the system Launchpad's own SQLite
// DB on first launch. We never write to it — Apple's launchd-managed Dock owns
// that file. We open it `readonly` to make accidental writes impossible.
//
// Schema (reverse-engineered, undocumented by Apple):
//   `items` — every node in the launcher tree (root, pages, folders, apps).
//             Columns we care about: rowid (PK), parent_id, ordering, type.
//   `apps`  — maps `items.rowid` (via `item_id`) to a `bundleid`.
//   `groups` — folder metadata; the human-readable folder title lives here.
//
// `type` values:
//   1 = Launchpad root
//   2 = folder
//   3 = page (top-level page OR a page inside a folder)
//   4, 5 = app (different categories: regular vs. system, both treated equally)
//
// Hierarchy:  Root → Page → [App | Folder]
//                                   └─ FolderPage → App
//
// Returns `nil` if the system DB is missing or empty — caller falls back to
// alphabetical ordering (see `LaunchpadViewModel.applyOrdering`).

// A folder reconstructed from the system DB. `appBundleIDs` is the list of
// member apps in their original order.
struct FolderInfo {
    let title: String
    let pageIndex: Int
    let orderIndex: Int
    let appBundleIDs: [(bundleID: String, orderIndex: Int)]
}

// Everything we extracted from the system Launchpad DB on first launch.
struct LaunchpadOrdering {
    // bundleID → (pageIndex, orderIndex) for top-level apps only.
    let appPositions: [String: (pageIndex: Int, orderIndex: Int)]
    let folders: [FolderInfo]
}

final class SystemLaunchpadDB {

    static func readOrdering(dbPath overridePath: String? = nil) -> LaunchpadOrdering? {
        guard let dbPath = overridePath ?? systemDBPath(),
              FileManager.default.fileExists(atPath: dbPath) else {
            return nil
        }

        do {
            // `readonly = true` opens the SQLite file with the same flag at the
            // libsqlite3 level — guarantees we cannot corrupt Apple's DB.
            var config = Configuration()
            config.readonly = true
            let dbQueue = try DatabaseQueue(path: dbPath, configuration: config)

            return try dbQueue.read { db in
                // Find the Launchpad root (type=1, parent_id=0).
                // There can be multiple type=1 rows historically; we take the
                // first by rowid — that's the live Launchpad tree.
                guard let rootRow = try Row.fetchOne(db, sql: """
                    SELECT rowid FROM items WHERE type = 1 AND parent_id = 0 ORDER BY rowid LIMIT 1
                """) else {
                    return nil
                }
                let rootID: Int64 = rootRow["rowid"]

                // Top-level pages (type=3) that live directly under the root.
                let pageRows = try Row.fetchAll(db, sql: """
                    SELECT rowid, ordering FROM items
                    WHERE type = 3 AND parent_id = ?
                    ORDER BY ordering ASC
                """, arguments: [rootID])

                // Filter out pages that no longer contain any items. macOS
                // keeps empty page rows around after uninstalls; including
                // them would produce blank pages in our launcher.
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

                // Map the system DB's arbitrary `rowid` values to our dense
                // 0-based page indices.
                var pageIndexMap: [Int64: Int] = [:]
                for (index, rowid) in pageRowIDs.enumerated() {
                    pageIndexMap[rowid] = index
                }

                // Read folders (type=2) with titles from groups table.
                // LEFT JOIN: a folder row may legitimately have no entry in
                // `groups` (untitled folder) — we fall back to "Folder" below.
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

                // Find folder-pages (type=3 children of folders) and build a
                // reverse map: folder-page rowid → folder rowid.
                // Folders are paginated internally — a folder with 15 apps has
                // 2 folder-pages. Apps sit under these folder-pages, so we
                // need this map to attribute an app back to its folder.
                //
                // Why dynamic placeholders instead of one IN-literal? SQLite
                // bound parameters are the only safe way to pass a variable-
                // length list; we generate "?, ?, ?, …" then provide the
                // values via `StatementArguments`.
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

                // Each app row needs to be classified by what its `parent_id`
                // is in our maps:
                //   1. folder-page → app belongs to that folder-page's folder
                //   2. folder      → app sits directly under the folder
                //                    (some apps skip the folder-page level)
                //   3. top-level page → free-standing app on the main grid
                for row in appRows {
                    guard let bundleID: String = row["bundleid"] else { continue }
                    let parentID: Int64 = row["parent_id"]
                    let appOrdering: Int = row["app_ordering"]

                    if let folderRowid = folderPageToFolder[parentID] {
                        folderAppsMap[folderRowid, default: []].append((bundleID: bundleID, orderIndex: appOrdering))
                    } else if folderRowIDs.contains(parentID) {
                        folderAppsMap[parentID, default: []].append((bundleID: bundleID, orderIndex: appOrdering))
                    } else if pageIndexMap[parentID] != nil {
                        // Force-unwrap is safe: we just checked the key exists.
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

    // Resolves the per-user Darwin temp/cache dir — something like
    //   /private/var/folders/xx/yyy/0/
    // The system Launchpad keeps its SQLite DB at
    //   <darwinUserDir>com.apple.dock.launchpad/db/db
    //
    // We can't hard-code this path: the `xx/yyy` segments are random per user.
    // `confstr(_CS_DARWIN_USER_DIR, ...)` is the documented C API for this —
    // there is no first-party Swift equivalent.
    private static func systemDBPath() -> String? {
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        let result = confstr(_CS_DARWIN_USER_DIR, &buf, buf.count)
        guard result > 0 else { return nil }
        let darwinUserDir = String(cString: buf)
        return darwinUserDir + "com.apple.dock.launchpad/db/db"
    }
}
