# Design: fallow-cleanup

## Overview

Make propio-providers and propio-agent clean under Fallow before strict release CI

## Approach

1. Prepare isolated `feature/fallow-cleanup` worktrees for the two repositories; do not inspect or modify the existing `automated-npm-releases` worktrees as part of implementation.
2. In each worktree, determine the repository's package manager and existing quality-tool conventions. Add or align a reproducible Fallow installation/version and a repository-root command without relying on a developer-global Fallow installation.
3. Capture the initial Fallow output and configuration as the baseline. Triage every finding, then fix the underlying code or tests where possible. If a finding must be treated as policy, use the smallest supported exclusion/exception and document its rationale alongside the configuration.
4. Re-run the complete repository scan until `fallow --fail-on-issues` reports zero findings. Run normal repository validation to ensure remediations preserve behavior.
5. Verify and document the strict delta invocation `fallow audit --gate all`, including any repository-specific prerequisites so release CI can adopt it in a follow-up change.

## Cross-repository changes

| Repository | Change |
|------------|--------|
| `propio-providers` | Add reproducible Fallow setup/baseline, remediate all repository findings, and document the future strict delta gate. |
| `propio-agent` | Add reproducible Fallow setup/baseline, remediate all repository findings, and document the future strict delta gate. |

## Risks and mitigations

| Risk | Mitigation |
|------|------------|
| Fallow output differs across developer or CI environments. | Pin or otherwise reproducibly invoke the version through the repository's existing package tooling and record the command/configuration. |
| Suppressions conceal real maintainability or release risks. | Prefer code/test remediation; permit only narrow, documented exceptions with a clear rationale. |
| Cleanup disrupts package behavior or existing release tooling. | Run the affected repository's normal validation and keep CI enablement out of scope. |
| Existing `automated-npm-releases` changes are accidentally touched. | Work only in the newly prepared `fallow-cleanup` worktrees and verify the existing worktrees remain unchanged. |

## Alternatives considered

- Enable the strict release CI before resolving the baseline. Rejected because it would immediately block releases on pre-existing findings.
- Use a single global Fallow installation. Rejected because it would not produce a repeatable local or CI baseline.
- Broadly exclude the repository from Fallow. Rejected because the goal is zero findings from the full-repository command.
