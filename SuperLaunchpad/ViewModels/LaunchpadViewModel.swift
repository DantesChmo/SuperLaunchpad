import AppKit
import SwiftUI

// The single source of truth for the launcher UI.
//
// `@Observable` (Swift 5.9+) replaces `ObservableObject` + `@Published`. Any
// stored property on this class is automatically tracked — SwiftUI views that
// read a property re-render when only that property changes.
//
// Threading: isolated to the main actor. Background work (file scan, DB I/O)
// runs in `Task.detached` and marshals state changes back via
// `await MainActor.run { ... }`.
@MainActor
@Observable
final class LaunchpadViewModel {
    // Every write to `apps` or `folders` rebuilds `pages` and `searchResults`,
    // unless it happens inside `updateContents { ... }`, which rebuilds once
    // at the end.
    var apps: [AppEntry] = [] {
        didSet { rebuildPagesUnlessBatching() }
    }
    var folders: [FolderEntry] = [] {
        didSet { rebuildPagesUnlessBatching() }
    }
    var currentPage: Int = 0
    var isVisible: Bool = false
    // Bound to the search field. A non-empty query replaces the paged grid
    // with `searchResults`; typing closes an open folder.
    var searchText: String = "" {
        didSet {
            guard searchText != oldValue else { return }
            let searching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            // Assigned only on change, so views reading it are not
            // re-rendered on every keystroke.
            if isSearching != searching { isSearching = searching }
            if isSearching {
                openFolderID = nil
                exitEditMode()
            }
            rebuildSearchResults()
            selectedResultIndex = 0
        }
    }
    var openFolderID: String?
    // Edges of the launcher's screen covered by the Dock; the content is laid
    // out beside them. Set by `LaunchpadPanel` when it is placed on a screen.
    var dockInsets = DockInsets.zero

    // Search results for `searchText` (see `AppSearch`), capped at one page.
    // Stored for the same reason as `pages`.
    private(set) var searchResults: [AppEntry] = []
    private(set) var selectedResultIndex = 0
    // Bumped on every `show()`; the search field takes focus when it changes,
    // so typing starts a query straight away.
    private(set) var searchFocusRequest = 0

    // True while the query has non-whitespace text.
    private(set) var isSearching = false

    var selectedResult: AppEntry? {
        searchResults.indices.contains(selectedResultIndex) ? searchResults[selectedResultIndex] : nil
    }

    // Derived view of `apps` + `folders` shaped for the UI:
    //   pages[i] = the items shown on page i, in display order.
    //
    // Stored, not computed: views read `pages` several times per render, and
    // rebuilding the grouping on each read made every re-render mid-swipe hand
    // a brand-new array to every page view. It is rebuilt only when `apps` or
    // `folders` change. Being a stored property of an `@Observable` class, it
    // is still tracked, so views reading it re-render when it is reassigned.
    private(set) var pages: [[LaunchpadItem]] = []

    // True while `updateContents` is assigning `apps` and `folders`, so the
    // `didSet`s skip their rebuild and `updateContents` does one at the end.
    // Ignored by observation: no view should re-render because of it.
    @ObservationIgnored private var isBatchingContentUpdates = false

    // Assign `apps` and/or `folders` together with a single `pages` rebuild.
    private func updateContents(_ body: () -> Void) {
        isBatchingContentUpdates = true
        body()
        isBatchingContentUpdates = false
        rebuildPages()
        rebuildSearchResults()
    }

    private func rebuildPagesUnlessBatching() {
        guard !isBatchingContentUpdates else { return }
        rebuildPages()
        rebuildSearchResults()
    }

