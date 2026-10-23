# AGENTS.md

Instructions for AI coding agents (Claude Code, Cursor, Codex, Aider, Continue, …) working in this repository. Read this first — it's the single source of truth for project conventions and constraints. Skip nothing.

## TL;DR

**SuperLaunchpad** — macOS Launchpad clone. Fullscreen app launcher with a 7×5 grid, paging, trackpad gestures, and ordering imported from the system Launchpad.

- **Language:** Swift 5.0
- **UI:** SwiftUI + AppKit (`NSPanel`, `NSWorkspace`, `NSVisualEffectView`)
- **Database:** GRDB 7.0+ (SQLite)
- **Platform:** macOS 15.4+ (Sequoia)
- **Tests:** swift-testing (`import Testing`) — **not** XCTest
- **Architecture:** MVVM with `@Observable`, single `LaunchpadViewModel` as source of truth

## Build, run, test

**HARD RULE — Always use `xcodebuildmcp` MCP tools. Never run `xcodebuild` via Bash by default.** All build / test / coverage / simulator / device operations MUST route through `mcp__xcodebuildmcp__*` (e.g. `session_show_defaults`, `build_macos`, `test_macos`, `build_run_macos`, `get_coverage_report`). Before the first build/test in a session, call `session_show_defaults` to verify project/scheme/destination — don't assume.

**The only allowed fallback to raw `xcodebuild`** is when the MCP server itself fails to start (binary missing, server crashes, tools not exposed at all). In that case: state explicitly that MCP is unavailable, then use `xcodebuild`. A missing _individual_ capability is not a fallback trigger — ask the user instead.

The project ships an `.mcp.json` that enables the `macos` workflow (plus `simulator`, `ui-automation`, `debugging`, `coverage`, etc.) — so `build_macos` / `test_macos` / `build_run_macos` are available out of the box. Requires `xcodebuildmcp` installed locally (`brew install getsentry/xcodebuildmcp/xcodebuildmcp`).

If macOS tools aren't visible after a restart, check `~/.claude.json > projects > <repo> > mcpServers.xcodebuildmcp.env` — a per-user override there can shadow the repo's `.mcp.json`. The env must include `XCODEBUILDMCP_ENABLED_WORKFLOWS` with `macos` in the list, otherwise only the simulator workflow tools register and the macOS ones silently disappear.

The raw commands below remain valid for CI, scripts, and humans:

```bash
# build
xcodebuild -project SuperLaunchpad.xcodeproj -scheme SuperLaunchpad build

# all tests
xcodebuild -project SuperLaunchpad.xcodeproj -scheme SuperLaunchpad test

# single test (swift-testing filter)
xcodebuild -project SuperLaunchpad.xcodeproj -scheme SuperLaunchpad test \
  -only-testing:SuperLaunchpadTests/AppDatabaseTests/saveAppsUpsertsByBundleIdentifier
```

For UI-affecting changes, open `SuperLaunchpad.xcodeproj` in Xcode and **⌘R** — tests alone don't validate visual behavior.

## Architecture in 60 seconds

`LaunchpadViewModel` (`@Observable`, `@MainActor`) is the single source of truth. `LaunchpadPanel` (`NSPanel`) hosts the SwiftUI hierarchy. `AppDatabase` (GRDB) persists app/folder ordering across launches.

Data flow:

1. `AppDelegate.applicationDidFinishLaunching()` → creates `LaunchpadPanel`, calls `viewModel.loadApps()`.
2. `loadApps()` reads DB cache first, then `Task.detached` scans `/Applications` + `/System/Applications` via `AppEnumerator`, syncs back to `@MainActor`.
3. First launch only: `SystemLaunchpadDB` reads `~/.com.apple.dock.launchpad/db/db` for ordering and folders; otherwise alphabetical fallback.
4. Subsequent launches: existing positions preserved; new apps (no DB row yet) get `isNew` and go where Settings → New Apps says (`Helpers/NewAppPlacement.swift`: end / category folder / "New" folder). The rescan's DB work is the pure-ish `LaunchpadViewModel.syncScan`, testable with a temp DB.
5. `AppDirectoryWatcher` (DispatchSource) triggers `loadApps()` on install/uninstall.
6. `GestureMonitor` listens for global trackpad pinch (threshold 0.5) to show/hide.

**Storage:** `~/Library/Application Support/com.dantes.SuperLaunchpad/apps.db`

## Project map

