# SuperLaunchpad

[![Latest release](https://img.shields.io/github/v/release/DantesChmo/SuperLaunchpad?display_name=tag&sort=semver&logo=github)](https://github.com/DantesChmo/SuperLaunchpad/releases/latest)
[![Release build](https://img.shields.io/github/actions/workflow/status/DantesChmo/SuperLaunchpad/release.yml?label=release%20build)](https://github.com/DantesChmo/SuperLaunchpad/actions/workflows/release.yml)
[![Unit tests](https://img.shields.io/github/actions/workflow/status/DantesChmo/SuperLaunchpad/ci.yml?label=unit%20tests&branch=main)](https://github.com/DantesChmo/SuperLaunchpad/actions/workflows/ci.yml)
[![UI tests](https://img.shields.io/github/actions/workflow/status/DantesChmo/SuperLaunchpad/ui-tests.yml?label=UI%20tests&branch=main)](https://github.com/DantesChmo/SuperLaunchpad/actions/workflows/ui-tests.yml)
[![Coverage](https://codecov.io/gh/DantesChmo/SuperLaunchpad/branch/main/graph/badge.svg)](https://codecov.io/gh/DantesChmo/SuperLaunchpad)
[![Downloads](https://img.shields.io/github/downloads/DantesChmo/SuperLaunchpad/total?logo=github)](https://github.com/DantesChmo/SuperLaunchpad/releases)
[![Platform](https://img.shields.io/badge/macOS-15.4%2B-blue?logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.0-orange?logo=swift)](https://swift.org)

A macOS Launchpad clone — a fullscreen app launcher with a grid layout, paging, trackpad gestures, and ordering imported from the system Launchpad.

Built as a replacement for the system Launchpad removed in macOS 26.

## Features

- Fullscreen launcher with a **7×5** grid (35 apps per page)
- Smooth snap-based paging animation
- Imports icon and folder layout from the system Launchpad on first launch
- Folder support (3×3 icon preview + expanding popup)
- Automatic detection of installed/removed apps
- Activation:
  - Global shortcut `⌘⌥L`
  - Menu bar item
  - Pinch-in gesture on the trackpad
- macOS-style blurred background (`NSVisualEffectView`)
- Icons scale on hover (1.08×)
- Caches icons and ordering in a local SQLite database

## Requirements

- macOS 15.4 (Sequoia) or newer

## Install

Download the latest `.dmg` from the [Releases](../../releases) page, open it and drag **SuperLaunchpad** into `Applications`.

The build is **not signed or notarized**, so on first launch macOS Gatekeeper will block it with «cannot be opened because the developer cannot be verified». To run it:

1. Right-click (or Control-click) **SuperLaunchpad.app** in `/Applications` → **Open**
2. Confirm **Open** in the dialog

After this, the app launches normally. Alternatively, build from source — open `SuperLaunchpad.xcodeproj` in Xcode and press **⌘R**.

## Controls

| Action | Gesture / Key |
|--------|---------------|
| Open Launchpad | `⌘⌥L` / trackpad pinch-in / menu bar icon |
| Close | `Esc` / pinch-out / click outside an icon |
| Switch pages | `←` / `→` / scroll / two-finger swipe |
| Launch an app | Click on the icon |
| Open a folder | Click on the folder icon |

## Contributing

After cloning, run the one-shot setup:

```bash
./bootstrap.sh
```

This activates the repo-tracked git hooks (commit-msg validation, the interactive commit-type wizard, the pre-push drift check). Idempotent, safe to re-run.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the tech stack, architecture, and project layout.
