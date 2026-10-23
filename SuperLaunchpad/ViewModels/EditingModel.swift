import Foundation

// Edit mode, icon drags and the layout edits they end in, hiding included.
// Owned by `LaunchpadViewModel`; every edit goes through its `applyEdit`.
@MainActor
@Observable
final class EditingModel {
    private unowned let launchpad: LaunchpadViewModel

    init(launchpad: LaunchpadViewModel) {
        self.launchpad = launchpad
    }

    // MARK: - Edit mode
    //
    // Icons wiggle and clicks don't launch apps. Entered by a long press, by
    // starting a drag (both stay on until dismissed), or while ⌥ is held.

    private(set) var isEditing = false
    // Entered by a long press or a drag: stays on when ⌥ is released.
    @ObservationIgnored private var isEditingSticky = false
    @ObservationIgnored private var isOptionHeld = false

    // True while a folder title is being edited. The panel's key monitor then
    // leaves Escape and the arrows to the title field.
    @ObservationIgnored var isRenamingFolder = false

    func enterEditMode() {
        guard !launchpad.search.isSearching else { return }
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
        if held, launchpad.search.isSearching || isRenamingFolder || !launchpad.isVisible { return }
        isOptionHeld = held
        updateEditing()
    }

    // On show: a ⌥ held before the launcher opened doesn't count.
    func resetOptionKey() {
        isOptionHeld = false
    }

    private func updateEditing() {
        let editing = isEditingSticky || isOptionHeld
        if isEditing != editing { isEditing = editing }
    }

    // MARK: - Drag session

    // True while an icon is dragged on the grid. Set by the grid view.
    @ObservationIgnored private(set) var isDragSessionActive = false

    // An empty page after the last one, shown while a dragged icon is held
    // past the last page so it can be dropped there. Dropping on it creates
    // the page (`moveItem` to `pages.count`); ending the drag removes it.
    private(set) var hasTrailingDragPage = false
    // Bumped by `cancelDrag()`; the grid observes it.
    private(set) var dragCancelRequest = 0

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

    // Safe to call more than once per drag. A rescan that finished during
    // the drag is applied now.
    func endDragSession() {
        guard isDragSessionActive else { return }
        isDragSessionActive = false
        hasTrailingDragPage = false
        launchpad.receiveParkedRescan()
    }

    // MARK: - Drop

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
                  let index = launchpad.folderApps(folderID).firstIndex(where: { $0.id == session.itemID }) else { return nil }
            return DropOutcome(page: 0, slot: index)
        }
        if let targetID = session.mergeTargetID {
            guard case .app(let appID) = session.item else { return nil }
            // Back onto its own folder: it stays where it was.
            if targetID == session.sourceFolderID {
                return launchpad.gridLocation(of: targetID).map { DropOutcome(page: $0.page, slot: $0.slot) }
            }
            if launchpad.folders.contains(where: { $0.id == targetID }) {
                guard addApp(appID, toFolder: targetID) else { return nil }
                return launchpad.gridLocation(of: targetID).map { DropOutcome(page: $0.page, slot: $0.slot) }
            }
            guard let folderID = createFolder(dropping: appID, onto: targetID),
                  let location = launchpad.gridLocation(of: folderID) else { return nil }
            return DropOutcome(page: location.page, slot: location.slot, createdFolderID: folderID)
        }
        if let folderID = session.sourceFolderID {
            guard removeApp(session.itemID, fromFolder: folderID, toPage: session.page, slot: session.targetSlot) else { return nil }
        } else {
            guard moveItem(session.item, toPage: session.page, slot: session.targetSlot) else { return nil }
        }
        return launchpad.gridLocation(of: session.itemID).map { DropOutcome(page: $0.page, slot: $0.slot) }
    }

    // MARK: - Layout edits
    //
    // Each edit runs one `GridLayout` operation on the current layout through
    // `LaunchpadViewModel.applyEdit`, which writes the normalized result back
    // into `apps`/`folders` and persists it in a single DB transaction. Every
    // method returns false (and changes nothing) when the edit is not
    // possible.

    nonisolated static let defaultFolderTitle = "Folder"

    @discardableResult
    func moveItem(_ item: GridLayout.Item, toPage page: Int, slot: Int) -> Bool {
        launchpad.applyEdit { $0.move(item, toPage: page, slot: slot) }
    }

    // Returns the ID of the new folder, or nil when the merge is not possible.
    @discardableResult
    func mergeApps(_ appID: String, onto targetAppID: String, title: String = defaultFolderTitle) -> String? {
        let folderID = UUID().uuidString
        let merged = launchpad.applyEdit { $0.merge(appID, onto: targetAppID, folderID: folderID, title: title) }
        return merged ? folderID : nil
    }

    @discardableResult
    func addApp(_ appID: String, toFolder folderID: String, at index: Int? = nil) -> Bool {
        launchpad.applyEdit { $0.add(appID, toFolder: folderID, at: index) }
    }

    // A folder left without apps is dissolved.
    @discardableResult
    func removeApp(_ appID: String, fromFolder folderID: String, toPage page: Int, slot: Int) -> Bool {
        launchpad.applyEdit { $0.remove(appID, fromFolder: folderID, toPage: page, slot: slot) }
    }

    // Drop app `appID` on app `targetAppID`: a new folder titled after the
    // target app's category. Returns the folder's ID.
    @discardableResult
    func createFolder(dropping appID: String, onto targetAppID: String) -> String? {
        guard let target = launchpad.apps.first(where: { $0.bundleIdentifier == targetAppID }) else { return nil }
        let title = AppCategoryTitle.folderTitle(forAppAt: target.appPath, fallback: Self.defaultFolderTitle)
        return mergeApps(appID, onto: targetAppID, title: title)
    }

    // The folder's apps take its place on the grid, in folder order.
    @discardableResult
    func disbandFolder(_ folderID: String) -> Bool {
        launchpad.applyEdit { $0.disband(folderID) }
    }

    @discardableResult
    func sortFolderByName(_ folderID: String) -> Bool {
        let names = Dictionary(launchpad.apps.map { ($0.bundleIdentifier, $0.displayName) }) { first, _ in first }
        return launchpad.applyEdit { layout in
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
        var layout = GridLayout(apps: launchpad.apps, folders: launchpad.folders)
        guard layout.rename(folder: folderID, to: title),
              let newTitle = layout.folders[folderID]?.title,
              let index = launchpad.folders.firstIndex(where: { $0.id == folderID }) else { return false }
        launchpad.folders[index].title = newTitle
        launchpad.layoutRevision += 1
        try? launchpad.database?.renameFolder(id: folderID, title: newTitle)
        return true
    }

    // MARK: - Hidden apps
    //
    // A hidden app leaves the layout: its page or folder closes the gap (a
    // folder it leaves empty is dissolved) and it keeps no position. Search
    // still finds it. Unhiding puts it after the last item of the last page.

    // For Settings, by name.
    var hiddenApps: [AppEntry] {
        launchpad.apps.filter(\.isHidden)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    @discardableResult
    func hideApp(_ appID: String) -> Bool {
        guard launchpad.apps.contains(where: { $0.bundleIdentifier == appID && !$0.isHidden }) else { return false }
        return launchpad.applyEdit({ $0.delete(appID) }, updateApps: { apps in
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
        guard launchpad.apps.contains(where: { $0.bundleIdentifier == appID && $0.isHidden }) else { return false }
        return launchpad.applyEdit({ $0.append(appID) }, updateApps: { apps in
            guard let index = apps.firstIndex(where: { $0.bundleIdentifier == appID }) else { return }
            apps[index].isHidden = false
        })
    }
}
