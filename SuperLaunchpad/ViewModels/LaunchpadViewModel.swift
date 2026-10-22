import AppKit
import SwiftUI

// The single source of truth for the launcher UI.
//
// `@Observable` (Swift 5.9+) replaces `ObservableObject` + `@Published`. Any
// stored property on this class is automatically tracked — SwiftUI views that
// read a property re-render when only that property changes.
//
// Threading: this class is meant to be mutated only from the main thread.
// Background work (file scan, DB I/O) runs in `Task.detached` and marshals
// state changes back via `await MainActor.run { ... }`.
@Observable
final class LaunchpadViewModel {
    var apps: [AppEntry] = []
    var folders: [FolderEntry] = []
    var currentPage: Int = 0
    var isVisible: Bool = false
    // Exists for future search support; intentionally not wired up.
    // See AGENTS.md > "Known limitations".
    var searchText: String = ""
    var openFolderID: String?

    // Derived view of `apps` + `folders` shaped for the UI:
    //   pages[i] = the items shown on page i, in display order.
    //
    // Recomputed on every access (cheap — ~200 items max). `@Observable`
    // re-runs this when the views that read `pages` re-render and the
    // dependencies have changed.
    var pages: [[LaunchpadItem]] {
        // 1. Apps shown directly on the grid (not nested in a folder).
        let topLevelApps = apps.filter { $0.folderID == nil }

        // 2. Bucket folder apps by their folder. `Dictionary(grouping:by:)`
        //    is the idiomatic Swift "group-by" — produces [folderID: [apps]].
        //    `$0.folderID!` is safe because we've already filtered to apps
        //    that have a non-nil folderID.
        let folderAppsGrouped = Dictionary(grouping: apps.filter { $0.folderID != nil }) { $0.folderID! }

        // 3. Wrap everything in the `LaunchpadItem` sum type so a page can
        //    contain a heterogeneous list of apps and folders.
        var items: [LaunchpadItem] = topLevelApps.map { .app($0) }

        for folder in folders {
            let folderApps = (folderAppsGrouped[folder.id] ?? []).sorted { a, b in
                (a.folderOrderIndex ?? Int.max) < (b.folderOrderIndex ?? Int.max)
            }
            items.append(.folder(folder, apps: folderApps))
        }

        // 4. Group items by page index, then sort each page by order index.
        //    `grouped[key]!` is safe — `key` came from `grouped.keys`.
        let grouped = Dictionary(grouping: items) { $0.pageIndex }
        return grouped.keys.sorted().map { key in
            grouped[key]!.sorted { $0.orderIndex < $1.orderIndex }
        }
    }

    // The currently expanded folder (or nil). Derived from `openFolderID` — we
    // store the ID, not the FolderEntry, so the displayed folder stays in sync
    // if the folder is reloaded with a fresh `apps`/`folders` snapshot.
    var openFolder: FolderEntry? {
        guard let id = openFolderID else { return nil }
        return folders.first { $0.id == id }
    }

    // Apps inside the open folder, sorted by `folderOrderIndex`.
    var openFolderApps: [AppEntry] {
        guard let id = openFolderID else { return [] }
        return apps.filter { $0.folderID == id }
            .sorted { ($0.folderOrderIndex ?? 0) < ($1.folderOrderIndex ?? 0) }
    }

    // Optional because the DB may fail to open (disk full, sandbox issue).
    // The launcher still works in-memory — just doesn't persist between launches.
    var database: AppDatabase?

    // Production init — owns its own AppDatabase.
    init() {
        do {
            database = try AppDatabase()
        } catch {
            print("Failed to initialize database: \(error)")
        }
    }

    // Test init — accept a pre-built (typically temp) database. See
    // `makeTempDB()` in the tests.
    init(database: AppDatabase?) {
        self.database = database
    }

