# Tasks: meta-muse-spark

## Checklist

- [x] Review requirements and design
- [x] Run prepare-spec and confirm worktrees
- [x] Implement changes in specs/meta-muse-spark/repos/ worktrees (not reference clones)
- [x] Verify acceptance criteria
- [x] Open and merge pull requests per repository
- [x] Run close-spec when worktrees are no longer needed

## Implementation tasks

- [x] Extract shared Responses streaming, serialization, replay, and error behavior without changing OpenAI behavior.
- [x] Add Meta config, factory wiring, provider implementation, exports, metadata, and documentation.
- [x] Add Meta unit and credential-gated integration coverage, including a complete tool loop.
- [x] Prepare provider package version 0.1.4.
- [x] Validate the agent against a local provider package tarball.
- [x] Update the agent to the exact published provider 0.1.4, refresh shrinkwrap, document Meta configuration and session-persistence behavior, update sandbox credential passthrough, and prepare agent 1.1.4.

## Verification

- [x] Provider: `npm test`
- [x] Provider: `npm run build`
- [x] Provider: `npm run format:check`
- [x] Provider: `npx fallow audit`
- [x] Provider with credentials: targeted Meta integration test
- [x] Agent against published provider 0.1.4: `npm test`
- [x] Agent against published provider 0.1.4: `npm run build`
- [x] Agent: `npm run format:check`
- [x] Agent: `npx fallow audit`
- [x] Agent: package dry-run and install/import smoke test against the published artifact

## Release gates

- [x] Receive explicit authorization and publish `@propio-ai/providers@0.1.4`.
- [x] Install the published provider in the agent, refresh `npm-shrinkwrap.json`, set agent version `1.1.4`, and rerun all agent checks.
- [x] Receive explicit authorization and publish `@propio-ai/agent@1.1.4`.
