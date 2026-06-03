---
description: Run a full regression — unit tests, XCUI tests, drive the app through core flows, take screenshots, report state
argument-hint: (optional) custom checklist of flows to verify, e.g. "after folder-create feature"
---

Run a full regression pass on the current branch and produce a structured report. Delegate to the `qa-runner` subagent via the `Agent` tool with `subagent_type=qa-runner` — it's specialised for execute-and-report and is forbidden from editing production code.

The subagent should:

1. **Plan first** — state the order of execution before running anything long.
2. **Build & test (unit)** — `xcodebuild -project SuperLaunchpad.xcodeproj -scheme SuperLaunchpad test`. Capture pass/fail counts, list every failure with `file:line` + one-line cause.
3. **XCUI tests, if the target exists** — same xcodebuild target, separate scheme if configured. If the target isn't present, note it (skipped, not failed).
4. **Drive the app** — build, launch (via `xcodebuildmcp` macOS workflow if enabled, else `open` the built `.app`). Walk through the checklist in `$ARGUMENTS` if provided, or the default checklist from the `qa-runner` agent prompt.
5. **Capture screenshots** at key moments — launcher visible, folder popup, after gesture. Reference them by number in the report.
6. **Report** in the structured shape defined in the qa-runner agent prompt.

Important:

- **No production-code edits.** If qa-runner finds a bug, it surfaces it. Re-route to `dev` for the fix.
- **No test writing.** Coverage gaps are reported, not filled. Re-route to `dev` (with `qa-engineer` skill loaded) for new tests.
- **Don't auto-fix.** Even an obvious flake is reported, not patched, so you see the signal.
- **Honest about what wasn't runnable.** If the MCP macOS workflow isn't configured and the app can't be driven automatically, say "manual flows skipped — automation not available", don't fake the result.

After the subagent returns, summarise in 2-3 sentences: top failures (if any), what's healthy, whether anything needs immediate routing to `dev` or `architect`.

$ARGUMENTS
