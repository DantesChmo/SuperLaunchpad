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
    private let pager: PagerController
    // Token returned by `NSEvent.addLocalMonitor...` — stored so we can pass it
    // back to `removeMonitor` when hiding.
    private var eventMonitor: Any?
    // Deferred `orderOut` scheduled by `hidePanel`. Kept so `showPanel` can
    // cancel it: otherwise a quick hide→show lets the stale `orderOut` remove
    // the window while `viewModel.isVisible` is already true again.
    private var pendingOrderOut: DispatchWorkItem?

    init(viewModel: LaunchpadViewModel) {
        self.viewModel = viewModel
        pager = PagerController(viewModel: viewModel)

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
        let hostingView = NSHostingView(rootView: LaunchpadView(viewModel: viewModel, pager: pager))
        // Explicit frame is required — `NSHostingView` does NOT auto-resize to
        // its parent panel in this configuration. AGENTS.md flags this.
        hostingView.frame = screen.frame
        contentView = hostingView
    }

    func showPanel() {
        pendingOrderOut?.cancel()
        pendingOrderOut = nil
        // Re-resolve the screen at show-time so display unplug/replug or a
        // resolution change picks up the latest frame.
        let screen = NSScreen.main ?? NSScreen.screens[0]
        setFrame(screen.frame, display: true)
        (contentView as? NSHostingView<LaunchpadView>)?.frame = screen.frame
        // Normally already done on hide; repeated here (before `show()`, while
        // still transparent) so the grid never slides back to page 0 on screen.
        pager.reset()
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
        // fade-out has finished. The slack avoids clipping the tail of the
        // spring animation.
        pendingOrderOut?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingOrderOut = nil
            // `showPanel` cancels this item, but guard anyway in case it was
            // already dequeued: never remove a window that is visible again.
            guard !self.viewModel.isVisible else { return }
            self.orderOut(nil)
            self.pager.reset()
        }
        pendingOrderOut = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + AnimationDuration.hide + AnimationDuration.orderOutSlack,
            execute: workItem
        )
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
            guard !viewModel.cancelDrag() else { return }
            // Escape acts on the innermost context: close the open folder if
            // any, otherwise dismiss the launcher.
            if viewModel.openFolderID != nil {
                viewModel.closeFolder()
            } else {
                hidePanel()
            }
        case 123: // Left arrow
            pager.step(by: -1)
        case 124: // Right arrow
            pager.step(by: 1)
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - Event Monitor

    // All main-grid paging input (trackpad and mouse wheel) goes through
    // `PagerController`. Events are swallowed so nothing else scrolls the grid;
    // while a folder is open they pass through to the folder's own ScrollView.
    private func startEventMonitor() {
        stopEventMonitor()
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.scrollWheel]
        ) { [weak self] event in
            guard let self, self.viewModel.isVisible, self.viewModel.openFolderID == nil else { return event }
            self.pager.handleScroll(event)
            return nil
        }
    }

    private func stopEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
    }
}