    private func rebuildPages() {
        // 1. Split apps into those shown directly on the grid and those nested
        //    in a folder, bucketed by folder ID. Hidden apps are in neither.
        var topLevelApps: [AppEntry] = []
        var folderAppsGrouped: [String: [AppEntry]] = [:]
        for app in apps where !app.isHidden {
            if let folderID = app.folderID {
                folderAppsGrouped[folderID, default: []].append(app)
            } else {
                topLevelApps.append(app)
            }
        }

        // 2. Wrap everything in the `LaunchpadItem` sum type so a page can
        //    contain a heterogeneous list of apps and folders.
        var items: [LaunchpadItem] = topLevelApps.map { .app($0) }

        for folder in folders {
            let folderApps = (folderAppsGrouped[folder.id] ?? []).sorted { a, b in
                (a.folderOrderIndex ?? Int.max) < (b.folderOrderIndex ?? Int.max)
            }
            items.append(.folder(folder, apps: folderApps))
        }

        // 3. Group items by page index, then sort each page by order index.
        let grouped = Dictionary(grouping: items) { $0.pageIndex }
        pages = grouped
            .sorted { $0.key < $1.key }
            .map { $0.value.sorted { $0.orderIndex < $1.orderIndex } }
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
        return folderApps(id)
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
    // Called on first launch; `AppDirectoryWatcher` goes through
    // `scheduleRescan()` instead.
    func loadApps() {
        // Phase 1: cache repaint. `try?` + non-empty guard means we only
        // overwrite UI state if the read actually returned something.
        updateContents {
            if let cached = try? database?.fetchAllApps(), !cached.isEmpty {
                apps = cached
            }
            if let cachedFolders = try? database?.fetchAllFolders(), !cachedFolders.isEmpty {
                folders = cachedFolders
            }
        }
        // Decode the cached icons off the main thread before the first swipe
        // reaches them; `IconCache` would otherwise decode each one on first draw.
        let cachedApps = apps
        Task { await IconCache.shared.prewarm(cachedApps) }

        // Phase 2: background rescan.
        requestRescan()
    }

    // MARK: - Rescan

    // At most one rescan runs at a time; see `RescanGate`.
    @ObservationIgnored private var rescanGate = RescanGate()
    @ObservationIgnored private var pendingRescan: Task<Void, Never>?

    // Directory events arrive in bursts (an install touches the folder several
    // times). Each call restarts the wait, so a burst ends in a single rescan.
    func scheduleRescan() {
        pendingRescan?.cancel()
        pendingRescan = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Rescan.debounceInterval))
            guard !Task.isCancelled else { return }
            self?.requestRescan()
        }
    }

    private func requestRescan() {
        guard rescanGate.request() else { return }
        startRescan()
    }

    private func startRescan() {
        // Captured once: the detached task must not read main-actor state.
        let database = database
        let startRevision = layoutRevision
        let newAppPlacement = Preferences().newAppPlacement

        // `Task.detached` runs outside the structured concurrency tree of the
        // caller — important here because `loadApps` is `@MainActor` and we
        // explicitly want file-system work OFF the main thread.
        Task.detached { [weak self] in
            // `AppEnumerator.enumerate()` is the slow part (icon extraction).
            // Runs on the detached task's background executor.
            let enumerated = AppEnumerator.enumerate()
            guard let self else { return }

            let (sortedApps, sortedFolders) = LaunchpadViewModel.syncScan(
                enumerated,
                systemOrdering: SystemLaunchpadDB.readOrdering(),
                placement: newAppPlacement,
                database: database
            )

            // `MainActor.run` is the bridge back to the main thread for UI
            // state updates. Mutating `@Observable` state off-main is a
            // compile-time error under strict concurrency.
            await MainActor.run {
                self.receiveRescanResult(apps: sortedApps, folders: sortedFolders, startRevision: startRevision)
                if self.rescanGate.finish() {
                    self.startRescan()
                }
            }
        }
    }

    // Writes one scan's result to the DB: the first-launch layout for an empty
    // DB, otherwise the existing layout plus new apps minus uninstalled ones.
    // Returns the rows as stored.
    //
    // `nonisolated static`: runs inside the detached rescan.
    nonisolated static func syncScan(
        _ enumerated: [AppEntry],
        systemOrdering: LaunchpadOrdering?,
        placement: NewAppPlacement,
        database: AppDatabase?
    ) -> (apps: [AppEntry], folders: [FolderEntry]) {
        // First launch heuristic: if no app has a pageIndex yet, we treat
        // this as a fresh install and import ordering from macOS Launchpad.
        let hasOrdering = (try? database?.hasOrderingData()) ?? false

        let appsToSave: [AppEntry]
        let foldersToSave: [FolderEntry]

        if !hasOrdering {
            // Fresh DB → apply system Launchpad layout (or alphabetical
            // fallback if the system DB is empty).
            (appsToSave, foldersToSave) = LaunchpadViewModel.applyOrdering(systemOrdering, to: enumerated)
        } else {
            // Existing DB → preserve user's existing positions, append
            // any newly installed apps at the end.
            let folderImportDone = (try? database?.setting(.folderImportDone)) != nil
            let tracksNewApps = (try? database?.setting(.newAppTracking)) != nil
            (appsToSave, foldersToSave) = LaunchpadViewModel.mergeNewApps(
                enumerated,
                existingApps: (try? database?.fetchAllApps()) ?? [],
                existingFolders: (try? database?.fetchAllFolders()) ?? [],
                systemOrdering: systemOrdering,
                folderImportDone: folderImportDone,
                markNew: tracksNewApps,
                placement: placement
            )
        }

        // Order matters: folders must exist before apps with FK references
        // to them are inserted. (FK constraint would otherwise fire.)
        try? database?.saveFolders(foldersToSave)
        try? database?.saveApps(appsToSave)

        // With a system layout available, both paths above have imported
        // its folders by now; never import them again.
        if systemOrdering != nil {
            try? database?.setSetting(.folderImportDone, "1")
        }

        // Every app on disk has a row now, unless the first import skipped
        // apps the system layout doesn't know: from the next rescan on, an
        // app without a row was just installed.
        if appsToSave.count == enumerated.count {
            try? database?.setSetting(.newAppTracking, "1")
        }

        // Drop rows for apps that were uninstalled since the last scan.
        let validIDs = Set(enumerated.map(\.bundleIdentifier))
        try? database?.deleteStale(validIdentifiers: validIDs)

        // After deleting stale apps, some folders may now be empty —
        // remove those too so they don't appear as ghost tiles.
        let folderIDsWithApps = Set(appsToSave.compactMap(\.folderID))
        let staleFolderIDs = Set(foldersToSave.map(\.id)).subtracting(folderIDsWithApps)
        if !staleFolderIDs.isEmpty {
            let validFolderIDs = Set(foldersToSave.map(\.id)).subtracting(staleFolderIDs)
            try? database?.deleteStaleFolders(validIDs: validFolderIDs)
        }

        // Re-read from DB so we get rows sorted by the canonical SQL
        // ordering (with locale-aware collation). Falls back to the
        // in-memory list if the read fails.
        let sortedApps = (try? database?.fetchAllApps()) ?? appsToSave
        let sortedFolders = (try? database?.fetchAllFolders()) ?? foldersToSave
        return (sortedApps, sortedFolders)
    }

    // A rescan that finishes mid-drag would swap `pages` under the dragged
    // icon; its result is parked until the drag ends.
    func receiveRescanResult(apps scannedApps: [AppEntry], folders scannedFolders: [FolderEntry], startRevision: Int) {
        guard !isDragSessionActive else {
            parkedRescan = ParkedRescan(apps: scannedApps, folders: scannedFolders, startRevision: startRevision)
            return
        }
        if layoutRevision == startRevision {
            updateContents {
                apps = scannedApps
                folders = scannedFolders
            }
            // Only icons that changed in the rescan are decoded again.
            Task { await IconCache.shared.prewarm(scannedApps) }
        } else {
            // The user edited the layout while this scan ran on rows read
            // before the edit, and the scan's writes may have undone it. Write
            // the edited layout back and scan again so new apps still arrive.
            try? database?.saveLayout(apps: apps, folders: folders)
            if rescanGate.request() {
                startRescan()
            }
        }
    }

    // MARK: - Ordering

    // First-launch ordering. Take the freshly enumerated apps and assign
    // positions based on the system Launchpad layout. Falls back to a
    // categorized layout when the system DB is empty.
    //
    // `nonisolated static`: runs inside the detached rescan, so it must not
    // touch main-actor state.
    nonisolated static func applyOrdering(_ ordering: LaunchpadOrdering?, to apps: [AppEntry]) -> ([AppEntry], [FolderEntry]) {
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
    // only if we don't yet have any and never imported them (recovery path).
    //
    // `nonisolated static` like `applyOrdering`; the caller passes in the rows
    // currently in the DB and the `folderImportDone` setting.
    //
    // With `markNew` the new apps are marked `isNew` and go where `placement`
    // says; `categoryTitles` names the folders that match an app's category.
    nonisolated static func mergeNewApps(
        _ enumerated: [AppEntry],
        existingApps existing: [AppEntry],
        existingFolders: [FolderEntry],
        systemOrdering: LaunchpadOrdering?,
        folderImportDone: Bool,
        markNew: Bool = false,
        placement: NewAppPlacement = .end,
        categoryTitles: (AppEntry) -> [String] = NewAppPlacement.categoryFolderTitles
    ) -> ([AppEntry], [FolderEntry]) {
        // O(1) bundleID lookup for the merge loop below.
        // `uniqueKeysWithValues` traps on duplicate keys — safe here because
        // bundleIdentifier is the primary key.
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.bundleIdentifier, $0) })
        var existingFolders = existingFolders

        // Recovery path: a DB where folders were dropped (e.g. older app version
        // never imported them) should re-import on the next run. We detect this
        // by checking: do we have folder rows AND apps actually linked to them?
        // Once the import happened (or the user edited the layout) an empty
        // folder list is the user's choice: dissolving the last folder must not
        // bring the system folders back.
        var folderAppPositions: [String: (folderID: String, folderOrderIndex: Int)] = [:]
        let hasFolderApps = existing.contains { $0.folderID != nil }
        if !folderImportDone, existingFolders.isEmpty || !hasFolderApps, let ordering = systemOrdering {
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
                // this existing app to its folder, unless the user hid it.
                if !existingApp.isHidden, let folderPos = folderAppPositions[app.bundleIdentifier] {
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

        // The next free slot, paging over when the current page fills up.
        func takeNextSlot() -> (page: Int, order: Int) {
            if nextOrder >= Grid.appsPerPage {
                currentPage += 1
                nextOrder = 0
            }
            defer { nextOrder += 1 }
            return (currentPage, nextOrder)
        }

        // The folder `placement` puts a new app into, if any. The "New"
        // folder is made in the next free slot the first time it is needed.
        func placementFolderID(for app: AppEntry) -> String? {
            switch placement {
            case .end:
                return nil
            case .categoryFolder:
                let titles = categoryTitles(app)
                return existingFolders.first { folder in
                    titles.contains { $0.localizedCaseInsensitiveCompare(folder.title) == .orderedSame }
                }?.id
            case .newFolder:
                let title = NewAppPlacement.newFolderTitle
                if let folder = existingFolders.first(where: { $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame }) {
                    return folder.id
                }
                let slot = takeNextSlot()
                let folder = FolderEntry(id: UUID().uuidString, title: title, pageIndex: slot.page, orderIndex: slot.order)
                existingFolders.append(folder)
                return folder.id
            }
        }

        for var app in newApps {
            app.isNew = markNew
            // Priority 1: this new app belongs to a folder according to the
            // (possibly just-imported) system DB layout.
            if let folderPos = folderAppPositions[app.bundleIdentifier] {
                app.folderID = folderPos.folderID
                app.folderOrderIndex = folderPos.folderOrderIndex
                app.pageIndex = nil
                app.orderIndex = nil
            } else if markNew, let folderID = placementFolderID(for: app) {
                // Priority 2: the user's choice in Settings, after the
                // folder's last app.
                let lastIndex = result.filter { $0.folderID == folderID }.compactMap(\.folderOrderIndex).max() ?? -1
                app.folderID = folderID
                app.folderOrderIndex = lastIndex + 1
                app.pageIndex = nil
                app.orderIndex = nil
            } else if let pos = systemOrdering?.appPositions[app.bundleIdentifier] {
                // Priority 3: the system DB knows where this app should go.
                app.pageIndex = pos.pageIndex
                app.orderIndex = pos.orderIndex
            } else {
                // Priority 4: append at the next free slot.
                let slot = takeNextSlot()
                app.pageIndex = slot.page
                app.orderIndex = slot.order
            }
            result.append(app)
        }

        return (result, existingFolders)
    }

    // Launches the app (see `AppOpener`) and hides the launcher straight
    // after so the user lands on the launched app.
    //
    // Does nothing in edit mode, where a click on an app only selects it for
    // dragging. Returns whether the app was launched.
    @discardableResult
    func launchApp(_ app: AppEntry) -> Bool {
        guard !isEditing else { return false }
        opener.open(app.appPath, true)
        clearNew(app.bundleIdentifier)
        hide()
        return true
    }

    // The blue dot goes once the app is opened from the launcher.
    func clearNew(_ appID: String) {
        guard let index = apps.firstIndex(where: { $0.bundleIdentifier == appID }), apps[index].isNew else { return }
        apps[index].isNew = false
        // A rescan running now read the flag before it was cleared.
        layoutRevision += 1
        try? database?.clearNew(bundleIdentifier: appID)
    }

    func show() {
        // Always reset to the first page on show — matches macOS Launchpad UX.
        currentPage = 0
        isVisible = true
        isOptionHeld = false
        searchFocusRequest += 1
    }

    func hide() {
        // Also close any open folder and clear the query so the next show is
        // in a clean state.
        openFolderID = nil
        searchText = ""
        pendingRemoval = nil
        exitEditMode()
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

    // MARK: - Editing
    //
    // Each edit runs one `GridLayout` operation on the current layout, writes
    // the normalized result back into `apps`/`folders` and persists it in a
    // single DB transaction. Every method returns false (and changes nothing)
    // when the edit is not possible.

    nonisolated static let defaultFolderTitle = "Folder"

    // Bumped by every edit; a rescan that started before an edit must not
    // overwrite it (see `startRescan`).
    @ObservationIgnored private var layoutRevision = 0

    @discardableResult
    func moveItem(_ item: GridLayout.Item, toPage page: Int, slot: Int) -> Bool {
        applyEdit { $0.move(item, toPage: page, slot: slot) }
    }

    // Returns the ID of the new folder, or nil when the merge is not possible.
    @discardableResult
    func mergeApps(_ appID: String, onto targetAppID: String, title: String = defaultFolderTitle) -> String? {
        let folderID = UUID().uuidString
        let merged = applyEdit { $0.merge(appID, onto: targetAppID, folderID: folderID, title: title) }
        return merged ? folderID : nil
    }

    @discardableResult
    func addApp(_ appID: String, toFolder folderID: String, at index: Int? = nil) -> Bool {
        applyEdit { $0.add(appID, toFolder: folderID, at: index) }
    }

    // A folder left without apps is dissolved.
    @discardableResult
    func removeApp(_ appID: String, fromFolder folderID: String, toPage page: Int, slot: Int) -> Bool {
        applyEdit { $0.remove(appID, fromFolder: folderID, toPage: page, slot: slot) }
    }

    // Drop app `appID` on app `targetAppID`: a new folder titled after the
    // target app's category. Returns the folder's ID.
    @discardableResult
    func createFolder(dropping appID: String, onto targetAppID: String) -> String? {
        guard let target = apps.first(where: { $0.bundleIdentifier == targetAppID }) else { return nil }
        let title = AppCategoryTitle.folderTitle(forAppAt: target.appPath, fallback: Self.defaultFolderTitle)
        return mergeApps(appID, onto: targetAppID, title: title)
    }

    // Where a finished drag left the item: page + slot on the grid, or the
    // index in the folder it was reordered within. `createdFolderID` is set
    // when the drop made a new folder (opened in rename mode by the view).
    struct DropOutcome: Equatable {
        var page: Int
        var slot: Int
        var createdFolderID: String?
    }

    // Persists a drag: reorder within its folder, merge into the target icon,
    // take an app out of its folder, or move an item on the grid. Returns
    // nil (and changes nothing) when the edit is not possible.
    func commitDrop(_ session: DragSession) -> DropOutcome? {
        if session.isInFolder, let folderID = session.sourceFolderID {
            guard addApp(session.itemID, toFolder: folderID, at: session.targetSlot),
                  let index = folderApps(folderID).firstIndex(where: { $0.id == session.itemID }) else { return nil }
            return DropOutcome(page: 0, slot: index)
        }
        if let targetID = session.mergeTargetID {
            guard case .app(let appID) = session.item else { return nil }
            // Back onto its own folder: it stays where it was.
            if targetID == session.sourceFolderID {
                return gridLocation(of: targetID).map { DropOutcome(page: $0.page, slot: $0.slot) }
            }
            if folders.contains(where: { $0.id == targetID }) {
                guard addApp(appID, toFolder: targetID) else { return nil }
                return gridLocation(of: targetID).map { DropOutcome(page: $0.page, slot: $0.slot) }
            }
            guard let folderID = createFolder(dropping: appID, onto: targetID),
                  let location = gridLocation(of: folderID) else { return nil }
            return DropOutcome(page: location.page, slot: location.slot, createdFolderID: folderID)
        }
        if let folderID = session.sourceFolderID {
            guard removeApp(session.itemID, fromFolder: folderID, toPage: session.page, slot: session.targetSlot) else { return nil }
        } else {
            guard moveItem(session.item, toPage: session.page, slot: session.targetSlot) else { return nil }
        }
        return gridLocation(of: session.itemID).map { DropOutcome(page: $0.page, slot: $0.slot) }
    }

    // Where a top-level item sits on the grid.
    func gridLocation(of itemID: String) -> (page: Int, slot: Int)? {
        for (page, items) in pages.enumerated() {
            if let slot = items.firstIndex(where: { $0.id == itemID }) {
                return (page, slot)
            }
        }
        return nil
    }

    // Apps of folder `folderID`, in folder order.
    func folderApps(_ folderID: String) -> [AppEntry] {
        apps.filter { $0.folderID == folderID }
            .sorted { ($0.folderOrderIndex ?? 0) < ($1.folderOrderIndex ?? 0) }
    }

    // The folder's apps take its place on the grid, in folder order.
    @discardableResult
    func disbandFolder(_ folderID: String) -> Bool {
        applyEdit { $0.disband(folderID) }
    }

    @discardableResult
    func sortFolderByName(_ folderID: String) -> Bool {
        let names = Dictionary(apps.map { ($0.bundleIdentifier, $0.displayName) }) { first, _ in first }
        return applyEdit { layout in
            layout.sortFolder(folderID) { a, b in
                switch (names[a] ?? a).localizedCaseInsensitiveCompare(names[b] ?? b) {
                case .orderedAscending: true
                case .orderedDescending: false
                case .orderedSame: a < b
                }
            }
        }
    }

    @discardableResult
    func renameFolder(_ folderID: String, to title: String) -> Bool {
        var layout = GridLayout(apps: apps, folders: folders)
        guard layout.rename(folder: folderID, to: title),
              let newTitle = layout.folders[folderID]?.title,
              let index = folders.firstIndex(where: { $0.id == folderID }) else { return false }
        folders[index].title = newTitle
        layoutRevision += 1
        try? database?.renameFolder(id: folderID, title: newTitle)
        return true
    }

    // MARK: - Hidden apps
    //
    // A hidden app leaves the layout: its page or folder closes the gap (a
    // folder it leaves empty is dissolved) and it keeps no position. Search
    // still finds it. Unhiding puts it after the last item of the last page.

    // For Settings, by name.
    var hiddenApps: [AppEntry] {
        apps.filter(\.isHidden)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    @discardableResult
    func hideApp(_ appID: String) -> Bool {
        guard apps.contains(where: { $0.bundleIdentifier == appID && !$0.isHidden }) else { return false }
        return applyEdit({ $0.delete(appID) }, updateApps: { apps in
            guard let index = apps.firstIndex(where: { $0.bundleIdentifier == appID }) else { return }
            apps[index].isHidden = true
            apps[index].pageIndex = nil
            apps[index].orderIndex = nil
            apps[index].folderID = nil
            apps[index].folderOrderIndex = nil
        })
    }

    @discardableResult
    func unhideApp(_ appID: String) -> Bool {
        guard apps.contains(where: { $0.bundleIdentifier == appID && $0.isHidden }) else { return false }
        return applyEdit({ $0.append(appID) }, updateApps: { apps in
            guard let index = apps.firstIndex(where: { $0.bundleIdentifier == appID }) else { return }
            apps[index].isHidden = false
        })
    }

    // MARK: - Drag session

    private struct ParkedRescan {
        let apps: [AppEntry]
        let folders: [FolderEntry]
        let startRevision: Int
    }

    // True while an icon is dragged on the grid. Set by the grid view.
    @ObservationIgnored private(set) var isDragSessionActive = false
    @ObservationIgnored private var parkedRescan: ParkedRescan?

    // An empty page after the last one, shown while a dragged icon is held
    // past the last page so it can be dropped there. Dropping on it creates
    // the page (`moveItem` to `pages.count`); ending the drag removes it.
    private(set) var hasTrailingDragPage = false
    // Bumped by `cancelDrag()`; the grid observes it.
    private(set) var dragCancelRequest = 0

    // True while a folder title is being edited. The panel's key monitor then
    // leaves Escape and the arrows to the title field.
    @ObservationIgnored var isRenamingFolder = false

    // Pages the pager shows: the stored ones plus the trailing drag page.
    var displayedPageCount: Int {
        pages.count + (hasTrailingDragPage ? 1 : 0)
    }

    // Starting a drag also enters edit mode, which stays on after the drop.
    func beginDragSession() {
        isDragSessionActive = true
        enterEditMode()
    }

    // Returns false when there is no drag or the page is already shown.
    @discardableResult
    func openTrailingDragPage() -> Bool {
        guard isDragSessionActive, !hasTrailingDragPage else { return false }
        hasTrailingDragPage = true
        return true
    }

    // Esc: asks the grid to drop the dragged icon back where it came from.
    // Returns false when no icon is being dragged.
    @discardableResult
    func cancelDrag() -> Bool {
        guard isDragSessionActive else { return false }
        dragCancelRequest += 1
        return true
    }

    // Safe to call more than once per drag.
    func endDragSession() {
        guard isDragSessionActive else { return }
        isDragSessionActive = false
        hasTrailingDragPage = false
        guard let parked = parkedRescan else { return }
        parkedRescan = nil
        receiveRescanResult(apps: parked.apps, folders: parked.folders, startRevision: parked.startRevision)
    }

    // `updateApps` changes rows the layout doesn't carry (hiding), after the
    // edit and before the layout is written back into them.
    private func applyEdit(
        _ edit: (inout GridLayout) -> Bool,
        updateApps: (inout [AppEntry]) -> Void = { _ in }
    ) -> Bool {
        var layout = GridLayout(apps: apps, folders: folders)
        guard edit(&layout) else { return false }
        layout.dissolveEmptyFolders()
        var changedApps = apps
        updateApps(&changedApps)
        let result = layout.apply(to: changedApps, folders: folders)
        updateContents {
            apps = result.apps
            folders = result.folders
        }
        if let openFolderID, !result.folders.contains(where: { $0.id == openFolderID }) {
            self.openFolderID = nil
        }
        layoutRevision += 1
        try? database?.saveLayout(apps: result.apps, folders: result.folders)
        return true
    }

    // MARK: - Edit mode
    //
    // Icons wiggle and clicks don't launch apps. Entered by a long press, by
    // starting a drag (both stay on until dismissed), or while ⌥ is held.

    private(set) var isEditing = false
    // Entered by a long press or a drag: stays on when ⌥ is released.
    @ObservationIgnored private var isEditingSticky = false
    @ObservationIgnored private var isOptionHeld = false

    func enterEditMode() {
        guard !isSearching else { return }
        isEditingSticky = true
        updateEditing()
    }

    // Returns false when edit mode was already off.
    @discardableResult
    func exitEditMode() -> Bool {
        let wasEditing = isEditing
        isEditingSticky = false
        // A still-held ⌥ no longer counts; pressing it again re-enters.
        isOptionHeld = false
        updateEditing()
        return wasEditing
    }

    // ⌥ pressed or released. A press is ignored while typing a query or a
    // folder title, where ⌥ types characters.
    func setOptionHeld(_ held: Bool) {
        guard held != isOptionHeld else { return }
        if held, isSearching || isRenamingFolder || !isVisible { return }
        isOptionHeld = held
        updateEditing()
    }

    private func updateEditing() {
        let editing = isEditingSticky || isOptionHeld
        if isEditing != editing { isEditing = editing }
    }

    // MARK: - Item actions
    //
    // A click on an app, with its modifiers, and the items of an icon's
    // context menu (see `ItemMenu`), which VoiceOver offers as actions too.
    // Those returning true want the launcher hidden: the caller hides the
    // panel, which hides the view model as well.

    @ObservationIgnored var opener = AppOpener.Operations.live
    @ObservationIgnored var runningApps = RunningApps(source: .live)

    // A folder the launcher view should open, from a menu. A fresh value on
    // every request, so asking twice for the same folder still reaches it.
    struct FolderOpenRequest: Equatable {
        let folderID: String
        // Opens with the title in edit mode.
        let renaming: Bool
        let serial: Int
    }

    private(set) var folderOpenRequest: FolderOpenRequest?

    // Asked for every icon's VoiceOver actions on render; the answer for a
    // path doesn't change, so the disk is asked once.
    @ObservationIgnored private var removableByPath: [String: Bool] = [:]

    func isRemovable(_ app: AppEntry) -> Bool {
        if let known = removableByPath[app.appPath] { return known }
        let removable = AppTrash.isRemovable(appPath: app.appPath)
        removableByPath[app.appPath] = removable
        return removable
    }

    func menuItems(for app: AppEntry) -> ItemMenu.Sections {
        ItemMenu.items(for: ItemMenu.AppState(
            isRemovable: isRemovable(app),
            canEditLayout: canEditLayout,
            isHidden: app.isHidden,
            isRunning: runningApps.isRunning(app)
        ))
    }

    func menuItems(for folder: FolderEntry) -> ItemMenu.Sections {
        let appCount = apps.lazy.filter { $0.folderID == folder.id }.count
        return ItemMenu.items(for: ItemMenu.FolderState(appCount: appCount, canEditLayout: canEditLayout))
    }

    // Edit mode is already on, or can't be entered while searching.
    private var canEditLayout: Bool {
        !isEditing && !isSearching
    }

    func click(_ app: AppEntry, modifiers: NSEvent.ModifierFlags) -> Bool {
        switch ItemMenu.clickAction(modifiers: modifiers, isEditing: isEditing) {
        case .launch:
            opener.open(app.appPath, true)
            clearNew(app.bundleIdentifier)
            return true
        case .launchKeepingLauncher:
            // The app stays in the background, so the launcher keeps the
            // keyboard for the next click.
            opener.open(app.appPath, false)
            clearNew(app.bundleIdentifier)
            return false
        case .showInFinder:
            opener.showInFinder(app.appPath)
            return true
        case .none:
            return false
        }
    }

    func perform(_ action: ItemMenu.Action, on app: AppEntry) -> Bool {
        switch action {
        case .open:
            opener.open(app.appPath, true)
            clearNew(app.bundleIdentifier)
            return true
        case .showInFinder:
            // Finder opens below the launcher's panel.
            opener.showInFinder(app.appPath)
            return true
        case .moveToTrash:
            requestRemoval(of: app)
        case .hide:
            hideApp(app.bundleIdentifier)
        case .unhide:
            unhideApp(app.bundleIdentifier)
        case .quit:
            runningApps.quit(app)
        case .forceQuit:
            runningApps.quit(app, force: true)
        case .editLayout:
            enterEditMode()
        case .rename, .sortByName, .disband:
            break
        }
        return false
    }

    func perform(_ action: ItemMenu.Action, on folder: FolderEntry) {
        switch action {
        case .open:
            requestFolderOpen(folder.id, renaming: false)
        case .rename:
            requestFolderOpen(folder.id, renaming: true)
        case .sortByName:
            sortFolderByName(folder.id)
        case .disband:
            disbandFolder(folder.id)
        case .editLayout:
            enterEditMode()
        case .showInFinder, .moveToTrash, .hide, .unhide, .quit, .forceQuit:
            break
        }
    }

    private func requestFolderOpen(_ folderID: String, renaming: Bool) {
        folderOpenRequest = FolderOpenRequest(
            folderID: folderID,
            renaming: renaming,
            serial: (folderOpenRequest?.serial ?? 0) + 1
        )
    }

    // MARK: - Uninstall
    //
    // The × on an app in edit mode, or Move to Trash in its context menu,
    // asks for confirmation, then moves the app to the Trash and drops it
    // from the layout. A running app is quit first.

    struct PendingRemoval: Equatable {
        enum Stage: Equatable {
            case confirm
            // Confirming quits the app, then moves it.
            case appIsOpen
            // Waiting for the app to quit; only Cancel works.
            case quitting
            // Still running after `quitTimeout`, likely asking to save changes.
            case didNotQuit
            case failed(AppTrash.Failure)
        }

        let app: AppEntry
        var stage: Stage
    }

    // The dialog on screen, if any.
    private(set) var pendingRemoval: PendingRemoval?
    @ObservationIgnored var trash = AppTrash.Operations.live
    @ObservationIgnored var quitTimeout = Duration.seconds(Uninstall.quitTimeout)

    // Apps that are part of macOS can't be removed: no ×, a disabled menu item.
    func requestRemoval(of app: AppEntry) {
        guard isRemovable(app) else { return }
        let stage: PendingRemoval.Stage = runningApps.isRunning(app) ? .appIsOpen : .confirm
        pendingRemoval = PendingRemoval(app: app, stage: stage)
    }

    func cancelRemoval() {
        pendingRemoval = nil
    }

    // The dialog's default button: moves the app to the Trash when asked to
    // (quitting it first if it is open), otherwise just closes the dialog.
    // Finder's password prompt would open behind the launcher, so the
    // launcher hides before Finder is asked; a failure there shows its
    // dialog when the launcher opens next.
    func confirmRemoval(hideLauncher: () -> Void) async {
        guard let removal = pendingRemoval else { return }
        switch removal.stage {
        case .confirm:
            break
        case .appIsOpen:
            guard await quitBeforeRemoval(removal.app) else { return }
        case .quitting:
            return
        case .didNotQuit, .failed:
            pendingRemoval = nil
            return
        }
        pendingRemoval = nil
        let app = removal.app
        do {
            if trash.needsAuthorization(app.appPath) {
                hideLauncher()
                try? await Task.sleep(for: .seconds(AnimationDuration.hide + AnimationDuration.orderOutSlack))
                try trash.moveToTrashWithFinder(app.appPath)
            } else {
                try trash.moveToTrash(app.appPath)
            }
        } catch AppTrash.Failure.cancelled {
            return
        } catch {
            let failure = error as? AppTrash.Failure ?? .other(error.localizedDescription)
            pendingRemoval = PendingRemoval(app: app, stage: .failed(failure))
            return
        }
        dropUninstalledApp(app.bundleIdentifier)
    }

    // False if the dialog was closed meanwhile (the app still gets the quit
    // request), or the app didn't quit in time; the dialog then says so.
    private func quitBeforeRemoval(_ app: AppEntry) async -> Bool {
        let quitting = PendingRemoval(app: app, stage: .quitting)
        pendingRemoval = quitting
        runningApps.quit(app)
        let quit = await runningApps.waitUntilQuit(app, timeout: quitTimeout)
        guard pendingRemoval == quitting else { return false }
        guard quit else {
            pendingRemoval = PendingRemoval(app: app, stage: .didNotQuit)
            return false
        }
        return true
    }

    // Takes an app that is gone from disk out of the layout right away,
    // without waiting for the directory watcher's rescan (which doesn't see
    // subfolders like /Applications/Utilities).
    @discardableResult
    func dropUninstalledApp(_ appID: String) -> Bool {
        guard applyEdit({ $0.delete(appID) }) else { return false }
        apps.removeAll { $0.bundleIdentifier == appID }
        try? database?.deleteApp(bundleIdentifier: appID)
        return true
    }

    // MARK: - Search

    enum EscapeAction: Equatable {
        case cancelledRemoval
        case cancelledDrag
        case exitedEditMode
        case clearedSearch
        case closedFolder
        case hideLauncher
    }

    // Escape acts on the innermost context: the Trash dialog, a dragged icon,
    // edit mode, the query, then an open folder, then the launcher itself
    // (which the caller hides).
    func handleEscape() -> EscapeAction {
        if pendingRemoval != nil {
            cancelRemoval()
            return .cancelledRemoval
        }
        if cancelDrag() {
            return .cancelledDrag
        }
        if exitEditMode() {
            return .exitedEditMode
        }
        if !searchText.isEmpty {
            searchText = ""
            return .clearedSearch
        }
        if openFolderID != nil {
            closeFolder()
            return .closedFolder
        }
        return .hideLauncher
    }

    // Clamped to the results: the selection never wraps or leaves the page.
    func moveSelection(by delta: Int) {
        guard !searchResults.isEmpty else { return }
        selectedResultIndex = min(max(selectedResultIndex + delta, 0), searchResults.count - 1)
    }

    private func rebuildSearchResults() {
        searchResults = Array(AppSearch.results(for: searchText, in: apps).prefix(Grid.appsPerPage))
        selectedResultIndex = min(selectedResultIndex, max(searchResults.count - 1, 0))
    }
}