| Path | Role |
|------|------|
| `SuperLaunchpadApp.swift` | `@main`, `AppDelegate`, `MenuBarExtra` |
| `ViewModels/LaunchpadViewModel.swift` | source of truth — apps, pages, currentPage, show/hide/launch |
| `Models/AppEntry.swift` | GRDB record — bundleIdentifier (PK), pageIndex, orderIndex, folderID, folderOrderIndex, isHidden, isNew (blue dot) |
| `Models/FolderEntry.swift` | GRDB record — id (PK), title, pageIndex, orderIndex |
| `Models/GridItem.swift` | `LaunchpadItem` enum: `.app(AppEntry)` / `.folder(FolderEntry, apps)` |
| `Database/AppDatabase.swift` | SQLite, migrations, CRUD |
| `Views/LaunchpadView.swift` | root, GeometryReader, LayoutMetrics |
| `Views/PagingGridView.swift` | horizontal ScrollView + `SinglePageBehavior` snap |
| `Views/AppGridPageView.swift` | LazyVGrid for one page |
| `Views/AppIconView.swift` | icon + label, hover scale 1.08 |
| `Views/FolderIconView.swift` | 3×3 mini preview |
| `Views/FolderDetailView.swift` | folder popup, 4×3 grid |
| `Views/ItemContextMenu.swift` | right-click menu on app icons and folder tiles, same items as VoiceOver actions |
| `Helpers/ItemMenu.swift` | context-menu items per app / folder and their availability; what a click does by its modifiers |
| `Services/AppOpener.swift` | open an app (in front or in the background), show it in Finder; injectable like `AppTrash.Operations` |
| `Window/LaunchpadPanel.swift` | `NSPanel`, borderless, screenSaver level |
| `Window/VisualEffectBackground.swift` | `NSVisualEffectView` wrapper |
| `Services/AppEnumerator.swift` | scans `/Applications`, extracts 128×128 PNG icons |
| `Services/SystemLaunchpadDB.swift` | parses macOS Launchpad DB |
| `Services/GestureMonitor.swift` | global+local `NSEvent.magnify` monitors |
| `Services/AppDirectoryWatcher.swift` | DispatchSource on `/Applications` |
| `Helpers/Constants.swift` | `Grid`, `FolderGrid`, `AnimationDuration`, `LayoutMetrics` |
| `Helpers/NSImageExtensions.swift` | `pngData()`, `resized(to:)` |
| `Helpers/NewAppPlacement.swift` | Settings → New Apps: where a rescan puts a new app; category folder title matching |
| `SuperLaunchpadTests/` | swift-testing test suites |

## Conventions

### Swift style

- **Naming:** `PascalCase` for types, `camelCase` for methods and properties. No Hungarian notation, no `m_` prefixes.
- **Visibility:** mark members `private` aggressively. Default to `private`, widen only when needed.
- **`// MARK: - …`** to group methods in large classes (`AppDatabase`, `LaunchpadPanel`, `LaunchpadViewModel`).
- **Error handling:** prefer `try?` with an explicit default over `do/catch`:
  ```swift
  let apps = (try? database?.fetchAllApps()) ?? []
  ```
  Only use `do/catch` when the error path needs distinct behavior.
- **No force unwrap (`!`)** except in `lazy` initializers where the value is guaranteed.
- **`guard` for early exits**, not for the happy path.

### SwiftUI

- `LaunchpadViewModel` is the only source of truth. Pass it (or a slice of it) to child views **through parameters** — do not reach for a global singleton.
- `@State` is reserved for **local UI state only** (hover, animation toggles, open/closed flags). Anything persistent or shared lives on the ViewModel.
- `@Bindable` (Swift 5.9+) when a child needs to write back to the `@Observable` model.
- Use `NSViewRepresentable` for AppKit bridges (see `VisualEffectBackground.swift`). For a top-level window use `NSPanel` directly, not a SwiftUI overlay.
- Animations: `.spring(duration: 0.25, bounce: 0)` for page transitions; `.easeInOut(duration: 0.15)` for hover. Wrap state changes in `withAnimation`. Constants live in `AnimationDuration`.

### GRDB

- Models are `struct` and conform to `Codable, Identifiable, Equatable`.
- Persistence in a **separate extension**:
  ```swift
  extension AppEntry: FetchableRecord, PersistableRecord {
      static let databaseTableName = "appEntry"
      enum Columns: String, ColumnExpression {
          case bundleIdentifier, displayName, pageIndex, orderIndex, folderID, folderOrderIndex
      }
  }
  ```
