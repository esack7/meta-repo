---
name: setup-repositories
description: Clone missing reference repositories into repos/ from project-repositories.yaml. Use when the user asks to set up project repositories, initialize clones, or run setup-repositories. Never transcribe clone URLs or default branches; invoke the bundled helper only.
---

# setup-repositories

Clone missing reference repositories under `repos/<name>/` using Git coordinates read directly from `project-repositories.yaml`.

## When to use

- "Set up the project repositories"
- `/setup-repositories` (Claude Code) or `$setup-repositories` (Codex)
- Before **prepare-spec** when reference clones are missing

## Rules

- **Never** transcribe `git.clone_url`, `git.default_branch`, or improvise clone commands.
- **Never** fetch, pull, checkout, or reset existing valid clones.
- Explain helper output; do not bypass the helper.

## Steps

1. Resolve the meta-repo root and `project-repositories.yaml`.
2. Run the bundled helper:

```sh
sh .claude/skills/setup-repositories/scripts/setup-repositories.sh project-repositories.yaml
```

Optionally pass specific repository `name` values after the map path.

3. Report which repositories were cloned, which already existed, and any errors verbatim.

## Helper behavior

- Requires Git 2.5+.
- Validates repository names and constrained project-map formatting.
- Clones through a temporary directory under `repos/` on the same filesystem, verifies `origin` and default branch, then moves into place.
- Leaves existing clones with matching `origin` unchanged.

See [AGENTS.md](../../../AGENTS.md) for project-map schema and troubleshooting.
