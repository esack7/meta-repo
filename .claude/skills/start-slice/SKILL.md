---
name: start-slice
description: Start the next planned PR slice of a prepared specification, preserving registered branches and checking dependencies.
---

# start-slice

Read `specs/<spec>/delivery.json` and [delivery guidance](../../../../docs/DELIVERY.md).
Select the next authorized slice whose dependencies are merged. Run:
`sh .claude/skills/start-slice/scripts/start-slice.sh project-repositories.yaml <spec> <slice>`.
Use `--branch-prefix <namespace>` to customize the default `codex/` namespace.
Invoke the bundled helper for branch switching and registration. It refuses dirty
or unregistered worktrees, collisions, and unmerged dependencies. Do not bypass a
refusal by changing the status alone. Keep the user's working agreement in effect;
a new slice does not automatically require fresh approval. Load repository context
in configured order before implementing. Record PR and acceptance evidence at the
review handoff, and state the next action.
