# Design: automated-npm-releases

## Overview

Each repository receives three independent GitHub Actions workflows:

1. **CI** validates pull requests and exposes the stable `required` check.
2. **Main build** validates every push to `main` and uploads an inspectable
   package candidate tied to the exact commit.
3. **Release** runs only when a maintainer manually dispatches it. It previews
   or publishes the accumulated Conventional Commits through Semantic Release
   and npm Trusted Publishing.

The main-build candidate is evidence, not the publication input. It contains the
source version still committed to `main`, while Semantic Release assigns the
final version during its prepare step. The manual release therefore rebuilds
from the selected current `main` commit after checking the maintainer-provided
SHA.

The repositories share this design pattern but no workflow, credential, version,
artifact, dependency-update mechanism, or release state.

## Approach

### Repository-local pull-request CI

Add `.github/workflows/ci.yml` to each repository:

- Trigger for pull requests targeting `main`, including the `edited` event so
  title and body changes invalidate the previous commit-convention result.
- Grant read-only repository permissions.
- Install with `npm ci` from `npm-shrinkwrap.json` in `propio-agent` and
  `package-lock.json` in `propio-providers`.
- Run formatting, build, and unit tests on Node.js 20 and Node.js 24.10.0.
- Run the pinned local Fallow package in a separate Node.js 24.10.0 job with
  `fetch-depth: 0`.
- Require both `fallow audit --gate all` for the pull-request delta and
  `fallow --fail-on-issues` for the complete repository.
- Keep credentialed providers integration tests outside required CI.
- Add a stable aggregate job with the literal name `required`.

Node.js 20 remains a deliberate legacy consumer-compatibility check even though
it is end-of-life. Development-only Fallow and release tooling may produce
`EBADENGINE` warnings during its install because those tools require newer Node
versions; the application build and tests must still pass.

### Merge-message determinism

Both repositories use squash-only merging:

- squash title: `PR_TITLE`;
- squash body: `PR_BODY`;
- merge commits disabled;
- rebase merges disabled.

CI validates the title and body that become the squash commit and limits titles
to `feat`, `fix`, `perf`, `refactor`, `docs`, `test`, `build`, `ci`, `chore`,
and `revert`. The agent accepts standard breaking markers, while providers
rejects `!` and `BREAKING CHANGE` until a separate 1.0 stabilization decision.

### Main-build candidate workflow

Add `.github/workflows/main-build.yml` to each repository:

- Trigger on pushes to `main`.
- Use read-only repository permissions and no `id-token: write`.
- Run on Node.js 24.10.0 with a clean install, formatting, build, unit tests, and
  the whole-repository Fallow check.
- Run `npm pack --json` to build the source-version tarball and capture npm pack
  metadata.
- Record a SHA-256 checksum.
- Write `release-candidate.json` with package identity, source version, exact
  commit, `publishable: false`, and an explanatory note.
- Upload the tarball and metadata as
  `npm-package-candidate-<full-commit-sha>`.
- Retain the artifact for 30 days.

The artifact is useful for inspecting contents and associating a concrete build
with a merge. It must not be passed to `npm publish`: its version has not yet
been prepared by Semantic Release, it may expire, and `main` may accumulate more
commits before the maintainer chooses to release.

### Manual release workflow

Add `.github/workflows/release.yml` and a Semantic Release configuration to each
repository.

The workflow has only `workflow_dispatch`; it has no push, schedule,
`repository_dispatch`, `workflow_call`, or cross-repository trigger.

Inputs:

| Input | Type | Behavior |
|---|---|---|
| `mode` | choice | Defaults to `dry-run`; `publish` enables the live path. |
| `expected_sha` | string | Optional for a dry run and mandatory for publish; must be the full current `main` SHA. |

Before installing dependencies, the workflow:

1. Refuses any selected ref other than `refs/heads/main`.
2. Fetches current remote `main`.
3. Refuses the run if the dispatch commit is no longer current `main`.
4. Validates a supplied `expected_sha`.
5. In publish mode, requires a non-empty matching `expected_sha` and
   `NPM_PUBLISH_ENABLED=true`.

This makes live publication a two-key action: an explicit manual `publish`
dispatch bound to a commit, plus the repository kill-switch variable.

The workflow then:

- serializes runs with a repository-local concurrency group and does not cancel
  an active release;
- checks out complete tag history;
- uses Node.js 24.10.0 and installs npm 11.5.1 exactly;
- verifies the Node.js and npm versions;
- installs from the committed lockfile or shrinkwrap;
- repeats formatting, build, unit tests, and `npm pack --dry-run`;
- in the agent repository, runs both `fallow audit --gate all` and
  `fallow --fail-on-issues` before evaluating a release;