    // Two-phase loading strategy:
    //   1. Synchronously paint cached apps from SQLite — gives an instant first
    //      frame so the launcher doesn't appear empty during the rescan.
    //   2. Asynchronously rescan `/Applications`, sync to disk, and update UI.
    //
    // Called on first launch and whenever `AppDirectoryWatcher` fires.
    func loadApps() {
        // Phase 1: cache repaint. `try?` + non-empty guard means we only
        // overwrite UI state if the read actually returned something.
        if let cached = try? database?.fetchAllApps(), !cached.isEmpty {
            apps = cached
        }
        if let cachedFolders = try? database?.fetchAllFolders(), !cachedFolders.isEmpty {
            folders = cachedFolders
        }

        // Phase 2: background rescan.
        // `Task.detached` runs outside the structured concurrency tree of the
        // caller — important here because `loadApps` is `@MainActor` (the
        // ViewModel is `@Observable`-isolated to main) and we explicitly want
        // file-system work OFF the main thread.
        Task.detached { [weak self] in
            // `AppEnumerator.enumerate()` is the slow part (icon extraction).
            // Runs on the detached task's background executor.
            let enumerated = AppEnumerator.enumerate()
            guard let self else { return }

            // First launch heuristic: if no app has a pageIndex yet, we treat
            // this as a fresh install and import ordering from macOS Launchpad.
            let hasOrdering = (try? self.database?.hasOrderingData()) ?? false
            let systemOrdering = SystemLaunchpadDB.readOrdering()

            let appsToSave: [AppEntry]
            let foldersToSave: [FolderEntry]

            if !hasOrdering {
                // Fresh DB → apply system Launchpad layout (or alphabetical
                // fallback if the system DB is empty).
                (appsToSave, foldersToSave) = self.applyOrdering(systemOrdering, to: enumerated)
            } else {
                // Existing DB → preserve user's existing positions, append
                // any newly installed apps at the end.
                (appsToSave, foldersToSave) = self.mergeNewApps(enumerated, systemOrdering: systemOrdering)
            }

            // Order matters: folders must exist before apps with FK references
            // to them are inserted. (FK constraint would otherwise fire.)
            try? self.database?.saveFolders(foldersToSave)
            try? self.database?.saveApps(appsToSave)

            // Drop rows for apps that were uninstalled since the last scan.
            let validIDs = Set(enumerated.map(\.bundleIdentifier))
            try? self.database?.deleteStale(validIdentifiers: validIDs)

            // After deleting stale apps, some folders may now be empty —
            // remove those too so they don't appear as ghost tiles.
            let folderIDsWithApps = Set(appsToSave.compactMap(\.folderID))
            let staleFolderIDs = Set(foldersToSave.map(\.id)).subtracting(folderIDsWithApps)
            if !staleFolderIDs.isEmpty {
                let validFolderIDs = Set(foldersToSave.map(\.id)).subtracting(staleFolderIDs)
                try? self.database?.deleteStaleFolders(validIDs: validFolderIDs)
            }

            // Re-read from DB so we get rows sorted by the canonical SQL
            // ordering (with locale-aware collation). Falls back to the
            // in-memory list if the read fails.
            let sortedApps = (try? self.database?.fetchAllApps()) ?? appsToSave
            let sortedFolders = (try? self.database?.fetchAllFolders()) ?? foldersToSave

            // `MainActor.run` is the bridge back to the main thread for UI
            // state updates. Mutating `@Observable` state off-main is a
            // compile-time error under strict concurrency.
            await MainActor.run {
                self.apps = sortedApps
                self.folders = sortedFolders
            }
        }
    }

    // First-launch ordering. Take the freshly enumerated apps and assign
    // positions based on the system Launchpad layout. Falls back to a
    // categorized layout when the system DB is empty.
    func applyOrdering(_ ordering: LaunchpadOrdering?, to apps: [AppEntry]) -> ([AppEntry], [FolderEntry]) {
        guard let ordering else {
            // No system DB (always the case on macOS 26 Tahoe) — group apps
            // by category, see `InitialLayout`.
            return InitialLayout.build(apps, categoryOf: AppCategory.of)
        }

        // The system DB identifies folders by an internal rowid we can't
        // reuse — generate fresh UUID strings and build a lookup from
        // bundleID → which folder + position inside it.
        var folderAppPositions: [String: (folderID: String, folderOrderIndex: Int)] = [:]
        var newFolders: [FolderEntry] = []

        for folderInfo in ordering.folders {
            let folderID = UUID().uuidString
            newFolders.append(FolderEntry(
                id: folderID,
                title: folderInfo.title,
                pageIndex: folderInfo.pageIndex,
                orderIndex: folderInfo.orderIndex
            ))
            for appRef in folderInfo.appBundleIDs {
                folderAppPositions[appRef.bundleID] = (folderID: folderID, folderOrderIndex: appRef.orderIndex)
            }
        }

        var ordered: [AppEntry] = []
        var unordered: [AppEntry] = []

        for app in apps {
            if let folderPos = folderAppPositions[app.bundleIdentifier] {
                // App belongs to a folder — set folder fields, clear page fields.
                // The "either page OR folder, never both" invariant lives here.
                var app = app
                app.folderID = folderPos.folderID
                app.folderOrderIndex = folderPos.folderOrderIndex
                app.pageIndex = nil
                app.orderIndex = nil
                ordered.append(app)
            } else if let pos = ordering.appPositions[app.bundleIdentifier] {
                // Top-level app with known position from the system DB.
                var app = app
                app.pageIndex = pos.pageIndex
                app.orderIndex = pos.orderIndex
                ordered.append(app)
            } else {
                unordered.append(app)
            }
        }

        // Drop apps that aren't tracked by the system Launchpad at all.
        // These are typically background-only apps the user shouldn't see
        // in a launcher (CLI installers, login helpers, etc.).
        _ = unordered

        return (ordered, newFolders)
    }

