import Foundation
import Testing
@testable import SuperLaunchpad

struct PinchRecognizerTests {

    // Feeds a whole gesture: `.began` with the first delta, `.changed` for the
    // rest, events `step` seconds apart. Returns every non-`.none` action.
    private func run(
        _ deltas: [CGFloat],
        step: TimeInterval = 0.016,
        visible: Bool,
        recognizer: inout PinchRecognizer
    ) -> [PinchRecognizer.Action] {
        var actions: [PinchRecognizer.Action] = []
        for (i, delta) in deltas.enumerated() {
            let action = recognizer.feed(
                phase: i == 0 ? .began : .changed,
                magnification: delta,
                timestamp: 100 + Double(i) * step,
                isLauncherVisible: visible
            )
            if action != .none { actions.append(action) }
        }
        return actions
    }

    // MARK: - Opening

    @Test func quickStrongPinchInOpens() {
        var r = PinchRecognizer()
        #expect(run(Array(repeating: -0.1, count: 10), visible: false, recognizer: &r) == [.open])
    }

    @Test func pinchInBelowOpenThresholdDoesNothing() {
        // -0.6 would have opened under the old 0.5 threshold.
        var r = PinchRecognizer()
        #expect(run(Array(repeating: -0.1, count: 6), visible: false, recognizer: &r) == [])
    }

    @Test func slowPinchInIsTreatedAsZoom() {
        // Reaches -1.0 in total, but over 1.9 s — past the open window.
        var r = PinchRecognizer()
        #expect(run(Array(repeating: -0.05, count: 20), step: 0.1, visible: false, recognizer: &r) == [])
        #expect(r.isActive == false)
    }

    @Test func pinchOutWhileHiddenDoesNothing() {
        var r = PinchRecognizer()
        #expect(run(Array(repeating: 0.1, count: 10), visible: false, recognizer: &r) == [])
    }

    @Test func opensOnlyOncePerGesture() {
        var r = PinchRecognizer()
        #expect(run(Array(repeating: -0.1, count: 30), visible: false, recognizer: &r) == [.open])
    }

    // MARK: - Closing

    @Test func pinchOutWhileVisibleCloses() {
        var r = PinchRecognizer()
        #expect(run(Array(repeating: 0.1, count: 6), visible: true, recognizer: &r) == [.close])
    }

    @Test func slowPinchOutWhileVisibleStillCloses() {
        // The open window does not apply to closing.
        var r = PinchRecognizer()
        #expect(run(Array(repeating: 0.05, count: 12), step: 0.2, visible: true, recognizer: &r) == [.close])
    }

    @Test func pinchInWhileVisibleDoesNothing() {
        var r = PinchRecognizer()
        #expect(run(Array(repeating: -0.1, count: 10), visible: true, recognizer: &r) == [])
    }

    // MARK: - Gesture boundaries

    @Test func eventsWithoutBeganAreIgnored() {
        var r = PinchRecognizer()
        let action = r.feed(phase: .changed, magnification: -2, timestamp: 0, isLauncherVisible: false)
        #expect(action == .none)
    }

    @Test func endedStopsTheGesture() {
        var r = PinchRecognizer()
        _ = r.feed(phase: .began, magnification: -0.5, timestamp: 0, isLauncherVisible: false)
        _ = r.feed(phase: .ended, magnification: 0, timestamp: 0.1, isLauncherVisible: false)
        #expect(r.isActive == false)
        let action = r.feed(phase: .changed, magnification: -0.5, timestamp: 0.2, isLauncherVisible: false)
        #expect(action == .none)
    }

    @Test func newGestureResetsAccumulator() {
        var r = PinchRecognizer()
        _ = run(Array(repeating: -0.1, count: 6), visible: false, recognizer: &r)
        #expect(run(Array(repeating: -0.1, count: 6), visible: false, recognizer: &r) == [])
        #expect(abs(r.cumulativeMagnification - -0.6) < 0.0001)
    }
}

struct GestureSettingsTests {

    private func makeDefaults() throws -> UserDefaults {
        let name = "GestureSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func pinchGestureEnabledByDefault() throws {
        #expect(GestureMonitor.isEnabled(in: try makeDefaults()) == true)
    }

    @Test func pinchGestureCanBeTurnedOff() throws {
        let defaults = try makeDefaults()
        defaults.set(false, forKey: GestureMonitor.enabledDefaultsKey)
        #expect(GestureMonitor.isEnabled(in: defaults) == false)
    }

    @Test(arguments: [
        ([nil, nil, nil, nil] as [Int?], true),   // never configured → system default (on)
        ([2, 2, 2, 2], true),
        ([0, 0, 0, 0], false),
        ([0, nil, 0, nil], false),
        ([0, 2, nil, nil], true),                 // either trackpad copy on wins
    ])
    func systemPinchGestureDetection(values: [Int?], expected: Bool) {
        #expect(SystemPinchGesture.isEnabled(values: values.map { $0 as Any? }) == expected)
    }
}
