---
name: close-spec
description: Safely remove feature worktrees for a specification without deleting branches or spec documents. Use when the user asks to close a spec or run close-spec.
---

# close-spec

Remove feature worktrees for `specs/<spec-name>/` after a two-phase safety preflight.

## When to use

- "Close the `<spec-name>` spec"
- `/close-spec <spec-name>` or `$close-spec <spec-name>`

## Rules

- Invoke the bundled helper only.
- **Never** delete local or remote branches or specification Markdown files.
- If preflight fails for any repository, **nothing** is removed.

## Steps

1. Confirm the user wants to close `specs/<spec-name>/` worktrees (not delete the spec).
2. If worktrees may have unpushed commits, warn and obtain `--acknowledge-unpushed` authorization if they still want to close.
3. If network fetch may fail, use normal close first; offer `--offline` only with explicit acknowledgment of stale remote reachability.
4. Run:

```sh
sh .claude/skills/close-spec/scripts/close-spec.sh project-repositories.yaml <spec-name>
```

Optional flags (only with explicit user authorization):

- `--acknowledge-unpushed` — close despite unpushed commits (branch retained)
- `--offline` — use last-known remote refs; no branch removal; reports stale reachability

5. Remind the user that `feature/<spec-name>` branches remain for manual cleanup after merge.

See [AGENTS.md](../../../AGENTS.md) for manual branch cleanup guidance.