- **`enum Columns: String, ColumnExpression`** is mandatory — use it for type-safe queries, never raw strings.
- Queries via method chains: `AppEntry.order(Columns.orderIndex.ascNullsLast).fetchAll(db)`.
- **Migrations only ADD/ALTER** — never `DROP TABLE`. Versions are `"v1"`, `"v2"`, `"v3"`. Add a new `"vN+1"` block; never edit a shipped one.
- Foreign keys use `.setNull` on delete (e.g. removing a folder nulls `appEntry.folderID`).
- Upsert by primary key: `app.save(db)`. For batches, loop in a single transaction.

### Threading

- `Task.detached` for background work (file scans, icon extraction). Always capture `[weak self]`.
- Return to the main thread with explicit `await MainActor.run { … }` for state mutation.
- The ViewModel is `@MainActor`. Do not call its setters from a background queue.
- No `actor` types in this codebase — concurrency is structured around `@MainActor` + `Task.detached`.
- `DispatchQueue.main.asyncAfter` is used only for deferred UI cosmetics (folder close delays). Don't put logic in it.

### Constants

- **All numbers** that aren't loop indices live in `Helpers/Constants.swift`. No inline literals.
- Existing namespaces:

  | Constant | Value |
  |----------|-------|
  | `Grid.columns` | 7 |
  | `Grid.rows` | 5 |
  | `Grid.appsPerPage` | 35 |
  | `AnimationDuration.show` | 0.25 |
  | `AnimationDuration.hide` | 0.20 |
  | `LayoutMetrics.horizontalPadding` | 6% of screen width |
  | `LayoutMetrics.iconSize` | 50% of `itemWidth` |
  | Pinch threshold | 0.5 magnitude |

- `LayoutMetrics` is computed from `GeometryReader` size — don't cache it across resize.

## Testing

- **Framework: swift-testing**, not XCTest. `import Testing`, decorate tests with `@Test`, assert with `#expect(…)`. If you see `XCTestCase` or `XCTAssert` anywhere — that's wrong, fix it.
- File layout:
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
- `@MainActor` is required on test suites that touch the ViewModel.
- Use `makeTempDB()` helper from `AppDatabaseTests.swift` for a fresh on-disk SQLite per test, cleaned up via `defer`. Do **not** share a database between tests.
- Fixtures: small private helpers like `func app(_ id: String = "com.test.app") -> AppEntry { … }` inside the test struct. Don't build a fixture framework.
- `throws` on the test function — propagate, don't `try?` inside the test (failures should surface).

## Domain gotchas

Things a new developer cannot guess from the code:

