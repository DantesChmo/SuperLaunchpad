# AGENTS.md

Instructions for AI coding agents (Claude Code, Cursor, Codex, Aider, Continue, …) working in this repository. Read this first — it's the single source of truth for project conventions and constraints. Skip nothing.

## TL;DR

**SuperLaunchpad** — macOS Launchpad clone. Fullscreen app launcher with a 7×5 grid, paging, trackpad gestures, and ordering imported from the system Launchpad.

- **Language:** Swift 5.0
- **UI:** SwiftUI + AppKit (`NSPanel`, `NSWorkspace`, `NSVisualEffectView`)
- **Database:** GRDB 7.0+ (SQLite)
- **Platform:** macOS 15.4+ (Sequoia)
- **Tests:** swift-testing (`import Testing`) — **not** XCTest
- **Architecture:** MVVM with `@Observable`: `LaunchpadViewModel` is the source of truth and coordinator; focused models (`search`, `editing`, `removal`, `layoutFiles`, `itemActions`) hang off it

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

`LaunchpadViewModel` (`@Observable`, `@MainActor`) is the single source of truth and the coordinator of the focused models (see "View model split"). `LaunchpadPanel` (`NSPanel`) hosts the SwiftUI hierarchy. `AppDatabase` (GRDB) persists app/folder ordering across launches.

Data flow:

1. `AppDelegate.applicationDidFinishLaunching()` → creates `LaunchpadPanel`, calls `viewModel.loadApps()`.
2. `loadApps()` reads DB cache first, then `Task.detached` scans `/Applications` + `/System/Applications` via `AppEnumerator`, syncs back to `@MainActor`.
3. First launch only: `SystemLaunchpadDB` reads `~/.com.apple.dock.launchpad/db/db` for ordering and folders; otherwise alphabetical fallback.
4. Subsequent launches: existing positions preserved; new apps (no DB row yet) get `isNew` and go where Settings → New Apps says (`Helpers/NewAppPlacement.swift`: end / category folder / "New" folder). The rescan's DB work is the pure-ish `LaunchpadViewModel.syncScan` (`LaunchpadViewModel+Ordering.swift`), testable with a temp DB.
5. `AppDirectoryWatcher` (DispatchSource) triggers `loadApps()` on install/uninstall.
6. `GestureMonitor` listens for global trackpad pinch (threshold 0.5) to show/hide.

**Storage:** `~/Library/Application Support/com.dantes.SuperLaunchpad/apps.db`

## Project map

