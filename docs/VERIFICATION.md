# Verification Status

This document records what the automated test suite verifies and what still requires manual or harness-based validation.

## Verified locally (`tests/run-tests.sh`)

- Shell syntax for all bundled helpers
- Skill `SKILL.md` frontmatter and `agents/openai.yaml` UI metadata presence
- Codex symlink resolution (`.agents/skills/*` → `.claude/skills/*`)
- Propio symlink resolution (`.propio/skills/*` → `.claude/skills/*`)
- Project-map constrained-layout parsing (positive and negative cases)
- Reference-clone setup, temporary-directory ownership, post-clone validation, refresh, and refusal paths
- Spec lifecycle helpers: `create-spec`, `prepare-spec`, and atomic-preflight/stale-metadata behavior in `close-spec`
- Worktree registration under paths containing spaces
- `repos.txt` validation
- `.gitignore` behavior for ignored clone/worktree paths and trackable spec documents

Run:

```sh
tests/run-tests.sh
```

## Unverified (requires external harness)

The following items from `docs/PLAN.md` are **not** covered by static tests in this repository:

| Item | Status | Notes |
|------|--------|-------|
| Skill validator CLI | **Unverified** | `skill-validator` is not installed in this environment. Tests use frontmatter grep only. |
| Claude Code native discovery | **Unverified in CI** | Symlink readability is tested. Live `claude skills list` smoke tests are not run in `tests/run-tests.sh` (see manual checklist below). |
| Codex native discovery | **Unverified** | `$setup-repositories` and sibling invocations require an interactive Codex session. Symlink readability is tested; live selector loading is not. |
| Propio native discovery | **Unverified** | `/skills` and `/skill setup-repositories` require an interactive Propio session. Symlink readability is tested; live selector loading is not. |
| Natural-language skill routing | **Unverified** | Requires live agent sessions in each tool. |

### Manual smoke checklist

When validating in a fresh environment:

1. Open the meta-repo root in Claude Code and confirm all five skills appear in the skill selector.
2. Run a non-destructive invocation such as `/setup-repositories` with `repositories: []`.
3. Open the meta-repo in Codex and confirm the same five skills appear via `.agents/skills` symlinks.
4. Run `$setup-repositories` with the empty project map.
5. Open the meta-repo in Propio, run `/skills`, and confirm the same five skills appear via `.propio/skills` symlinks.
6. Run `/skill setup-repositories` with the empty project map.
7. If any agent does not load symlinks, replace them with thin-wrapper skill directories per `docs/PLAN.md`.

If any harness above is unavailable, treat that discovery path as unverified rather than equivalent to passing `tests/run-tests.sh`.