- **`NSPanel` must be `.screenSaver` level** with `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`. Lower levels leave the launcher behind Dock/menubar; wrong collection behavior breaks multi-Space usage.
- **Trackpad gestures only work via `NSEvent.addGlobalMonitorForEvents`** (and a paired local monitor for events while the app is focused). SwiftUI `.gesture(MagnifyGesture)` does **not** fire when SuperLaunchpad isn't the frontmost app — that's why the global monitor exists.
- **An app inside a folder has `pageIndex == nil` and `orderIndex == nil`.** Its position is solely `folderID + folderOrderIndex`. Setting both at once is a bug; pick one positioning scheme.
- **Sort display names with `localizedCaseInsensitiveCompare`**, not `<`. Otherwise unicode/locale ordering goes wrong (e.g. `é` vs `e`).
- **`FolderEntry.id` is generated in code** (`UUID().uuidString`), not by SQLite. Newly created folders need this set before `save(db)`.
- **System Launchpad DB at `~/.com.apple.dock.launchpad/db/db`** — read-only import on first launch via `Services/SystemLaunchpadDB.swift`. Hierarchy is `Root → Page → Folder(type=2) → FolderPage(type=3) → App`; folder titles in `groups` table. Never write to this DB.
- **`NSHostingView` needs an explicit frame of the screen's size at origin `.zero`** on resize when embedded in `NSPanel` — SwiftUI doesn't propagate sizing to the AppKit host automatically here. Not `screen.frame` itself: a secondary display has a non-zero origin.
- **Multi-monitor:** `LaunchpadPanel` opens on the screen under the cursor (`Helpers/ScreenSelection.swift`, pure and tested). On `didChangeScreenParametersNotification` a visible panel stays on its display (by display ID) with the new frame, or moves under the cursor if that display was unplugged.
- **Context menus open below the `.screenSaver` panel.** NSMenu windows sit at the pop-up menu level, so `LaunchpadPanel` steps down to just below it on `NSMenu.didBeginTrackingNotification` and back up on `didEndTrackingNotification` — still above the Dock and menu bar. `NSAlert` has the same problem, which is why the Trash dialog is drawn inside the launcher.
- **Context menu items are built in one place:** `ItemMenu.items(for:)`, one function per item kind (app, folder). A new action (Hide, Quit, …) is a new `ItemMenu.Action` case, a line there and a branch in `LaunchpadViewModel.perform(_:on:)`; the menu and the VoiceOver actions pick it up. Actions returning `true` want the launcher hidden — the view posts `.hideLaunchpad`, it is not the view model's job.
- **Hidden apps (`appEntry.isHidden`) have no position at all** — `pageIndex`, `orderIndex`, `folderID`, `folderOrderIndex` are all nil, so they take no slot on a page or in a folder (a folder they leave empty is dissolved). `rebuildPages` and `GridLayout.init` skip them; only search (`AppSearch` runs over every app) and Settings → Hidden Apps show them. `hideApp` / `unhideApp` go through `applyEdit`; unhiding appends to the end of the last page (`GridLayout.append`). A rescan keeps the flag (`mergeNewApps` copies existing rows and never attaches a hidden app to a re-imported folder), and `hasOrderingData` counts hidden rows so they are never re-imported as visible.
- **Modifier clicks:** `⌘`-click opens the app without activating it (`AppOpener`, `activates = false`) so the launcher keeps the keyboard; `⌥⌘`-click shows it in Finder; `⌃`-click is left to the context menu. None of them act in edit mode.
- **New apps (blue dot).** An app is marked `isNew` only when a rescan finds it without a DB row *and* `AppSetting.Key.newAppTracking` is set. The flag is set by the v6 migration for an existing layout, or by the first scan after which every app on disk has a row — so the first-run import (and apps the system Launchpad import skipped, added on the next rescan) never get the dot. Opening it from the launcher (click, `⌘`-click, menu Open) clears it (`clearNew`); a folder's label shows the dot while it holds a new app.
- **`searchText` exists on the ViewModel but is not wired.** Don't add filtering downstream of it without also building the search UI and decide on debounce/scope first.

## Forbidden patterns

- ❌ Force unwrap `!` outside `lazy` initializers.
- ❌ `do/catch` that swallows errors silently — use `try?` + explicit default instead.
- ❌ `DROP TABLE` in migrations. Ever.
- ❌ Magic numbers inline. Add them to `Constants.swift`.
- ❌ Duplicating state (one copy on the ViewModel, another in `@State`) without an `onChange` sync — pick one home.
- ❌ Mutating `@Observable` ViewModel state off the main thread.
- ❌ Hardcoded filesystem paths. Use `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)`.
- ❌ Inventing new persistence layers. There is one `AppDatabase` — extend it.
- ❌ Running `xcodebuild` via Bash. Hard rule — use `xcodebuildmcp` MCP tools. Only fall back if the MCP server itself fails to start. See "Build, run, test".

## Known limitations / dead ends

These are intentionally unimplemented. Don't half-implement them as a side effect of another task.

- **Search** — `searchText` property exists, not wired. Requires a full UI before backend filtering.
- **Drag-and-drop reorder** — not feasible inside SwiftUI `ScrollView` on macOS as of Sequoia. Several attempts have been ruled out; consult before re-attempting.

## Workflow

- **Commits:** short, lowercase, imperative. Match the style in `git log` (`init`, etc.). Keep PR titles ≤ 70 chars; put detail in the body.
- **Branches:** feature branches off `main`; PRs target `main`.
- **CI:** `.github/workflows/release.yml` builds a `.dmg` on tag `v*` and publishes a GitHub Release. Runs on `macos-15`. To trigger: `git tag vX.Y.Z && git push origin vX.Y.Z`. Optional parts switch on by secrets: Developer ID signing + notarization, and a Sparkle `appcast.xml` (variable `SPARKLE_PUBLIC_ED_KEY` + secret `SPARKLE_ED_PRIVATE_KEY`); `.github/workflows/homebrew.yml` then bumps the cask in `DantesChmo/homebrew-tap`. Setup: `docs/RELEASING.md`.
- **Changelog:** add user-facing changes to `CHANGELOG.md` under `[Unreleased]`.
- **Versioning:** version comes from the git tag via `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` xcodebuild flags. Don't bump version in `project.pbxproj` manually.

## Context economy — delegate to Explore

