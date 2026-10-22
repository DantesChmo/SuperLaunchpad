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
//
// Coexisting with macOS 26 (Tahoe): `.magnify` carries no finger count, so a
// two-finger zoom-out in Safari/Maps/Preview looks exactly like our pinch-in.
// The four/five-finger system pinch (→ Apps.app) is consumed by the Dock and
// never reaches us. `PinchRecognizer` therefore only opens on a deliberate,
// quick pinch; the gesture can be switched off via `enabledDefaultsKey`, and
// `SystemPinchGesture` tells onboarding whether the system pinch is on.
// None of this was measured on a real trackpad — see gesture.md in the stage-4
// notes.
final class GestureMonitor {
    // UserDefaults key for the "open with pinch" setting. Absent = enabled.
    static let enabledDefaultsKey = "pinchGestureEnabled"

    // Returned tokens are typed `Any?` for legacy reasons — store them so we
    // can pass them back to `removeMonitor(_:)` later.
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var recognizer = PinchRecognizer()

    var onPinchIn: (() -> Void)?
    var onPinchOut: (() -> Void)?
    // Asked on every event so the recognizer knows which direction matters:
    // only pinch-in while hidden, only pinch-out while shown.
    var isLauncherVisible: (() -> Bool)?

    // `object(forKey:)` rather than `bool(forKey:)`: an unset key must read as
    // "enabled", not `false`.
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledDefaultsKey) as? Bool ?? true
    }

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
        guard Self.isEnabled() else { return }

        let phase: PinchRecognizer.Phase
        if event.phase.contains(.began) {
            phase = .began
        } else if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            phase = .ended
        } else {
            phase = .changed
        }

        let action = recognizer.feed(
            phase: phase,
            magnification: event.magnification,
            timestamp: event.timestamp,
            isLauncherVisible: isLauncherVisible?() ?? false
        )
        switch action {
        case .open: onPinchIn?()
        case .close: onPinchOut?()
        case .none: break
        }
    }
}

// The decision logic, kept free of NSEvent so it can be unit-tested.
//
// A single pinch is delivered as many tiny magnification deltas (one per
// frame). We accumulate them and act once the total crosses a threshold, then
// ignore the rest of that gesture so the launcher doesn't flicker.
//
// Sign convention from AppKit: negative = fingers moved together (pinch in /
// "open"), positive = fingers spread apart (pinch out / "close").
struct PinchRecognizer {
    enum Phase { case began, changed, ended }
    enum Action: Equatable { case none, open, close }

    // Opening is stricter than closing: a pinch-in from another app is
    // indistinguishable from that app's zoom-out, so we want a bigger and
    // faster movement than people use for zooming. Closing only happens while
    // the launcher is up, where nothing else competes for the gesture.
    static let openThreshold: CGFloat = 0.8
    static let closeThreshold: CGFloat = 0.5
    // A pinch that hasn't reached `openThreshold` within this many seconds is
    // treated as a slow zoom and dropped.
    static let openWindow: TimeInterval = 0.8

    private(set) var cumulativeMagnification: CGFloat = 0
    private(set) var isActive = false
    private var startTime: TimeInterval = 0

    mutating func feed(
        phase: Phase,
        magnification: CGFloat,
        timestamp: TimeInterval,
        isLauncherVisible: Bool
    ) -> Action {
        // `.began` marks the start of a new continuous gesture — reset so the
        // previous gesture doesn't leak into this one.
        if phase == .began {
            cumulativeMagnification = 0
            isActive = true
            startTime = timestamp
        }
        guard isActive else { return .none }

        if phase == .ended {
            isActive = false
            return .none
        }

        cumulativeMagnification += magnification

        if isLauncherVisible {
            if cumulativeMagnification >= Self.closeThreshold {
                isActive = false
                return .close
            }
            return .none
        }

        if timestamp - startTime > Self.openWindow {
            isActive = false
            return .none
        }
        if cumulativeMagnification <= -Self.openThreshold {
            isActive = false
            return .open
        }
        return .none
    }
}

// Read-only check of the system "Pinch with thumb and three fingers" gesture,
// which on Tahoe opens Apps.app (Launchpad before that). Lets onboarding tell
// the user to turn it off in System Settings → Trackpad → More Gestures.
// We never write these keys.
enum SystemPinchGesture {
    // Built-in trackpad and Magic Trackpad keep separate copies.
    static let domains = [
        "com.apple.AppleMultitouchTrackpad",
        "com.apple.driver.AppleBluetoothMultitouch.trackpad",
    ]
    static let keys = ["TrackpadFourFingerPinchGesture", "TrackpadFiveFingerPinchGesture"]
    // 2 = gesture on, 0 = off.
    static let enabledValue = 2

    static var isEnabled: Bool {
        let values = domains.flatMap { domain in
            keys.map { UserDefaults(suiteName: domain)?.object(forKey: $0) }
        }
        return isEnabled(values: values)
    }

    // Unset keys mean the user never touched the setting, and the system
    // default is on. Otherwise any copy set to "on" wins.
    static func isEnabled(values: [Any?]) -> Bool {
        let set = values.compactMap { $0 as? Int }
        guard !set.isEmpty else { return true }
        return set.contains(enabledValue)
    }
}
