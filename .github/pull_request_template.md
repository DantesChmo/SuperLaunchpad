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

## Test plan

- [ ] `xcodebuild -project SuperLaunchpad.xcodeproj -scheme SuperLaunchpad build` succeeds
- [ ] `xcodebuild -project SuperLaunchpad.xcodeproj -scheme SuperLaunchpad test` passes
- [ ] For UI changes: opened the project in Xcode, ran (⌘R), and verified the affected screens/interactions visually