**Default to spawning an `Explore` subagent for any multi-file search or codebase question.** The main agent's context is precious; the Explore subagent reads in its own context and returns a compact summary. Use it whenever you'd otherwise read more than ~2 files to answer one question.

Triggers — delegate to Explore when you need to:

- find where a symbol / function / type is defined or used (`grep`-style searches across the repo);
- understand a subsystem you haven't touched yet (e.g. "how does folder import work?");
- audit consistency across multiple files (e.g. "is `try?` used everywhere or do we have `do/catch` somewhere?");
- locate the right place to add a new feature.

Do **not** delegate when:

- you already know the exact file and line range — `Read` directly;
- the task is a single targeted edit and you have all the context;
- the question is conceptual / architectural and already answered by this `AGENTS.md`.

In Claude Code: call the `Agent` tool with `subagent_type: "Explore"` and a self-contained prompt (the subagent doesn't see the parent conversation). Specify search breadth in the prompt: `"quick"` for one targeted lookup, `"medium"` for moderate exploration, `"very thorough"` for cross-cutting audits.

Pattern: short, specific prompt → compact reply (under 300 words). If you find yourself writing a long prompt explaining the whole project, you're doing it wrong — most of that context is already in this file, just point at it.

## Routing — delegate by task shape

This repo defines three project-scoped subagents in `.claude/agents/`:

| Subagent     | Model  | Use for                                                            |
| ------------ | ------ | ------------------------------------------------------------------ |
| `dev`        | Sonnet | Feature implementation against a clear spec, clear-cause bug fixes, tests, UI wiring |
| `architect`  | Opus   | Architecture, cross-cutting refactors, murky bugs, design reviews  |
| `refactor`   | Haiku  | Mechanical transformations with an unambiguous rule                |
| `qa-runner`  | Sonnet | Execute regression: run tests, drive the app, capture screenshots, report state. Read-only on production code. |

When the user's request fits one of these shapes, delegate via the `Agent` tool with the matching `subagent_type` rather than doing the work inline in the main session. Each agent's own `description` and system prompt hold the precise scope; this table is just the index.

If the routing is ambiguous (e.g. a "refactor" that actually requires design decisions), ask before delegating. Don't force-fit. Trivial in-conversation Q&A and reading a single file don't need delegation.

## Skills — knowledge packs

Beyond subagents, this repo defines three project-scoped **skills** in `.claude/skills/`. A skill is a reusable knowledge pack invoked via the `Skill` tool — load it *before* writing code (or critique) when the task hits its area, so you don't re-derive the domain checklist from scratch:

| Skill | Load before…  | Contents in brief |
| ---------------------- | -------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `macos-desktop-architect` | Designing or debugging anything window/event/system-integration | NSPanel/NSWindow levels & collectionBehavior, AppKit↔SwiftUI bridges, Spaces/Stage Manager, global event monitors, threading, sandbox/entitlements, performance |
| `swift-engineer`          | Writing or reviewing non-trivial Swift code                    | Modern idioms (Swift Concurrency, `@Observable`, generics, error-handling), swift-testing, anti-pattern list |
| `ui-ux-designer`          | Building or critiquing a visible UI surface                    | macOS HIG, hierarchy & typography, motion duration ladder, accessibility (VoiceOver/Dynamic Type/contrast), Nielsen/Fitts/Hick heuristics |
| `qa-engineer`             | Writing or reviewing tests, designing a test matrix, auditing coverage | Test pyramid for macOS GUI, 5-bucket scenario matrix (happy / sad / edge / state-transition / environmental), swift-testing in depth (parameterised, traits, `withKnownIssue`, `confirmation`), XCUITest for macOS, edge-case checklist, anti-patterns |

Rules of thumb:

- **Skills are knowledge, subagents are workers.** A skill is loaded *in the current session* to bias your reasoning; a subagent is a *separate session* you delegate work to. They compose: a subagent (e.g. `dev`) can itself load `swift-engineer` before writing code.
- **Load before, not after.** A skill loaded after you've already written the code can only critique — its value is in shaping the approach.
- **Skills and `AGENTS.md` complement each other.** This file holds *project-specific* conventions (the GRDB column enum rule, the `try?` style, the `NSPanel` level used here). Skills hold *domain knowledge* applicable across macOS Swift projects. Project rules override skill defaults when they conflict.
- **Don't load all three by default.** Pick the one that matches the task; loading every skill burns context for nothing.

Subagents `architect`, `dev`, `refactor`, and `qa-runner` each list the skills they should consider in their own system prompts (`.claude/agents/*.md`). The main session also has access — invoke `Skill` directly when the task warrants it.

## QA workflow — quality as a continuous concern

Quality is not a phase. The setup below keeps the app working *at every stage* of development, separates "writing tests" from "running them", and gives an on-demand view of overall test health.

| Layer | Mechanism | When |
|---|---|---|
| **Unit tests** (swift-testing) | `SuperLaunchpadTests/`, `xcodebuild ... test`, CI on PR | Every feature / bug fix. Designed via `qa-engineer` skill, written by `dev`. |
| **Functional tests** (XCUITest) | `SuperLaunchpadUITests/`, runs on CI when files present | One stable test per user-observable core flow. See `SuperLaunchpadUITests/README.md` for the contract. |
| **Regression pass** | `/regression-check` slash command → `qa-runner` subagent | Before merge of a non-trivial change. Builds, runs all tests, drives the app, captures screenshots, reports. |
| **Coverage gate** | `.github/workflows/ci.yml` → Codecov | Automatic on every PR. |
| **Drift / health snapshot** | `/quality-report` slash command | On-demand. Disabled tests, files without test pairs, recently churned tests. |
| **Pre-push nudge** | `.githooks/pre-push` "code without tests" check | On `git push`. Soft warning when new production code lands without test changes. |

Rules of thumb:

- **`qa-engineer` is the knowledge; `qa-runner` is the worker.** A `dev` agent loads `qa-engineer` before writing tests; the user invokes `qa-runner` (via `/regression-check`) to verify the app currently works.
- **`qa-runner` does not write or edit code.** It runs, observes, reports. Bugs it finds go to `dev`; design gaps go to `architect`.
- **Pre-push warnings are advisory.** The "new code without tests" check has false positives (cosmetic Views/ tweaks don't need new tests) — it's a question, not a gate.
- **`/quality-report` is read-only.** It's a snapshot you read; nothing is edited.

## Keeping AGENTS.md in sync — when to suggest `/sync-agents-md`

`AGENTS.md` is the source of truth for every AI agent on this repo. When it drifts from the code, every agent loses ground. The `/sync-agents-md` slash command proposes a patch; the pre-push hook prints a soft warning. Both are reactive — you, the agent, can be the first to notice.

At the end of a task, **suggest** running `/sync-agents-md` (one short line, no insistence) when at least one of these is true:

- A `.swift` file was **added or removed** in `SuperLaunchpad/{Models,Views,Services,Database,Window,Helpers,ViewModels}/` → Project map row needs updating.
- `Helpers/Constants.swift` gained a new namespace or member → constants table.
- The change altered the data flow described in "Architecture in 60 seconds" (new watcher, new entry point in `loadApps()`, new persistence path, new gesture source).
- New non-obvious behaviour was introduced that a future developer wouldn't guess from the code → gotcha candidate.
- A rule in "Forbidden patterns" no longer applies, or a new project-wide rule emerged.

**Do not** suggest when:

- Pure bug fix with no structural change; comment/whitespace/formatting edits; test-only changes that don't introduce new conventions.
- You already suggested it once in this session.
- The user has explicitly said they'll handle docs separately for this PR.

Format the suggestion as a single closing line, no header, no urgency:

> Note: this added `Services/AppDirectoryWatcher.swift` — consider running `/sync-agents-md` before pushing to update the Project map.

The user decides. Don't run the command yourself unless asked. Don't edit `AGENTS.md` directly as a side-effect of another task — let `/sync-agents-md` route through the `architect` subagent so the patch reflects judgement, not a mechanical scrape.

## Scope discipline (for AI agents)

- Do only the task asked. No drive-by refactors, no "while I'm here" cleanups, no defensive abstractions for hypothetical futures.
- Don't add error handling for cases that can't happen. Trust internal invariants; validate only at boundaries (user input, external APIs).
- **Default: no comments.** Add one only when the *why* is non-obvious (a workaround, a hidden constraint, a surprising invariant). Never narrate *what* the code does.
- Don't create new `.md` files unless explicitly asked. This includes README updates, ADRs, plans, summaries.
- For UI-affecting changes: build and run the app in Xcode, exercise the feature, and verify visually. Type-check / test pass is not enough — say so explicitly if you couldn't run it.
- When unsure between two reasonable approaches, pick one and proceed. The user will redirect if needed; don't stall on clarifying questions in this codebase unless the task is genuinely ambiguous.
