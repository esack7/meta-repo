# Tasks: automated-npm-releases

## Checklist

- [x] Review requirements and design
- [x] Run prepare-spec and confirm worktrees
- [x] Implement changes in `specs/automated-npm-releases/repos/` worktrees
- [ ] Verify all acceptance criteria
- [x] Open pull requests per repository
- [ ] Run close-spec when worktrees are no longer needed

## Shared preparation

- [ ] Reconfirm npm versions and `gitHead` commits immediately before rollout.
- [x] Record squash-only `PR_TITLE` / `PR_BODY` merge policy.
- [x] Record providers policy rejecting breaking markers until 1.0.
- [x] Record exact action revisions, Node/npm versions, Fallow versions,
      Semantic Release version, and plugin versions.
- [x] Use `required` as the aggregate CI job and branch-protection context.
- [x] Replace publish-on-merge with main-build inspection artifacts and
      manually authorized publication.

## `propio-agent`

- [x] Add PR CI with Node.js 20 and Node.js 24.10.0 matrix validation.
- [x] Run strict changed-file and whole-repository Fallow gates.
- [x] Validate allowed Conventional Commit PR title types and breaking footers,
      including reruns after title or body edits.
- [x] Add the stable `required` aggregate job.
- [x] Add a push-to-`main` workflow that builds and uploads a 30-day
      inspection-only package candidate with SHA-256 and commit metadata.
- [x] Pin Semantic Release and its four required plugins in
      `npm-shrinkwrap.json`.
- [x] Add Semantic Release configuration for `main` and `v${version}` tags.
- [x] Configure `revert:` squash commits to produce the documented patch
      release.
- [x] Configure matching analyzer and release-notes parsing for agent bang
      headers so they produce major releases and breaking-change notes.
- [x] Make `release.yml` manual-only with `dry-run` / `publish` modes.
- [x] Refuse non-main, stale-main, and mismatched expected-SHA releases, and
      recheck remote `main` immediately before Semantic Release.
- [x] Require matching `expected_sha` and `NPM_PUBLISH_ENABLED=true` for live
      publication.
- [x] Use Node.js 24.10.0, npm 11.5.1, full tag history, fresh validation,
      package inspection, concurrency, minimal permissions, and OIDC.
- [x] Run both strict Fallow checks again before evaluating a manual release.
- [x] Refuse release evaluation unless the verified `v1.1.4` baseline tag
      target and ancestry are correct.
- [x] Pass the ephemeral GitHub Actions token to Semantic Release and request
      npm provenance explicitly.
- [x] Document candidate artifacts, manual authorization, npm trust, dry runs,
      disablement, and recovery.
- [ ] Confirm a published CLI reports the Semantic Release-computed version.
- [ ] Confirm a published `npm-shrinkwrap.json` root version matches the package.

## `propio-providers`

- [x] Add PR CI with Node.js 20 and Node.js 24.10.0 matrix validation.
- [x] Run strict changed-file and whole-repository Fallow gates.
- [x] Keep credentialed integration tests outside required automation.
- [x] Validate allowed Conventional Commit PR title types and reject breaking
      markers, including reruns after title or body edits.
- [x] Add the stable `required` aggregate job.
- [x] Add a push-to-`main` workflow that builds and uploads a 30-day
      inspection-only package candidate with SHA-256 and commit metadata.
- [x] Pin Semantic Release and its four required plugins in `package-lock.json`.
- [x] Add Semantic Release configuration for `main` and `v${version}` tags.
- [x] Configure `revert:` squash commits to produce the documented patch
      release.
- [x] Make `release.yml` manual-only with `dry-run` / `publish` modes.
- [x] Refuse non-main, stale-main, and mismatched expected-SHA releases, and
      recheck remote `main` immediately before Semantic Release.
- [x] Require matching `expected_sha` and `NPM_PUBLISH_ENABLED=true` for live
      publication.
- [x] Use Node.js 24.10.0, npm 11.5.1, full tag history, fresh validation,
      package inspection, concurrency, minimal permissions, and OIDC.
- [x] Pass the ephemeral GitHub Actions token to Semantic Release and request
      npm provenance explicitly.
- [x] Document candidate artifacts, manual authorization, npm trust, dry runs,
      disablement, recovery, and manual integration testing.

## Repository and npm configuration

- [ ] Create and push verified agent baseline tag `v1.1.4` at npm `gitHead`.
- [ ] Create and push verified providers baseline tag `v0.1.4` at npm `gitHead`.
- [x] Confirm each pull request reports the literal `required` context.
- [ ] Configure squash-only merges with `PR_TITLE` and `PR_BODY`.
- [ ] Protect `main` and require `required`.
- [ ] Require pull requests with zero approvals while each repository has one
      maintainer.
- [ ] Add immutable-update/delete `v*` tag rules without a broad Actions bypass.
- [ ] Configure `@propio-ai/agent` to trust only
      `esack7/propio-agent` workflow `release.yml`.
- [ ] Configure `@propio-ai/providers` to trust only
      `esack7/propio-providers` workflow `release.yml`.
- [ ] Set `NPM_PUBLISH_ENABLED=true` only after Trusted Publishing is ready.
- [ ] After successful OIDC releases, disallow traditional npm publishing
      tokens.

## Verification

- [x] Validate all six workflow files with an Actions-aware YAML linter.
- [x] Run `npm ci`, formatting, build, and unit tests under Node.js 20 and
      Node.js 24.10.0 in both worktrees.
- [x] Run locked strict Fallow audit and whole-repository checks in both
      worktrees.
- [x] Generate each main-build candidate locally and inspect tarball metadata,
      checksum, and `publishable: false` metadata.
- [x] Run `npm pack --dry-run` in both repositories and inspect contents.
- [x] Confirm only `main-build.yml` has a push trigger and only `release.yml`
      has `id-token: write`.
- [x] Confirm `release.yml` has only `workflow_dispatch` and cannot publish from
      a branch, stale `main`, missing/mismatched SHA, or disabled kill switch.
- [x] Confirm no workflow references the other repository, a reusable release
      workflow, `NPM_TOKEN`, or `NODE_AUTH_TOKEN`.
- [x] Confirm the explicit Semantic Release plugin list omits git/changelog and
      disables GitHub comments and labels with non-deprecated options.
- [ ] Merge each workflow pull request and inspect its exact-SHA Main-build
      artifact.
- [ ] After npm trust is configured, manually dispatch `mode=dry-run` and
      confirm the proposed version, release notes, and successful OIDC exchange.
- [ ] Manually dispatch `mode=publish` with the exact current `main` SHA and
      verify tag, GitHub Release, npm provenance, contents, and runtime version.
- [ ] Confirm a manual publish with no releasable commits exits without
      publication.
- [ ] Confirm overlapping manual releases are serialized.
- [ ] Verify new `v*` tags can be created while existing tags cannot be updated
      or deleted through ordinary write access.
