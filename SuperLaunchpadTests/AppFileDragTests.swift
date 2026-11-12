import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import SuperLaunchpad

// Outside edit mode an icon drags as its .app file (to keep it in the Dock);
// only edit mode moves icons on the grid.
@MainActor
struct AppFileDragTests {

    // 7×5 cells of 100×80 on a 1000 pt page: slot 0 is centered at (200, 40).
    private func context(_ pages: [[LaunchpadItem]]) -> GridDragController.GridContext {
        GridDragController.GridContext(
            pages: pages,
            page: 0,
            geometry: GridGeometry(
                columns: 7,
                rows: 5,
                cellSize: CGSize(width: 100, height: 80),
                rowSpacing: 10,
                hitSize: CGSize(width: 50, height: 60),
                pageWidth: 1000
            ),
            frame: CGRect(x: 0, y: 0, width: 1000, height: 600),
            pagerPosition: 0
        )
    }

    private func entry(_ id: String) -> AppEntry {
        AppEntry(bundleIdentifier: id, displayName: id, appPath: "/Applications/\(id).app", pageIndex: 0, orderIndex: 0)
    }

    @Test func outsideEditModeAnIconIsNotLifted() {
        let controller = GridDragController()
        let pages = [["a", "b"].map { LaunchpadItem.app(entry($0)) }]

        let lifted = controller.update(
            start: CGPoint(x: 200, y: 40),
            pointer: CGPoint(x: 260, y: 40),
            grid: context(pages),
            canLift: false,
            flipPage: { _ in nil }
        )

        #expect(!lifted)
        #expect(controller.session == nil)
        // The click that started it is the file drag's, not a grid move.
        #expect(!controller.isTapSuppressed)
    }

    @Test func theRestOfAnIgnoredGestureLiftsNothing() {
        let controller = GridDragController()
        let pages = [["a", "b"].map { LaunchpadItem.app(entry($0)) }]
        controller.update(start: CGPoint(x: 200, y: 40), pointer: CGPoint(x: 230, y: 40), grid: context(pages), canLift: false, flipPage: { _ in nil })

        // Edit mode turning on mid-gesture doesn't pick the icon up.
        let lifted = controller.update(start: CGPoint(x: 200, y: 40), pointer: CGPoint(x: 300, y: 40), grid: context(pages), canLift: true, flipPage: { _ in nil })

        #expect(!lifted)
        #expect(controller.session == nil)
        #expect(controller.end { _ in nil } == nil)
    }

    @Test func inEditModeTheSameDragLiftsTheIcon() {
        let controller = GridDragController()
        let pages = [["a", "b"].map { LaunchpadItem.app(entry($0)) }]

        let lifted = controller.update(start: CGPoint(x: 200, y: 40), pointer: CGPoint(x: 260, y: 40), grid: context(pages), canLift: true, flipPage: { _ in nil })

        #expect(lifted)
        #expect(controller.session?.itemID == "a")
        controller.cancel()
    }

    @Test func theDragCarriesTheAppBundleURL() async throws {
        let app = entry("Notes")
        let provider = AppFileDrag.itemProvider(for: app)

        #expect(provider.suggestedName == "Notes")
        #expect(provider.canLoadObject(ofClass: NSURL.self))
        let url: URL = try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                }
            }
        }
        #expect(url == URL(fileURLWithPath: "/Applications/Notes.app"))
        #expect(url.isFileURL)
    }
}
