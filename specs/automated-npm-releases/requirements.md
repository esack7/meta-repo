# Requirements: automated-npm-releases

## Summary

Add independent GitHub Actions CI, inspectable package-candidate builds on
`main`, and manually authorized npm releases with OIDC Trusted Publishing to
`propio-agent` and `propio-providers`.

## Goals

- Give each repository its own CI, main-build, and release workflows,
  configuration, release history, and npm publishing identity.
- Validate pull requests against the repositories' documented checks before
  merge.
- Build and retain an inspectable package candidate after each push to `main`
  without publishing it.
- Require an explicit maintainer-triggered GitHub Actions run for every npm
  publication.
- Derive semantic versions from Conventional Commit-compatible squash commits:
  - `fix:` produces a patch release.
  - `feat:` produces a minor release.
  - a breaking-change marker produces a major agent release.
  - `propio-providers` rejects breaking-change markers until a separate
    stabilization decision promotes it to 1.0.
  - non-releasable changes such as documentation-only or CI-only commits do not
    publish by default.
- Publish public packages through npm Trusted Publishing and GitHub Actions OIDC
  without a long-lived npm token.
- Generate an npm provenance attestation for every publication.
- Require the maintainer to identify the exact current `main` commit before a
  live manual release.
- Retain `NPM_PUBLISH_ENABLED=true` as an emergency live-publication kill switch,
  not as an automatic trigger.
- Deliberately retain the packages' existing Node.js 20 consumer compatibility
  claim even though Node.js 20 is end-of-life, while also proving the supported
  Node.js 24 release runtime in CI.
- Use Node.js 24.10.0 or newer and npm 11.5.1 or newer for OIDC publication.
- Serialize manual release execution and discover versions from complete tag
  history.

## Non-goals

- Publishing automatically because a commit was merged or pushed to `main`.
- Publishing the merge-time package candidate directly; its source version is
  intentionally not the final Semantic Release version.
- Coordinating the two repositories in a shared workflow or triggering one
  repository from the other.
- Automatically updating the agent's `@propio-ai/providers` dependency when a
  providers package is published. Dependency-currency automation is deferred to
  a follow-up Dependabot or Renovate specification.
- Releasing both packages together or forcing their versions to remain aligned.
- Adding prerelease channels, canary releases, or npm distribution tags other
  than `latest`.
- Running credentialed live-provider integration tests in GitHub Actions.
- Changing either package's runtime behavior or public API.
- Storing or rotating an `NPM_TOKEN`.
- Committing generated release versions or changelogs back to `main`; Git tags,
  GitHub Releases, and npm metadata are the release source of truth.

## Acceptance criteria

- [ ] `propio-agent` and `propio-providers` each contain their own CI workflow
      triggered for pull requests targeting `main`, including title or body
      edits after the initial run.
- [ ] Each CI workflow installs from the committed lockfile or shrinkwrap and
      runs formatting, build, and unit tests in a Node.js matrix containing
      Node.js 20 and Node.js 24.10.0 or newer.
- [ ] Fallow is an exact, locked development dependency in each repository and
      runs locally on Node.js 24.10.0 or newer with full Git history.
- [ ] CI runs both `fallow audit --gate all` for the pull-request delta and
      `fallow --fail-on-issues` for the whole repository.
- [ ] Each CI workflow exposes one stable aggregate job named `required`.
- [ ] Both repositories allow squash merges only, use the validated PR title as
      the squash commit title, and use the PR body as the squash commit body.
- [ ] PR titles are limited to the documented Conventional Commit types;
      unknown types fail CI instead of silently producing no release.
- [ ] Each repository contains an independent main-build workflow triggered by
      pushes to `main`, with read-only repository permissions and no npm OIDC
      permission.
- [ ] Each main-build workflow runs the release-runtime validation, builds an
      npm tarball, records npm pack metadata and a SHA-256 checksum, and uploads
      an artifact named for the exact `main` commit.
- [ ] Candidate metadata clearly marks the merge-time tarball as inspection-only
      and not publishable; artifacts are retained for 30 days.
- [ ] Each repository contains a `release.yml` triggered only by
      `workflow_dispatch`, with no push, schedule, repository-dispatch,
      workflow-call, or cross-repository trigger.
