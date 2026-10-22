import Foundation

// User preferences live in UserDefaults, not in `AppDatabase`: they are settings,
// not app data. Inject `defaults` so tests can use an isolated suite.
struct Preferences {
    enum Key {
        static let pinchGestureEnabled = "pinchGestureEnabled"
        // Global hotkey (keyCode + modifiers) keys go here.
    }

    enum Default {
        static let pinchGestureEnabled = true
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.pinchGestureEnabled: Default.pinchGestureEnabled,
        ])
    }

    var pinchGestureEnabled: Bool {
        get { defaults.bool(forKey: Key.pinchGestureEnabled) }
        nonmutating set { defaults.set(newValue, forKey: Key.pinchGestureEnabled) }
    }
}
