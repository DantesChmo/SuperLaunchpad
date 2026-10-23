import AppKit

// What a right-click on an icon offers. The same list feeds the context menu
// and the icon's VoiceOver actions, so a new action (Hide, Quit, …) is a new
// `Action` case plus a line in `items(for:)`; both pick it up. The view model
// carries the actions out (`ItemActionsModel.perform`).
enum ItemMenu {
    enum Action: Hashable {
        case open
        case showInFinder
        case moveToTrash
        case hide
        case unhide
        case quit
        case forceQuit
        case rename
        case sortByName
        case disband
        case changeIcon
        case restoreIcon
        case changeCover
        case restoreCover
        case editLayout

        var title: String {
            switch self {
            case .open: "Open"
            case .showInFinder: "Show in Finder"
            case .moveToTrash: "Move to Trash"
            case .hide: "Hide"
            case .unhide: "Unhide"
            case .quit: "Quit"
            case .forceQuit: "Force Quit"
            case .rename: "Rename"
            case .sortByName: "Sort by Name"
            case .disband: "Disband Folder"
            case .changeIcon: "Change Icon…"
            case .restoreIcon: "Restore Default Icon"
            case .changeCover: "Change Cover…"
            case .restoreCover: "Restore Default Cover"
            case .editLayout: "Edit Layout"
            }
        }

        var systemImage: String {
            switch self {
            case .open: "arrow.up.forward.app"
            case .showInFinder: "folder"
            case .moveToTrash: "trash"
            case .hide: "eye.slash"
            case .unhide: "eye"
            case .quit: "xmark.circle"
            case .forceQuit: "xmark.octagon"
            case .rename: "pencil"
            case .sortByName: "arrow.up.arrow.down"
            case .disband: "folder.badge.minus"
            case .changeIcon, .changeCover: "photo"
            case .restoreIcon, .restoreCover: "arrow.uturn.backward"
            case .editLayout: "square.grid.3x3"
            }
        }
    }

    struct Item: Hashable {
        let action: Action
        var isEnabled = true
        // Shown in its place while ⌥ is held.
        var alternate: Action?
    }

    // Sections, separated by dividers in the menu.
    typealias Sections = [[Item]]

    // What an app's items depend on, read when the menu is built.
    struct AppState: Equatable {
        // Apps that are part of macOS can't be moved to the Trash.
        var isRemovable: Bool
        var canEditLayout: Bool
        // Only search shows a hidden app; its menu offers Unhide for Hide.
        var isHidden = false
        var isRunning = false
        var hasCustomIcon = false
    }

    struct FolderState: Equatable {
        var appCount: Int
        var canEditLayout: Bool
        var hasCover = false
    }

    static func items(for app: AppState) -> Sections {
        [
            [Item(action: .open), Item(action: .showInFinder)],
            app.isRunning ? [Item(action: .quit, alternate: .forceQuit)] : [],
            [Item(action: app.isHidden ? .unhide : .hide), Item(action: .moveToTrash, isEnabled: app.isRemovable)],
            [Item(action: .changeIcon)] + (app.hasCustomIcon ? [Item(action: .restoreIcon)] : []),
            [Item(action: .editLayout, isEnabled: app.canEditLayout)]
        ].filter { !$0.isEmpty }
    }

    static func items(for folder: FolderState) -> Sections {
        [
            [Item(action: .open), Item(action: .rename)],
            [Item(action: .sortByName, isEnabled: folder.appCount > 1), Item(action: .disband)],
            [Item(action: .changeCover)] + (folder.hasCover ? [Item(action: .restoreCover)] : []),
            [Item(action: .editLayout, isEnabled: folder.canEditLayout)]
        ]
    }

    // MARK: - Clicks

    enum ClickAction: Equatable {
        case launch
        // ⌘: open the app and keep the launcher up, to open several in a row.
        case launchKeepingLauncher
        // ⌥⌘
        case showInFinder
        // Edit mode, or ⌃-click (the context menu opens instead).
        case none
    }

    static func clickAction(modifiers: NSEvent.ModifierFlags, isEditing: Bool) -> ClickAction {
        guard !isEditing else { return .none }
        switch modifiers.intersection([.command, .option, .control, .shift]) {
        case []: return .launch
        case .command: return .launchKeepingLauncher
        case [.command, .option]: return .showInFinder
        case let flags where flags.contains(.control): return .none
        default: return .launch
        }
    }
}
