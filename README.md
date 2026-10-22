# SuperLaunchpad

[![Latest release](https://img.shields.io/github/v/release/DantesChmo/SuperLaunchpad?display_name=tag&sort=semver&logo=github)](https://github.com/DantesChmo/SuperLaunchpad/releases/latest)
[![Release build](https://img.shields.io/github/actions/workflow/status/DantesChmo/SuperLaunchpad/release.yml?label=release%20build)](https://github.com/DantesChmo/SuperLaunchpad/actions/workflows/release.yml)
[![Unit tests](https://img.shields.io/github/actions/workflow/status/DantesChmo/SuperLaunchpad/ci.yml?label=unit%20tests&branch=main)](https://github.com/DantesChmo/SuperLaunchpad/actions/workflows/ci.yml)
[![UI tests](https://img.shields.io/github/actions/workflow/status/DantesChmo/SuperLaunchpad/ui-tests.yml?label=UI%20tests&branch=main)](https://github.com/DantesChmo/SuperLaunchpad/actions/workflows/ui-tests.yml)
[![Coverage](https://codecov.io/gh/DantesChmo/SuperLaunchpad/branch/main/graph/badge.svg)](https://codecov.io/gh/DantesChmo/SuperLaunchpad)
[![Downloads](https://img.shields.io/github/downloads/DantesChmo/SuperLaunchpad/total?logo=github)](https://github.com/DantesChmo/SuperLaunchpad/releases)
[![Platform](https://img.shields.io/badge/macOS-15.4%2B-blue?logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.0-orange?logo=swift)](https://swift.org)

A macOS Launchpad clone — a fullscreen app launcher with a paged grid, folders, search and trackpad gestures.

Built as a replacement for the system Launchpad removed in macOS 26 Tahoe.

## Features

- Fullscreen launcher with a **7×5** grid (35 apps per page) and a custom pager: one page per swipe, snap animation, arrow keys
- **Keyboard search**: start typing to filter all apps, including apps inside folders, by name (case- and diacritic-insensitive); arrow keys pick a result, `Return` opens it
- **Global hotkey** `⌘⌥L`, changeable or removable in Settings
- **Settings** window: launch at login, pinch gesture on/off, hotkey, updates
- **Launch at login** through the system login items
- **Drag to reorder** icons; hold an icon at the screen edge to flip pages (past the last page a new one is added)
- **Folders by drag and drop**: hold an app over another app to make a folder named after its category, drop apps onto folders, drag them out of an open folder
- **Folder rename**: click the title of an open folder
- **Jiggle mode** for editing the layout: long-press an icon, start a drag, or hold `⌥`; `Esc`, `Return` or a click on the background ends it
- **First-run layout**: imports icons and folders from the system Launchpad database when it exists; on macOS 26 Tahoe, where it doesn't, builds a categorized layout (Apple apps first, Utilities in an "Other" folder, third-party apps in category folders)
- **Multi-monitor**: opens on the display under the cursor
- **Accessibility**: honours Reduce Motion (cross-fades instead of zooms, no jiggle) and Increase Contrast; VoiceOver labels and an "Edit Layout" action
- **Automatic updates** with [Sparkle](https://sparkle-project.org) (menu bar → Check for Updates…)
- Picks up installed and removed apps automatically; icons and layout are cached in a local SQLite database
- Menu bar app with no Dock icon

## Requirements

- macOS 15.4 (Sequoia) or newer; made for macOS 26 Tahoe

## Install

### Homebrew

```bash
brew install --cask dantesChmo/tap/superlaunchpad
```

The app updates itself through Sparkle, so `brew upgrade` skips it unless you pass `--greedy`.

### DMG

Download the latest `SuperLaunchpad-X.Y.Z.dmg` from the [Releases](../../releases) page, open it and drag **SuperLaunchpad** into `Applications`.

### First launch: allowing the app

SuperLaunchpad is not notarized by Apple, so macOS blocks it the first time you open it, whether it came from the DMG or Homebrew. Allow it once:

1. Open **SuperLaunchpad**. When macOS says it can't verify the developer, click **Done**.
2. Open **System Settings → Privacy & Security** and scroll down to the **Security** section.
3. Next to the message about SuperLaunchpad, click **Open Anyway**, then confirm with your password or Touch ID.

After that it opens normally. (Right-click → **Open** no longer bypasses this on macOS 15 Sequoia and later.)

To build from source, open `SuperLaunchpad.xcodeproj` in Xcode and press **⌘R**.

### First run: the system pinch gesture

macOS 26 has its own trackpad pinch (four or five fingers, on by default) that opens the system Apps launcher, so a pinch may open the system launcher as well as SuperLaunchpad. To leave the pinch to SuperLaunchpad, turn off the pinch gesture in System Settings → Trackpad → More Gestures. To keep the system one instead, turn off **Pinch to open/close** in SuperLaunchpad's Settings.

## Controls

| Action | Gesture / Key |
|--------|---------------|
| Open / close | `⌘⌥L` (or your hotkey) / trackpad pinch-in to open, pinch-out to close / menu bar → Show / Hide |
| Close | `Esc` / click outside an icon |
| Switch pages | `←` / `→` / scroll / two-finger swipe |
| Search | Start typing; `←` `→` `↑` `↓` select, `Return` opens, `Esc` clears |
| Launch an app | Click its icon |
| Open a folder | Click the folder icon |
| Rename a folder | Click the title of an open folder |
| Edit layout | Long-press an icon or hold `⌥`; drag icons to move them or onto each other to make a folder |
| Leave edit mode | `Esc` / `Return` / click the background |
| Settings | Menu bar → Settings… (`⌘,`) |

## Releasing (maintainers)

Pushing a `v*` tag runs [`.github/workflows/release.yml`](.github/workflows/release.yml), which builds `SuperLaunchpad-X.Y.Z.dmg` and publishes a GitHub Release:

```bash
git tag v1.2.3
```

```bash
git push origin v1.2.3
```

Each optional part turns on when its secrets exist; without them the workflow still succeeds and prints a warning.

| Part | Repository secrets / variables | Without them |
|------|--------------------------------|--------------|
| Developer ID signing and notarization | secrets `MACOS_CERTIFICATE_P12_BASE64`, `MACOS_CERTIFICATE_PASSWORD`, `MACOS_KEYCHAIN_PASSWORD`, `APPLE_TEAM_ID`, `APPSTORE_API_KEY_P8_BASE64`, `APPSTORE_API_KEY_ID`, `APPSTORE_API_ISSUER_ID` | unsigned DMG |
| Sparkle updates (`appcast.xml` attached to the release) | secret `SPARKLE_ED_PRIVATE_KEY` and variable `SPARKLE_PUBLIC_ED_KEY` (set both or neither: one alone fails the build) | updater off, Check for Updates… disabled |
| Homebrew cask in `DantesChmo/homebrew-tap` ([`.github/workflows/homebrew.yml`](.github/workflows/homebrew.yml), template in [`packaging/homebrew/`](packaging/homebrew/)) | secret `HOMEBREW_TAP_TOKEN`: a fine-grained token with Contents read/write on the tap repository only | cask not updated |

Step-by-step setup of every secret is in [docs/RELEASING.md](docs/RELEASING.md). Keep tags increasing (Sparkle compares versions), turn Sparkle on only together with signing, and record changes in [CHANGELOG.md](CHANGELOG.md).

## Contributing

After cloning, run the one-shot setup:

```bash
./bootstrap.sh
```

This activates the repo-tracked git hooks (commit-msg validation, the interactive commit-type wizard, the pre-push drift check). Idempotent, safe to re-run.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the tech stack, architecture, and project layout.
