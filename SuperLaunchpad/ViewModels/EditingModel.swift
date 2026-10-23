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
        if !editing {
            clearSelection()
            marqueeBase = nil
        }
    }

    // MARK: - Selection
    //
    // Apps checked in edit mode (see AGENTS.md → "Multi-select"): visible apps
    // on the grid or in a folder, never folders or hidden apps. Clicks toggle,
    // a marquee adds (or toggles with ⌘/⇧); leaving edit mode clears it.

    private(set) var selection: Set<String> = []
    // The selection when the current marquee started.
    @ObservationIgnored private var marqueeBase: Set<String>?

    // Returns false when the app can't be selected (not in edit mode, not
    // shown on the grid or in a folder).
    @discardableResult
    func toggleSelection(_ appID: String) -> Bool {
        guard isEditing, isSelectable(appID) else { return false }
        if selection.contains(appID) {
            selection.remove(appID)
        } else {
            selection.insert(appID)
        }
        return true
    }

    // Returns false when nothing was selected.
    @discardableResult
    func clearSelection() -> Bool {
        guard !selection.isEmpty else { return false }
        selection = []
        return true
    }

    // One marquee sample: `hits` are the apps under the band now. The first
    // sample remembers the selection it started from; the band adds to it,
    // or flips its apps when `toggling`.
    func updateMarquee(hits: Set<String>, toggling: Bool) {
        guard isEditing else { return }
        let base = marqueeBase ?? selection
        marqueeBase = base
        let hits = hits.filter(isSelectable)
        let updated = toggling ? base.symmetricDifference(hits) : base.union(hits)
        if updated != selection { selection = updated }
    }

    func endMarquee() {
        marqueeBase = nil
    }

    // The selection in layout order (see `GridLayout.ordered`).
    var orderedSelection: [String] {
        GridLayout(apps: launchpad.apps, folders: launchpad.folders).ordered(selection)
    }

    // The apps a drag lifting `appID` carries along: the rest of the
    // selection in layout order, when `appID` is selected with others.
    func dragCompanions(for appID: String) -> [AppEntry] {
        guard selection.contains(appID), selection.count > 1 else { return [] }
        let byID = Dictionary(launchpad.apps.map { ($0.bundleIdentifier, $0) }) { first, _ in first }
        return orderedSelection.filter { $0 != appID }.compactMap { byID[$0] }
    }

    // Called by the coordinator after `apps`/`folders` change: apps that left
    // the layout (hidden, trashed, uninstalled) leave the selection.
    func contentsDidChange() {
        guard !selection.isEmpty else { return }
        let kept = selection.filter(isSelectable)
        if kept != selection { selection = kept }
    }

    private func isSelectable(_ appID: String) -> Bool {
        launchpad.apps.contains { $0.bundleIdentifier == appID && !$0.isHidden }
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
        guard session.companionIDs.isEmpty else { return commitGroupDrop(session) }
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

    // A group drag: the lead, then its companions, land together — in the
    // open folder, into the folder or app under them, or consecutively on
    // the grid. The selection is spent.
    private func commitGroupDrop(_ session: DragSession) -> DropOutcome? {
        let group = [session.itemID] + session.companionIDs
        let outcome: DropOutcome?
        if session.isInFolder, let folderID = session.sourceFolderID {
            guard launchpad.applyEdit({ $0.addGroup(group, toFolder: folderID, at: session.targetSlot) }),
                  let index = launchpad.folderApps(folderID).firstIndex(where: { $0.id == session.itemID }) else { return nil }
            outcome = DropOutcome(page: 0, slot: index)
        } else if let targetID = session.mergeTargetID {
            if launchpad.folders.contains(where: { $0.id == targetID }) {
                guard launchpad.applyEdit({ $0.addGroup(group, toFolder: targetID) }) else { return nil }
                outcome = launchpad.gridLocation(of: targetID).map { DropOutcome(page: $0.page, slot: $0.slot) }
            } else {
                guard let target = launchpad.apps.first(where: { $0.bundleIdentifier == targetID }) else { return nil }
                let folderID = UUID().uuidString
                let title = AppCategoryTitle.folderTitle(forAppAt: target.appPath, fallback: Self.defaultFolderTitle)
                guard launchpad.applyEdit({ $0.mergeGroup(group, onto: targetID, folderID: folderID, title: title) }),
                      let location = launchpad.gridLocation(of: folderID) else { return nil }
                outcome = DropOutcome(page: location.page, slot: location.slot, createdFolderID: folderID)
            }
        } else {
            guard launchpad.applyEdit({ $0.moveGroup(group, toPage: session.page, slot: session.targetSlot) }) else { return nil }
            outcome = launchpad.gridLocation(of: session.itemID).map { DropOutcome(page: $0.page, slot: $0.slot) }
        }
        clearSelection()
        return outcome
    }

    // MARK: - Group actions
    //
    // What the selection bar does with the selected apps, each one
    // `applyEdit`. The selection is spent.

    // The new folder (titled after the first app's category) opens in rename
    // mode. Returns its ID.
    @discardableResult
    func makeFolderFromSelection() -> String? {
        let group = orderedSelection
        guard let first = group.first.flatMap({ id in launchpad.apps.first { $0.bundleIdentifier == id } }) else { return nil }
        let folderID = UUID().uuidString
        let title = AppCategoryTitle.folderTitle(forAppAt: first.appPath, fallback: Self.defaultFolderTitle)
        guard launchpad.applyEdit({ $0.makeFolder(group, folderID: folderID, title: title) }) else { return nil }
        clearSelection()
        launchpad.requestFolderOpen(folderID, renaming: true)
        return folderID
    }

    @discardableResult
    func hideSelection() -> Bool {
        let group = orderedSelection
        guard hideApps(group) else { return false }
        clearSelection()
        return true
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
        hideApps([appID])
    }

    // All in one edit; false (and nothing hidden) if one of them is unknown
    // or already hidden.
    @discardableResult
    func hideApps(_ appIDs: [String]) -> Bool {
        let ids = Set(appIDs)
        guard !ids.isEmpty,
              ids.allSatisfy({ id in launchpad.apps.contains { $0.bundleIdentifier == id && !$0.isHidden } }) else { return false }
        return launchpad.applyEdit({ layout in
            ids.allSatisfy { layout.delete($0) }
        }, updateApps: { apps in
            for index in apps.indices where ids.contains(apps[index].bundleIdentifier) {
                apps[index].isHidden = true
                apps[index].pageIndex = nil
                apps[index].orderIndex = nil
                apps[index].folderID = nil
                apps[index].folderOrderIndex = nil
            }
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
