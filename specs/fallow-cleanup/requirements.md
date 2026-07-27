# Requirements: fallow-cleanup

## Summary

Make propio-providers and propio-agent clean under Fallow before strict release CI

## Goals

- Establish a repeatable, repository-root Fallow baseline for `propio-providers` and `propio-agent`, including the Fallow version, invocation, relevant configuration, and baseline results.
- Remediate every finding reported by the full-repository check in each repository so `fallow --fail-on-issues` exits successfully with zero findings.
- Leave each repository ready for a future strict PR-delta gate using `fallow audit --gate all`.
- Keep the cleanup isolated from the existing `automated-npm-releases` worktrees and their uncommitted changes.

## Non-goals

- Enabling, modifying, or deploying strict release CI in this spec.
- Changing release automation except where a repository's Fallow configuration or reproducibility tooling requires an explicitly scoped change.
- Editing reference clones or any existing feature worktree, including `automated-npm-releases`.

## Acceptance criteria

- [ ] `propio-providers` documents and commits a reproducible Fallow baseline (tool version, repository-root command, configuration, and result) appropriate to its existing tooling.
- [ ] `propio-agent` documents and commits a reproducible Fallow baseline (tool version, repository-root command, configuration, and result) appropriate to its existing tooling.
- [ ] From the root of each feature worktree, `fallow --fail-on-issues` completes with exit status 0 and reports zero findings.
- [ ] All Fallow findings are fixed in source, tests, configuration, or explicitly justified project policy; no unexplained blanket suppression is introduced merely to make the command pass.
- [ ] Each repository can run `fallow audit --gate all` as its strict PR-delta check, with any required invocation/configuration documented for subsequent CI enablement.
- [ ] Repository tests, linting, type checks, and package-specific validation affected by remediation pass.
- [ ] No file in `specs/automated-npm-releases/repos/` is changed by this work.

## Affected repositories

<!-- Confirmed names are listed in repos.txt -->

- `propio-providers` — provider-adapter package whose full source and tests must be made Fallow-clean.
- `propio-agent` — CLI agent package whose source, tooling, and configuration must be made Fallow-clean.

## Open questions

- What Fallow version and installation mechanism best fit each repository's existing package-management conventions?
- Which findings represent true code defects, and which require narrowly scoped, documented policy/configuration decisions?
- What exact CI command and changed-file/base-ref inputs should the later release-CI implementation use for `fallow audit --gate all`?
