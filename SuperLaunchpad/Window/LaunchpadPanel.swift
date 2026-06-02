import AppKit
import SwiftUI

final class LaunchpadPanel: NSPanel {
    private let viewModel: LaunchpadViewModel
    private var eventMonitor: Any?

    init(viewModel: LaunchpadViewModel) {
        self.viewModel = viewModel

        let screen = NSScreen.main ?? NSScreen.screens[0]
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        animationBehavior = .none
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false

        let hostingView = NSHostingView(rootView: LaunchpadView(viewModel: viewModel))
        hostingView.frame = screen.frame
        contentView = hostingView
    }

    func showPanel() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        setFrame(screen.frame, display: true)
        (contentView as? NSHostingView<LaunchpadView>)?.frame = screen.frame
        viewModel.show()
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        startEventMonitor()
    }

    func hidePanel() {
        guard viewModel.isVisible else { return }
        stopEventMonitor()
        viewModel.hide()
        DispatchQueue.main.asyncAfter(deadline: .now() + AnimationDuration.hide + 0.1) {
            self.orderOut(nil)
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Escape
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

    private func startEventMonitor() {
        stopEventMonitor()
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.scrollWheel]
        ) { [weak self] event in
            guard let self, self.viewModel.isVisible else { return event }
            if !event.hasPreciseScrollingDeltas {
                self.handleMouseScroll(event)
            }
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
        let delta: CGFloat
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            delta = event.scrollingDeltaX
        } else {
            delta = -event.scrollingDeltaY
        }

        guard abs(delta) > 0.5 else { return }

        if delta > 0 {
            goToPreviousPage()
        } else {
            goToNextPage()
        }
    }
}
