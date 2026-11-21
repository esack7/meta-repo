---
name: verify-packages
description: Test a packed local package against a consumer at exact commits, or verify the published dependency, without publishing.
---

# verify-packages

Use [delivery guidance](../../../../docs/DELIVERY.md#package-integration-without-publication)
for prerequisites and interpretation. Run:
`python3 .claude/skills/verify-packages/scripts/verify-packages.py project-repositories.yaml <spec> <producer> <consumer> --producer-commit <sha> --consumer-commit <sha> --check build --check test --report <new-report.json>`.
Run only when package-artifact verification is requested. Delivery tracking is optional.
Select scripts from the consumer's package.json; pin full commits. Use
`--producer-build-script <script>` for producers whose build script has another name. Use `--mode published`
with a separate report for the locked registry dependency. The helper executes npm
lifecycle scripts in temporary copies of trusted code. It does not publish, alter
source checkouts, or authorize release. Report candidate and published checks
separately; a local link is not evidence that the packed artifact works.
