import AppKit

// Listens for trackpad pinch (magnify) gestures system-wide and reports them
// as semantic pinch-in / pinch-out events.
//
// Why two monitors?
//   • Global monitor fires for events delivered to OTHER apps — required so the
//     launcher can be summoned from anywhere on the desktop.
//   • Local monitor fires for events delivered to OUR app (only when our panel
//     is the first responder). The two callbacks never both fire for the same
//     event; we need both to cover both cases.
//
// Global monitors are read-only (no `return event`); local monitors must return
// the (possibly-modified) event to let it continue down the responder chain.
//
// Heads-up: global monitors for `.magnify`, `.keyDown`, etc. may require
// "Accessibility" permission in System Settings → Privacy & Security depending
// on macOS version and what events you subscribe to.
final class GestureMonitor {
    // Returned tokens are typed `Any?` for legacy reasons — store them so we
    // can pass them back to `removeMonitor(_:)` later.
    private var globalMonitor: Any?
    private var localMonitor: Any?
    // We accumulate small per-event magnification deltas because a single
    // pinch gesture is delivered as many tiny events (one per frame). Acting
    // on the first event would be jittery; we instead wait until the total
    // crosses a threshold.
    private var cumulativeMagnification: CGFloat = 0
    private var isGestureActive = false

    var onPinchIn: (() -> Void)?
    var onPinchOut: (() -> Void)?

    func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .magnify) { [weak self] event in
            self?.handleMagnify(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
            self?.handleMagnify(event)
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handleMagnify(_ event: NSEvent) {
        // `.began` marks the start of a new continuous gesture — reset the
        // accumulator so the previous gesture doesn't leak into this one.
        if event.phase == .began {
            cumulativeMagnification = 0
            isGestureActive = true
        }

        // After we've already fired, ignore the remaining events of the same
        // gesture — otherwise we'd toggle show/hide rapidly until the user
        // lifts their fingers.
        guard isGestureActive else { return }
        cumulativeMagnification += event.magnification

        // Sign convention from AppKit: negative = fingers moved together
        // (pinch in / "show Launchpad"), positive = fingers spread apart
        // (pinch out / "hide"). 0.5 is the magnitude threshold from AGENTS.md.
        if cumulativeMagnification < -0.5 {
            isGestureActive = false
            onPinchIn?()
        } else if cumulativeMagnification > 0.5 {
            isGestureActive = false
            onPinchOut?()
        }

        if event.phase == .ended || event.phase == .cancelled {
            isGestureActive = false
        }
    }
}
