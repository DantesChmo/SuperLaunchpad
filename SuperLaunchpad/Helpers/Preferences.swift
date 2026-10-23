import Foundation

// User preferences live in UserDefaults, not in `AppDatabase`: they are settings,
// not app data. Inject `defaults` so tests can use an isolated suite.
struct Preferences {
    enum Key {
        static let pinchGestureEnabled = "pinchGestureEnabled"
        static let hotKeyCode = "hotKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
        static let newAppPlacement = "newAppPlacement"
    }

    enum Default {
        static let pinchGestureEnabled = true
        static let hotKey = KeyCombo.default
        static let newAppPlacement = NewAppPlacement.end
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.pinchGestureEnabled: Default.pinchGestureEnabled,
            Key.hotKeyCode: Int(Default.hotKey.keyCode),
            Key.hotKeyModifiers: Int(Default.hotKey.modifiers),
            Key.newAppPlacement: Default.newAppPlacement.rawValue,
        ])
    }

    var pinchGestureEnabled: Bool {
        get { defaults.bool(forKey: Key.pinchGestureEnabled) }
        nonmutating set { defaults.set(newValue, forKey: Key.pinchGestureEnabled) }
    }

    // `nil` means "no hotkey", stored as `HotKey.noKeyCode` so the registered
    // default doesn't come back.
    var hotKey: KeyCombo? {
        get {
            let keyCode = defaults.integer(forKey: Key.hotKeyCode)
            let modifiers = defaults.integer(forKey: Key.hotKeyModifiers)
            guard keyCode >= 0, modifiers >= 0 else { return nil }
            return KeyCombo(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers))
        }
        nonmutating set {
            defaults.set(newValue.map { Int($0.modifiers) } ?? 0, forKey: Key.hotKeyModifiers)
            defaults.set(newValue.map { Int($0.keyCode) } ?? HotKey.noKeyCode, forKey: Key.hotKeyCode)
        }
    }

    var newAppPlacement: NewAppPlacement {
        get {
            defaults.string(forKey: Key.newAppPlacement).flatMap(NewAppPlacement.init(rawValue:))
                ?? Default.newAppPlacement
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.newAppPlacement) }
    }
}
