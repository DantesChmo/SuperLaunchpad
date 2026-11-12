import AppKit
import SwiftUI

// Outside edit mode an app icon drags as its .app file, the way Finder drags
// it: dropped on the Dock, the app is kept there. The icon stays where it is
// in the launcher. In edit mode the same drag moves the icon on the grid
// instead (`LaunchpadDragGesture`, which lifts icons only in edit mode).
enum AppFileDrag {
    // What the drag carries: the app bundle's file URL.
    static func itemProvider(for app: AppEntry) -> NSItemProvider {
        let provider = NSItemProvider(object: URL(fileURLWithPath: app.appPath) as NSURL)
        provider.suggestedName = app.displayName
        return provider
    }
}

extension View {
    // The app's file drag on its icon (see `AppFileDrag`), off in edit mode.
    func appFileDrag(_ app: AppEntry, iconSize: CGFloat) -> some View {
        modifier(AppFileDragModifier(app: app, iconSize: iconSize))
    }
}

private struct AppFileDragModifier: ViewModifier {
    let app: AppEntry
    let iconSize: CGFloat

    @Environment(\.isEditing) private var isEditing

    func body(content: Content) -> some View {
        if isEditing {
            content
        } else {
            content.onDrag {
                AppFileDrag.itemProvider(for: app)
            } preview: {
                preview
            }
        }
    }

    // Just the icon, without the running dot or the label.
    @ViewBuilder
    private var preview: some View {
        if let image = IconCache.shared.image(for: app) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSize, height: iconSize)
        }
    }
}
