---
name: spec-status
description: Inspect tracked delivery state, acceptance gaps, worktrees, and PR drift when asking what remains in a spec.
---

# spec-status

Run `sh .claude/skills/spec-status/scripts/spec-status.sh project-repositories.yaml <spec> status`.
Use `--remote` for current GitHub PR comparisons and `--json` for structured output.
The command is read-only and does not fetch. Report unknown remote state honestly.
Enable delivery tracking only when requested, using the explicit `init` command
before recording slices.
Read [delivery guidance](../../../../docs/DELIVERY.md) for the schema, working agreement,
and evidence requirements. Reconcile the record after each review and merge;
do not infer whole-spec completion from a single merged PR.
