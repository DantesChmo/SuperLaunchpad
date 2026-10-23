import AppKit

// Launching an app, a click on an app with its modifiers, and the items of
// an icon's context menu (see `ItemMenu`), which VoiceOver offers as actions
// too. Owned by `LaunchpadViewModel`; the actions themselves land on the
// other models. Those returning true want the launcher hidden: the caller
// hides the panel, which hides the view model as well.
@MainActor
@Observable
final class ItemActionsModel {
    private unowned let launchpad: LaunchpadViewModel

    init(launchpad: LaunchpadViewModel) {
        self.launchpad = launchpad
    }

    @ObservationIgnored var opener = AppOpener.Operations.live

    // Launches the app (see `AppOpener`) and hides the launcher straight
    // after so the user lands on the launched app.
    //
    // Does nothing in edit mode, where a click on an app only selects it for
    // dragging. Returns whether the app was launched.
    @discardableResult
    func launchApp(_ app: AppEntry) -> Bool {
        guard !launchpad.editing.isEditing else { return false }
        opener.open(app.appPath, true)
        launchpad.recordLaunch(app.bundleIdentifier)
        launchpad.hide()
        return true
    }

    func menuItems(for app: AppEntry) -> ItemMenu.Sections {
        ItemMenu.items(for: ItemMenu.AppState(
            isRemovable: launchpad.removal.isRemovable(app),
            canEditLayout: canEditLayout,
            isHidden: app.isHidden,
            isRunning: launchpad.runningApps.isRunning(app)
        ))
    }

    func menuItems(for folder: FolderEntry) -> ItemMenu.Sections {
        let appCount = launchpad.apps.lazy.filter { $0.folderID == folder.id }.count
        return ItemMenu.items(for: ItemMenu.FolderState(appCount: appCount, canEditLayout: canEditLayout))
    }

    // Edit mode is already on, or can't be entered while searching.
    private var canEditLayout: Bool {
        !launchpad.editing.isEditing && !launchpad.search.isSearching
    }

    func click(_ app: AppEntry, modifiers: NSEvent.ModifierFlags) -> Bool {
        switch ItemMenu.clickAction(modifiers: modifiers, isEditing: launchpad.editing.isEditing) {
        case .launch:
            opener.open(app.appPath, true)
            launchpad.recordLaunch(app.bundleIdentifier)
            return true
        case .launchKeepingLauncher:
            // The app stays in the background, so the launcher keeps the
            // keyboard for the next click.
            opener.open(app.appPath, false)
            launchpad.recordLaunch(app.bundleIdentifier)
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
            launchpad.recordLaunch(app.bundleIdentifier)
            return true
        case .showInFinder:
            // Finder opens below the launcher's panel.
            opener.showInFinder(app.appPath)
            return true
        case .moveToTrash:
            launchpad.removal.requestRemoval(of: app)
        case .hide:
            launchpad.editing.hideApp(app.bundleIdentifier)
        case .unhide:
            launchpad.editing.unhideApp(app.bundleIdentifier)
        case .quit:
            launchpad.runningApps.quit(app)
        case .forceQuit:
            launchpad.runningApps.quit(app, force: true)
        case .editLayout:
            launchpad.editing.enterEditMode()
        case .rename, .sortByName, .disband:
            break
        }
        return false
    }

    func perform(_ action: ItemMenu.Action, on folder: FolderEntry) {
        switch action {
        case .open:
            launchpad.requestFolderOpen(folder.id, renaming: false)
        case .rename:
            launchpad.requestFolderOpen(folder.id, renaming: true)
        case .sortByName:
            launchpad.editing.sortFolderByName(folder.id)
        case .disband:
            launchpad.editing.disbandFolder(folder.id)
        case .editLayout:
            launchpad.editing.enterEditMode()
        case .showInFinder, .moveToTrash, .hide, .unhide, .quit, .forceQuit:
            break
        }
    }
}
