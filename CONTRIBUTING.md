# Contributing to SuperLaunchpad

## Working with AI agents

If you're using Claude Code, Cursor, Codex, Aider, or similar tools to work on this project, point them at [AGENTS.md](AGENTS.md) — it contains the conventions, patterns, and gotchas an agent needs to be productive without re-exploring the codebase.

### Claude Code subagents

This repo defines three Claude Code subagents in [`.claude/agents/`](.claude/agents)
so work gets routed to the right model + thinking depth automatically:

| Subagent     | Model  | Use for                                                            |
| ------------ | ------ | ------------------------------------------------------------------ |
| `dev`        | Sonnet | Everyday features, clear-cause bug fixes, tests, UI wiring         |
| `architect`  | Opus   | Architecture, cross-cutting refactors, murky bugs, design reviews  |
| `refactor`   | Haiku  | Mechanical transformations with an unambiguous rule                |
| `qa-runner`  | Sonnet | Run regression: tests + drive app + screenshots + report. Read-only on production code. |

The main Claude Code session will delegate to these automatically based on
their `description`. For explicit routing, use the slash commands in
[`.claude/commands/`](.claude/commands):

```
/dev                <task>      — delegates to dev (Sonnet)
/arch               <task>      — delegates to architect (Opus)
/refactor           <rule>      — delegates to refactor (Haiku)
/regression-check   [checklist] — delegates to qa-runner (Sonnet)
/quality-report     [area]      — read-only test-health snapshot
/sync-agents-md     [section]   — propose AGENTS.md patch
```

### Claude Code skills

Beyond subagents, [`.claude/skills/`](.claude/skills) defines three project-scoped
**skills** — reusable knowledge packs invoked via the `Skill` tool. A skill is
loaded *in the current session* to bias the model's reasoning with a domain
checklist; it's not a separate worker. Use *before* writing the code, not after.

| Skill                     | Load before…                                                                  |
| ------------------------- | ----------------------------------------------------------------------------- |
| `macos-desktop-architect` | Designing or debugging window / event / system-integration code (NSPanel, AppKit↔SwiftUI bridges, Spaces, global event monitors) |
| `swift-engineer`          | Writing or reviewing non-trivial Swift (concurrency, Observation, generics, error handling, swift-testing) |
| `ui-ux-designer`          | Building or critiquing a visible UI surface (HIG, motion, accessibility, Nielsen/Fitts/Hick heuristics) |
| `qa-engineer`             | Writing or expanding tests, designing a test matrix, auditing coverage (test pyramid, swift-testing in depth, XCUITest, macOS edge cases) |

Subagents are wired to consider these skills automatically; the main session can
also invoke `Skill` directly. Skills hold *domain knowledge*; `AGENTS.md` holds
*project-specific conventions*. When they conflict, the project wins.

### Keeping the app working — QA workflow

Quality is treated as a continuous concern, not a release-time phase. The setup:

- **Unit tests** (swift-testing) live in `SuperLaunchpadTests/`. Required for every feature / bug fix. Designed with the `qa-engineer` skill, written by `dev`.
- **Functional UI tests** (XCUITest) live in `SuperLaunchpadUITests/`. One stable test per user-observable core flow. See `SuperLaunchpadUITests/README.md` for the contract (accessibility identifiers, no `Thread.sleep`).
- **CI on every PR** (`.github/workflows/ci.yml`) runs unit tests + XCUITest + uploads coverage to Codecov.
- **Pre-push hook** prints a soft warning when new production code lands without test changes (false-positive-friendly — cosmetic Views/ tweaks can be ignored).
- **`/regression-check`** runs a full pass: build → unit tests → XCUITest → drive the app through core flows → screenshots → structured report. Use before merging non-trivial changes. Delegates to `qa-runner` — read-only on production code.
- **`/quality-report`** is an on-demand snapshot: disabled tests, files without test pairs, recently churned tests. Read-only analysis.

Typical flow on a feature branch:

```
# while implementing:
# - dev agent loads qa-engineer skill, writes unit tests as part of the feature

git push                # pre-push warns if production code changed but tests didn't
# in Claude Code (before opening PR):
/regression-check       # qa-runner verifies the app currently works
/sync-agents-md         # propose AGENTS.md updates if structure drifted
# open PR — CI runs unit + UI tests on the diff
```

### Keeping AGENTS.md accurate

`AGENTS.md` is the source of truth for every AI agent working on this repo,
so the moment it drifts from the code, every agent loses ground. Two automated
nudges keep it accurate:

