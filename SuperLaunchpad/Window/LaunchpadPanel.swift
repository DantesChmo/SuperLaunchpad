import AppKit
import SwiftUI

// Fullscreen borderless window that hosts the SwiftUI launcher UI.
//
// `NSPanel` (vs `NSWindow`) is preferred for transient utility windows:
// it can float above other apps, doesn't take "main window" status by default,
// and survives space changes more gracefully. This is the same primitive Apple
// uses for Spotlight, Quick Note, etc.
final class LaunchpadPanel: NSPanel {
    private let viewModel: LaunchpadViewModel
    // Token returned by `NSEvent.addLocalMonitor...` — stored so we can pass it
    // back to `removeMonitor` when hiding.
    private var eventMonitor: Any?

    init(viewModel: LaunchpadViewModel) {
        self.viewModel = viewModel

        // Multi-monitor is intentionally out of scope (see AGENTS.md > known
        // limitations); fall back to first screen if `.main` is nil during
        // sleep/wake transitions.
        let screen = NSScreen.main ?? NSScreen.screens[0]
        super.init(
            contentRect: screen.frame,
            // `.borderless` removes the title bar; `.fullSizeContentView`
            // extends the content under the (invisible) title bar area.
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            // `defer: false` creates the underlying window server resource now.
            // `true` would lazy-create on first show — we want it ready so the
            // first show animation is smooth.
            defer: false
        )

        // ── Window level / behaviour. Each line is load-bearing — see
        //    AGENTS.md > "Domain gotchas". Don't change without testing.

        // `.screenSaver` is the highest "normal" level — sits above the Dock
        // and menu bar. Lower levels (e.g. `.floating`) leave the launcher
        // hiding behind system UI.
        level = .screenSaver
        // Allow our transparent background to show through.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // `.canJoinAllSpaces` makes the panel visible on every Space (desktop).
        // `.fullScreenAuxiliary` allows it to appear over fullscreen apps
        // without forcing them out of fullscreen.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        // Don't disappear when the user switches to another app — we manage
        // visibility manually via `showPanel` / `hidePanel`.
        hidesOnDeactivate = false
        // We do our own SwiftUI opacity+scale animation; turn off AppKit's.
        animationBehavior = .none
        isFloatingPanel = true
        // Always become key when ordered front, so we can receive key events
        // (Escape, arrow keys) immediately after `makeKeyAndOrderFront`.
        becomesKeyOnlyIfNeeded = false

        // `NSHostingView` is the AppKit bridge that lets us put a SwiftUI tree
        // into any AppKit window. The `contentView` is what `NSPanel` renders.
        let hostingView = NSHostingView(rootView: LaunchpadView(viewModel: viewModel))
        // Explicit frame is required — `NSHostingView` does NOT auto-resize to
        // its parent panel in this configuration. AGENTS.md flags this.
        hostingView.frame = screen.frame
        contentView = hostingView
    }

    func showPanel() {
        // Re-resolve the screen at show-time so display unplug/replug or a
        // resolution change picks up the latest frame.
        let screen = NSScreen.main ?? NSScreen.screens[0]
        setFrame(screen.frame, display: true)
        (contentView as? NSHostingView<LaunchpadView>)?.frame = screen.frame
        viewModel.show()
        // `ignoringOtherApps: true` — bring our process to the front even if
        // the user clicked another app's window in between.
        NSApp.activate(ignoringOtherApps: true)
        // Show the window AND make it key (focused for keyboard input).
        makeKeyAndOrderFront(nil)
        startEventMonitor()
    }

    func hidePanel() {
        // Idempotent: calling hide twice is a no-op. Prevents double animations
        // if both a click and the global hotkey trigger close in quick succession.
        guard viewModel.isVisible else { return }
        stopEventMonitor()
        viewModel.hide()
        // Delay the actual `orderOut` (window removal) until AFTER the SwiftUI
        // fade-out has finished. The `+ 0.1` is slack to avoid clipping the
        // tail of the spring animation.
        DispatchQueue.main.asyncAfter(deadline: .now() + AnimationDuration.hide + 0.1) {
            self.orderOut(nil)
        }
    }

    // `NSPanel` defaults to NOT becoming key/main (panels are usually auxiliary).
    // We override both: we want keyboard focus (key) and we are the "primary"
    // window when shown (main).
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // Hardware key code constants used below (from NSEvent / HIToolbox).
    // We could use `event.charactersIgnoringModifiers` but key codes are
    // layout-independent — arrow keys behave the same on AZERTY / Dvorak.
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Escape
            // Escape acts on the innermost context: close the open folder if
            // any, otherwise dismiss the launcher.
            if viewModel.openFolderID != nil {
                viewModel.closeFolder()
            } else {
                hidePanel()
            }
        case 123: // Left arrow
            goToPreviousPage()
        case 124: // Right arrow
            goToNextPage()
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - Page Navigation

    private func goToNextPage() {
        if viewModel.currentPage < viewModel.pages.count - 1 {
            viewModel.currentPage += 1
        }
    }

    private func goToPreviousPage() {
        if viewModel.currentPage > 0 {
            viewModel.currentPage -= 1
        }
    }

    // MARK: - Event Monitor

    // Scroll-wheel monitor for mouse-driven paging (regular mice, not trackpads).
    // Trackpads scroll the inner SwiftUI ScrollView natively; we only intercept
    // discrete mouse wheel ticks here.
    private func startEventMonitor() {
        stopEventMonitor()
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.scrollWheel]
        ) { [weak self] event in
            guard let self, self.viewModel.isVisible else { return event }
            // `hasPreciseScrollingDeltas` is `true` for trackpads (continuous,
            // pixel-precise). When `false`, it's a mouse wheel — fixed steps
            // that we want to convert into page jumps.
            if !event.hasPreciseScrollingDeltas {
                self.handleMouseScroll(event)
            }
            // Local monitor: returning the event lets it continue to SwiftUI.
            return event
        }
    }

    private func stopEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
    }

    // MARK: - Mouse Scroll

    private func handleMouseScroll(_ event: NSEvent) {
        // Some mice (e.g. tilting wheel) report horizontal deltas; respect the
        // dominant axis. Negate Y because positive Y means "scroll up" but we
        // want "scroll down → next page".
        let delta: CGFloat
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            delta = event.scrollingDeltaX
        } else {
            delta = -event.scrollingDeltaY
        }

        // 0.5 threshold filters out tiny noise from imprecise hardware.
        guard abs(delta) > 0.5 else { return }

        if delta > 0 {
            goToPreviousPage()
        } else {
            goToNextPage()
        }
    }
}
