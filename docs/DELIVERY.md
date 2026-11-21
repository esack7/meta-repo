# Delivering a multi-repository specification

`requirements.md` owns intended behavior and acceptance descriptions. `design.md`
owns design decisions. `delivery.json` owns slice order, dependencies, PRs, status,
and commit-specific evidence. `tasks.md` links to that record rather than copying
its status. Commit the plan at the start and update the delivery record at each
review handoff and merge. Delivery helpers require Python 3.9+; no Python packages are needed.

## Plan once, keep moving

For an implementation request, establish the working agreement from existing user
instructions. Record it in `working_agreement`; the file documents authorization,
it cannot grant new authorization. Continue through approved slices and routine,
in-scope fixes without asking the user to repeat instructions. Assessment-only
requests stay assessment-only. Ask about material scope changes or actions outside
the agreement. Merging, publication, and sending review replies require applicable
user authorization; do not infer them from a status value.

At each handoff report the completed slice, acceptance evidence, remaining slices,
next action, and any actual decision needed. After a merge, reconcile state and
continue the next authorized slice. Do not recommend closing the whole spec just
because one pair of PRs merged.

## Delivery record

Delivery tracking is opt-in for each spec. New specs use the Markdown task
checklist. Enable tracking explicitly for a new or existing spec:

```sh
sh .claude/skills/spec-status/scripts/spec-status.sh project-repositories.yaml example init
```

Edit this tracked file deliberately, then run `status` to validate it. Repository
selection remains exclusively in `repos.txt`; do not duplicate clone URLs or base
branches. Example (replace the sample repository with a selected repository):

```json
{
  "version": 1,
  "spec": "example",
  "working_agreement": "Implement approved slices and fix in-scope review findings; ask before merging or publishing.",
  "criteria": {
    "a1": "Interrupted operations retain their completed results"
  },
  "slices": [
    {
      "id": "recovery",
      "repo": "api-service",
      "depends_on": [],
      "criteria": ["a1"],
      "status": "planned",
      "branch": null,
      "pr": null,
      "evidence": {},
      "note": "Start with an interrupted-operation regression fixture"
    }
  ]
}
```

Slice and criterion IDs are lowercase slugs. Dependencies name earlier slices,
which prevents cycles. `start-slice` records a unique, increasing `start_order` when
it starts a slice. For a manually registered branch, record its historical
`start_order` if more than one branch exists for that repository. Use one slice per repository/PR; coordinated PRs can share
criteria. Every slice must cover at least one criterion. Plan the entire known
scope before implementing, including verification work. Add new discoveries to
the plan instead of silently treating them as optional.

Statuses are `planned`, `implementing`, `review`, `blocked`, `merged`, and
`verified`. `blocked` needs a reason and next action in `note`. A verified slice
must have evidence for each assigned criterion:

```json
"evidence": {
  "a1": {
    "commit": "0123456789012345678901234567890123456789",
    "check": "tests/recovery.test.ts: interrupted batch; npm test passed"
  }
}
```

Use real full commit hashes and concrete checks. Validation checks that the commit
matches the current retained slice branch head (later commits require renewed evidence). It cannot prove the assertion or that the test
was run: reviewers must assess the linked test and result. PR numbers are resolved
only against the selected repository. Retain slice branches while their evidence
is in use. Invalid records fail closed; a populated slice plan prevents changing
`repos.txt` through amendment.

## Status and slices

```sh
sh .claude/skills/spec-status/scripts/spec-status.sh project-repositories.yaml example status
sh .claude/skills/spec-status/scripts/spec-status.sh project-repositories.yaml example status --remote --json
sh .claude/skills/start-slice/scripts/start-slice.sh project-repositories.yaml example recovery
```

Status is read-only. It reports local worktrees, dirty or unregistered branches,
acceptance gaps, next action, and optionally GitHub PR drift. Without `--remote`,
remote state is explicitly unverified. It never changes a recorded status merely
because GitHub changed. Refresh before making decisions that depend on current
upstream code; avoid repeatedly refreshing unchanged code during a single slice.

Start requires prepared, clean worktrees and a planned slice. It fetches the
selected repository and dependencies, verifies the previous slice and dependencies
have actually merged, creates `codex/<spec>-<slice>` from the configured remote
default branch, and atomically records the branch and status. Pass `--branch-prefix team` to use `team/<spec>-<slice>` instead. Failed state writes
restore the prior checkout and remove only the newly created branch. Collisions,
unregistered branches, unfinished dependencies, or dirty worktrees are refused.
Delivery initialization and slice starts use a per-spec lock; do not run lifecycle helpers concurrently; after a crash, inspect it and remove a stale
lock only after confirming no helper is running. Do not edit state concurrently
with a helper.

For an existing PR branch, explicitly record its repository, branch, PR, criteria,
and evidence in a slice, then inspect `status --remote`. This registers the branch
without renaming or switching it. Do not register an unrelated branch merely to
make cleanup pass. Preparation accepts registered slices and, with explicit
`--reuse-branches`, reopens an active slice (`implementing`, `review`, or
`blocked`) first. If none is active, it uses the greatest `start_order`. A legacy
record with multiple started branches and no known order must be corrected before
reopening; the helper does not guess from array position.

## Completion and cleanup

Completion requires every planned slice verified and every criterion covered.
Normal close additionally verifies the retained branch head is in the fetched
default branch, or that a GitHub PR with that exact head and expected base merged
and its merge commit is in the fetched default branch. This supports squash
merges even when GitHub deleted the source branch. Extra local commits invalidate
that proof. `gh` authentication is needed for squash-merge evidence.

The existing preflight still checks all worktrees before removing any. Branches
and documents remain. Worktree removal is reported as cleanup, not as completion.
Specs without a delivery record retain their previous cleanup behavior,
with an explicit warning that acceptance was not certified.

`close-spec --worktrees-only` explicitly allows cleanup of an unfinished spec; it
does not change delivery status or bypass dirty-worktree, registration, or unpushed
commit checks. Offline completion cannot be certified: use explicit
`--worktrees-only --offline`, plus `--acknowledge-unpushed` only if authorized and
needed. Those exceptions must follow the user's actual request.

## Verification during development

Assign checks to acceptance criteria before writing the implementation. Select
risks relevant to the change: growing-data benchmarks for persistence, cancellation
and interruption for asynchronous work, malformed inputs and ownership for exports,
and a provider-by-scenario matrix for adapter work. Assert that expected events
exist before comparing their values. Record risk-specific thresholds in the design.

Run focused checks while editing, then repository-required checks once the slice
is ready. Repeat when new changes or failures justify it. Record results at their
commit and dependency versions; do not reuse evidence after those inputs change.
CI checks and test counts supplement acceptance evidence rather than replacing it.

