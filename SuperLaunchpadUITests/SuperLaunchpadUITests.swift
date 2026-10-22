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

        // `click()`, not `tap()`: after the Escape below, a synthesized tap
        // no longer reaches the title's tap gesture, while a click does.

        // Escape cancels the edit but keeps the folder open.
        title.click()
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
        let debug = app.descendants(matching: .any).matching(identifier: "rename-debug").firstMatch
        func dbg(_ tag: String) { print("RENAME-DEBUG \(tag): field=\(field.exists) fr=\(String(describing: app.windows.firstMatch.value)) log=[\(debug.exists ? String(describing: debug.value) : "<none>")]") }
        dbg("after escape")
        title.click()
        _ = field.waitForExistence(timeout: 2)
        dbg("after click 1")
        if !field.exists {
            title.click()
            _ = field.waitForExistence(timeout: 2)
            dbg("after click 2")
        }
        if !field.exists {
            title.click()
            _ = field.waitForExistence(timeout: 2)
            dbg("after click 3")
        }
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.typeKey(.rightArrow, modifierFlags: [])
        field.typeText(suffix)
        field.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        XCTAssertEqual(title.label, originalTitle + suffix)

        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = "folder-renamed"
        attachment.lifetime = .keepAlways
        add(attachment)

        // The open popup is modal, so the grid is hidden from accessibility:
        // close the folder to check its tile, then open it again.
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForNonExistence(of: detail), "Escape did not close the folder.")
        let renamedTile = app.buttons
            .matching(NSPredicate(format: "identifier == 'folder-icon' AND label == %@", originalTitle + suffix))
            .firstMatch
        XCTAssertTrue(renamedTile.waitForExistence(timeout: 2), "The folder tile on the grid kept the old title.")
        renamedTile.click()
        XCTAssertTrue(detail.waitForExistence(timeout: 2), "Folder detail did not reopen.")
        XCTAssertTrue(title.waitForExistence(timeout: 2))

        // A blank title reverts.
        title.click()
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.typeKey(.delete, modifierFlags: [])
        field.typeText(" ")
        field.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        XCTAssertEqual(title.label, originalTitle + suffix)

        // Trailing whitespace is trimmed; clicking the card commits.
        title.click()
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