- **Pre-push drift check** (see [Git hooks](#git-hooks) below) prints a soft
  warning when the push touches files documented in `AGENTS.md` (Project map,
  Constants, architecturally significant directories) or introduces a forbidden
  pattern.
- **`/sync-agents-md` slash command** — runs the `architect` subagent against
  the current branch's diff vs. `AGENTS.md` and proposes a unified-diff patch
  for the sections that have drifted. It does not auto-apply — you review and
  decide.

Typical flow before opening a PR:

```
git push                # pre-push prints drift warnings, doesn't block
# in Claude Code:
/sync-agents-md         # → review and apply the proposed AGENTS.md patch
git push                # warnings should be gone
```

## Requirements

- macOS 15.4 (Sequoia) or newer
- Xcode 16+
- Swift 5.0

## Git hooks

Repo-tracked hooks live in [`.githooks/`](.githooks). Activate them once after
cloning:

```bash
./.githooks/install.sh
```

This sets `core.hooksPath` to `.githooks` for this repository only.

What the hooks do:

- **`prepare-commit-msg`** — when you run `git commit -m "add logs"`, a TUI
  appears asking for a commit type (arrow keys or `j`/`k`, `Enter` to confirm,
  `Esc` to cancel). The chosen type is prepended: `infra: add logs`. The wizard
  is skipped if the message already follows the Conventional Commits format,
  for `merge`/`squash`/`--amend` flows, and when there is no TTY (GUI clients,
  CI).
- **`commit-msg`** — validates the final subject against the Conventional
  Commits regex and rejects commits that bypass the wizard with an invalid
  format.
- **`pre-push`** — non-blocking drift check. Warns when the branch:
  - adds/removes Swift files in directories listed under "Project map",
  - changes `Helpers/Constants.swift`,
  - touches architecturally significant files (`ViewModels/`, `Database/`, `Window/`, `Services/`, `SuperLaunchpadApp.swift`),
  - introduces a pattern banned in "Forbidden patterns" (`XCTest` in `SuperLaunchpadTests/`, `DROP TABLE`, `actor` types),
  - adds new production code in `Models/Services/Database/ViewModels/Helpers` without corresponding changes in `SuperLaunchpadTests/` or `SuperLaunchpadUITests/`.

  The warning ends with `→ /sync-agents-md` or a nudge to load the `qa-engineer` skill. Use `git push --no-verify` to skip (discouraged).

Commit format:

```
<type>(<scope>): <subject>
```

Types: `feat`, `fix`, `infra`, `refactor`, `perf`, `test`, `docs`, `build`,
`ci`, `chore`, `style`, `revert`. Append `!` for breaking changes
(`feat!: ...`).

## Build & Test

```bash
xcodebuild -project SuperLaunchpad.xcodeproj -scheme SuperLaunchpad build
```

Run tests:

```bash
xcodebuild -project SuperLaunchpad.xcodeproj -scheme SuperLaunchpad test
```

Or open `SuperLaunchpad.xcodeproj` in Xcode and press **⌘R** / **⌘U**.

## Stack

- **Language:** Swift 5.0
- **UI:** SwiftUI + AppKit (`NSPanel`, `NSWorkspace`, `NSVisualEffectView`)
- **Database:** [GRDB](https://github.com/groue/GRDB.swift) 7.0+ (SQLite)
- **Architecture:** MVVM with `@Observable`

## Architecture

`LaunchpadViewModel` (`@Observable`) is the single source of truth. `NSPanel` hosts the SwiftUI hierarchy, and GRDB persists app ordering between launches.

Data flow:

1. `AppDelegate.applicationDidFinishLaunching()` creates `LaunchpadPanel` and calls `viewModel.loadApps()`
2. `loadApps()` first reads the DB cache, then in the background scans `/Applications` and `/System/Applications` via `AppEnumerator`
3. On first launch, ordering is taken from the system Launchpad DB (`~/.com.apple.dock.launchpad/db/db`); otherwise it falls back to alphabetical
4. On subsequent launches, existing positions are preserved and new apps are appended at the end
5. `AppDirectoryWatcher` (DispatchSource) triggers `loadApps()` when apps are installed/uninstalled
6. `GestureMonitor` listens for global trackpad pinch gestures to show/hide the launcher

Storage: `~/Library/Application Support/com.dantes.SuperLaunchpad/apps.db`

## Project Structure

```
SuperLaunchpad/
├── SuperLaunchpadApp.swift          # @main, AppDelegate, MenuBarExtra
├── ViewModels/
│   └── LaunchpadViewModel.swift     # source of truth
├── Models/
│   ├── AppEntry.swift               # GRDB record for an app
│   ├── FolderEntry.swift            # GRDB record for a folder
│   └── GridItem.swift               # LaunchpadItem enum
├── Database/
│   └── AppDatabase.swift            # SQLite + migrations
├── Views/
│   ├── LaunchpadView.swift          # root view
│   ├── PagingGridView.swift         # horizontal ScrollView with snap
│   ├── AppGridPageView.swift        # LazyVGrid for a single page
│   ├── AppIconView.swift            # icon + label
│   ├── FolderIconView.swift         # folder icon with 3×3 preview
│   ├── FolderDetailView.swift       # folder popup (4×3)
│   ├── SearchBarView.swift          # (not wired up)
│   └── PageIndicatorView.swift      # dot indicators
├── Window/
│   ├── LaunchpadPanel.swift         # NSPanel, borderless, screenSaver level
│   └── VisualEffectBackground.swift # blurred background
├── Services/
│   ├── AppEnumerator.swift          # /Applications scanner
│   ├── SystemLaunchpadDB.swift      # parser for the system Launchpad DB
│   ├── GestureMonitor.swift         # NSEvent.magnify
│   └── AppDirectoryWatcher.swift    # DispatchSource on /Applications
└── Helpers/
    ├── Constants.swift              # Grid, AnimationDuration, LayoutMetrics
    └── NSImageExtensions.swift      # pngData(), resized(to:)
```

## Known Limitations

- **Search** — `searchText` exists in the ViewModel but is not wired up to filtering
- **Drag-and-drop reordering** — not implemented (SwiftUI ScrollView limitation on macOS)
- **Folders** — read-only import from the system Launchpad (no creation or renaming)
- **Multi-monitor** — only `NSScreen.main` is used
