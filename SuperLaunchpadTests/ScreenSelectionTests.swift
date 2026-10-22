import CoreGraphics
import Testing
@testable import SuperLaunchpad

struct ScreenSelectionTests {

    // Built-in 1512×982 with the menu bar, an external 2560×1440 to its right
    // (bottoms aligned), and a 1920×1080 above the built-in.
    private let builtIn = ScreenSelection.Display(id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982))
    private let right = ScreenSelection.Display(id: 2, frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440))
    private let above = ScreenSelection.Display(id: 3, frame: CGRect(x: 0, y: 982, width: 1920, height: 1080))

    private var displays: [ScreenSelection.Display] { [builtIn, right, above] }

    // MARK: - Screen under the cursor

    @Test(arguments: [
        (CGPoint(x: 700, y: 500), 0),
        (CGPoint(x: 3000, y: 1200), 1),
        (CGPoint(x: 100, y: 1500), 2),
        // Shared edges belong to the display whose min edge they are.
        (CGPoint(x: 1512, y: 100), 1),
        (CGPoint(x: 100, y: 982), 2),
        (CGPoint(x: 0, y: 0), 0),
    ])
    func picksDisplayUnderCursor(point: CGPoint, expected: Int) {
        #expect(ScreenSelection.index(at: point, in: displays) == expected)
    }

    @Test(arguments: [
        // Outer right edge of the external display (`contains` excludes maxX).
        (CGPoint(x: 4072, y: 700), 1),
        // Outer top edge of the display above.
        (CGPoint(x: 500, y: 2062), 2),
        // In the gap right of the display above, closer to it than to `right`.
        (CGPoint(x: 2000, y: 1900), 2),
    ])
    func pointOnNoDisplayGoesToNearest(point: CGPoint, expected: Int) {
        #expect(ScreenSelection.index(at: point, in: displays) == expected)
    }

    @Test func singleDisplayAlwaysWins() {
        #expect(ScreenSelection.index(at: CGPoint(x: -500, y: 5000), in: [builtIn]) == 0)
    }

    @Test func noDisplaysGivesNil() {
        #expect(ScreenSelection.index(at: .zero, in: []) == nil)
        #expect(ScreenSelection.indexAfterChange(currentID: 1, point: .zero, in: []) == nil)
    }

    // MARK: - Display changes

    @Test func staysOnCurrentDisplayAfterResolutionChange() {
        let resized = ScreenSelection.Display(id: 2, frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080))
        let index = ScreenSelection.indexAfterChange(
            currentID: 2,
            point: CGPoint(x: 700, y: 500),
            in: [builtIn, resized]
        )
        #expect(index == 1)
    }

    @Test func staysOnCurrentDisplayWhenAnotherIsPlugged() {
        let index = ScreenSelection.indexAfterChange(
            currentID: 1,
            point: CGPoint(x: 3000, y: 500),
            in: displays
        )
        #expect(index == 0)
    }

    @Test func movesUnderCursorWhenCurrentDisplayIsUnplugged() {
        let index = ScreenSelection.indexAfterChange(
            currentID: 2,
            point: CGPoint(x: 100, y: 1500),
            in: [builtIn, above]
        )
        #expect(index == 1)
    }

    @Test func unknownCurrentDisplayFallsBackToCursor() {
        let index = ScreenSelection.indexAfterChange(currentID: nil, point: CGPoint(x: 3000, y: 100), in: displays)
        #expect(index == 1)
    }
}
