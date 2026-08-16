# Meta-Repo

A reusable home for planning and implementing changes that span multiple Git repositories.

This scaffold gives an AI coding agent a map of your project without combining your repositories or checking their contents into another repository. It keeps local reference clones for context, creates isolated worktrees for feature work, and tracks the specifications that connect everything together.

The approach is inspired by [The Meta Repo: The AI Map of Your Codebase](https://bsokol.substack.com/p/the-meta-repo-the-ai-map-of-your/).

## What you get

- A structured catalog of your repositories in `project-repositories.yaml`
- Ignored reference clones under `repos/` for browsing and cross-repository planning
- Tracked requirements, designs, and task lists under `specs/`
- Isolated feature worktrees for each active specification
- Project-local workflows for Codex, Claude Code, and Propio
- Guardrails around cloning, refreshing, creating worktrees, and closing completed work

Your source repositories remain independent. The meta-repo tracks the map and the plans; it does not track cloned source code.

## Prerequisites

- Git 2.17 or newer
- macOS or Linux with a POSIX-compatible shell
- [Codex](https://openai.com/codex/), Claude Code, or Propio for the agent-driven workflows
- Access to every Git remote you add to the project map

The bundled helpers do not require `yq` or another YAML parser.

## Set up your meta-repo

### 1. Create your copy

Copy this scaffold into a new directory, or publish it as a Git hosting template and create a repository from that template. Then initialize or connect the copy as your own Git repository as needed.

### 2. Describe your repositories

Add one block to `project-repositories.yaml` for each repository in your project. A new copy of the scaffold starts with `repositories: []`:

```yaml
version: 1

repositories:
  - name: api-service
    description: Public HTTP API and application services
    git:
      clone_url: git@github.com:your-org/api-service.git
      default_branch: main
    context:
      - AGENTS.md
      - README.md
    key_directories:
      - path: src/handlers
        description: HTTP request handlers
    selection:
      use_for: API endpoints, request validation, and service behavior
      avoid_for: Browser UI and mobile client work

  - name: web-app
    description: Customer-facing web application
    git:
      clone_url: git@github.com:your-org/web-app.git
      default_branch: main
    context:
      - AGENTS.md
      - README.md
    selection:
      use_for: Browser UI, client state, and frontend routing
      avoid_for: Backend-only implementation changes
```

The descriptive fields help an agent choose the right repositories and navigate them efficiently:

| Field | Purpose |
|---|---|
| `name` | Unique local directory name and stable repository identifier |
| `description` | Short explanation of the repository's responsibility |
| `git` | Canonical clone URL and default branch |
| `context` | Files the agent should read, in order, before working in the repository |
| `key_directories` | Optional landmarks for navigating a larger codebase |
| `selection` | Guidance about when the repository should or should not be included in a feature |

The Git-critical fields use a deliberately constrained YAML layout so the safety helpers can parse them without an external dependency. Preserve the indentation and block structure shown above. See [AGENTS.md](AGENTS.md) for the complete schema and validation rules.

### 3. Clone the reference repositories

Open the meta-repo root in your coding agent and ask it to set up the project repositories:

```text
Codex:       $setup-repositories
Claude Code: /setup-repositories
Propio:      /skill setup-repositories
Natural language: "Set up the project repositories."
```

This creates one clone per configured repository under `repos/<name>/`. Existing valid clones are left unchanged.

### 4. Commit your scaffold

Commit the meta-repo configuration and guidance to your own remote. The cloned repositories under `repos/` are ignored by Git.

At this point the meta-repo is ready for day-to-day cross-repository work.

## Work on a feature

The normal lifecycle is:

### 1. Create a specification

```text
Codex:       $create-spec add organization-wide tags
Claude Code: /create-spec add organization-wide tags
Propio:      /skill create-spec add organization-wide tags
Natural language: "Create a spec for organization-wide tags."
```

The agent gathers requirements, proposes affected repositories from the project map, and asks you to confirm the exact selection. It then creates:

```text
specs/organization-wide-tags/
├── requirements.md
├── design.md
├── tasks.md
└── repos.txt
```

These files are tracked. `repos.txt` is the authoritative list of repositories involved in the feature.

If the confirmed repository selection needs correction before preparation, rerun `create-spec` through the agent and provide the complete replacement list. The guarded amendment path updates `repos.txt` atomically and refuses changes after feature branches or worktrees exist.

### 2. Prepare isolated worktrees

```text
Codex:       $prepare-spec organization-wide-tags
Claude Code: /prepare-spec organization-wide-tags
Propio:      /skill prepare-spec organization-wide-tags
```

The helper fetches and validates every repository before making the first branch or worktree. It then creates a `feature/organization-wide-tags` branch from each configured remote default branch and checks it out beneath:

```text
specs/organization-wide-tags/repos/<repository-name>/
```

Implementation happens in these feature worktrees—not in the reference clones under `repos/`.

Rerunning preparation safely skips a registered worktree already on the expected feature branch, including one with in-progress changes. A worktree on a different branch is refused rather than skipped. Existing files are never cleaned, reset, or overwritten.

### 3. Implement and review

Ask your agent to work from the specification directory. Because the spec, selected repositories, and repository-specific context are all explicit, it can reason across the feature while keeping changes isolated in the correct worktrees.

When one selected repository publishes a package that another consumes, link them so the change is testable immediately instead of after a release:

```text
Codex:       $link-local-packages
Claude Code: /link-local-packages
Propio:      /skill link-local-packages
Cursor:      /link-local-packages
Natural language: "Link the local packages for this spec."
```

Pass `--spec <spec-name>` to link the feature worktrees rather than the reference clones. Reference clones and worktrees are never linked to each other, because that would test the wrong branch.

Commit and publish changes in each source repository using your normal Git and review process.

### 4. Close the specification

After the work is safely committed:

```text
Codex:       $close-spec organization-wide-tags
Claude Code: /close-spec organization-wide-tags
Propio:      /skill close-spec organization-wide-tags
```

The close workflow checks every selected worktree before removing any of them. It removes worktrees and prunes their metadata, but it does not delete feature branches or specification documents.

## Keep reference context current

Reference clones are intentionally stable: setup does not pull repositories that already exist. Before planning against current upstream code, run:

```text
Codex:       $refresh-repositories
Claude Code: /refresh-repositories
Propio:      /skill refresh-repositories
Natural language: "Refresh the reference clones."
```

Refresh only fast-forwards clean clones on their configured default branch. It refuses dirty, divergent, locally ahead, or wrong-branch clones instead of altering them unexpectedly.

## Directory layout

```text
.
├── AGENTS.md                    # Canonical agent guidance and detailed reference
├── CLAUDE.md                    # Claude Code entrypoint
├── project-repositories.yaml    # Your project map
├── repos/                       # Ignored reference clones
├── specs/
│   └── <spec-name>/
│       ├── requirements.md      # Tracked
│       ├── design.md            # Tracked
│       ├── tasks.md             # Tracked
│       ├── repos.txt            # Tracked repository selection
│       └── repos/               # Ignored feature worktrees
├── .claude/skills/              # Canonical workflow definitions and helpers
├── .agents/skills/              # Thin Codex discovery wrappers for canonical workflows
├── .propio/skills/              # Propio links to the same workflows
└── .cursor/                     # Cursor command and rule wrappers
    ├── commands/                # Slash-command entrypoints
    └── rules/                   # Agent-requested rule entrypoints
```

## Safety model

The repository's Git and filesystem workflows run through tested, bundled helpers. They validate repository names, remote URLs, default branches, worktree state, and branch collisions before making changes. They also avoid guessing a default branch or silently resolving dirty or divergent state.

The key boundary is simple:

- `repos/` is local reference context.
- `specs/<name>/repos/` contains active feature worktrees.
- Specification documents and the project map are the durable, tracked coordination layer.

For branch reuse, offline close behavior, troubleshooting, and the full operating contract, read [AGENTS.md](AGENTS.md).

## Verify the scaffold

Run the local integration suite after changing the project-map format, skills, or workflow helpers:

```sh
tests/run-tests.sh
```

See [docs/VERIFICATION.md](docs/VERIFICATION.md) for automated coverage and the remaining interactive smoke checks.