| Path | Role |
|------|------|
| `SuperLaunchpadApp.swift` | `@main`, `AppDelegate`, `MenuBarExtra` |
| `ViewModels/LaunchpadViewModel.swift` | source of truth and coordinator — apps, folders, pages, currentPage, visibility, open folder, DB, rescan, `layoutRevision`, the layout write path (`applyEdit` / `replaceLayout` / `recordLaunch`), show/hide, Escape ladder, `folderOpenRequest`; owns the models below |
| `ViewModels/LaunchpadViewModel+Ordering.swift` | pure `nonisolated static` rescan steps: `syncScan`, `applyOrdering` (first run), `mergeNewApps` |
| `ViewModels/SearchModel.swift` | `viewModel.search` — query, results, keyboard selection, focus request, Frequently Used row |
| `ViewModels/EditingModel.swift` | `viewModel.editing` — edit mode (⌥, sticky), selection (toggle, marquee, companions), drag session (trailing page, cancel), `commitDrop` (single and group), group actions (new folder, hide), layout edits (move, merge / create folder, add / remove from folder, disband, sort, rename), hide / unhide |
| `ViewModels/RemovalModel.swift` | `viewModel.removal` — Trash dialog (`PendingRemoval`, one app or a group), quit before Trash, `isRemovable` cache, `dropUninstalledApp(s)` |
| `ViewModels/LayoutFileModel.swift` | `viewModel.layoutFiles` — current `layoutFile`, reset, load, restore previous, `layoutBackups` |
| `ViewModels/ItemActionsModel.swift` | `viewModel.itemActions` — `launchApp`, clicks with modifiers, context-menu items and `perform(_:on:)`; `opener` |
| `Models/AppEntry.swift` | GRDB record — bundleIdentifier (PK), pageIndex, orderIndex, folderID, folderOrderIndex, isHidden, isNew (blue dot), launchCount |
| `Models/FolderEntry.swift` | GRDB record — id (PK), title, pageIndex, orderIndex |
| `Models/GridItem.swift` | `LaunchpadItem` enum: `.app(AppEntry)` / `.folder(FolderEntry, apps)` |
| `Database/AppDatabase.swift` | SQLite, migrations, CRUD |
| `Views/LaunchpadView.swift` | root, GeometryReader, LayoutMetrics |
| `Views/PagingGridView.swift` | horizontal ScrollView + `SinglePageBehavior` snap |
| `Views/AppGridPageView.swift` | LazyVGrid for one page |
| `Views/AppIconView.swift` | icon + label, hover scale 1.08 |
| `Views/FolderIconView.swift` | 3×3 mini preview |
| `Views/FolderDetailView.swift` | folder popup, 4×3 grid |
| `Views/SearchResultsView.swift` | one page of search results (apps and folders) with the keyboard selection |
| `Views/FrequentAppsRow.swift` | Settings → Search: the most launched apps in a row above the grid |
| `Views/SelectionBar.swift` | edit mode with a selection: New Folder / Hide / Move to Trash / Deselect, in place of the search field |
| `Views/ItemContextMenu.swift` | right-click menu on app icons and folder tiles, same items as VoiceOver actions |
| `Helpers/AppSearch.swift` | pure search: name / word prefix, word initials, contains, fuzzy; ranking by launch count; folders by title |
| `Helpers/ItemMenu.swift` | context-menu items per app / folder and their availability; what a click does by its modifiers |
| `Services/AppOpener.swift` | open an app (in front or in the background), show it in Finder; injectable like `AppTrash.Operations` |
| `Services/RunningApps.swift` | which apps run (dot under the icon, Quit / Force Quit, quit before Trash); `@Observable`, fed by an injectable `Source` (live: `NSWorkspace` + launch/terminate notifications) |
| `Window/LaunchpadPanel.swift` | `NSPanel`, borderless, screenSaver level |
| `Window/VisualEffectBackground.swift` | `NSVisualEffectView` wrapper |
| `Services/AppEnumerator.swift` | scans `/Applications`, extracts `AppIcon.pixelSize` (256 px) PNG icons |
| `Services/SystemLaunchpadDB.swift` | parses macOS Launchpad DB |
| `Services/GestureMonitor.swift` | global+local `NSEvent.magnify` monitors |
| `Services/AppDirectoryWatcher.swift` | DispatchSource on `/Applications` |
| `Helpers/Constants.swift` | `Grid`, `FolderGrid`, `AnimationDuration`, `LayoutMetrics` |
| `Helpers/NSImageExtensions.swift` | `pngData(pixelSize:)` — exact-pixel PNG for `iconData` |
| `Helpers/NewAppPlacement.swift` | Settings → New Apps: where a rescan puts a new app; category folder title matching |
| `Models/LayoutFile.swift` | layout file (JSON, `formatVersion`): pages, folders by title, hidden apps by bundle ID; pure encode/decode and `apply(to:)` onto the installed apps |
| `Services/LayoutReset.swift` | Settings → Reset Layout: system Launchpad / categories / alphabetical, pure, reuses the first-run paths |
| `Services/LayoutBackupStore.swift` | automatic backups before a reset or load (`Application Support/…/Layout Backups`, newest `LayoutBackup.keepCount` kept) |
| `Views/LayoutSettingsSection.swift` | Settings → Layout: save / load / reset / restore previous, reset-mode sheet |
| `SuperLaunchpadTests/` | swift-testing test suites |

## Conventions

### Swift style

- **Naming:** `PascalCase` for types, `camelCase` for methods and properties. No Hungarian notation, no `m_` prefixes.
- **Visibility:** mark members `private` aggressively. Default to `private`, widen only when needed.
- **`// MARK: - …`** to group methods in large classes (`AppDatabase`, `LaunchpadPanel`, `LaunchpadViewModel`, `EditingModel`).
- **Error handling:** prefer `try?` with an explicit default over `do/catch`:
  ```swift
  let apps = (try? database?.fetchAllApps()) ?? []
  ```
  Only use `do/catch` when the error path needs distinct behavior.
- **No force unwrap (`!`)** except in `lazy` initializers where the value is guaranteed.
- **`guard` for early exits**, not for the happy path.

### SwiftUI

