import Foundation

// User preferences live in UserDefaults, not in `AppDatabase`: they are settings,
// not app data. Inject `defaults` so tests can use an isolated suite.
struct Preferences {
    enum Key {
        static let pinchGestureEnabled = "pinchGestureEnabled"
        static let hotKeyCode = "hotKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
        static let newAppPlacement = "newAppPlacement"
        static let showsFrequentApps = "showsFrequentApps"
        static let backgroundStyle = "backgroundStyle"
        static let backgroundBlur = "backgroundBlur"
        static let backgroundDimming = "backgroundDimming"
        static let labelSize = "labelSize"
        static let hidesLabels = "hidesLabels"
    }

    enum Default {
        static let pinchGestureEnabled = true
        static let hotKey = KeyCombo.default
        static let newAppPlacement = NewAppPlacement.end
        static let showsFrequentApps = false
        // Today's look: the full system blur and `LabelContrast.dimOpacity`.
        static let backgroundStyle = BackgroundStyle.desktop
        static let backgroundBlur: Double = 1
        static let backgroundDimming = LabelContrast.dimOpacity
        static let labelSize = LabelSize.medium
        static let hidesLabels = false
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.pinchGestureEnabled: Default.pinchGestureEnabled,
            Key.hotKeyCode: Int(Default.hotKey.keyCode),
            Key.hotKeyModifiers: Int(Default.hotKey.modifiers),
            Key.newAppPlacement: Default.newAppPlacement.rawValue,
            Key.showsFrequentApps: Default.showsFrequentApps,
            Key.backgroundStyle: Default.backgroundStyle.rawValue,
            Key.backgroundBlur: Default.backgroundBlur,
            Key.backgroundDimming: Default.backgroundDimming,
            Key.labelSize: Default.labelSize.rawValue,
            Key.hidesLabels: Default.hidesLabels,
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

    // Settings → Search: a row of the most launched apps above the grid.
    var showsFrequentApps: Bool {
        get { defaults.bool(forKey: Key.showsFrequentApps) }
        nonmutating set { defaults.set(newValue, forKey: Key.showsFrequentApps) }
    }

    // MARK: - Appearance

    var backgroundStyle: BackgroundStyle {
        get {
            defaults.string(forKey: Key.backgroundStyle).flatMap(BackgroundStyle.init(rawValue:))
                ?? Default.backgroundStyle
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.backgroundStyle) }
    }

    // 0…1: none to the full blur.
    var backgroundBlur: Double {
        get { min(max(defaults.double(forKey: Key.backgroundBlur), 0), 1) }
        nonmutating set { defaults.set(newValue, forKey: Key.backgroundBlur) }
    }

    // Opacity of the dark layer over the background, 0…`BackgroundAppearance.maxDimming`.
    var backgroundDimming: Double {
        get { min(max(defaults.double(forKey: Key.backgroundDimming), 0), BackgroundAppearance.maxDimming) }
        nonmutating set { defaults.set(newValue, forKey: Key.backgroundDimming) }
    }

    var labelSize: LabelSize {
        get { defaults.string(forKey: Key.labelSize).flatMap(LabelSize.init(rawValue:)) ?? Default.labelSize }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.labelSize) }
    }

    var hidesLabels: Bool {
        get { defaults.bool(forKey: Key.hidesLabels) }
        nonmutating set { defaults.set(newValue, forKey: Key.hidesLabels) }
    }
}
