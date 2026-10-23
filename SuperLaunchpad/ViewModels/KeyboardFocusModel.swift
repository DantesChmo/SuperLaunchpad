import Foundation

// The arrow-key focus over the icons (see AGENTS.md → "Keyboard navigation"):
// on the shown page of the grid, or in the open folder. It stays hidden until
// the first arrow press after the launcher shows, so mouse users never see
// it. Owned by `LaunchpadViewModel`; the panel's key monitor drives it and
// pages the grid when the focus crosses a page edge. Search keeps its own
// result selection (`SearchModel`).
@MainActor
@Observable
final class KeyboardFocusModel {
    private unowned let launchpad: LaunchpadViewModel

    init(launchpad: LaunchpadViewModel) {
        self.launchpad = launchpad
    }

    // The focused app in the open folder, with that folder's ID.
    struct FolderFocus: Equatable {
        let folderID: String
        let appID: String
    }

    // True from the first arrow press until the launcher shows again.
    private(set) var isActive = false
    // The focused grid item (an app's bundle ID or a folder's ID).
    private(set) var gridItemID: String?
    private(set) var folderFocus: FolderFocus?
    // Where on its page the grid focus was last. A focus whose item left the
    // grid, or whose page the user swiped away from, comes back at this
    // index on the shown page.
    @ObservationIgnored private var lastGridIndex = 0

    // The grid item that draws the ring: on the shown page only, and not
    // while search results replace the grid or an open folder covers it (the
    // folder's app has the ring then; the grid focus comes back on close).
    var focusedGridItemID: String? {
        guard isActive, !launchpad.search.isSearching, launchpad.openFolderID == nil, let gridItemID,
              launchpad.gridLocation(of: gridItemID)?.page == launchpad.currentPage else { return nil }
        return gridItemID
    }

    // The app in the open folder that draws the ring.
    var focusedFolderAppID: String? {
        guard isActive, let folderFocus, folderFocus.folderID == launchpad.openFolderID,
              launchpad.folderApps(folderFocus.folderID).contains(where: { $0.bundleIdentifier == folderFocus.appID })
        else { return nil }
        return folderFocus.appID
    }

    // What Return acts on: the focused app of the open folder, or else the
    // focused item of the shown page; nil while nothing shows the ring.
    var focusedItem: LaunchpadItem? {
        if launchpad.openFolderID != nil {
            guard let appID = focusedFolderAppID,
                  let app = launchpad.apps.first(where: { $0.bundleIdentifier == appID }) else { return nil }
            return .app(app)
        }
        guard let id = focusedGridItemID, let location = launchpad.gridLocation(of: id) else { return nil }
        return launchpad.pages[location.page][location.slot]
    }

    // MARK: - Arrow keys

    // One arrow press. The first one only shows the focus: on the shown page
    // (where it was, if the user hasn't swiped away) or on the open folder's
    // first app. Returns the grid page the focus moved to when it crossed a
    // page edge; the caller pages there.
    func move(_ direction: GridNavigation.Direction) -> Int? {
        if let folderID = launchpad.openFolderID {
            moveInFolder(folderID, direction)
            return nil
        }
        let pages = launchpad.pages
        let current = launchpad.currentPage
        guard pages.indices.contains(current) else { return nil }
        guard isActive, let gridItemID, let location = launchpad.gridLocation(of: gridItemID),
              location.page == current else {
            isActive = true
            setGridFocus(GridPosition(page: current, index: min(lastGridIndex, pages[current].count - 1)))
            return nil
        }
        let next = GridNavigation.move(
            GridPosition(page: location.page, index: location.slot),
            direction,
            pageCounts: pages.map(\.count),
            columns: Grid.columns
        )
        setGridFocus(next)
        return next.page != current ? next.page : nil
    }

    private func moveInFolder(_ folderID: String, _ direction: GridNavigation.Direction) {
        let apps = launchpad.folderApps(folderID)
        guard let first = apps.first else { return }
        guard let appID = focusedFolderAppID,
              let index = apps.firstIndex(where: { $0.bundleIdentifier == appID }) else {
            isActive = true
            folderFocus = FolderFocus(folderID: folderID, appID: first.bundleIdentifier)
            return
        }
        let perPage = FolderGrid.appsPerPage
        let next = GridNavigation.move(
            GridNavigation.position(ofFlatIndex: index, perPage: perPage),
            direction,
            pageCounts: GridNavigation.pageCounts(itemCount: apps.count, perPage: perPage),
            columns: FolderGrid.columns
        )
        folderFocus = FolderFocus(folderID: folderID, appID: apps[next.page * perPage + next.index].bundleIdentifier)
    }

    private func setGridFocus(_ position: GridPosition) {
        let pages = launchpad.pages
        guard pages.indices.contains(position.page), pages[position.page].indices.contains(position.index) else { return }
        gridItemID = pages[position.page][position.index].id
        lastGridIndex = position.index
    }

    // MARK: - Return and Space

    // Return on a focused folder: it opens with the focus on its first app.
    func openFolder(_ folder: FolderEntry) {
        if let first = launchpad.folderApps(folder.id).first {
            folderFocus = FolderFocus(folderID: folder.id, appID: first.bundleIdentifier)
        }
        launchpad.requestFolderOpen(folder.id, renaming: false)
    }

    // Space in edit mode checks or unchecks the focused app (see
    // `EditingModel.toggleSelection`). Returns false when nothing was
    // toggled: no focus, a folder, or not in edit mode.
    @discardableResult
    func toggleSelection() -> Bool {
        guard launchpad.editing.isEditing, case .app(let app) = focusedItem else { return false }
        return launchpad.editing.toggleSelection(app.bundleIdentifier)
    }

    // MARK: - Coordinator hooks

    // Every show starts with no focus.
    func launcherDidShow() {
        isActive = false
        gridItemID = nil
        folderFocus = nil
        lastGridIndex = 0
    }

    // A folder the keyboard didn't open (or a closed one) starts without focus.
    func openFolderDidChange() {
        guard let folderFocus, folderFocus.folderID != launchpad.openFolderID else { return }
        self.folderFocus = nil
    }

    // The focused item left the grid (into a folder, hidden, trashed): the
    // focus stays where it was on the shown page.
    func contentsDidChange() {
        guard isActive, let gridItemID, launchpad.gridLocation(of: gridItemID) == nil else { return }
        let pages = launchpad.pages
        let current = launchpad.currentPage
        guard pages.indices.contains(current) else {
            self.gridItemID = nil
            return
        }
        setGridFocus(GridPosition(page: current, index: min(lastGridIndex, pages[current].count - 1)))
    }
}
