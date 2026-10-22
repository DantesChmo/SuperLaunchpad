import CoreGraphics
import Testing
@testable import SuperLaunchpad

struct DockInsetsTests {

    // A 1512×982 screen with a 24 pt menu bar.
    private let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let menuBar: CGFloat = 24

    @Test func bottomDock() {
        let visible = CGRect(x: 0, y: 80, width: 1512, height: 982 - 80 - menuBar)
        #expect(DockInsets(frame: frame, visibleFrame: visible) == insets(bottom: 80))
    }

    @Test func leftDock() {
        let visible = CGRect(x: 70, y: 0, width: 1512 - 70, height: 982 - menuBar)
        #expect(DockInsets(frame: frame, visibleFrame: visible) == insets(left: 70))
    }

    @Test func rightDock() {
        let visible = CGRect(x: 0, y: 0, width: 1512 - 70, height: 982 - menuBar)
        #expect(DockInsets(frame: frame, visibleFrame: visible) == insets(right: 70))
    }

    @Test func menuBarAloneLeavesNoInsets() {
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 982 - menuBar)
        #expect(DockInsets(frame: frame, visibleFrame: visible) == .zero)
    }

    // A secondary display has a non-zero origin; only the differences count.
    @Test func secondaryDisplayWithBottomDock() {
        let external = CGRect(x: 1512, y: -200, width: 2560, height: 1440)
        let visible = CGRect(x: 1512, y: -200 + 90, width: 2560, height: 1440 - 90 - menuBar)
        #expect(DockInsets(frame: external, visibleFrame: visible) == insets(bottom: 90))
    }

    // Expected insets, built through the same initializer from a 1000×1000
    // screen with those edges cut off.
    private func insets(left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0) -> DockInsets {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let visible = CGRect(x: left, y: bottom, width: 1000 - left - right, height: 1000 - bottom)
        return DockInsets(frame: screen, visibleFrame: visible)
    }
}
