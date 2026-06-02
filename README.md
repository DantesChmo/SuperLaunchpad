# SuperLaunchpad

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

See [CONTRIBUTING.md](CONTRIBUTING.md) for the tech stack, architecture, and project layout.
