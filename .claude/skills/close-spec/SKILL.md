---
name: close-spec
description: Safely remove feature worktrees for a specification without deleting branches or spec documents. Use when the user asks to close a spec or run close-spec.
---

# close-spec

Remove feature worktrees for `specs/<spec-name>/` after a two-phase safety preflight.

## When to use

- "Close the `<spec-name>` spec"
- `/close-spec <spec-name>` (Claude Code), `$close-spec <spec-name>` (Codex), or `/skill close-spec <spec-name>` (Propio)

## Rules

- Invoke the bundled helper only.
- **Never** delete local or remote branches or specification Markdown files.
- If preflight fails for any repository, **nothing** is removed.

## Steps

1. Use existing authorization to close the worktrees; do not ask again when the user already requested it. Inspect `spec-status` first for delivery-aware specs. Never infer whole-spec completion from one merged slice.
2. If worktrees may have unpushed commits, warn and obtain `--acknowledge-unpushed` authorization if they still want to close.
3. If network fetch may fail, use normal close first; offer `--offline` only with explicit acknowledgment of stale remote reachability.
4. Run:

```sh
sh .claude/skills/close-spec/scripts/close-spec.sh project-repositories.yaml <spec-name>
```

Optional flags (only with explicit user authorization):

- `--acknowledge-unpushed` — close despite unpushed commits (branch retained)
- `--worktrees-only` — explicitly requested cleanup before acceptance is complete; does not change delivery status or bypass other safety checks
- `--offline` — use last-known remote refs; no branch removal; reports stale reachability

5. Report worktree cleanup separately from implementation completion. All original and registered slice branches remain. Delivery-aware normal close requires verified acceptance and current merge evidence; offline early cleanup needs `--worktrees-only`. Legacy specs do not certify acceptance. See [delivery guidance](../../../docs/DELIVERY.md).

See [AGENTS.md](../../../AGENTS.md) for manual branch cleanup guidance.
