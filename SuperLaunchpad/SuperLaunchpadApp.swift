import SwiftUI

// `@main` makes this struct the program entry point. SwiftUI synthesises `main()`
// from the `App` protocol — there is no traditional `main.swift` in this project.
@main
struct SuperLaunchpadApp: App {
    // Bridges the SwiftUI app lifecycle to a classic AppKit `NSApplicationDelegate`.
    // We need an AppDelegate because the launcher relies on AppKit primitives
    // (NSPanel, global NSEvent monitors, DispatchSource) that don't fit into the
    // pure SwiftUI scene lifecycle.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // `MenuBarExtra` is the SwiftUI way to add a menu-bar (status-bar) item.
        // The closure is the menu's content; the title/systemImage define how the
        // status item appears next to the clock.
        MenuBarExtra("SuperLaunchpad", systemImage: "square.grid.3x3") {
            Button("Show / Hide") {
                appDelegate.toggleLaunchpad()
            }
            SettingsMenuButton {
                appDelegate.prepareForSettings()
            }
            Divider()
            Button("Quit") {
                // `NSApp` is the shared `NSApplication` singleton.
                // `terminate(_:)` is the standard, graceful way to quit a macOS app —
                // it runs `applicationShouldTerminate` and flushes pending work.
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }

        Settings {
            SettingsView(hotKeyMonitor: appDelegate.hotKeyMonitor)
        }
    }
}

// `SettingsLink` can't run code before opening the window, and the launcher panel
// (`.screenSaver` level) must be hidden first or it covers Settings.
// `openSettings` gives the same result with a hook.
private struct SettingsMenuButton: View {
    @Environment(\.openSettings) private var openSettings
    let onOpen: () -> Void

    var body: some View {
        Button("Settings…") {
            onOpen()
            openSettings()
        }
        .keyboardShortcut(",")
    }
}

// `NSApplicationDelegate` requires `NSObject` (it's an Objective-C protocol).
// `final` — we never subclass this; the compiler can devirtualise method calls.
// `@MainActor` because it owns and drives the main-actor `LaunchpadViewModel`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Implicitly-unwrapped optional (`!`) is used here because `panel` is created
    // in `applicationDidFinishLaunching`, not in `init`. By the time any UI code
    // touches it, it is guaranteed to be non-nil. This is the one place AGENTS.md
    // allows `!` outside `lazy`.
    private var panel: LaunchpadPanel!
    private let viewModel = LaunchpadViewModel()
    private var watcher: AppDirectoryWatcher!
    private let gestureMonitor = GestureMonitor()
    let hotKeyMonitor = HotKeyMonitor()
    private let preferences = Preferences()
    private var isGestureMonitorRunning = false

    // Called once the AppKit framework has finished bootstrapping the app.
    // This is the right place to create top-level windows and start long-running
    // services — `init` runs too early (before NSScreen, etc. are usable).
    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = LaunchpadPanel(viewModel: viewModel)

        // Load cached apps from SQLite, then kick off a background rescan.
        // Non-blocking: see `LaunchpadViewModel.loadApps` for the two-phase flow.
        viewModel.loadApps()

        // `[weak self]` breaks the retain cycle: AppDelegate -> watcher -> closure -> self.
        // Without it the AppDelegate would never deallocate (not fatal here since it
        // lives for the whole app session, but it's the correct habit).
        watcher = AppDirectoryWatcher { [weak self] in
            self?.viewModel.scheduleRescan()
        }
        watcher.start()

        // Trackpad pinch-in (fingers together) opens the launcher; pinch-out closes.
        // `guard` ensures we don't re-trigger the same state (e.g. opening when
        // already open, which would replay the show animation).
        gestureMonitor.onPinchIn = { [weak self] in
            guard let self, !self.viewModel.isVisible else { return }
            self.panel.showPanel()
        }
        gestureMonitor.onPinchOut = { [weak self] in
            guard let self, self.viewModel.isVisible else { return }
            self.panel.hidePanel()
        }
        applyGesturePreference()
        hotKeyMonitor.onPress = { [weak self] in
            self?.toggleLaunchpad()
        }
        applyHotKeyPreference()
        // Settings writes through @AppStorage; re-apply on any defaults change.
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyGesturePreference()
                self?.applyHotKeyPreference()
            }
        }

        // UI tests launch with `-UITestMode YES`. The launcher panel is normally
        // hidden until the user pinches or clicks the menu-bar item, neither of
        // which XCUITest can drive reliably on a headless CI runner. Show the
        // panel immediately so `app.windows.firstMatch` resolves.
        if UserDefaults.standard.bool(forKey: "UITestMode") {
            panel.showPanel()
        }

        // SwiftUI views can't reach `panel.hidePanel()` directly without coupling
        // (the panel is an AppKit object far up the ownership tree). A named
        // notification — `.hideLaunchpad` declared at the bottom of LaunchpadView.swift —
        // decouples them: any view can post it, and the delegate dismisses the panel.
        NotificationCenter.default.addObserver(
            forName: .hideLaunchpad,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Delivered on `.main`, but the closure type is not main-actor isolated.
            MainActor.assumeIsolated {
                self?.panel.hidePanel()
            }
        }
    }

    // Called when the user clicks the Dock icon (or opens the app while it is
    // already running). Returning `false` tells AppKit "I handled it — don't
    // perform the default behaviour of re-creating windows".
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

    func prepareForSettings() {
        panel.hidePanel()
        NSApp.activate(ignoringOtherApps: true)
    }

    // `GestureMonitor.start()` is not idempotent (it would add duplicate monitors),
    // so track whether it is running.
    private func applyGesturePreference() {
        let enabled = preferences.pinchGestureEnabled
        guard enabled != isGestureMonitorRunning else { return }
        if enabled {
            gestureMonitor.start()
        } else {
            gestureMonitor.stop()
        }
        isGestureMonitorRunning = enabled
    }

    // Any defaults write lands here, so skip re-registering an unchanged combo.
    private func applyHotKeyPreference() {
        let combo = preferences.hotKey
        guard combo != hotKeyMonitor.combo else { return }
        if let combo {
            hotKeyMonitor.register(combo)
        } else {
            hotKeyMonitor.unregister()
        }
    }
}
