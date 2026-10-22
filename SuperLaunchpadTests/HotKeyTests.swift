import AppKit
import Carbon.HIToolbox
import Testing
@testable import SuperLaunchpad

struct HotKeyTests {

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "HotKeyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return (defaults, suiteName)
    }

    // MARK: - Modifier conversion

    private static let modifierCases: [(NSEvent.ModifierFlags, UInt32)] = [
        (.command, UInt32(cmdKey)),
        (.option, UInt32(optionKey)),
        (.control, UInt32(controlKey)),
        (.shift, UInt32(shiftKey)),
        ([.command, .option], UInt32(cmdKey | optionKey)),
        ([.control, .option, .shift, .command], UInt32(controlKey | optionKey | shiftKey | cmdKey)),
        ([], 0),
    ]

    @Test(arguments: modifierCases)
    func carbonModifiersMatchFlags(flags: NSEvent.ModifierFlags, expected: UInt32) {
        #expect(KeyCombo.carbonModifiers(from: flags) == expected)
    }

    @Test func carbonModifiersIgnoreNonModifierFlags() {
        let flags: NSEvent.ModifierFlags = [.command, .capsLock, .function, .numericPad]
        #expect(KeyCombo.carbonModifiers(from: flags) == UInt32(cmdKey))
    }

    // MARK: - Validity

    @Test func comboNeedsPrimaryModifier() {
        #expect(KeyCombo(keyCode: UInt32(kVK_ANSI_L), modifiers: 0).isValidHotKey == false)
        #expect(KeyCombo(keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(shiftKey)).isValidHotKey == false)
        #expect(KeyCombo(keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(controlKey)).isValidHotKey == true)
        #expect(KeyCombo.default.isValidHotKey == true)
    }

    @Test func functionKeyIsValidWithoutModifiers() {
        #expect(KeyCombo(keyCode: UInt32(kVK_F5), modifiers: 0).isValidHotKey == true)
    }

    // MARK: - Display

    @Test func displayStringOrdersModifiersLikeMenus() {
        let combo = KeyCombo(keyCode: UInt32(kVK_F5), modifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey))
        #expect(combo.displayString == "⌃⌥⇧⌘F5")
    }

    @Test func fallbackKeyNameUsesANSITable() {
        #expect(KeyCombo.fallbackKeyName(for: UInt32(kVK_ANSI_L)) == "L")
        #expect(KeyCombo.default.modifierSymbols == "⌥⌘")
    }

    // MARK: - Preferences

    @Test func hotKeyDefaultsToOptionCommandL() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = Preferences(defaults: defaults)

        #expect(preferences.hotKey == Preferences.Default.hotKey)
        #expect(preferences.hotKey == KeyCombo(keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(optionKey | cmdKey)))
    }

    @Test func hotKeyRoundTrips() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let combo = KeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey))

        Preferences(defaults: defaults).hotKey = combo

        #expect(Preferences(defaults: defaults).hotKey == combo)
    }

    @Test func noHotKeyIsStoredAndDoesNotFallBackToDefault() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        Preferences(defaults: defaults).hotKey = nil

        #expect(Preferences(defaults: defaults).hotKey == nil)
        #expect(defaults.integer(forKey: Preferences.Key.hotKeyCode) == HotKey.noKeyCode)
    }

    @Test func hotKeyCanBeRestoredAfterClearing() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = Preferences(defaults: defaults)

        preferences.hotKey = nil
        preferences.hotKey = KeyCombo.default

        #expect(preferences.hotKey == KeyCombo.default)
    }
}