- `LaunchpadViewModel` is the only source of truth. Pass it (or one of its models, e.g. `viewModel.search` to `SearchBarView`) to child views **through parameters** — do not reach for a global singleton.
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
- The ViewModel and its models are `@MainActor`. Do not call their setters from a background queue.
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
- `@MainActor` is required on test suites that touch the ViewModel. Tests build a `LaunchpadViewModel` and reach a model through it (`vm.editing.hideApp(…)`, `vm.removal.trash = …`); suites are named after the model they cover (`SearchModelTests`, `EditingModel…Tests`, `RemovalModelTests`, `ItemActionsModelTests`).
- Use `makeTempDB()` helper from `AppDatabaseTests.swift` for a fresh on-disk SQLite per test, cleaned up via `defer`. Do **not** share a database between tests.
- Fixtures: small private helpers like `func app(_ id: String = "com.test.app") -> AppEntry { … }` inside the test struct. Don't build a fixture framework.
- `throws` on the test function — propagate, don't `try?` inside the test (failures should surface).

## View model split

`LaunchpadViewModel` is a thin coordinator; behaviour lives in five `@MainActor @Observable` models it creates and owns: `search`, `editing`, `removal`, `layoutFiles`, `itemActions`.

- **Ownership.** The coordinator holds each model in an `@ObservationIgnored private(set) lazy var` (lazy so `self` can be passed in); each model holds `private unowned let launchpad: LaunchpadViewModel`. The models never outlive the coordinator, so `unowned` is safe and there is no retain cycle. Don't store a model anywhere that outlives its view model, and don't create one outside the coordinator.
- **Shared state stays on the coordinator:** `apps`, `folders`, `pages`, `currentPage`, `isVisible`, `openFolderID`, `dockInsets`, `database`, `runningApps`, `layoutRevision`, `folderOpenRequest`. A model owns only its own state (query and results, edit mode and drag flags, the Trash dialog, backups, the opener) and reads the rest through `launchpad`.
- **One write path.** A layout change goes through `LaunchpadViewModel.applyEdit` (one `GridLayout` operation → `apps`/`folders` in one `updateContents`, `layoutRevision += 1`, one DB transaction) or `replaceLayout` (reset / load). `renameFolder` and `recordLaunch` are the only other writers and bump `layoutRevision` too. A new edit is a method on `EditingModel` (or the model it belongs to) that calls `applyEdit`; don't add DB writes elsewhere.
- **Cross-model calls go through the coordinator:** a model reaches a sibling as `launchpad.editing`, `launchpad.search`, …. The coordinator calls into models for its own flows: `updateContents` → `search.contentsDidChange()`, `show()` → `search.launcherDidShow()` / `editing.resetOptionKey()`, `hide()` / `handleEscape()` → `removal` / `editing` / `search`, a rescan result checks `editing.isDragSessionActive` and `editing.endDragSession()` hands the parked one back (`receiveParkedRescan`).
- **Views** take `viewModel` and read `viewModel.search.isSearching`, `viewModel.editing.isEditing`, …; observation tracks the model's own properties. A view that binds to a model's property takes the model (`SearchBarView(search:)`), since `$viewModel.search.x` can't bind through a `private(set)` property.
- **Multi-select** lives in `EditingModel` (see "Multi-select" below); `ItemActionsModel.click` toggles it in edit mode, `RemovalModel` has the group Trash flow.

## Multi-select

In edit mode several apps can be selected and moved, foldered, hidden or trashed at once (1.8.0).

