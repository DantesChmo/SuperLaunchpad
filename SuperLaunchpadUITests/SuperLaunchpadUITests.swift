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
    func testRenamingFolderInline() throws {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))

        // Same environment caveat as `testTappingFolderOpensFolderDetail`.
        let folders = app.buttons.matching(identifier: "folder-icon")
        guard folders.firstMatch.waitForExistence(timeout: 3) else {
            throw XCTSkip("No folders present — system DB had no folder import.")
        }
        let detail = app.descendants(matching: .any).matching(identifier: "folder-detail").firstMatch
        let title = app.descendants(matching: .any).matching(identifier: "folder-title").firstMatch
        let field = app.textFields.matching(identifier: "folder-title-field").firstMatch
        // Right after launch a click can land while the grid is still being
        // rebuilt by the first rescan and get lost, so retry it.
        for _ in 0..<3 where !detail.exists {
            folders.firstMatch.tap()
            _ = detail.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(detail.exists, "Folder detail did not open.")
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        let originalTitle = title.label

        // Typed text sticks to digits and single spaces: XCUI drops letters
        // the active keyboard layout cannot produce (e.g. a Cyrillic one), and
        // macOS turns a double space into ". ".

        // Escape cancels the edit but keeps the folder open.
        title.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.typeText("123")
        XCTAssertEqual(field.value as? String, "123", "The title was not selected when editing began.")
        field.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        XCTAssertEqual(title.label, originalTitle)
        XCTAssertTrue(detail.exists, "Escape while renaming closed the folder.")

        // Enter commits. Edits only append and delete, so the test ends with
        // the original name in the real launcher DB.
        let suffix = " 2026"
        title.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.typeKey(.rightArrow, modifierFlags: [])
        field.typeText(suffix)
        field.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        XCTAssertEqual(title.label, originalTitle + suffix)
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "identifier == 'folder-icon' AND label == %@", originalTitle + suffix))
                .firstMatch.exists,
            "The folder tile on the grid kept the old title."
        )

        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = "folder-renamed"
        attachment.lifetime = .keepAlways
        add(attachment)

        // A blank title reverts.
        title.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.typeKey(.delete, modifierFlags: [])
        field.typeText(" ")
        field.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        XCTAssertEqual(title.label, originalTitle + suffix)

        // Trailing whitespace is trimmed; clicking the card commits.
        title.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.typeKey(.rightArrow, modifierFlags: [])
        for _ in 0..<suffix.count {
            field.typeKey(.delete, modifierFlags: [])
        }
        field.typeText(" ")
        // The card's padding corner, away from any app icon.
        detail.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.03)).click()
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        XCTAssertEqual(title.label, originalTitle)
    }
}
