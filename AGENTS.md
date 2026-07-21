# Meta-Repo Agent Guidance

This meta-repo maps multiple Git repositories for cross-repo planning and feature work. Reference clones live under `repos/` (ignored by Git). Feature work uses isolated worktrees under `specs/<spec-name>/repos/` (also ignored). Specification documents and `repos.txt` are tracked.

Inspired by [The Meta Repo: The AI Map of Your Codebase](https://bsokol.substack.com/p/the-meta-repo-the-ai-map-of-your).

## Repository index

Use [`project-repositories.yaml`](project-repositories.yaml) as the canonical project map. For each repository entry:

| Field | Purpose |
|-------|---------|
| `name` | Unique local directory name and `repos.txt` identifier. Must match `^[A-Za-z0-9][A-Za-z0-9._-]*$` (single path component, no separators or traversal). |
| `description` | Concise repository purpose. |
| `git.clone_url` | Canonical clone URL. |
| `git.default_branch` | Default branch ref (for example `main`). |
| `context` | Ordered context-file paths (for example `AGENTS.md`, `CLAUDE.md`, `README.md`) to load when working in that clone. |
| `key_directories` | Optional `path` and `description` entries for navigation. |
| `selection.use_for` | When to propose this repository for a feature. |
| `selection.avoid_for` | When not to propose this repository. |

Git-critical fields (`name`, `git.clone_url`, `git.default_branch`) use a constrained layout documented below. Workflow helpers read these values directly; agents must not transcribe or improvise them.

### Example entry

```yaml
repositories:
  - name: api-service
    description: Public HTTP API
    git:
      clone_url: https://github.com/example/api-service.git
      default_branch: main
    context:
      - AGENTS.md
      - README.md
    key_directories:
      - path: src/handlers
        description: Route handlers
    selection:
      use_for: API endpoints, request validation, OpenAPI changes
      avoid_for: Frontend UI, mobile clients
```

### Constrained Git-critical layout

Helpers accept only this formatting for Git-critical fields:

- Top level: `version: 1` and `repositories:` as a block list, or the starter form `repositories: []`.
- Each repository block starts with `  - name: <value>` (two spaces, block style).
- The nested `git:` block uses four-space indentation; `clone_url` and `default_branch` use six-space indentation.
- `name`, `clone_url`, and `default_branch` are single-line scalars with no inline comments, YAML anchors, aliases, or flow-style mappings.

Rich descriptive fields (`description`, `context`, `key_directories`, `selection`) use normal YAML. Unsupported critical-field formatting is rejected.

## Cross-repo work

1. Load [`project-repositories.yaml`](project-repositories.yaml) to see which repositories exist and how they relate.
2. For the repositories selected for your task (from a spec's `repos.txt` or explicit user direction), open the reference clone under `repos/<name>/` and read each path listed in `context` **in configured order** before making changes.
3. Reference-clone **working trees** are not modified during feature work. Feature changes happen in worktrees under `specs/<spec-name>/repos/`. Fetches, worktree metadata, and explicit fast-forward refreshes may update Git metadata or the checked-out default branch of reference clones.
4. When current remote context matters (planning, comparing branches, verifying upstream state), run **refresh-repositories** on the relevant reference clones before cross-repo planning.

## Workflows (skills)

Invoke workflows through your agent's native skill syntax or natural language.

| Workflow | Codex | Claude Code | Propio | Natural language examples |
|----------|-------|-------------|--------|---------------------------|
| Clone missing reference repos | `$setup-repositories` | `/setup-repositories` | `/skill setup-repositories` | "set up the project repositories" |
| Fast-forward reference clones | `$refresh-repositories` | `/refresh-repositories` | `/skill refresh-repositories` | "refresh the reference clones" |
| Start a feature spec | `$create-spec <description>` | `/create-spec <description>` | `/skill create-spec <description>` | "create a spec for tags" |
| Create feature worktrees | `$prepare-spec <spec-name>` | `/prepare-spec <spec-name>` | `/skill prepare-spec <spec-name>` | "prepare the tags spec" |
| Remove feature worktrees | `$close-spec <spec-name>` | `/close-spec <spec-name>` | `/skill close-spec <spec-name>` | "close the tags spec" |

Canonical skills live under `.claude/skills/<skill-name>/`. Codex discovers thin compatibility wrappers under `.agents/skills/<skill-name>/`; those wrappers point back to the canonical skill and contain no helper copies. Propio discovers the canonical definitions through `.propio/skills/<skill-name>` symlinks.

**Safety rule:** Git and filesystem mutations run only through bundled skill helpers. Agents select inputs and explain results; they do not reproduce or bypass helper logic.

### setup-repositories

Clones missing repositories into `repos/<name>/`. Existing valid clones are left exactly as-is (no fetch, pull, checkout, or reset). Requires network only when cloning.

### refresh-repositories

Fast-forwards clean reference clones on their configured default branch. Refuses dirty, divergent, locally-ahead, or wrong-branch clones. Never touches feature worktrees.

### create-spec

Gathers requirements, proposes affected repositories from the project map, obtains confirmation, and creates `specs/<spec-name>/` with `requirements.md`, `design.md`, `tasks.md`, and `repos.txt`.

- Spec names must match `^[a-z0-9][a-z0-9-]*$` and must not collide with an existing spec directory.
- `repos.txt` lists one repository `name` per line; it is the sole input for later worktree operations.
- Before preparation, an explicitly confirmed correction may atomically replace `repos.txt` through the helper's `--amend` mode. Amendment is refused after any feature branch, worktree, or worktree registration exists so historical repository selection remains durable.

### prepare-spec

Validates `repos.txt`, requires reference clones under `repos/<name>/`, fetches and prunes `origin`, and verifies every `origin/<default_branch>` before creating anything. It then creates `feature/<spec-name>` worktrees under `specs/<spec-name>/repos/`, rolling back newly created clean worktrees and unchanged branches if a later creation fails. It skips an already-correct worktree on the expected feature branch without requiring it to be clean. A worktree on another branch is refused, as are pre-existing feature branches unless you explicitly authorize reuse.

### close-spec

Two-phase safety check across all listed repositories. On success, removes worktrees and prunes worktree metadata only—never deletes local or remote branches or specification documents.

## repos.txt format

- One repository `name` per line (must exist in `project-repositories.yaml`).
- Readers trim surrounding whitespace.
- Blank lines and lines whose first non-whitespace character is `#` are ignored.
- Duplicate or unknown names are rejected.

## Branches and base refs

- Feature branches: `feature/<spec-name>` created from `origin/<git.default_branch>` at prepare time.
- Helpers never guess `main`, `master`, or another base branch; they use only `git.default_branch` from the project map.
- Spec names are durable identifiers. Reopening an existing spec means running `prepare-spec` against its existing directory with explicit authorization to reuse retained feature branches. A new iteration uses a new spec name.

## Context freshness

- **setup-repositories** does not update existing clones.
- **prepare-spec** fetches before selecting its base ref; it fails with setup guidance when a selected clone is missing.
- **refresh-repositories** updates reference clones when you need current default-branch context.
- **close-spec** fetches during normal preflight; acknowledged offline close uses last-known remote refs and reports that reachability is stale.

## Specification lifecycle

1. **create-spec** — requirements, design, tasks, confirmed `repos.txt`.
2. **prepare-spec** — feature worktrees on `feature/<spec-name>`.
3. Implement in worktrees under `specs/<spec-name>/repos/` (not in reference clones).
4. **close-spec** — remove worktrees when done; branches and spec documents remain.

Multiple specs may be active concurrently; paths and branch names provide isolation.

### Reopening a closed spec

Run `prepare-spec <spec-name>` on the existing spec directory and explicitly authorize reuse of retained `feature/<spec-name>` branches.

### Manual branch cleanup

After a feature is fully merged, you may delete local and remote `feature/<spec-name>` branches manually when you want to retire them. Do not delete unmerged or unpushed branches you still need. **close-spec** never performs branch deletion.

## Reuse as a template

1. Copy this scaffold or publish it as a Git-host template.
2. Populate `project-repositories.yaml`.
3. Run **setup-repositories**.
4. Create the project's initial commit and remote outside scaffold automation.

## Troubleshooting

| Problem | Action |
|---------|--------|
| Helper rejects project map formatting | Fix `name`, `git.clone_url`, and `git.default_branch` to match the constrained layout. |
| prepare-spec says clone missing | Run **setup-repositories** for that repository. |
| refresh-repositories refuses | Clean the working tree, check out the configured default branch, resolve divergence manually, then retry. |
| prepare-spec branch collision | Use a new spec name, or rerun with explicit branch reuse authorization. |
| close-spec refuses on fetch failure | Fix network or use acknowledged offline close; nothing is removed on failure. |
| close-spec reports unpushed commits | Push, acknowledge retention, or keep the worktree open. |
| Dirty worktree blocks close | Commit, stash elsewhere, or discard changes in the **worktree** (not the reference clone). |

## Agent context loading

When working across repositories for a spec or explicit selection:

1. Read `specs/<spec-name>/repos.txt` (or the user-confirmed list).
2. For each name, resolve `repos/<name>/` (reference) or `specs/<spec-name>/repos/<name>/` (active feature worktree).
3. Load each repository's `context` files from the project map in order before proposing or making changes.
