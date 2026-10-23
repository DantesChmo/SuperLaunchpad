import SwiftUI
import UniformTypeIdentifiers

extension EnvironmentValues {
    @Entry var customIconDrop = CustomIconDropAction(viewModel: nil)
}

// What a file dropped on an app icon does. Compared by view model identity,
// like `RemoveAppAction`.
struct CustomIconDropAction: Equatable {
    let viewModel: LaunchpadViewModel?

    @MainActor func callAsFunction(_ urls: [URL], on app: AppEntry) {
        viewModel?.customIcons.dropFiles(urls, on: app.bundleIdentifier)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.viewModel === rhs.viewModel
    }
}

extension View {
    // In edit mode an image file (or an app) dropped on the icon becomes its
    // custom icon. Dragging icons around the grid is a gesture, not a
    // drag-and-drop session, so only drags from other apps (Finder) land here.
    func customIconDrop(_ app: AppEntry, iconSize: CGFloat) -> some View {
        modifier(CustomIconDrop(app: app, iconSize: iconSize))
    }
}

private struct CustomIconDrop: ViewModifier {
    let app: AppEntry
    let iconSize: CGFloat

    @Environment(\.isEditing) private var isEditing
    @Environment(\.customIconDrop) private var customIconDrop
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if isEditing && isTargeted {
                    RoundedRectangle(cornerRadius: iconSize * 0.2)
                        .stroke(.white, lineWidth: iconSize * CustomIcons.dropRingWidthRatio)
                        .padding(-iconSize * CustomIcons.dropRingOutsetRatio)
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: [.fileURL], delegate: FileDropDelegate(isEditing: isEditing, isTargeted: $isTargeted) { url in
                customIconDrop([url], on: app)
            })
    }
}

// A delegate rather than `onDrop(of:isTargeted:perform:)`, so outside edit
// mode the icon refuses the drop instead of showing the copy cursor.
private struct FileDropDelegate: DropDelegate {
    let isEditing: Bool
    @Binding var isTargeted: Bool
    let onDrop: @MainActor (URL) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        isEditing && info.hasItemsConforming(to: [.fileURL])
    }

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        guard isEditing, let provider = info.itemProviders(for: [.fileURL]).first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in onDrop(url) }
        }
        return true
    }
}
