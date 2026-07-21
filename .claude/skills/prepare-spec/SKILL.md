---
name: prepare-spec
description: Validate repos.txt and create feature worktrees on feature/<spec-name> from origin/<default_branch>. Use when the user asks to prepare a spec, start feature worktrees, or run prepare-spec.
---

# prepare-spec

Create isolated feature worktrees under `specs/<spec-name>/repos/` for every repository listed in `repos.txt`.

## When to use

- "Prepare the `<spec-name>` spec"
- `/prepare-spec <spec-name>` (Claude Code), `$prepare-spec <spec-name>` (Codex), or `/skill prepare-spec <spec-name>` (Propio)
- Reopening an existing spec with retained feature branches (requires explicit reuse authorization)

## Rules

- Invoke the bundled helper for all Git mutations.
- Never guess base branches; the helper uses `git.default_branch` from the project map.
- If a reference clone is missing, direct the user to **setup-repositories**.

## Steps

1. Confirm `specs/<spec-name>/repos.txt` exists.
2. If reopening a spec and `feature/<spec-name>` branches already exist, obtain **explicit user authorization** to reuse them.
3. Run:

```sh
sh .claude/skills/prepare-spec/scripts/prepare-spec.sh project-repositories.yaml <spec-name>
```

Add `--reuse-branches` only after explicit user authorization to reuse retained branches.

4. Report prepared, skipped, or refused repositories.

## Helper behavior

- Validates every `repos.txt` entry against the project map.
- Requires `repos/<name>/` reference clones.
- Fetches and prunes every `origin` and verifies every `origin/<default_branch>` before creating the first worktree.
- Rolls back clean worktrees and unchanged branches created by the current invocation if a later creation fails.
- Skips an already-correct worktree on the expected feature branch even when it contains in-progress changes. A worktree on another branch is refused rather than skipped; other branch collisions require `--reuse-branches`.

See [AGENTS.md](../../../AGENTS.md) for branch and reopen guidance.