    // Subsequent-launch merge. Preserve every existing position; append
    // newly-installed apps at the end. Re-import folders from the system DB
    // only if we don't yet have any (recovery path).
    func mergeNewApps(_ enumerated: [AppEntry], systemOrdering: LaunchpadOrdering?) -> ([AppEntry], [FolderEntry]) {
        let existing = (try? database?.fetchAllApps()) ?? []
        // O(1) bundleID lookup for the merge loop below.
        // `uniqueKeysWithValues` traps on duplicate keys — safe here because
        // bundleIdentifier is the primary key.
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.bundleIdentifier, $0) })
        var existingFolders = (try? database?.fetchAllFolders()) ?? []

        // Recovery path: a DB where folders were dropped (e.g. older app version
        // never imported them) should re-import on the next run. We detect this
        // by checking: do we have folder rows AND apps actually linked to them?
        var folderAppPositions: [String: (folderID: String, folderOrderIndex: Int)] = [:]
        let hasFolderApps = existing.contains { $0.folderID != nil }
        if (existingFolders.isEmpty || !hasFolderApps), let ordering = systemOrdering {
            existingFolders = []
            for folderInfo in ordering.folders {
                let folderID = UUID().uuidString
                existingFolders.append(FolderEntry(
                    id: folderID,
                    title: folderInfo.title,
                    pageIndex: folderInfo.pageIndex,
                    orderIndex: folderInfo.orderIndex
                ))
                for appRef in folderInfo.appBundleIDs {
                    folderAppPositions[appRef.bundleID] = (folderID: folderID, folderOrderIndex: appRef.orderIndex)
                }
            }
        }

        var result: [AppEntry] = []
        var newApps: [AppEntry] = []

        // Walk the freshly-enumerated apps. For each one decide: update an
        // existing row (keep position) or queue it as a brand-new app.
        for app in enumerated {
            if var existingApp = existingByID[app.bundleIdentifier] {
                // Refresh mutable metadata (name and icon can change between
                // updates) but preserve user-positioning fields.
                existingApp.displayName = app.displayName
                existingApp.appPath = app.appPath
                existingApp.iconData = app.iconData
                // If folders were just re-imported, retroactively attach
                // this existing app to its folder.
                if let folderPos = folderAppPositions[app.bundleIdentifier] {
                    existingApp.folderID = folderPos.folderID
                    existingApp.folderOrderIndex = folderPos.folderOrderIndex
                    existingApp.pageIndex = nil
                    existingApp.orderIndex = nil
                }
                result.append(existingApp)
            } else {
                newApps.append(app)
            }
        }

        // Find the highest page/slot currently occupied — new apps will be
        // appended starting at lastPage + 1 slot. We consider both top-level
        // apps and folders since both occupy slots on the main grid.
        let topLevel = result.filter { $0.folderID == nil }
        let lastPage = max(
            topLevel.compactMap(\.pageIndex).max() ?? 0,
            existingFolders.map(\.pageIndex).max() ?? 0
        )
        // `-1` so `lastOrder + 1 = 0` when the last page is empty.
        let lastOrder = max(
            topLevel.filter { $0.pageIndex == lastPage }.compactMap(\.orderIndex).max() ?? -1,
            existingFolders.filter { $0.pageIndex == lastPage }.map(\.orderIndex).max() ?? -1
        )

        var nextOrder = lastOrder + 1
        var currentPage = lastPage

        for var app in newApps {
            // Priority 1: this new app belongs to a folder according to the
            // (possibly just-imported) system DB layout.
            if let folderPos = folderAppPositions[app.bundleIdentifier] {
                app.folderID = folderPos.folderID
                app.folderOrderIndex = folderPos.folderOrderIndex
                app.pageIndex = nil
                app.orderIndex = nil
            } else if let pos = systemOrdering?.appPositions[app.bundleIdentifier] {
                // Priority 2: the system DB knows where this app should go.
                app.pageIndex = pos.pageIndex
                app.orderIndex = pos.orderIndex
            } else {
                // Priority 3: append at the next free slot, paging over when
                // the current page fills up.
                if nextOrder >= Grid.appsPerPage {
                    currentPage += 1
                    nextOrder = 0
                }
                app.pageIndex = currentPage
                app.orderIndex = nextOrder
                nextOrder += 1
            }
            result.append(app)
        }

        return (result, existingFolders)
    }

    // `NSWorkspace.open(_:)` launches the app at the given URL via Launch
    // Services — the same mechanism Finder uses on double-click. We hide
    // the launcher straight after so the user lands on the launched app.
    func launchApp(_ app: AppEntry) {
        let url = URL(fileURLWithPath: app.appPath)
        NSWorkspace.shared.open(url)
        hide()
    }

    func show() {
        // Always reset to the first page on show — matches macOS Launchpad UX.
        currentPage = 0
        isVisible = true
    }

    func hide() {
        // Also close any open folder so the next show is in a clean state.
        openFolderID = nil
        isVisible = false
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func openFolder(_ folder: FolderEntry) {
        openFolderID = folder.id
    }

    func closeFolder() {
        openFolderID = nil
    }
}
