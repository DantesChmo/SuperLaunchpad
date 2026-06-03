# SuperLaunchpadUITests

XCUITest target for SuperLaunchpad — functional UI tests that drive the actual app via the accessibility tree.

## Why a separate directory

- `SuperLaunchpadTests/` uses **swift-testing** (`import Testing`, `@Test`, `#expect`) for unit-level coverage of ViewModels, DB, Services.
- `SuperLaunchpadUITests/` uses **XCUITest** (`import XCTest`, `XCUIApplication`) — the only exception to the "no XCTest" rule in `AGENTS.md`. swift-testing cannot drive XCUI as of Xcode 16.

The two never share infrastructure. Unit tests run in seconds; UI tests run in tens of seconds. CI runs both (see `.github/workflows/ci.yml`).

## Status

The XCUITest target is already registered in `SuperLaunchpad.xcodeproj` and the scheme already runs it under **Test**. CI runs `-only-testing:SuperLaunchpadUITests` on every PR (see `.github/workflows/ci.yml`). Just add `.swift` files to this directory and to the target's **Build Phases ▸ Compile Sources** in Xcode.

The default Xcode boilerplate has been replaced with two meaningful tests in `SuperLaunchpadUITests.swift`:

- `testAppLaunchesAndShowsWindow` — asserts the launcher window appears within 5 s; attaches a screenshot.
- `testGridShowsAtLeastOneApp` — queries icons by `accessibilityIdentifier("app-icon")` (see below).

`SuperLaunchpadUITestsLaunchTests.swift` remains as the Xcode-default launch performance baseline.

## Required app-side changes to make tests stable

The sample test in `SuperLaunchpadUITests.swift` queries icons via `.accessibilityIdentifier("app-icon")`. SwiftUI views must set the identifier explicitly — without it, the query returns 0 elements and the test fails meaninglessly.

Add to `Views/AppIconView.swift`:

```swift
.accessibilityIdentifier("app-icon")
.accessibilityLabel(app.displayName)
```

Same pattern for `FolderIconView` (`"folder-icon"`), the main grid (`"launchpad-grid"`), etc. The `qa-engineer` skill (`.claude/skills/qa-engineer/SKILL.md`) explains why identifiers, not display names, are the right query primitive.

## Adding more UI tests

- Keep each test focused on one user-observable flow. "App launches and shows grid" is one test; "Pinch shows the window" is another.
- Wait on `waitForExistence(timeout:)` / `XCTNSPredicateExpectation`, never `Thread.sleep`.
- Attach a screenshot of the failing window state — when CI fails on a UI test, the screenshot is the only way to diagnose remotely.
- Performance baselines: `measure(metrics: [XCTApplicationLaunchMetric()]) { … }` for launch-time / scroll regression.

See `qa-engineer` skill → "XCUITest for macOS" for the full reference.
