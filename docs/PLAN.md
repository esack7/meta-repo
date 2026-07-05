# Meta-Repo Scaffold

## Summary

Create a reusable `meta-repo` following [The Meta Repo: The AI Map of Your Codebase](https://bsokol.substack.com/p/the-meta-repo-the-ai-map-of-your): ignored reference clones, a structured cross-repo project map, feature specifications, and isolated Git worktrees. Expose repository setup, safe reference-clone refresh, and the recurring specification workflow through project-local agent skills, with no top-level setup script or external YAML parser dependency.

## Implementation

- Initialize `meta-repo` as a Git repository without creating a commit or remote.
- Add canonical `AGENTS.md` guidance plus a small `CLAUDE.md` compatibility entrypoint.
- Add `project-repositories.yaml` as the structured project map. Start with `version: 1` and an empty `repositories: []`, plus comments that direct users to the schema guidance. Configured repositories use actual YAML fields rather than comment-only metadata:
  - `name`: unique local directory and `repos.txt` identifier. It must match `^[A-Za-z0-9][A-Za-z0-9._-]*$`, making it a single non-hidden path component with no separators or traversal segments.
  - `description`: concise repository purpose.
  - `git.clone_url` and `git.default_branch`: canonical Git coordinates; do not duplicate organization or repository fields derivable from the URL.
  - `context`: ordered context-file paths such as `AGENTS.md`, `CLAUDE.md`, and `README.md`.
  - `key_directories`: optional path and description entries.
  - `selection.use_for` and `selection.avoid_for`: structured guidance used when proposing affected repositories.
- Define a constrained serialization contract for Git-critical fields: repository entries and nested `git` blocks use fixed indentation and block style; `name`, `clone_url`, and `default_branch` are single-line scalars without inline comments, anchors, aliases, or flow-style mappings. The sole supported flow-style exception is the starter/no-op form `repositories: []`. Rich descriptive fields remain normal YAML. The helper rejects unsupported critical-field formatting instead of attempting to parse arbitrary YAML.
- Add concise, project-local skills with bundled specification templates and deterministic helpers where mutations are safety-relevant:
  - Use one shared deterministic project-map extraction helper for all four Git-touching skills: `setup-repositories`, `refresh-repositories`, `prepare-spec`, and `close-spec`. Agents may select repository names, but the helper reads and validates `name`, `clone_url`, and `default_branch` directly from `project-repositories.yaml`; agents never transcribe Git-critical values.
  - `setup-repositories` invokes its bundled POSIX `sh` helper with the project-map path. The helper deterministically enumerates repositories and extracts `name`, `git.clone_url`, and `git.default_branch` from the constrained critical-field layout, rejecting duplicate names, missing fields, or unsupported formatting. The agent explains results but never transcribes Git-critical values or improvises clone operations.
  - The setup helper checks for Git 2.5 or newer, revalidates the repository name and default-branch ref, anchors all paths beneath the meta-repo's `repos/` directory, and rejects conflicting paths. It clones missing repositories through a helper-owned temporary directory created beneath `repos/`, ensuring the final move remains on the same filesystem. It verifies the resulting `origin` URL and configured remote default branch against values read directly from the project map, then moves the validated clone into place. Existing valid clones are checked for an exact `origin` match and otherwise left exactly as-is: no fetch, pull, checkout, or reset. Cleanup is limited to temporary paths created by that helper invocation.
  - `refresh-repositories` invokes a bundled helper that reads the same critical fields directly from the project map. For each requested repository, it requires the reference clone's working tree to be clean, verifies `origin`, fetches with prune, requires the configured default branch to be checked out with no local-only commits or divergence, and advances it using fast-forward-only behavior. It refuses rather than stashing, resetting, switching branches, or merging divergent history.
  - `create-spec` gathers requirements, uses the project map to propose affected repositories, obtains user confirmation of the exact selection, and creates `requirements.md`, `design.md`, `tasks.md`, and a machine-readable `repos.txt` under `specs/<feature>/`. Spec names must match `^[a-z0-9][a-z0-9-]*$`. `repos.txt` is the sole input for later worktree operations. Readers trim surrounding whitespace, ignore blank lines and lines whose first non-whitespace character is `#`, and reject duplicate or unknown repository names.
  - `prepare-spec` validates every `repos.txt` entry against the project map and requires a corresponding clone under `repos/<name>/`. A missing clone causes a clear refusal directing the user to `setup-repositories`. It then fetches and prunes each selected repository's `origin`, verifies the configured `git.default_branch` exists remotely, and creates `feature/<spec-name>` worktrees under `specs/<feature>/repos/` from the latest `origin/<default-branch>`. An already-correct worktree is skipped; any other pre-existing local or remote feature branch causes a safe refusal unless the user explicitly authorizes reuse.
  - `close-spec` performs a two-phase safety check across all listed repositories before removing anything. It fetches and prunes every selected repository's `origin` so reachability checks use current remote refs; if any fetch fails, it defaults to refusing the entire close operation and removes nothing. An explicitly acknowledged offline-close path may proceed using last-known remote refs, but still requires every worktree to be clean, reports that remote reachability is stale, removes no branches, and retains all commits. After successful preflight, it removes worktrees and prunes worktree metadata, but never deletes local or remote branches and never deletes specification documents.
- Keep canonical skill contents under `.claude/skills/<skill-name>/` so Claude Code exposes the five workflows through `/skill-name`. Add corresponding `.agents/skills/<skill-name>` and `.propio/skills/<skill-name>` symlinks so Codex and Propio can discover the same skills without duplicated definitions. Live discovery tests are authoritative: if an agent does not load the symlinks, replace them with real compatibility skill directories containing thin `SKILL.md` wrappers that point to the canonical Claude skill and its resources; do not duplicate full workflow bodies.
- Keep safety-relevant Git and filesystem mutations in tested helpers bundled inside their owning skills; agents may select inputs and explain outcomes but must not reproduce or bypass helper logic. Do not expose root-level workflow scripts.
- Make the root `AGENTS.md` use `project-repositories.yaml` as its repository index and direct agents doing cross-repo work to load the selected clone context files in their configured order.
- Document that reference-clone working trees, not their Git metadata, remain untouched during feature work. Direct users to run `refresh-repositories` before cross-repo planning when current context matters.
- Document natural-language and tool-specific skill invocation, the project-map schema, `repos.txt` format, branch/base-ref behavior, context freshness, specification lifecycle, manual branch cleanup, and troubleshooting.
- Treat spec names as durable identifiers. Reopening an existing spec means running `prepare-spec` against its existing directory and explicitly authorizing reuse of retained feature branches; a new iteration uses a new spec name. Document safe manual deletion of fully merged local and remote feature branches when users want to retire them.
- Document reuse as a template workflow: copy the scaffold directory or publish it as a Git-host template, populate `project-repositories.yaml`, run `setup-repositories`, then create the project's initial commit and remote outside the scaffold automation.
- Use the exact root `.gitignore` entries `/repos/` and `/specs/*/repos/`, leaving `specs/*/*.md` and `specs/*/repos.txt` tracked.

## Interfaces

```text
Codex:       $setup-repositories
Claude Code: /setup-repositories
Propio:      /skill setup-repositories

Codex:       $refresh-repositories
Claude Code: /refresh-repositories
Propio:      /skill refresh-repositories

Codex:       $create-spec <feature description>
Claude Code: /create-spec <feature description>
Propio:      /skill create-spec <feature description>
```

The same tool-specific prefix applies to `prepare-spec <spec-name>` and `close-spec <spec-name>`. Natural-language requests such as "set up the project repositories," "refresh the reference clones," or "create a spec for tags" may also trigger the skills. No separate custom slash-command files are added.

## Verification

- Run shell syntax checks on any deterministic helper bundled inside a skill.
- Validate each skill's metadata and structure with the skill validator.
- Use temporary local Git repositories to test skill-driven cloning, repeat setup, spec creation, worktree creation, and cleanup.
- Verify `repositories: []` is a successful no-op with no filesystem changes.
- Verify the helper rejects malformed, duplicate, missing, ambiguously formatted, or unsupported Git-critical fields directly from the project map, plus unsafe names, invalid branch refs, path traversal, conflicting paths, post-clone remote mismatches, unavailable configured default branches, and existing-clone remote mismatches.
- Verify duplicate repository names, invalid `repos.txt` entries, and existing feature-branch collisions fail clearly.
- Verify `setup-repositories` never updates existing clones, while `prepare-spec` fetches before selecting its configured base ref and fails clearly with `setup-repositories` guidance when a selected clone is missing.
- Verify `refresh-repositories` fast-forwards clean default-branch clones, refuses dirty, divergent, locally-ahead, or wrong-branch clones, and updates context files without touching feature worktrees.
- Verify `create-spec` presents its proposed repository selection for confirmation and persists exactly the confirmed names to `repos.txt`.
- Verify `close-spec` detects dirty worktrees and unpushed commits, never deletes branches, and removes nothing if any repository fails preflight.
- Exercise one two-repository scenario with one clean worktree and one dirty worktree, then confirm neither is removed.
- Verify normal close refuses on fetch failure, explicitly acknowledged offline close uses last-known refs while preserving branches, and both paths retain clean-worktree and atomic-preflight guarantees.
- Verify an existing closed spec can be reopened only through explicit branch reuse and that safe manual cleanup guidance does not delete unmerged or unpushed branches.
- Verify natural-language and explicit invocations select the intended skill and produce the expected specification files.
- Start fresh Codex, Claude Code, and Propio sessions from the meta-repo, confirm all five skills appear in each tool's selector, and run non-destructive discovery smoke tests through the native invocation syntax. If symlink discovery fails, install the thin-wrapper fallback and repeat the test. If a harness is unavailable, report that discovery path as unverified rather than treating static file validation as equivalent.
- Confirm `/repos/` and `/specs/*/repos/` stay absent from Git status while specification Markdown and `repos.txt` remain trackable.

## Assumptions

- This is a generic scaffold; no real repository URLs are included yet.
- No root `setup.sh`, `yq`, or external YAML parser dependency is required. Bundled helpers parse only the documented constrained layout for Git-critical fields and reject unsupported representations. Helpers target macOS/Linux using POSIX `sh` and avoid Bash 4-only features.
- Project-local skills are the canonical workflow interface; Codex, Claude Code, and Propio use their native invocation syntax over the same skill definitions.
- Each skill includes `SKILL.md` and agent UI metadata, and keeps reusable templates or deterministic helpers bundled with the skill.
- Feature work never modifies reference-clone working trees; fetches, worktree metadata, and explicitly requested fast-forward refreshes may update their Git metadata or checked-out default branch.
- `setup-repositories` requires network access only when cloning a missing repository.
- `refresh-repositories` requires network access and never performs non-fast-forward updates or resolves dirty/divergent clones automatically.
- `prepare-spec` requires network access to refresh remote refs and refuses to create worktrees when fetch fails or the configured `origin/<default-branch>` does not exist. It never guesses `main`, `master`, or another base branch.
- `close-spec` normally requires network access to refresh remote refs. Its explicit offline-close path is a degraded, acknowledged mode that relies on last-known remote refs and remains non-destructive to branches and commits.
- Multiple specifications may remain active concurrently. Their distinct `specs/<spec-name>/repos/` paths and `feature/<spec-name>` branches provide isolation. `create-spec` rejects an existing name, while `prepare-spec` may reopen that existing spec through explicit retained-branch reuse.
- `close-spec` defaults to refusing worktrees with apparently unpushed commits, permits explicit acknowledgement because the local branch is retained, and never performs branch deletion.
- The existing empty `meta-repo/` is retained and populated during implementation.
