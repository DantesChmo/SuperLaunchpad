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

        // Folders only exist if the system Launchpad DB was imported (first
        // launch) or apps were assigned to folders by hand. On a fresh CI
        // box `/Applications` is mostly system apps with no folder data, so
        // the launcher may have zero folders — skip rather than fail in
        // that environment.
        let folders = app.buttons.matching(identifier: "folder-icon")
        guard folders.firstMatch.waitForExistence(timeout: 3) else {
            throw XCTSkip("No folders present — system DB had no folder import.")
        }

        folders.firstMatch.tap()

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

    @MainActor
    func testSearchQueryAndReturnLaunchesTopResult() throws {
        let calculator = XCUIApplication(bundleIdentifier: "com.apple.calculator")
        addTeardownBlock { @MainActor in calculator.terminate() }
        // The bundle file name matches even under a non-English display name.
        let field = try relaunchWithQuery("Calculator")

        let results = app.descendants(matching: .any).matching(identifier: "search-results").firstMatch
        XCTAssertTrue(results.waitForExistence(timeout: 5), "Search results did not replace the grid.")
        // Each cell exposes its icon and its label as "app-icon" elements.
        let labels = results.buttons.matching(identifier: "app-icon").allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(Set(labels).count, 1, "Expected exactly one matching app, got \(Set(labels)).")
        XCTAssertEqual(field.value as? String, "Calculator")

        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "search-results"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.typeKey(.return, modifierFlags: [])
        // Running, not necessarily frontmost yet: activation can lag on a busy machine.
        let launched = expectation(
            for: NSPredicate(format: "state >= %d", XCUIApplication.State.runningBackground.rawValue),
            evaluatedWith: calculator
        )
        XCTAssertEqual(XCTWaiter.wait(for: [launched], timeout: 15), .completed, "Return did not launch the selected result.")
        XCTAssertTrue(waitForNonExistence(of: results), "Launcher did not hide after launching.")
    }

    @MainActor
    func testEscapeClearsQueryThenHidesLauncher() throws {
        let field = try relaunchWithQuery("Calculator")
        let results = app.descendants(matching: .any).matching(identifier: "search-results").firstMatch
        XCTAssertTrue(results.waitForExistence(timeout: 5))

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForNonExistence(of: results), "First Escape did not clear the query.")
        XCTAssertEqual(field.value as? String, "")
        XCTAssertTrue(
            app.buttons.matching(identifier: "app-icon").firstMatch.waitForExistence(timeout: 2),
            "Grid did not come back."
        )

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(
            waitForNonExistence(of: app.buttons.matching(identifier: "app-icon").firstMatch),
            "Second Escape did not hide the launcher."
        )
    }

    // MARK: - Helpers

    // The query is passed in rather than typed: with a non-Latin keyboard
    // layout (e.g. Russian only) XCUI sends Latin letters as ⌘+key, which the
    // field treats as shortcuts. Returns the search field once it has focus
    // (the user types straight away) and the scan has filled the results.
    private func relaunchWithQuery(_ query: String) throws -> XCUIElement {
        app.terminate()
        app.launchArguments = ["-UITestMode", "YES", "-UITestSearchQuery", query]
        app.launch()

        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value(forKey: "hasKeyboardFocus") as? Bool, true)
        // Results appear once the background scan has delivered the apps.
        XCTAssertTrue(app.buttons.matching(identifier: "app-icon").firstMatch.waitForExistence(timeout: 15))
        // XCUI does not activate the launcher on its own; the click does, so
        // the keys below reach it.
        field.click()
        return field
    }

    private func waitForNonExistence(of element: XCUIElement) -> Bool {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        return XCTWaiter.wait(for: [gone], timeout: 3) == .completed
    }
}
