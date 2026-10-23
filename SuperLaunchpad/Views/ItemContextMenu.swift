import SwiftUI

extension EnvironmentValues {
    @Entry var itemMenu = ItemMenuAction(viewModel: nil)
}

// Builds and runs the icons' context menus. Compared by view model identity,
// like `EnterEditModeAction`.
struct ItemMenuAction: Equatable {
    let viewModel: LaunchpadViewModel?

    @MainActor func items(for app: AppEntry) -> ItemMenu.Sections {
        viewModel?.menuItems(for: app) ?? []
    }

    @MainActor func items(for folder: FolderEntry) -> ItemMenu.Sections {
        viewModel?.menuItems(for: folder) ?? []
    }

    @MainActor func perform(_ action: ItemMenu.Action, on app: AppEntry) {
        guard viewModel?.perform(action, on: app) == true else { return }
        NotificationCenter.default.post(name: .hideLaunchpad, object: nil)
    }

    @MainActor func perform(_ action: ItemMenu.Action, on folder: FolderEntry) {
        viewModel?.perform(action, on: folder)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.viewModel === rhs.viewModel
    }
}

extension View {
    // Right-click menu on an app icon; its items are VoiceOver actions too.
    func appContextMenu(_ app: AppEntry) -> some View {
        modifier(AppContextMenu(app: app))
    }

    // Right-click menu on a folder tile; its items are VoiceOver actions too.
    func folderContextMenu(_ folder: FolderEntry) -> some View {
        modifier(FolderContextMenu(folder: folder))
    }
}

private struct AppContextMenu: ViewModifier {
    let app: AppEntry

    @Environment(\.itemMenu) private var itemMenu

    func body(content: Content) -> some View {
        content.launcherMenu(itemMenu.items(for: app)) { action in
            itemMenu.perform(action, on: app)
        }
    }
}

private struct FolderContextMenu: ViewModifier {
    let folder: FolderEntry

    @Environment(\.itemMenu) private var itemMenu

    func body(content: Content) -> some View {
        content.launcherMenu(itemMenu.items(for: folder)) { action in
            itemMenu.perform(action, on: folder)
        }
    }
}

private extension View {
    // Open is left out of the VoiceOver actions: it is the icon's default
    // action already. An item's ⌥ alternate is an action of its own there.
    func launcherMenu(_ sections: ItemMenu.Sections, perform: @escaping (ItemMenu.Action) -> Void) -> some View {
        let actions = sections.joined()
            .filter { $0.isEnabled }
            .flatMap { [$0.action] + ($0.alternate.map { [$0] } ?? []) }
            .filter { $0 != .open }
        return contextMenu {
            ForEach(sections.indices, id: \.self) { index in
                if index > 0 {
                    Divider()
                }
                ForEach(sections[index], id: \.action) { item in
                    if let alternate = item.alternate {
                        menuButton(item.action, perform: perform)
                            .modifierKeyAlternate(.option) {
                                menuButton(alternate, perform: perform)
                            }
                            .disabled(!item.isEnabled)
                    } else {
                        menuButton(item.action, perform: perform)
                            .disabled(!item.isEnabled)
                    }
                }
            }
        }
        .accessibilityActions {
            ForEach(actions, id: \.self) { action in
                Button(action.title) {
                    perform(action)
                }
            }
        }
    }

    func menuButton(_ action: ItemMenu.Action, perform: @escaping (ItemMenu.Action) -> Void) -> some View {
        Button {
            perform(action)
        } label: {
            Label(action.title, systemImage: action.systemImage)
        }
    }
}
