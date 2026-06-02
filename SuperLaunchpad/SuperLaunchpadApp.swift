import SwiftUI

@main
struct SuperLaunchpadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("SuperLaunchpad", systemImage: "square.grid.3x3") {
            Button("Show / Hide") {
                appDelegate.toggleLaunchpad()
            }
            .keyboardShortcut("l", modifiers: [.command, .option])
            Divider()
            Button("Quit") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: LaunchpadPanel!
    private let viewModel = LaunchpadViewModel()
    private var watcher: AppDirectoryWatcher!
    private let gestureMonitor = GestureMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = LaunchpadPanel(viewModel: viewModel)

        viewModel.loadApps()

        watcher = AppDirectoryWatcher { [weak self] in
            self?.viewModel.loadApps()
        }
        watcher.start()

        gestureMonitor.onPinchIn = { [weak self] in
            guard let self, !self.viewModel.isVisible else { return }
            self.panel.showPanel()
        }
        gestureMonitor.onPinchOut = { [weak self] in
            guard let self, self.viewModel.isVisible else { return }
            self.panel.hidePanel()
        }
        gestureMonitor.start()

        NotificationCenter.default.addObserver(
            forName: .hideLaunchpad,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.panel.hidePanel()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        toggleLaunchpad()
        return false
    }

    func toggleLaunchpad() {
        if viewModel.isVisible {
            panel.hidePanel()
        } else {
            panel.showPanel()
        }
    }
}