- fetches and compares remote `main` again immediately before Semantic Release
  so a merge during validation makes the run fail safely;
- runs the pinned local Semantic Release binary;
- passes `--dry-run` only when `mode=dry-run`;
- grants only `contents: write` and `id-token: write` to the release job;
- exposes the ephemeral `GITHUB_TOKEN` to Semantic Release for tag and GitHub
  Release operations;
- passes no npm token and does not configure `registry-url`.

If `main` advances while a release waits, the stale run fails and the maintainer
dispatches again with the new SHA. Several merges may intentionally accumulate
into one release; Semantic Release examines all commits since the latest tag and
chooses the highest applicable version bump.

### Semantic Release configuration

Configure only:

1. `@semantic-release/commit-analyzer`
2. `@semantic-release/release-notes-generator`
3. `@semantic-release/npm`
4. `@semantic-release/github`

Configure each commit analyzer with an explicit `revert` type patch rule, so the
allowed squash title `revert: ...` has the documented release behavior. The
remaining default analyzer rules still apply.

Configure the agent analyzer and release-notes generator with the same
`breakingHeaderPattern`. The pinned Angular preset does not recognize
Conventional Commit bang headers by default; matching parser options ensure
`feat!:`, `fix!:`, and scoped bang headers both compute a major version and
appear correctly in release notes.

Configure the GitHub plugin with `successCommentCondition: false`,
`failCommentCondition: false`, `labels: false`, and `releasedLabels: false`.
Omit `@semantic-release/git` and `@semantic-release/changelog`.

The npm plugin updates `package.json` and the root lockfile or shrinkwrap version
inside the runner, executes package hooks, and publishes. The GitHub plugin
creates the immutable tag and GitHub Release. Generated version changes are not
committed to `main`.

Dry-run mode skips prepare, publish, tagging, success, and failure steps while
printing the proposed version and release notes. It still verifies repository
push access and npm conditions. A broken npm OIDC setup may fall back to token
authentication and end with `ENONPMTOKEN`; the preceding OIDC exchange log is
the useful diagnostic.

### Release semantics

| Commit signal | Result |
|---|---|
| `fix:`, `perf:`, configured `revert:` | Patch |
| `feat:` | Minor |
| `BREAKING CHANGE:` or breaking `!` | Major for agent; rejected by providers CI |
| `refactor:`, `docs:`, `test:`, `build:`, `chore:`, `ci:` | No publication |

A manual publish with no releasable commits exits successfully without creating
a package, tag, or GitHub Release.

### npm Trusted Publishing

Configure npm separately:

| Package | GitHub owner/repository | Trusted workflow |
|---|---|---|
| `@propio-ai/agent` | `esack7/propio-agent` | `release.yml` |
| `@propio-ai/providers` | `esack7/propio-providers` | `release.yml` |

Only the manually dispatched release workflow receives `id-token: write`.
Trusted Publishing produces a short-lived OIDC credential and automatic
provenance for public packages from public repositories. Each package also sets
`publishConfig.provenance=true` so the attestation requirement remains explicit.
After successful OIDC publication, disallow traditional publishing tokens.

Manual workflow dispatch is the release authorization. A protected GitHub
environment with another reviewer gate is optional and is not required by this
design.

### Pinned automation toolchain

| Tool | Pinned version or revision |
|---|---|
| `actions/checkout` | `11bd71901bbe5b1630ceea73d27597364c9af683` (`v4.2.2`) |
| `actions/setup-node` | `49933ea5288caeca8642d1e84afbd3f7d6820020` (`v4.4.0`) |
| `actions/upload-artifact` | `ea165f8d65b6e75b540449e92b4886f43607fa02` (`v4.6.2`) |
| CI compatibility runtimes | Node.js `20` and `24.10.0` |
| Release runtime | Node.js `24.10.0`, npm `11.5.1` |
| Fallow (`propio-agent`) | `3.3.0` |
| Fallow (`propio-providers`) | `3.3.0` (Node.js 20 compatible) |
| Semantic Release | `25.0.8` |
| Commit analyzer | `13.0.1` |
| Release notes generator | `14.1.1` |
| npm plugin | `13.1.5` |
| GitHub plugin | `12.0.9` |

### Baseline and rollout

The npm registry records these existing releases:

- `@propio-ai/agent@1.1.4`:
  `774910d0572531c8cad544dcc1a8ce7fec356293`
- `@propio-ai/providers@0.1.4`:
  `66d4cdf53e3efcb0bd391afd83944a3a7060ece5`

The baseline tags belong on those published commits, not newer non-release
cleanup commits.

The agent workflow also verifies that `v1.1.4` resolves to the recorded npm
`gitHead` and is an ancestor of the selected `main` commit. This turns the
load-bearing first-rollout instruction into a release-time safety check.

