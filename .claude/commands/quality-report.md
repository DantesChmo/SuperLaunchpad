---
description: Snapshot of project test-health — coverage, disabled/known-issue tests, files without test pairs, recent test churn
argument-hint: (optional) area to focus on, e.g. "ViewModels", "Database"
---

Produce a quality snapshot of the test suite for the current branch. This is read-only analysis — no edits.

Run the following checks directly via Bash (no subagent needed — this is mechanical extraction, not judgment):

### 1. Test inventory

```bash
# Total swift-testing test count
grep -rEn '^\s*@Test\b' SuperLaunchpadTests/ | wc -l

# XCUI tests (if target present)
find SuperLaunchpadUITests -name '*.swift' 2>/dev/null | xargs grep -En 'func test[A-Z]' 2>/dev/null | wc -l
```

### 2. Disabled / known-issue tests

```bash
# Tests explicitly disabled (with reasons)
grep -rEn '@Test\(\s*\.disabled' SuperLaunchpadTests/

# Tests wrapping known-broken behaviour
grep -rEn 'withKnownIssue' SuperLaunchpadTests/

# XCTSkip / fatalError pretending to be a test
grep -rEn 'XCTSkip|XCTFail|fatalError' SuperLaunchpadTests/ SuperLaunchpadUITests/ 2>/dev/null
```

For each hit, list `file:line` + the reason string (if present).

### 3. Files without test pairs

For each `.swift` file in `SuperLaunchpad/{Models,Services,Database,ViewModels,Helpers}/`, check whether a file named `<BaseName>Tests.swift` (or any test referencing the type) exists in `SuperLaunchpadTests/`:

```bash
for src in SuperLaunchpad/{Models,Services,Database,ViewModels,Helpers}/*.swift; do
  base=$(basename "$src" .swift)
  # Skip pure namespaces / extensions
  if [ "$base" = "Constants" ] || [ "$base" = "NSImageExtensions" ]; then continue; fi
  if ! grep -rEq "(class|struct|extension|@MainActor)\s+${base}\b" SuperLaunchpadTests/ 2>/dev/null \
     && ! grep -rEq "\b${base}\b" SuperLaunchpadTests/ 2>/dev/null; then
    echo "no tests reference: $src"
  fi
done
```

This is a *heuristic*. Views/ is intentionally not in the list because SwiftUI views are tested via XCUI, not unit tests.

### 4. Recently churned tests (flaky-test signal)

Tests modified in last 20 commits — high churn often correlates with flakiness:

```bash
git log --pretty=format: --name-only -n 20 -- SuperLaunchpadTests/ \
  | grep '\.swift$' | sort | uniq -c | sort -rn | head -10
```

### 5. Coverage (optional, slow)

If `$ARGUMENTS` includes `--coverage` or the user asks for coverage explicitly:

```bash
xcodebuild -project SuperLaunchpad.xcodeproj -scheme SuperLaunchpad \
  test -enableCodeCoverage YES -resultBundlePath /tmp/qa-coverage.xcresult \
  -quiet 2>/dev/null

xcrun xccov view --report --only-targets /tmp/qa-coverage.xcresult
```

This takes ≥30 s. Skip by default; only run when explicitly requested.

### Report shape

```
SuperLaunchpad quality report — <branch>

Test inventory
  swift-testing: 47 tests across 8 suites
  XCUITest:      5 tests
  
Disabled / known-issue
  SuperLaunchpadTests/FolderRenameTests.swift:22  @Test(.disabled("FB12345"))
  SuperLaunchpadTests/AppDatabaseTests.swift:140 withKnownIssue (folder mutation)

Files without test pairs
  SuperLaunchpad/Services/AppDirectoryWatcher.swift
  SuperLaunchpad/Helpers/NSImageExtensions.swift  (skipped: extension-only)

Recently churned tests (top 5)
  4× LaunchpadViewModelTests.swift   ← inspect for flakiness
  3× AppDatabaseTests.swift
  ...

Coverage  (skipped — pass --coverage to enable)
```

Filter by `$ARGUMENTS` area if provided (e.g., "ViewModels" → only list ViewModel-related files / tests / churn).

End with a short paragraph: any items that look concerning (long-disabled tests, frequently-churning tests, gaping coverage holes) and a single suggested next action (e.g., "FolderRenameTests has been disabled for 60 days — either re-enable or `withKnownIssue` it with a tracking link").

Do not modify any files. Do not run regression flows here — that's `/regression-check`.

$ARGUMENTS
