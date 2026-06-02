import AppKit

final class GestureMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
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
        if event.phase == .began {
            cumulativeMagnification = 0
            isGestureActive = true
        }

        guard isGestureActive else { return }
        cumulativeMagnification += event.magnification

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
