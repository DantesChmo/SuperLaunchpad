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
}
