import AppKit
import SwiftUI

// The single source of truth for the launcher UI, and the coordinator of the
// models that act on it: `search`, `editing`, `removal`, `layoutFiles`,
// `itemActions` and `customIcons`. It owns the shared state (apps, folders,
// pages, the current page, visibility, the open folder, the DB) and the one
// path every layout write takes (`applyEdit` / `replaceLayout`). The models own their own state
// and hold an `unowned` reference back here; they live exactly as long as
// this object, which creates them.
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
    // Every write to `apps` or `folders` rebuilds `pages` and the search
    // results, unless it happens inside `updateContents { ... }`, which
    // rebuilds once at the end.
    var apps: [AppEntry] = [] {
        didSet { rebuildPagesUnlessBatching() }
    }
    var folders: [FolderEntry] = [] {
        didSet { rebuildPagesUnlessBatching() }
    }
    var currentPage: Int = 0
    var isVisible: Bool = false
    var openFolderID: String? {
        didSet {
            if openFolderID != oldValue { keyboardFocus.openFolderDidChange() }
        }
    }
    // Edges of the launcher's screen covered by the Dock; the content is laid
    // out beside them. Set by `LaunchpadPanel` when it is placed on a screen.
    var dockInsets = DockInsets.zero

    // Ignored by observation: created once, on first use, and never replaced;
    // views observe the models' own properties.
    @ObservationIgnored private(set) lazy var search = SearchModel(launchpad: self)
    @ObservationIgnored private(set) lazy var editing = EditingModel(launchpad: self)
    @ObservationIgnored private(set) lazy var removal = RemovalModel(launchpad: self)
    @ObservationIgnored private(set) lazy var layoutFiles = LayoutFileModel(launchpad: self)
    @ObservationIgnored private(set) lazy var itemActions = ItemActionsModel(launchpad: self)
    @ObservationIgnored private(set) lazy var customIcons = CustomIconModel(launchpad: self)
    @ObservationIgnored private(set) lazy var keyboardFocus = KeyboardFocusModel(launchpad: self)

    @ObservationIgnored var runningApps = RunningApps(source: .live)

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
    func updateContents(_ body: () -> Void) {
        isBatchingContentUpdates = true
        body()
        isBatchingContentUpdates = false
        rebuildPages()
        search.contentsDidChange()
        editing.contentsDidChange()
        keyboardFocus.contentsDidChange()
    }

    private func rebuildPagesUnlessBatching() {
        guard !isBatchingContentUpdates else { return }
        rebuildPages()
        search.contentsDidChange()
        editing.contentsDidChange()
        keyboardFocus.contentsDidChange()
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

    // Pages the pager shows: the stored ones plus the trailing drag page.
    var displayedPageCount: Int {
        pages.count + (editing.hasTrailingDragPage ? 1 : 0)
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

    // Apps of folder `folderID`, in folder order.
    func folderApps(_ folderID: String) -> [AppEntry] {
        apps.filter { $0.folderID == folderID }
            .sorted { ($0.folderOrderIndex ?? 0) < ($1.folderOrderIndex ?? 0) }
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
        layoutFiles.layoutBackups = .standard
    }

    // Test init — accept a pre-built (typically temp) database. See
    // `makeTempDB()` in the tests.
    init(database: AppDatabase?, layoutBackups: LayoutBackupStore? = nil) {
        self.database = database
        layoutFiles.layoutBackups = layoutBackups
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

    private struct ParkedRescan {
        let apps: [AppEntry]
        let folders: [FolderEntry]
        let startRevision: Int
    }

    @ObservationIgnored private var parkedRescan: ParkedRescan?

    // A rescan that finishes mid-drag would swap `pages` under the dragged
    // icon; its result is parked until the drag ends.
    func receiveRescanResult(apps scannedApps: [AppEntry], folders scannedFolders: [FolderEntry], startRevision: Int) {
        guard !editing.isDragSessionActive else {
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

    // Called by `editing` when a drag ends.
    func receiveParkedRescan() {
        guard let parked = parkedRescan else { return }
        parkedRescan = nil
        receiveRescanResult(apps: parked.apps, folders: parked.folders, startRevision: parked.startRevision)
    }

    // MARK: - Layout writes
    //
    // Every change to the layout bumps `layoutRevision` and is persisted in a
    // single DB transaction; the edits themselves live in `editing` and
    // `removal`, the whole-layout replacements in `layoutFiles`.

    // Bumped by every edit and launch; a rescan that started before one must
    // not overwrite it (see `startRescan`).
    @ObservationIgnored var layoutRevision = 0

    // Runs one `GridLayout` operation on the current layout and writes the
    // normalized result back into `apps`/`folders`. Returns false (and
    // changes nothing) when the edit is not possible.
    //
    // `updateApps` changes rows the layout doesn't carry (hiding), after the
    // edit and before the layout is written back into them.
    func applyEdit(
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

    func replaceLayout(apps newApps: [AppEntry], folders newFolders: [FolderEntry]) {
        updateContents {
            apps = newApps
            folders = newFolders
        }
        openFolderID = nil
        currentPage = 0
        // A rescan running now read the old layout: make it write this one back.
        layoutRevision += 1
        try? database?.saveLayout(apps: newApps, folders: newFolders)
        // A loaded file may bring custom icons; they live in their own table.
        try? database?.saveCustomIcons(of: newApps)
    }

    // Every way of opening an app from the launcher counts a launch, which
    // search ranks by, and takes the blue dot away.
    func recordLaunch(_ appID: String) {
        guard let index = apps.firstIndex(where: { $0.bundleIdentifier == appID }) else { return }
        var app = apps[index]
        app.launchCount += 1
        app.isNew = false
        apps[index] = app
        // A rescan running now read the row before this launch.
        layoutRevision += 1
        try? database?.recordLaunch(bundleIdentifier: appID)
    }

    // The user's own icon for an app, or `nil` for its own again. Stored
    // apart from `iconData`, so a rescan keeps it.
    func setCustomIcon(_ imageData: Data?, for appID: String) {
        guard let index = apps.firstIndex(where: { $0.bundleIdentifier == appID }) else { return }
        apps[index].customIconData = imageData
        // A rescan running now read the apps without it.
        layoutRevision += 1
        try? database?.setCustomIcon(imageData, bundleIdentifier: appID)
    }

    // An emoji or image on the folder tile, or `nil` for the 3×3 preview.
    func setFolderCover(_ cover: FolderCover?, for folderID: String) {
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[index].cover = cover
        // A rescan running now read the folder without it.
        layoutRevision += 1
        try? database?.setFolderCover(id: folderID, cover: cover)
    }

    // MARK: - Show / hide

    func show() {
        // Always reset to the first page on show — matches macOS Launchpad UX.
        currentPage = 0
        isVisible = true
        editing.resetOptionKey()
        search.launcherDidShow()
        keyboardFocus.launcherDidShow()
    }

    func hide() {
        // Also close any open folder and clear the query so the next show is
        // in a clean state.
        openFolderID = nil
        search.searchText = ""
        removal.cancelRemoval()
        customIcons.cancelCoverEdit()
        editing.exitEditMode()
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

    // A folder the launcher view should open, from a menu or a search result.
    // A fresh value on every request, so asking twice for the same folder
    // still reaches it.
    struct FolderOpenRequest: Equatable {
        let folderID: String
        // Opens with the title in edit mode.
        let renaming: Bool
        let serial: Int
    }

    private(set) var folderOpenRequest: FolderOpenRequest?

    func requestFolderOpen(_ folderID: String, renaming: Bool) {
        folderOpenRequest = FolderOpenRequest(
            folderID: folderID,
            renaming: renaming,
            serial: (folderOpenRequest?.serial ?? 0) + 1
        )
    }

    // MARK: - Escape

    enum EscapeAction: Equatable {
        case cancelledRemoval
        case cancelledCoverEdit
        case cancelledDrag
        case clearedSelection
        case exitedEditMode
        case clearedSearch
        case closedFolder
        case hideLauncher
    }

    // Escape acts on the innermost context: the Trash or cover dialog, a dragged icon,
    // the selection, edit mode, the query, then an open folder, then the launcher itself
    // (which the caller hides).
    func handleEscape() -> EscapeAction {
        if removal.pendingRemoval != nil {
            removal.cancelRemoval()
            return .cancelledRemoval
        }
        if customIcons.cancelCoverEdit() {
            return .cancelledCoverEdit
        }
        if editing.cancelDrag() {
            return .cancelledDrag
        }
        if editing.clearSelection() {
            return .clearedSelection
        }
        if editing.exitEditMode() {
            return .exitedEditMode
        }
        if !search.searchText.isEmpty {
            search.searchText = ""
            return .clearedSearch
        }
        if openFolderID != nil {
            closeFolder()
            return .closedFolder
        }
        return .hideLauncher
    }
}
