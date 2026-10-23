import Foundation
import Testing
@testable import SuperLaunchpad

struct PreferencesTests {

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "PreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return (defaults, suiteName)
    }

    @Test func pinchGestureEnabledDefaultsToTrue() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = Preferences(defaults: defaults)

        #expect(preferences.pinchGestureEnabled == Preferences.Default.pinchGestureEnabled)
        #expect(preferences.pinchGestureEnabled == true)
    }

    @Test func pinchGestureEnabledRoundTrips() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        Preferences(defaults: defaults).pinchGestureEnabled = false

        #expect(Preferences(defaults: defaults).pinchGestureEnabled == false)
        #expect(defaults.bool(forKey: Preferences.Key.pinchGestureEnabled) == false)
    }

    @Test func storedValueWinsOverRegisteredDefault() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: Preferences.Key.pinchGestureEnabled)

        let preferences = Preferences(defaults: defaults)

        #expect(preferences.pinchGestureEnabled == false)
    }

    @Test func newAppPlacementDefaultsToEndAndRoundTrips() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(Preferences(defaults: defaults).newAppPlacement == .end)
        Preferences(defaults: defaults).newAppPlacement = .newFolder
        #expect(Preferences(defaults: defaults).newAppPlacement == .newFolder)
    }

    @Test func unknownNewAppPlacementFallsBackToDefault() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("somewhere", forKey: Preferences.Key.newAppPlacement)

        #expect(Preferences(defaults: defaults).newAppPlacement == Preferences.Default.newAppPlacement)
    }

    @Test func showsFrequentAppsDefaultsToOffAndRoundTrips() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(Preferences(defaults: defaults).showsFrequentApps == false)
        Preferences(defaults: defaults).showsFrequentApps = true
        #expect(Preferences(defaults: defaults).showsFrequentApps == true)
    }

    // MARK: - Appearance

    @Test func appearanceDefaultsAreTheOriginalLook() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = Preferences(defaults: defaults)

        #expect(preferences.backgroundStyle == .desktop)
        #expect(preferences.backgroundBlur == 1)
        #expect(preferences.backgroundDimming == LabelContrast.dimOpacity)
        #expect(preferences.labelSize == .medium)
        #expect(preferences.hidesLabels == false)
    }

    @Test func appearanceRoundTrips() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = Preferences(defaults: defaults)
        preferences.backgroundStyle = .wallpaper
        preferences.backgroundBlur = 0.4
        preferences.backgroundDimming = 0.6
        preferences.labelSize = .extraLarge
        preferences.hidesLabels = true

        let reread = Preferences(defaults: defaults)
        #expect(reread.backgroundStyle == .wallpaper)
        #expect(reread.backgroundBlur == 0.4)
        #expect(reread.backgroundDimming == 0.6)
        #expect(reread.labelSize == .extraLarge)
        #expect(reread.hidesLabels == true)
    }

    // `@AppStorage` in the views writes the same keys, so they must store
    // plain values: raw strings for the enums.
    @Test func appearanceIsStoredUnderItsKeys() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = Preferences(defaults: defaults)
        preferences.backgroundStyle = .wallpaper
        preferences.labelSize = .small

        #expect(defaults.string(forKey: Preferences.Key.backgroundStyle) == "wallpaper")
        #expect(defaults.string(forKey: Preferences.Key.labelSize) == "small")
    }

    @Test func unknownAppearanceValuesFallBackToDefaults() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("aurora", forKey: Preferences.Key.backgroundStyle)
        defaults.set("huge", forKey: Preferences.Key.labelSize)

        let preferences = Preferences(defaults: defaults)

        #expect(preferences.backgroundStyle == Preferences.Default.backgroundStyle)
        #expect(preferences.labelSize == Preferences.Default.labelSize)
    }

    @Test func outOfRangeBlurAndDimmingAreClamped() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(3.0, forKey: Preferences.Key.backgroundBlur)
        defaults.set(-1.0, forKey: Preferences.Key.backgroundDimming)

        let preferences = Preferences(defaults: defaults)
        #expect(preferences.backgroundBlur == 1)
        #expect(preferences.backgroundDimming == 0)

        defaults.set(2.0, forKey: Preferences.Key.backgroundDimming)
        #expect(preferences.backgroundDimming == BackgroundAppearance.maxDimming)
    }
}
