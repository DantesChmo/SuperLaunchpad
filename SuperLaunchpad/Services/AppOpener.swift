import AppKit

// Opens apps and shows them in Finder through Launch Services, as Finder
// does on a double-click.
enum AppOpener {
    // What the view model calls; tests swap in their own.
    struct Operations {
        // The app's path, and whether it comes to the front.
        var open: (String, Bool) -> Void
        var showInFinder: (String) -> Void

        static var live: Operations {
            Operations(
                open: AppOpener.open(appPath:activates:),
                showInFinder: AppOpener.showInFinder(appPath:)
            )
        }
    }

    static func open(appPath: String, activates: Bool) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activates
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: appPath), configuration: configuration)
    }

    static func showInFinder(appPath: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: appPath)])
    }
}
