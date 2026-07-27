# Tasks: fallow-cleanup

## Checklist

- [ ] Review requirements and design
- [ ] Run prepare-spec and confirm worktrees
- [ ] Implement changes in specs/fallow-cleanup/repos/ worktrees (not reference clones)
- [ ] Verify acceptance criteria
- [ ] Open pull requests per repository
- [ ] Run close-spec when worktrees are no longer needed

## Implementation tasks

- [ ] Run `prepare-spec fallow-cleanup` after confirming the reference clones are available and current.
- [ ] In `propio-providers`, identify the package-manager convention, add a reproducible Fallow setup, and record the initial baseline and command.
- [ ] In `propio-providers`, triage and remediate every finding from `fallow --fail-on-issues`; add narrowly scoped documented policy only when remediation is not applicable.
- [ ] In `propio-providers`, document the future strict PR-delta invocation: `fallow audit --gate all`.
- [ ] In `propio-agent`, identify the package-manager convention, add a reproducible Fallow setup, and record the initial baseline and command.
- [ ] In `propio-agent`, triage and remediate every finding from `fallow --fail-on-issues`; add narrowly scoped documented policy only when remediation is not applicable.
- [ ] In `propio-agent`, document the future strict PR-delta invocation: `fallow audit --gate all`.
- [ ] Confirm `specs/automated-npm-releases/repos/` has not been modified.

## Verification

- [ ] In each repository root, run `fallow --fail-on-issues` and confirm exit status 0 with zero findings.
- [ ] In each repository, run `fallow audit --gate all` using the documented strict-delta workflow and confirm it is suitable for later PR CI adoption.
- [ ] Run each repository's relevant unit tests, linting, type checks, and build/package validation after remediation.
- [ ] Review the resulting diffs to ensure Fallow configuration, exceptions, and baseline documentation are reproducible and narrowly scoped.