For each repository independently:

1. Reconfirm npm version and `gitHead`, then create the missing baseline tag.
2. Open the workflow/configuration pull request with
   `NPM_PUBLISH_ENABLED` unset.
3. Observe the literal `required` CI context.
4. Configure squash-only merges, required CI, the zero-approval solo-maintainer
   pull-request policy, and immutable-release-tag rules.
5. Merge the workflow pull request.
6. Inspect the Main-build artifact created for that merge.
7. Configure npm Trusted Publishing for the exact `release.yml`.
8. Set `NPM_PUBLISH_ENABLED=true`.
9. Manually dispatch `mode=dry-run` from `main` and confirm the proposed version
   and successful OIDC exchange.
10. When ready, manually dispatch `mode=publish` with the exact current full
    `main` SHA.
11. Verify the tag, GitHub Release, npm version, provenance, contents, and
    runtime-reported version.

### Branch and tag controls

- Protect `main` and require pull requests plus the literal `required` context.
- Require zero approvals while each repository has one maintainer.
- Restrict updates and deletions of existing `v*` tags while allowing creation
  of new tags.
- Do not grant the GitHub Actions app a repository-wide ruleset bypass.
- Require repository write access to dispatch the manual release workflow.

## Cross-repository changes

| Repository | Change |
|---|---|
| `propio-agent` | Add independent matrix PR CI, strict Fallow gates, a main-build inspection artifact, pinned Semantic Release tooling, a manually dispatched OIDC release, and agent rollout documentation. |
| `propio-providers` | Add independent matrix PR CI, strict Fallow gates, a main-build inspection artifact, pinned Semantic Release tooling, a manually dispatched OIDC release, and providers rollout documentation. |

Publishing providers does not dispatch agent automation or update the agent
dependency.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| A merge-time candidate is mistaken for the final package. | Mark metadata `publishable: false`, document it as inspection-only, and rebuild after Semantic Release computes the final version. |
| A maintainer dispatches from a branch or stale commit, or `main` advances during validation. | Require `main`, compare the dispatch SHA with remote `main` before and after validation, and require the full expected SHA for publish mode. |
| A manual release is accidentally invoked. | Default to `dry-run`; require explicit `publish`, matching `expected_sha`, and `NPM_PUBLISH_ENABLED=true`. |
| Missing baseline tags cause a duplicate or incorrect version. | Verify npm `gitHead` and create tags at the exact published commits before the first dry run. |
| The npm Trusted Publisher does not match the invoking workflow. | Configure the exact owner, repository, and `release.yml`; diagnose the OIDC exchange log before any token fallback error. |
| Several merges accumulate before release. | Treat that as intentional batching; Semantic Release evaluates all commits since the latest tag and applies the highest bump. |
| Two maintainers start releases concurrently. | Use repository-local concurrency without canceling the active release. |
| Validation passes on merge but the release environment differs. | Rebuild and rerun critical checks in the manual release job instead of publishing the retained artifact. |
| A partial failure occurs after npm or tag creation. | Inspect npm, tags, and GitHub Releases before rerunning; never reuse an immutable npm version. |
| A compromised workflow dependency accesses OIDC. | Pin actions and release packages exactly, minimize permissions, and grant OIDC only to manual `release.yml`. |

## Alternatives considered

- **Publish on every merge:** rejected for now because the maintainer wants an
  explicit release decision after inspecting the main build.
- **Publish the merge-time tarball:** rejected because it contains the source
  version, not the Semantic Release version, and may be stale when publication
  is authorized.
- **GitHub environment approval inside an automatic push workflow:** viable, but
  a manual-only release workflow makes the authorization and selected commit
  clearer.
- **Release Please:** rejected because it introduces a release pull request and
  release-version commit rather than using the existing tag-based model.
- **Long-lived npm automation tokens:** rejected in favor of OIDC.
- **A central meta-repository workflow:** rejected because repositories must
  retain independent release identities and state.

## References

- npm Trusted Publishing:
  <https://docs.npmjs.com/trusted-publishers/>
- GitHub manual workflows:
  <https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow>
- GitHub workflow artifacts:
  <https://docs.github.com/en/actions/concepts/workflows-and-actions/workflow-artifacts>
- Semantic Release configuration and dry runs:
  <https://semantic-release.gitbook.io/semantic-release/usage/configuration>
- Semantic Release GitHub Actions and OIDC:
  <https://semantic-release.gitbook.io/semantic-release/recipes/ci-configurations/github-actions>
- Semantic Release major-zero policy:
  <https://semantic-release.gitbook.io/semantic-release/support/faq>
- GitHub Actions concurrency:
  <https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency>
