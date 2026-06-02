# Tests — agent notes

Framework: **swift-testing** (`import Testing`). Not XCTest. If you see `XCTestCase` / `XCTAssert` — replace it.

## Skeleton

```swift
import Testing
@testable import SuperLaunchpad

@MainActor
struct LaunchpadViewModelStateTests {
    @Test func showSetsIsVisible() throws {
        let vm = LaunchpadViewModel(database: makeTempDB())
        vm.show()
        #expect(vm.isVisible == true)
    }
}
```

## Rules

- `@MainActor` on any suite touching `LaunchpadViewModel` (it's `@MainActor`-isolated).
- `throws` on the test function — let errors surface, don't `try?` inside a test.
- One fresh on-disk SQLite per test via `makeTempDB()` (see `AppDatabaseTests.swift`). Clean up with `defer { try? FileManager.default.removeItem(at: url) }`. Never share a DB between tests.
- Small private fixture helpers inside the test struct, e.g. `func app(_ id: String = "com.test.app", page: Int = 0, order: Int = 0) -> AppEntry { … }`. No fixture framework.
- Assertions: `#expect(...)` for non-fatal, `#require(...)` only when later code depends on the value being non-nil.
- Parameterize via `@Test(arguments: [...])` instead of for-loops where it helps clarity.

## Running

```bash
# whole suite
xcodebuild -project ../SuperLaunchpad.xcodeproj -scheme SuperLaunchpad test

# single test
xcodebuild -project ../SuperLaunchpad.xcodeproj -scheme SuperLaunchpad test \
  -only-testing:SuperLaunchpadTests/AppDatabaseTests/saveAppsUpsertsByBundleIdentifier
```

## Don't

- ❌ Mock `AppDatabase`. Use the real GRDB with `makeTempDB()` — migrations must run.
- ❌ Test through `LaunchpadPanel` / AppKit. Keep tests at the ViewModel and DB layer.
- ❌ Rely on `/Applications` contents (CI doesn't have your apps). Inject `AppEntry` fixtures.
- ❌ Add `sleep` / timing-based assertions. If you need async, use swift-testing's `await` + `confirmation`.
