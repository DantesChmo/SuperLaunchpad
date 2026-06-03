#!/usr/bin/env bash
# One-shot setup for a fresh clone of SuperLaunchpad.
#
# What this does:
#   - Activates the repo-tracked git hooks in .githooks/ by pointing
#     core.hooksPath at it (this is what enables commit-msg validation,
#     the interactive commit-type wizard, and the pre-push drift check).
#
# Run this once after cloning:
#   ./bootstrap.sh
#
# Idempotent — safe to re-run; subsequent invocations are no-ops.

set -euo pipefail

# Self-locate so the script can be invoked from any working directory.
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$SCRIPT_DIR"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '✗ Not inside a git working tree.\n' >&2
    printf '  bootstrap.sh must be run from a clone of this repository.\n' >&2
    exit 1
fi

if [ ! -d .githooks ]; then
    printf '✗ .githooks/ directory not found.\n' >&2
    printf '  This script must be run from the repository root.\n' >&2
    exit 1
fi

printf 'SuperLaunchpad — first-time setup\n'
printf '─────────────────────────────────\n'

# ── Git hooks ────────────────────────────────────────────────────────────────
CURRENT_HOOKS_PATH=$(git config --get core.hooksPath || true)
if [ "$CURRENT_HOOKS_PATH" = ".githooks" ]; then
    printf '✓ Git hooks already active (core.hooksPath = .githooks)\n'
else
    ./.githooks/install.sh
fi

# ── Done ─────────────────────────────────────────────────────────────────────
printf '\nAll set. You can now:\n'
printf '  • Make commits — the type wizard appears on bare `git commit -m "…"`\n'
printf '  • Push — pre-push prints a non-blocking drift check\n'
printf '  • Build & test in Xcode (⌘R / ⌘U) or via xcodebuild\n'
