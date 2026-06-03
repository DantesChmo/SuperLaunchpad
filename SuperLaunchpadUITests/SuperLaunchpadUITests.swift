import XCTest

// XCUITest is the one exception to the "no XCTest" rule in AGENTS.md:
// swift-testing does not yet drive XCUI. XCUI tests live here;
// swift-testing tests live in SuperLaunchpadTests/.

final class SuperLaunchpadUITests: XCTestCase {
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
        let icons = app.buttons.matching(identifier: "app-icon")
        XCTAssertGreaterThan(
            icons.count, 0,
            "Expected at least one app-icon in the grid."
        )
    }
}
