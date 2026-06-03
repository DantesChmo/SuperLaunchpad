#!/usr/bin/env bash
# Activates the repo-tracked git hooks by pointing core.hooksPath at .githooks.
# Idempotent — safe to re-run.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

chmod +x .githooks/prepare-commit-msg .githooks/commit-msg .githooks/pre-push
git config core.hooksPath .githooks

echo "✓ Git hooks активированы (core.hooksPath = .githooks)"
