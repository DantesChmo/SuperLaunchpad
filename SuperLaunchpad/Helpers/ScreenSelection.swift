import CoreGraphics

// Picks the display the launcher should cover. Pure: `LaunchpadPanel` passes
// `NSScreen.screens` as plain values (global coordinates, origin bottom-left,
// first entry = menu-bar screen), so this is testable without real displays.
enum ScreenSelection {
    struct Display: Equatable {
        let id: UInt32
        let frame: CGRect
    }

    // Index of the display under `point` (the mouse cursor). `CGRect.contains`
    // excludes the max edges, and the cursor can sit exactly on an outer top or
    // right edge, so a point on no display goes to the nearest one. Ties go to
    // the earlier entry. `nil` only when there are no displays.
    static func index(at point: CGPoint, in displays: [Display]) -> Int? {
        if let hit = displays.firstIndex(where: { $0.frame.contains(point) }) {
            return hit
        }
        return displays.indices.min { distance(from: point, to: displays[$0].frame) < distance(from: point, to: displays[$1].frame) }
    }

    // After a display change (plug, unplug, resolution, arrangement): stay on
    // the current display if it is still connected — its frame may be new —
    // otherwise move to the display under `point`.
    static func indexAfterChange(currentID: UInt32?, point: CGPoint, in displays: [Display]) -> Int? {
        if let currentID, let kept = displays.firstIndex(where: { $0.id == currentID }) {
            return kept
        }
        return index(at: point, in: displays)
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}
