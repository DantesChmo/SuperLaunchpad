import AppKit

// What a right-click on an icon offers. The same list feeds the context menu
// and the icon's VoiceOver actions, so a new action (Hide, Quit, …) is a new
// `Action` case plus a line in `items(for:)`; both pick it up. The view model
// carries the actions out (`LaunchpadViewModel.perform`).
enum ItemMenu {
    enum Action: Hashable {
        case open
        case showInFinder
        case moveToTrash
        case rename
        case sortByName
        case disband
        case editLayout

        var title: String {
            switch self {
            case .open: "Open"
            case .showInFinder: "Show in Finder"
            case .moveToTrash: "Move to Trash"
            case .rename: "Rename"
            case .sortByName: "Sort by Name"
            case .disband: "Disband Folder"
            case .editLayout: "Edit Layout"
            }
        }

        var systemImage: String {
            switch self {
            case .open: "arrow.up.forward.app"
            case .showInFinder: "folder"
            case .moveToTrash: "trash"
            case .rename: "pencil"
            case .sortByName: "arrow.up.arrow.down"
            case .disband: "folder.badge.minus"
            case .editLayout: "square.grid.3x3"
            }
        }
    }

    struct Item: Hashable {
        let action: Action
        var isEnabled = true
    }

    // Sections, separated by dividers in the menu.
    typealias Sections = [[Item]]

    // What an app's items depend on, read when the menu is built.
    struct AppState: Equatable {
        // Apps that are part of macOS can't be moved to the Trash.
        var isRemovable: Bool
        var canEditLayout: Bool
    }

    struct FolderState: Equatable {
        var appCount: Int
        var canEditLayout: Bool
    }

    static func items(for app: AppState) -> Sections {
        [
            [Item(action: .open), Item(action: .showInFinder)],
            [Item(action: .moveToTrash, isEnabled: app.isRemovable)],
            [Item(action: .editLayout, isEnabled: app.canEditLayout)]
        ]
    }

    static func items(for folder: FolderState) -> Sections {
        [
            [Item(action: .open), Item(action: .rename)],
            [Item(action: .sortByName, isEnabled: folder.appCount > 1), Item(action: .disband)],
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
