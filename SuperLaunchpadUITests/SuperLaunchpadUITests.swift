import XCTest

// XCUITest is the one exception to the "no XCTest" rule in AGENTS.md:
// swift-testing does not yet drive XCUI. XCUI tests live here;
// swift-testing tests live in SuperLaunchpadTests/.

final class SuperLaunchpadUITests: XCTestCase {
    private static let maxPagesToSearch = 5
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "YES"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    @MainActor
    func testAppLaunchesAndShowsWindow() throws {
        let window = app.windows.firstMatch
        XCTAssertTrue(
            window.waitForExistence(timeout: 5),
            "Launcher window did not appear within 5s of launch."
        )

        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = "launcher-on-launch"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testGridShowsAtLeastOneApp() throws {
        let window = app.windows.firstMatch
        _ = window.waitForExistence(timeout: 5)

        // Query depends on .accessibilityIdentifier("app-icon") being set on
        // AppIconView. If this fails with "0 elements", add the identifier in
        // Views/AppIconView.swift — see qa-engineer skill: "Accessibility
        // identifiers — the only stable query".
        // `loadApps()` runs the `/Applications` scan in a `Task.detached`, so
        // icons don't appear synchronously with the window. Counting buttons
        // immediately after `window.waitForExistence` races the scan and
        // reports 0. Wait on `firstMatch.waitForExistence` instead — XCUI
        // re-evaluates the query on each poll, so it picks up icons as soon
        // as the detached task hops back to MainActor.
        let icons = app.buttons.matching(identifier: "app-icon")
        XCTAssertTrue(
            icons.firstMatch.waitForExistence(timeout: 15),
            "Expected at least one app-icon in the grid within 15s of launch."
        )
    }

    @MainActor
    func testTappingFolderOpensFolderDetail() throws {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))

        // UI tests run on a fresh DB, so the first-launch layout applies and
        // always produces folders (at least Apple's Utilities). They may sit
        // on a later page, and off-screen pages are still in the
        // accessibility tree, so page right until one is hittable.
        let folders = app.buttons.matching(identifier: "folder-icon")
        XCTAssertTrue(folders.firstMatch.waitForExistence(timeout: 5), "No folders in the first-launch layout.")

        var folder = folders.allElementsBoundByIndex.first(where: \.isHittable)
        for _ in 0..<Self.maxPagesToSearch where folder == nil {
            app.typeKey(.rightArrow, modifierFlags: [])
            folder = folders.allElementsBoundByIndex.first(where: \.isHittable)
        }
        let target = try XCTUnwrap(folder, "No folder became hittable after paging.")
        target.tap()

        let detail = app.descendants(matching: .any)
            .matching(identifier: "folder-detail").firstMatch
        XCTAssertTrue(
            detail.waitForExistence(timeout: 2),
            "Folder detail did not appear after tapping a folder."
        )

        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = "folder-detail-open"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
