# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Move apps to the Trash from the launcher: in edit mode every app that
  isn't part of macOS gets a × badge; after a confirmation the app goes to
  the Trash and leaves the grid. Apps that need an administrator password
  (App Store and installer packages) are moved by Finder, which asks for it;
  the first time, macOS asks to let SuperLaunchpad control Finder. An app
  that is open has to be quit first.

## [1.0.2] - 2026-10-22

### Fixed

- The last row of icons no longer runs into the page indicator: the gaps
  between rows are now part of the grid's height budget.

## [1.0.1] - 2026-10-22

### Fixed

- The Dock no longer covers the launcher: the search bar, grid, page
  indicator and folders are laid out in the space beside the Dock, wherever
  it sits (bottom, left or right).

## [1.0.0] - 2026-10-22

### Added

- **Keyboard search.** Typing in the open launcher filters all apps, including
  apps inside folders, by display name or bundle file name (case- and
  diacritic-insensitive). Arrow keys move the selection, Return opens the
  selected app, Escape clears the query.
- **Custom global hotkey.** The default `⌘⌥L` can be changed or cleared in
  Settings with a shortcut recorder.
- **Settings window** (menu bar → Settings…, `⌘,`): launch at login, pinch
  gesture on/off, global hotkey, update preferences.
- **Launch at login** via the system login items (`SMAppService`), with a hint
  and a shortcut to System Settings when macOS needs approval.
- **Drag to reorder** icons; neighbours reflow live while dragging.
- **Edge paging while dragging:** hold an icon at the left or right screen edge
  to flip pages; dragging past the last page adds a new one.
- **Folders by drag and drop:** hold an app over another app to create a folder
  (named after the app's category), drop an app on a folder to add it, drag an
  app out of an open folder to remove it.
- **Inline folder rename:** click the title of an open folder; a new folder
  opens with its title ready to edit.
- **Jiggle (edit) mode:** entered by a long press, by starting a drag, or while
  `⌥` is held. Clicks don't launch apps in this mode; Escape, Return or a click
  on the background leave it.
- **Categorized first-run layout** when there is no system Launchpad database
  to import (macOS 26 Tahoe): Apple apps first, `Utilities` in an "Other"
  folder, third-party apps grouped into category folders.
- **Multi-monitor support:** the launcher opens on the display under the
  cursor and follows display changes.
- **Accessibility:** Reduce Motion turns zooms into cross-fades and stops the
  jiggle; VoiceOver labels, hints and an "Edit Layout" action for icons and
  folders; adjustable page indicator; better label contrast with Increase
  Contrast.
- **Automatic updates** with [Sparkle 2](https://sparkle-project.org):
  menu bar → Check for Updates…, and an automatic-check toggle in Settings.
- **Homebrew cask** in the `DantesChmo/tap` tap, updated by CI on every release.
- Release builds can be **signed with Developer ID and notarized** when the
  signing secrets are configured (see [docs/RELEASING.md](docs/RELEASING.md)).

### Changed

- Paging uses a custom pager that moves exactly one page per swipe and snaps
  into place.
- Pinch to open is stricter: only a quick pinch-in opens the launcher, so slow
  zooming in other apps no longer triggers it. It can be turned off in Settings.
- The app no longer shows a Dock icon (`LSUIElement`); it lives in the menu bar.
- Faster launcher: icons are decoded once and cached, pages are laid out up
  front, and hover effects are skipped while paging.

### Fixed

- Bursts of file-system events could run several app rescans at once and
  duplicate imported folders on first launch; rescans are now serialized and
  debounced.
- Showing the launcher right after hiding it could make the window disappear
  while the launcher counted as open.
- Settings changes are applied on the main thread.

## [0.0.1] - 2026-06-02

### Added

- Fullscreen launcher with a 7×5 grid, paging, folders and the menu bar item.
- Import of icon and folder layout from the system Launchpad database.
- Global shortcut `⌘⌥L` and trackpad pinch to open and close.
- Automatic detection of installed and removed apps; icons and layout cached in
  SQLite.

[Unreleased]: https://github.com/DantesChmo/SuperLaunchpad/compare/v1.0.2...HEAD
[1.0.2]: https://github.com/DantesChmo/SuperLaunchpad/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/DantesChmo/SuperLaunchpad/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/DantesChmo/SuperLaunchpad/compare/0.0.1...v1.0.0
[0.0.1]: https://github.com/DantesChmo/SuperLaunchpad/releases/tag/0.0.1
