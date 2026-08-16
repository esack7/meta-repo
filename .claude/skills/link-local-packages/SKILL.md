---
name: link-local-packages
description: Link local package checkouts so a change in one repository is testable in the repositories that depend on it without publishing to npm. Use when the user asks to link packages locally, test cross-repo changes, work on a dependency and its consumer together, or run link-local-packages.
---

# link-local-packages

Make a change in one repository testable in the repositories that consume it, without publishing a package version first.

## When to use

- "I changed the providers package, let me test it in the agent"
- Any feature that spans a package and one of its consumers
- Before publishing, to verify a consumer against unreleased dependency code
- `/link-local-packages` (Claude Code), `$link-local-packages` (Codex), `/skill link-local-packages` (Propio), `/link-local-packages` (Cursor)

## The problem this solves

Consumers declare their dependency by version, so `node_modules` normally holds the copy published to npm. Without linking, testing a dependency change means publishing a version first — a release round-trip per iteration.

Linking replaces the published copy inside the consumer's `node_modules` with a symlink to the local checkout. The consumer then resolves the dependency straight from your working tree.

## Rules

- Invoke the bundled helper only; do not improvise `npm link`, `ln -s`, or `file:` dependency edits.
- **Never mix contexts.** Link reference clones to reference clones, or one spec's worktrees to that same spec's worktrees. Linking a feature worktree to a reference clone silently tests the wrong branch.
- Never commit a link. The helper only writes inside `node_modules/` (ignored) and never edits `package.json`, a lockfile, or Git state.
- `npm install` and `npm ci` in a consumer silently remove links. Re-run `link` after either.
- Linking bypasses the package's `files` array and `exports` map, so it cannot catch packaging bugs. Verify with a real tarball before publishing (see below).

## Safety model

The helper follows the same preflight-first contract as the other workflows in this repo:

- **Every edge is validated before any change is applied.** If one consumer fails preflight, nothing is linked anywhere — a later failure cannot leave earlier consumers half-linked.
- **Only symlinks pointing at the expected local checkout are removed.** A symlink owned by something else (pnpm, a manual link) is reported as `foreign` and left in place; `unlink` skips it and `link` refuses to clobber it.
- **Destinations are anchored to the physical `node_modules` directory.** A scope directory that is itself a symlink resolving outside `node_modules` is refused, so a write cannot be redirected out of the tree.

When preflight fails, the helper reports every problem and exits without touching the filesystem. Resolve the reported condition and rerun; do not work around it by deleting paths by hand unless the message asks you to.

## Steps

1. Check current state:

```sh
sh .claude/skills/link-local-packages/scripts/link-local-packages.sh project-repositories.yaml status
```

Add `--spec <spec-name>` to operate on `specs/<spec-name>/repos/` instead of `repos/`. Add `--only <repository-name>` (repeatable) to narrow scope.

Each line reports one dependency edge:

| State | Meaning |
|-------|---------|
| `linked` | Symlinked to the expected local checkout |
| `dangling` | Linked, but the local checkout is missing |
| `foreign` | A symlink to something else; not managed by this helper |
| `registry` | The published copy is installed |
| `absent` | Nothing installed at that path |
| `unsafe` | The scope directory is a symlink resolving outside `node_modules` |

2. Build the dependency so the consumer has something to resolve:

```sh
cd repos/<dependency-name> && npm run build
```

3. Link:

```sh
sh .claude/skills/link-local-packages/scripts/link-local-packages.sh project-repositories.yaml link
```

The helper reads every local `package.json`, discovers which local checkouts depend on which, and links each edge it finds. New repositories are picked up automatically once they are in the project map and declare the dependency.

4. Iterate. Leave a watch build running in the dependency so each save reaches the consumer:

```sh
cd repos/<dependency-name> && npx tsc --watch
```

The consumer's dev command, build, and tests all resolve through the symlink, so no consumer-side step changes.

5. Unlink when finished:

```sh
sh .claude/skills/link-local-packages/scripts/link-local-packages.sh project-repositories.yaml unlink
```

`unlink` removes only the symlinks this helper would have created; it never deletes a real installed package or a `foreign` symlink. Because the published copy was replaced when linking, run `npm ci` in each consumer afterward to reinstall it.

## Before publishing

A link resolves the dependency's `dist/` directly, so it will happily pass even if `files` or `exports` would omit that code from the published tarball. Validate the real artifact first:

```sh
cd repos/<dependency-name> && npm pack
cd ../<consumer-name> && npm i ../<dependency-name>/<tarball>.tgz
```

Run the consumer's tests, then `npm ci` to restore, and re-`link` if you are still iterating.

## Reporting

Summarize which edges were linked, unlinked, or left alone, and state whether a build step was run. If the helper warned that a dependency has no `dist/`, say so — the consumer will fail to resolve it until it is built.

See [AGENTS.md](../../../AGENTS.md) for the repository index and the reference-clone versus worktree boundary.
