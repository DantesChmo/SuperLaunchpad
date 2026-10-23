import Foundation

// Settings → Appearance: what is behind the grid.
enum BackgroundStyle: String, CaseIterable, Identifiable {
    // `NSVisualEffectView` blurring whatever is on screen behind the panel.
    case desktop
    // The desktop picture of the launcher's screen, blurred by us (see
    // `DesktopWallpaper`); falls back to `desktop` when it can't be read.
    case wallpaper

    var id: String { rawValue }

    var title: String {
        switch self {
        case .desktop: String(localized: "Blurred desktop")
        case .wallpaper: String(localized: "Blurred wallpaper")
        }
    }
}

// Settings → Appearance: icon label size, a factor on `LayoutMetrics.labelFont`.
enum LabelSize: String, CaseIterable, Identifiable {
    case small
    case medium
    case large
    case extraLarge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: String(localized: "Small")
        case .medium: String(localized: "Medium")
        case .large: String(localized: "Large")
        case .extraLarge: String(localized: "Extra Large")
        }
    }

    var scale: CGFloat {
        switch self {
        case .small: LabelSizeScale.small
        case .medium: 1
        case .large: LabelSizeScale.large
        case .extraLarge: LabelSizeScale.extraLarge
        }
    }
}

enum BackgroundDimming {
    // Increase Contrast never dims less than `LabelContrast.increasedDimOpacity`,
    // so white labels stay readable whatever the setting.
    static func opacity(_ dimming: Double, increasedContrast: Bool) -> Double {
        increasedContrast ? max(dimming, LabelContrast.increasedDimOpacity) : dimming
    }
}
