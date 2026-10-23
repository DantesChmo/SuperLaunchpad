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
    // action already.
    func launcherMenu(_ sections: ItemMenu.Sections, perform: @escaping (ItemMenu.Action) -> Void) -> some View {
        let actions = sections.joined().filter { $0.isEnabled && $0.action != .open }
        return contextMenu {
            ForEach(sections.indices, id: \.self) { index in
                if index > 0 {
                    Divider()
                }
                ForEach(sections[index], id: \.action) { item in
                    Button {
                        perform(item.action)
                    } label: {
                        Label(item.action.title, systemImage: item.action.systemImage)
                    }
                    .disabled(!item.isEnabled)
                }
            }
        }
        .accessibilityActions {
            ForEach(actions, id: \.action) { item in
                Button(item.action.title) {
                    perform(item.action)
                }
            }
        }
    }
}
