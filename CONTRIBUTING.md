# Contributing to SuperLaunchpad

## Working with AI agents

If you're using Claude Code, Cursor, Codex, Aider, or similar tools to work on this project, point them at [AGENTS.md](AGENTS.md) — it contains the conventions, patterns, and gotchas an agent needs to be productive without re-exploring the codebase.

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