- **Selection model.** `EditingModel.selection: Set<String>` of app bundle IDs, next to `isEditing`. Only visible apps are selectable — on the grid or inside a folder opened in edit mode — never folders (no folder in a folder) and never hidden apps. The model is additive: a click (or `⌘`-click) in edit mode toggles one app (`ItemActionsModel.click` → `toggleSelection`), a marquee adds what it touches, a `⌘`/`⇧` marquee toggles it. It is cleared by `exitEditMode` (hide, search, Return, ⌥ released), by Escape (the `.clearedSelection` step of the ladder, before `.exitedEditMode`), by a click on an empty spot (before that click would leave edit mode), and after a group drop or group action. `updateContents` prunes apps that disappeared or got hidden (`contentsDidChange`). Opening and closing folders keeps it, so a selection can gather apps from several folders and pages. `orderedSelection` is the selection in layout order (pages in reading order, a folder's apps at the folder's tile).
- **Marquee.** A press-drag that starts on the grid outside any icon, in edit mode with no folder open, draws a rubber band (`GridDragController.marquee`, root coordinates) instead of being ignored. Hits are the apps on the shown page whose icon + label box (`GridGeometry.hitFrame`) intersects the band (`GridGeometry.slots(intersecting:itemCount:)`, page-local); `EditingModel.updateMarquee(hits:toggling:)` combines them with the selection captured when the band started, `endMarquee()` forgets it. No edge paging during a marquee. It suppresses the tap that ends it, so the background's click doesn't clear the selection.
- **Group drag.** Lifting a selected app while two or more are selected carries the whole selection. `DragSession` gets `companionIDs` (the other selected apps, in layout order); the lifted app stays the session's `itemID` (the lead) and all slot math is the single-drag math run over the pages and folder *without* the companions (`DragSession.lifting(_:)`; `sourceSlot` and `targetSlot` count in that filtered list). So the companions vanish from every page and the open folder while lifted, the grid closes up, and one gap shows where the stack lands. The lifted copy draws a stack (two layers behind it) with a count badge. Lifting an unselected app is a plain single drag and leaves the selection alone.
- **Where a group lands** (`EditingModel.commitDrop` → one `applyEdit`, one transaction, one `layoutRevision` bump), always lead first, then the companions in layout order:
  - on the grid: `GridLayout.moveGroup` — every member comes out of its page or folder, then all are inserted consecutively at the target slot of the target page (counted without them). A full page spills its overflow onto the next page, cascading (`normalize`); `page == pages.count` (the trailing drag page reached by edge paging) opens a new page. Folders emptied by the move are dissolved.
  - onto a folder tile, or back onto the lead's own folder: `addGroup` to the end of it.
  - onto an app: `mergeGroup` — a new folder in that app's place holding the app followed by the group, titled after its category, opened in rename mode (as a single merge).
  - inside the open folder: `addGroup` at the target index, companions from elsewhere join that folder.
  - refused or cancelled (Esc): nothing changes; the companions reappear where they were. A rescan finishing mid-drag is parked as before; the drop is refused if the lead moved.
