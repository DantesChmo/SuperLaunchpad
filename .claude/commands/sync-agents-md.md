---
description: Compare the current branch against AGENTS.md and propose a patch to keep it accurate
argument-hint: (optional) section to focus on — "project map", "constants", "architecture", "gotchas"
---

Compare this branch's code against `AGENTS.md` and propose a concrete patch where the doc has drifted.

This is judgment-level work (deciding *what's worth documenting*), not mechanical extraction — delegate the synthesis to the `architect` subagent (Opus) via the `Agent` tool with `subagent_type=architect`. Hand it the relevant diff + the current `AGENTS.md` and ask for a unified-diff patch.

Steps the subagent should follow:

1. **Compute the diff range** against `origin/main`:
   ```bash
   BASE=$(git merge-base origin/main HEAD)
   git diff --stat "$BASE..HEAD"
   git diff --name-status --diff-filter=ACMRD "$BASE..HEAD"
   ```
2. **Read `AGENTS.md`** and walk through the sections most likely to drift:
   - **Project map (table)** — every new `.swift` file in `SuperLaunchpad/{Models,Views,Services,Database,Window,Helpers,ViewModels}/` should have a row. Deleted files should be removed. Renamed roles updated.
   - **Constants** — new namespaces or members in `Helpers/Constants.swift` not in the constants table.
   - **Architecture in 60 seconds** — did the data flow change? New entry point in `loadApps()`, a new watcher, a new gesture, a new persistence path?
   - **Domain gotchas** — *new* non-obvious behaviour added in this branch that a future developer wouldn't guess from reading the code. Be selective: not every quirk is a gotcha.
   - **Forbidden patterns** — has a new project-wide rule emerged in this branch worth codifying?
   - **Known limitations / dead ends** — did this branch *resolve* a limitation still listed as a dead end? Move it out.
   - **Conventions → SwiftUI / GRDB / Threading** — only update if the rule actually changed, not for cosmetic edits.
3. **If `$ARGUMENTS` is provided**, focus only on that section. Otherwise scan all.
4. **Produce output as a unified diff** (`@@` blocks with file paths), one hunk per change cluster. Group small adjacent edits.
5. **Flag uncertainty.** If unsure whether a new behaviour is "gotcha-worthy" or "obvious from code", surface it as an open question for the user — don't auto-decide.

Constraints:

- **Do NOT auto-apply the patch.** The user reviews and chooses what to apply.
- **Every proposed edit must reflect actual divergence** in the diff — no edits "for completeness".
- **If the branch has no meaningful drift**, say so in one sentence and stop. Empty diff is a valid answer.
- **Don't touch sections the diff doesn't justify.** "TL;DR", "Build, run, test", "Workflow" are stable; only update them if the branch genuinely changes them.

After the subagent returns, summarise in 2-3 sentences: what sections it proposed to touch, how many hunks, any uncertainty flags worth a quick decision.

$ARGUMENTS
