# SuperLaunchpad

macOS Launchpad clone — fullscreen app launcher with grid layout, paging, trackpad gestures, and system Launchpad ordering import.

## Tech Stack
- **Language:** Swift 5.0
- **UI:** SwiftUI + AppKit (NSPanel, NSWorkspace, NSVisualEffectView)
- **Database:** GRDB 7.0.0+ (SQLite)
- **Platform:** macOS 15.4+ (Sequoia)
- **Bundle ID:** com.dantes.SuperLaunchpad
- **Team:** KHDQ5WLJ79

## Build & Run
```bash
xcodebuild -project SuperLaunchpad.xcodeproj -scheme SuperLaunchpad build
xcodebuild -project SuperLaunchpad.xcodeproj -scheme SuperLaunchpad test
```

## Architecture

**MVVM + @Observable.** Single `LaunchpadViewModel` is the source of truth. NSPanel hosts the SwiftUI view hierarchy. GRDB persists app ordering across launches.

**Data flow:**
1. `AppDelegate.applicationDidFinishLaunching()` → creates `LaunchpadPanel`, calls `viewModel.loadApps()`
2. `loadApps()` → tries DB cache first → background `AppEnumerator.enumerate()` scans `/Applications` + `/System/Applications`
3. First launch: reads system Launchpad DB (`~/.com.apple.dock.launchpad/db/db`) for ordering, falls back to alphabetical
4. Subsequent launches: preserves existing positions, appends new apps at end
5. `AppDirectoryWatcher` (DispatchSource) triggers `loadApps()` on app install/uninstall
6. `GestureMonitor` detects global trackpad pinch gestures to show/hide

**Activation:** MenuBarExtra status item, `⌘⌥L` shortcut, or trackpad pinch-in (threshold 0.5)

## Project Structure
```
SuperLaunchpad/
├── SuperLaunchpadApp.swift              # @main, AppDelegate, MenuBarExtra
├── ViewModels/
│   └── LaunchpadViewModel.swift         # @Observable — apps, pages, currentPage, show/hide/launch
├── Models/
│   ├── AppEntry.swift                   # GRDB record — bundleIdentifier (PK), displayName, appPath, iconData, pageIndex, orderIndex, folderID, folderOrderIndex
│   ├── FolderEntry.swift                # GRDB record — id (PK), title, pageIndex, orderIndex
│   └── GridItem.swift                   # LaunchpadItem enum — .app(AppEntry) | .folder(FolderEntry, apps)
├── Database/
│   └── AppDatabase.swift                # SQLite at ~/Library/Application Support/.../apps.db — migrations, CRUD
├── Views/
│   ├── LaunchpadView.swift              # Root — GeometryReader, blur background, LayoutMetrics
│   ├── PagingGridView.swift             # Horizontal ScrollView + SinglePageBehavior snap + ScrollViewReader
│   ├── AppGridPageView.swift            # LazyVGrid (7 cols), one page of icons
│   ├── AppIconView.swift                # Icon image + label, hover scale 1.08, tap to launch
│   ├── FolderIconView.swift             # Folder icon with 3×3 mini app preview grid
│   ├── FolderDetailView.swift           # Folder overlay popup — 4×3 grid, paging, material background
│   ├── SearchBarView.swift              # Placeholder (not wired)
│   └── PageIndicatorView.swift          # Dot indicators, active dot scale 1.15
├── Window/
│   ├── LaunchpadPanel.swift             # NSPanel — fullscreen, borderless, screenSaver level, event handling
│   └── VisualEffectBackground.swift     # NSVisualEffectView wrapper (.fullScreenUI)
├── Services/
│   ├── AppEnumerator.swift              # Scans /Applications dirs, extracts 128×128 PNG icons
│   ├── SystemLaunchpadDB.swift          # Parses macOS Launchpad DB for app positions + folders
│   ├── GestureMonitor.swift             # Global+local NSEvent.magnify monitors
│   └── AppDirectoryWatcher.swift        # DispatchSource file watcher on /Applications
├── Helpers/
│   ├── Constants.swift                  # Grid, FolderGrid, AnimationDuration, LayoutMetrics
│   └── NSImageExtensions.swift          # pngData(), resized(to:)
└── SuperLaunchpad.entitlements          # Empty (no sandbox)
```

## Key Constants (`Constants.swift`)
| Constant | Value |
|----------|-------|
| `Grid.columns` | 7 |
| `Grid.rows` | 5 |
| `Grid.appsPerPage` | 35 |
| `AnimationDuration.show` | 0.25s |
| `AnimationDuration.hide` | 0.2s |
| Page scroll animation | 0.35s spring (bounce: 0) |
| Icon hover scale | 1.08 (0.15s easeInOut) |
| Icon size | 50% of itemWidth |
| Horizontal padding | 6% screen width |
| Vertical padding | 6% top, 4% bottom |
| Font min size | 11pt, scaled to 1.2% screen height |
| Pinch threshold | 0.5 magnitude |

## Paging
- Native `ScrollView(.horizontal)` + custom `SinglePageBehavior: ScrollTargetBehavior` for snapping
- `ScrollViewReader` for programmatic navigation via `currentPage`
- Navigation: scroll wheel, keyboard arrows (←→), trackpad swipe
- `viewModel.pages` — computed property grouping `apps` by `pageIndex`, sorted by `orderIndex`

## Known Limitations / TODO
- **Search:** `searchText` property exists in ViewModel but not connected to filtering
- **Drag-and-drop reorder:** not implemented (SwiftUI ScrollView limitation on macOS)
- **Folders:** read-only import from system Launchpad DB (no creation/renaming)
- **Multi-monitor:** uses `NSScreen.main` only
