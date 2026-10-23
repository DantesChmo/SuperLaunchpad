import AppKit
import Carbon.HIToolbox
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
    // Display the panel was last placed on, so a display change can keep it
    // there (resolution change) or tell that it was unplugged.
    private var displayID: UInt32?
    // Settings → Appearance → Blurred wallpaper, for the screen the panel is on.
    private let wallpaper = DesktopWallpaper(provider: .live)

    init(viewModel: LaunchpadViewModel) {
        self.viewModel = viewModel
        pager = PagerController(viewModel: viewModel)

        // Placeholder frame: `showPanel` picks the screen under the cursor.
        // `screens` can be empty during sleep/wake transitions.
        let frame = (NSScreen.main ?? NSScreen.screens.first)?.frame ?? .zero
        super.init(
            contentRect: frame,
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
        let hostingView = NSHostingView(rootView: LaunchpadView(viewModel: viewModel, pager: pager, wallpaper: wallpaper))
        // Explicit frame is required — `NSHostingView` does NOT auto-resize to
        // its parent panel in this configuration. AGENTS.md flags this.
        hostingView.frame = NSRect(origin: .zero, size: frame.size)
        contentView = hostingView

        pager.screen = { [weak self] in self?.screen }
        // Selector-based: the observation goes away with the panel.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuDidBeginTracking),
            name: NSMenu.didBeginTrackingNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuDidEndTracking),
            name: NSMenu.didEndTrackingNotification,
            object: nil
        )
        // Each Space can have its own desktop picture.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    func showPanel() {
        pendingOrderOut?.cancel()
        pendingOrderOut = nil
        // Open on the screen under the cursor, like the system Launchpad.
        // Resolved on every show, so plugged / unplugged displays need no bookkeeping.
        placeOnScreen { mouse, displays in ScreenSelection.index(at: mouse, in: displays) }
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

    // MARK: - Screens

    // Display plugged in or out, resolution or arrangement changed. A hidden
    // panel is re-placed by `showPanel`; a visible one stays on its display with
    // the new frame, or moves under the cursor if its display is gone.
    @objc private func screenParametersDidChange(_ notification: Notification) {
        guard viewModel.isVisible else { return }
        placeOnScreen { [displayID] mouse, displays in
            ScreenSelection.indexAfterChange(currentID: displayID, point: mouse, in: displays)
        }
        pager.screenDidChange()
    }

    private func placeOnScreen(_ pick: (CGPoint, [ScreenSelection.Display]) -> Int?) {
        let screens = NSScreen.screens
        let displays = screens.map { ScreenSelection.Display(id: $0.displayID, frame: $0.frame) }
        guard let index = pick(NSEvent.mouseLocation, displays) else { return }
        let screen = screens[index]
        displayID = displays[index].id
        wallpaper.refresh(displayID: displays[index].id)
        setFrame(screen.frame, display: true)
        // Window coordinates, not `screen.frame`: on a secondary display the
        // screen origin is non-zero and would push the grid off the panel.
        contentView?.frame = NSRect(origin: .zero, size: screen.frame.size)
        // The panel covers the whole screen, but the Dock stays on top of it.
        // Moving or resizing the Dock changes `visibleFrame` and posts a
        // screen-parameters change, which lands here again.
        let dockInsets = DockInsets(frame: screen.frame, visibleFrame: screen.visibleFrame)
        if viewModel.dockInsets != dockInsets {
            viewModel.dockInsets = dockInsets
        }
    }

    @objc private func activeSpaceDidChange(_ notification: Notification) {
        guard viewModel.isVisible else { return }
        wallpaper.refresh()
    }

    // MARK: - Menus

    // An icon's context menu opens at the pop-up menu level, below this
    // `.screenSaver` panel, and would be hidden behind it. While a menu is
    // open the panel steps down to just below menus: still above the Dock
    // and the menu bar.
    @objc private func menuDidBeginTracking(_ notification: Notification) {
        guard viewModel.isVisible else { return }
        level = .belowMenus
    }

    @objc private func menuDidEndTracking(_ notification: Notification) {
        level = .screenSaver
    }

    // `NSPanel` defaults to NOT becoming key/main (panels are usually auxiliary).
    // We override both: we want keyboard focus (key) and we are the "primary"
    // window when shown (main).
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // MARK: - Event Monitor

    // All main-grid paging input (trackpad and mouse wheel) goes through
    // `PagerController`. Events are swallowed so nothing else scrolls the grid;
    // while a folder is open they pass through to the folder's own ScrollView.
    //
    // Navigation keys are taken here too, before the focused search field's
    // editor would consume them (see `handleKeyDown`). Holding ⌥ shows edit
    // mode; the event still goes on, so the field editor sees the modifier.
    private func startEventMonitor() {
        stopEventMonitor()
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.scrollWheel, .keyDown, .flagsChanged]
        ) { [weak self] event in
            guard let self, self.viewModel.isVisible, event.window === self else { return event }
            if event.type == .flagsChanged {
                let option = event.modifierFlags.intersection([.command, .option, .control, .shift]) == .option
                self.viewModel.editing.setOptionHeld(option)
                return event
            }
            if event.type == .keyDown {
                return self.handleKeyDown(event) ? nil : event
            }
            guard self.viewModel.openFolderID == nil, !self.viewModel.search.isSearching,
                  self.viewModel.removal.pendingRemoval == nil,
                  self.viewModel.customIcons.coverEditFolderID == nil else { return event }
            self.pager.handleScroll(event)
            return nil
        }
    }

    // Returns true if the key was handled. Key codes are layout-independent,
    // so arrows behave the same on AZERTY / Dvorak. Everything not handled
    // (letters, modified keys, Space outside edit mode) goes on to the search
    // field.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        // While an input method is composing, its candidate window owns the
        // arrows, Return and Escape.
        if let editor = firstResponder as? NSTextView, editor.hasMarkedText() { return false }
        // The folder title field handles its own Escape (cancel the edit) and arrows.
        guard !viewModel.editing.isRenamingFolder else { return false }
        // The cover dialog's emoji field takes every other key, Return included.
        if viewModel.customIcons.coverEditFolderID != nil {
            guard Int(event.keyCode) == kVK_Escape else { return false }
            viewModel.customIcons.cancelCoverEdit()
            return true
        }
        // The Trash dialog takes Escape and Return; other keys must not page
        // or start a search behind it.
        if viewModel.removal.pendingRemoval != nil {
            guard !event.modifierFlags.contains(.command) else { return false }
            switch Int(event.keyCode) {
            case kVK_Escape:
                viewModel.removal.cancelRemoval()
            case kVK_Return, kVK_ANSI_KeypadEnter:
                Task { [weak self] in
                    await self?.viewModel.removal.confirmRemoval { self?.hidePanel() }
                }
            default:
                break
            }
            return true
        }
        guard event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else { return false }

        let searching = viewModel.search.isSearching
        switch Int(event.keyCode) {
        case kVK_Escape:
            if viewModel.handleEscape() == .hideLauncher {
                hidePanel()
            }
        case kVK_LeftArrow:
            if searching { viewModel.search.moveSelection(by: -1) } else { moveFocus(.left) }
        case kVK_RightArrow:
            if searching { viewModel.search.moveSelection(by: 1) } else { moveFocus(.right) }
        case kVK_UpArrow:
            if searching { viewModel.search.moveSelection(by: -Grid.columns) } else { moveFocus(.up) }
        case kVK_DownArrow:
            if searching { viewModel.search.moveSelection(by: Grid.columns) } else { moveFocus(.down) }
        case kVK_Return where searching, kVK_ANSI_KeypadEnter where searching:
            switch viewModel.search.selectedResult {
            case .app(let app):
                // Hide first: `launchApp` also hides the view model, after
                // which `hidePanel` would skip the `orderOut`.
                hidePanel()
                viewModel.itemActions.launchApp(app)
            case .folder(let folder, _):
                viewModel.search.openFolderFromSearch(folder)
            case nil:
                break
            }
        case kVK_Return, kVK_ANSI_KeypadEnter:
            return activateFocusedItem()
        case kVK_Space where viewModel.editing.isEditing && !searching:
            // Without a focused app the space goes on to the field.
            return viewModel.keyboardFocus.toggleSelection()
        default:
            return false
        }
        return true
    }

    // An arrow outside search moves the keyboard focus (`KeyboardFocusModel`);
    // crossing a page edge pages the grid with the usual settle. During an
    // icon drag ← and → page as they always did.
    private func moveFocus(_ direction: GridNavigation.Direction) {
        if viewModel.editing.isDragSessionActive {
            switch direction {
            case .left: pager.step(by: -1)
            case .right: pager.step(by: 1)
            case .up, .down: break
            }
            return
        }
        if let page = viewModel.keyboardFocus.move(direction) {
            pager.step(by: page - viewModel.currentPage)
        }
    }

    // Return outside search: opens the focused folder (in edit mode too, as
    // a click does) or launches the focused app. Otherwise it leaves edit
    // mode, as before, or goes on to the field.
    private func activateFocusedItem() -> Bool {
        switch viewModel.keyboardFocus.focusedItem {
        case .folder(let folder, _):
            viewModel.keyboardFocus.openFolder(folder)
        case .app(let app) where !viewModel.editing.isEditing:
            // Hide first, as for a search result.
            hidePanel()
            viewModel.itemActions.launchApp(app)
        default:
            return viewModel.editing.exitEditMode()
        }
        return true
    }

    private func stopEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
    }
}

private extension NSWindow.Level {
    static let belowMenus = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
}