- [ ] Manual release inputs expose a `mode` choice that defaults to `dry-run`
      and supports `publish`, plus an `expected_sha` string.
- [ ] The release workflow refuses a non-`main` ref, refuses a stale selected
      commit when remote `main` has moved, rechecks `main` immediately before
      Semantic Release, and requires `expected_sha` to match the current full
      `main` SHA in publish mode.
- [ ] Live publication also requires `NPM_PUBLISH_ENABLED=true`; dry runs remain
      available while the kill switch is off.
- [ ] Dry-run mode calculates the next version and release notes without
      publishing, tagging, or creating a GitHub Release.
- [ ] Release validation and publication run on Node.js 24.10.0 with npm 11.5.1;
      the workflow verifies both versions before release.
- [ ] The manual release rebuilds from the selected `main` commit after fresh
      install, formatting, build, unit tests, and `npm pack --dry-run`; it does
      not publish the retained candidate tarball.
- [ ] The agent manual release also reruns both strict Fallow checks before
      evaluating Semantic Release.
- [ ] Semantic Release computes the next version from commits since the latest
      release tag and creates the corresponding `v<version>` tag and GitHub
      Release only in publish mode.
- [ ] Eligible `fix`, `perf`, and configured `revert` changes produce patch
      releases; `feat` produces a minor release; agent breaking changes produce
      major releases; providers CI rejects `!` and `BREAKING CHANGE`; and no
      releasable commits exits successfully.
- [ ] The agent analyzer and release-notes generator use matching parser
      configuration so `feat!:`, `fix!:`, and scoped bang headers produce a
      major release and corresponding breaking-change notes.
- [ ] The publish job uses `id-token: write`, a GitHub-hosted runner, and npm
      Trusted Publishing without `NPM_TOKEN`, `NODE_AUTH_TOKEN`, or another
      long-lived publishing credential.
- [ ] The Semantic Release step receives the ephemeral GitHub Actions token for
      tag and GitHub Release operations, while package publishing uses OIDC.
- [ ] `@propio-ai/agent` publishes only from
      `esack7/propio-agent/.github/workflows/release.yml`.
- [ ] `@propio-ai/providers` publishes only from
      `esack7/propio-providers/.github/workflows/release.yml`.
- [ ] Published packages remain public, include the expected build output,
      report the computed version at runtime, and include npm provenance
      explicitly requested through `publishConfig`.
- [ ] Repository-local concurrency prevents overlapping manual publications.
- [ ] Semantic Release explicitly configures only
      `@semantic-release/commit-analyzer`,
      `@semantic-release/release-notes-generator`, `@semantic-release/npm`, and
      `@semantic-release/github`.
- [ ] `@semantic-release/git` and `@semantic-release/changelog` are absent, and
      GitHub success/failure comments and labels are disabled using
      non-deprecated condition options.
- [ ] Existing published commits are established as the Semantic Release
      baselines: `@propio-ai/agent@1.1.4` / `v1.1.4` and
      `@propio-ai/providers@0.1.4` / `v0.1.4`.
- [ ] The agent release workflow refuses to run unless `v1.1.4` resolves to
      npm's recorded `gitHead` and is an ancestor of the selected `main`.
- [ ] Both `main` branches require the literal `required` job context before
      merge.
- [ ] Both repositories require pull requests but zero approving reviews while
      they are solo-maintainer repositories.
- [ ] A tag ruleset permits the manual release workflow to create a new
      `v<version>` tag but restricts updates and deletions of existing release
      tags without granting a repository-wide GitHub Actions bypass.
- [ ] The published agent tarball contains an `npm-shrinkwrap.json` whose root
      package version matches the released package version.
- [ ] Setup and recovery documentation explains candidate artifacts, baseline
      tags, npm trust, commit conventions, dry runs, expected-SHA confirmation,
      the publication kill switch, and recovery.

## Affected repositories

<!-- Confirmed names are listed in repos.txt -->

- `propio-agent`
- `propio-providers`

## Open questions

- None. Publication is manually authorized through `release.yml`; merge-time
  workflows produce inspection artifacts only. Both repositories use
  squash-only merging with `PR_TITLE` and `PR_BODY`. Providers rejects breaking
  markers until a separate 1.0 stabilization decision. The stable required
  check context is `required`.
