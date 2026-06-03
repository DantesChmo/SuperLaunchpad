## Summary

<!-- 1–3 bullets describing what changed and why. -->

-
-

## AGENTS.md

The repo's source of truth for AI agents is [`AGENTS.md`](../AGENTS.md). Tick exactly one:

- [ ] No structural / convention / behavioural changes — `AGENTS.md` is unaffected.
- [ ] Updated `AGENTS.md` in this PR to match the change.
- [ ] Ran `/sync-agents-md` in Claude Code and applied the suggested hunks.
- [ ] Structural changes were made, but `AGENTS.md` is intentionally not updated. Reason: <!-- explain -->

The pre-push hook prints a drift report. If it warned, address it here before merging.

## Tests

- [ ] Unit tests added/updated in `SuperLaunchpadTests/` for the changed behaviour
- [ ] UI test added/updated in `SuperLaunchpadUITests/` (only if a new user-observable flow was introduced)
- [ ] OR: no test added because — <!-- explain (cosmetic / infra / etc.) -->

## Regression

- [ ] `xcodebuild ... build` succeeds locally
- [ ] `xcodebuild ... test` passes locally
- [ ] Ran `/regression-check` in Claude Code and the report is clean (for non-trivial changes)
- [ ] For UI changes: opened the project in Xcode (⌘R) and verified the affected flows visually

## Manual verification checklist (UI changes only)

<!-- 3–5 subjective items the test suite can't capture: animation feel, hover timing, focus order, VoiceOver narrative. Delete this block for non-UI PRs. -->

-
-
-