- **Group actions** — the selection bar (`SelectionBar`, in place of the search field while a selection exists in edit mode; plain buttons, so VoiceOver reaches them): **New Folder** (`makeFolderFromSelection` → `GridLayout.makeFolder`: the folder takes the place of the first selected app on a page, or goes after the folder holding the first one when all are in folders, then opens in rename mode), **Hide** (`hideSelection`, one `applyEdit`), **Move to Trash** (`RemovalModel.requestRemoval(of: [AppEntry])`), **Deselect**. The app context menu and `ItemMenu` are unchanged (they act on the clicked app).
- **Group Trash.** Apps that are part of macOS are skipped (`PendingRemoval.skippedCount`); none left → nothing happens, one left → the single-app dialog. One dialog for the group (`PendingRemoval.apps`): `.confirm`, or `.appIsOpen` when any of them runs; confirming quits every running one and waits for all against one `quitTimeout` deadline. If any is still running then, nothing is trashed (`.didNotQuit`). Otherwise each goes to the Trash (Finder for the ones needing a password, after hiding the launcher once); the trashed ones leave the layout in one `applyEdit` (`dropUninstalledApps`); the first failure shows the single-app `.failed` dialog for that app.
- **VoiceOver.** A selected app has the `.isSelected` trait (its value stays "New" for the blue dot); the default action toggles it in edit mode (hint "Selects it. Drag to move"); a change posts "N selected" / "Selection cleared". The bar's buttons carry the group actions.

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
- **Context menu items are built in one place:** `ItemMenu.items(for:)`, one function per item kind (app, folder). A new action (Hide, Quit, …) is a new `ItemMenu.Action` case, a line there and a branch in `ItemActionsModel.perform(_:on:)`; the menu and the VoiceOver actions pick it up. Actions returning `true` want the launcher hidden — the view posts `.hideLaunchpad`, it is not the view model's job.
- **Hidden apps (`appEntry.isHidden`) have no position at all** — `pageIndex`, `orderIndex`, `folderID`, `folderOrderIndex` are all nil, so they take no slot on a page or in a folder (a folder they leave empty is dissolved). `rebuildPages` and `GridLayout.init` skip them; only search (`AppSearch` runs over every app) and Settings → Hidden Apps show them. `hideApp` / `unhideApp` go through `applyEdit`; unhiding appends to the end of the last page (`GridLayout.append`). A rescan keeps the flag (`mergeNewApps` copies existing rows and never attaches a hidden app to a re-imported folder), and `hasOrderingData` counts hidden rows so they are never re-imported as visible.
- **Running apps:** `RunningApps` is seeded from `NSWorkspace.runningApplications` and then follows `didLaunch`/`didTerminateApplicationNotification` on the *workspace's* notification center; nothing polls. An app matches a process by bundle ID, else by standardized bundle path. Views read it through `\.runningApps` (the dot, `runningDot(_:)` in `GridItemContainer.swift`, sits in the gap between icon and label — the name row is left to other badges). Tests use `FakeWorkspace` (`RunningAppsTests.swift`) and never touch real processes.
- **Menu alternates:** an `ItemMenu.Item` may carry an `alternate` action shown while ⌥ is held (`modifierKeyAlternate`); VoiceOver gets it as an action of its own. Quit → Force Quit is the only one.
- **Trash of a running app** quits it first: stage `.appIsOpen` → `.quitting` (only Cancel works; Return is ignored) → trash once it terminates, or `.didNotQuit` after `Uninstall.quitTimeout` (it is probably asking to save changes, behind the launcher's panel). Cancelling or hiding while quitting keeps the app on disk; the quit request has already gone out.
- **Modifier clicks:** `⌘`-click opens the app without activating it (`AppOpener`, `activates = false`) so the launcher keeps the keyboard; `⌥⌘`-click shows it in Finder; `⌃`-click is left to the context menu. None of them act in edit mode.
- **New apps (blue dot).** An app is marked `isNew` only when a rescan finds it without a DB row *and* `AppSetting.Key.newAppTracking` is set. The flag is set by the v6 migration for an existing layout, or by the first scan after which every app on disk has a row — so the first-run import (and apps the system Launchpad import skipped, added on the next rescan) never get the dot. Opening it from the launcher (click, `⌘`-click, menu Open, Return in search) clears it (`recordLaunch`); a folder's label shows the dot while it holds a new app.
- **Stored icons are `AppIcon.pixelSize` (256) px, whatever the display.** `NSImage.pngData(pixelSize:)` draws into an explicit 8-bit `NSBitmapImageRep`; `lockFocus` would render at the main screen's backing scale (128 px on a non-Retina main display, 16-bit 256 px on Retina). Migration v7 cleared the older icons; the launch rescan writes them back (`mergeNewApps` always refreshes `iconData`), and `IconCache` re-decodes because the fingerprint changes. Changing the size again needs another migration like v7.
- **Search** (`AppSearch`, pure) runs on every keystroke over all apps — hidden ones too, shown dimmed with an eye — and over folder titles. Match kinds, best first: name prefix, word prefix, word initials (`vsc` → Visual Studio Code, `sysset` → System Settings; words also split at camelCase), contains, fuzzy (letters in order). Order: name-prefix matches first and fuzzy matches last; in between, and inside each of those groups, `launchCount` beats match kind. A folder result (Return or click) clears the query and opens the folder over the grid via `folderOpenRequest`.
- **Launch counter.** Every launch from the launcher (click, `⌘`-click, menu Open, Return in search) goes through `recordLaunch`: `launchCount + 1` and `isNew = false` in memory and in one DB update, and a `layoutRevision` bump so a rescan running at that moment doesn't write back the row it read before. Show in Finder and clicks in edit mode don't count.
- **Frequently Used row** (Settings → Search, `Preferences.showsFrequentApps`, off by default): up to `FrequentApps.maxCount` most launched visible apps, picked on `show()` and kept in that order while the launcher is open (a `⌘`-click must not move the icon under the pointer). While it has apps, `LayoutMetrics(extraRows: 1)` shares the grid's height with it, also during search, and the icon shrinks if the shorter cell needs it. Click only; arrows and Return keep paging; in edit mode it is dimmed and ignores clicks.
- **Layout file and reset.** `LayoutFile` stores no folder IDs and no icons; `apply(to:)` makes new folder IDs, skips apps that aren't installed, drops folders left empty, spills pages longer than a page, puts apps the file doesn't have after the last item by name, and keeps an app hidden here that the file doesn't mention hidden. `decode` checks `formatVersion` first: a newer one is `LayoutFileError.newerFormat` and nothing is changed — bump `currentFormatVersion` whenever older builds can't read the file (2.0.0 grid size). `LayoutFileModel.resetLayout` / `loadLayout` save the current layout to `layoutBackups` first and change nothing if that throws; `restorePreviousLayout` loads the newest backup (after backing up, so a second restore undoes the first). A reset keeps hidden apps hidden and the new-app dot; the system Launchpad mode puts apps its DB doesn't know at the end (the first-run import drops them). Tests pass a temp `LayoutBackupStore`; the test init has none.

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
