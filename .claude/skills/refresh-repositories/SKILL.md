---
name: refresh-repositories
description: Fast-forward clean reference clones on their configured default branch. Use when the user asks to refresh reference clones, update repository context, or run refresh-repositories before cross-repo planning.
---

# refresh-repositories

Fast-forward reference clones in `repos/` on their configured default branch.

## When to use

- "Refresh the reference clones"
- Before cross-repo planning when current default-branch context matters
- `/refresh-repositories` (Claude Code), `$refresh-repositories` (Codex), or `/skill refresh-repositories` (Propio)

## Rules

- Invoke the bundled helper only; do not improvise fetch/merge commands.
- Never touches feature worktrees under `specs/*/repos/`.
- Refuses dirty, divergent, locally-ahead, or wrong-branch clones.

## Steps

1. Run:

```sh
sh .claude/skills/refresh-repositories/scripts/refresh-repositories.sh project-repositories.yaml
```

Optionally pass repository `name` values to limit scope.

2. Summarize which repositories were updated, up to date, or refused.

See [AGENTS.md](../../../AGENTS.md) for troubleshooting.
