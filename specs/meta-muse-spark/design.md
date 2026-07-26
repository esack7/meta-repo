# Design: meta-muse-spark

## Overview

Add and release a first-class Meta Model API provider for Muse Spark 1.1 across the provider library and CLI.

## Approach

Refactor the current OpenAI Responses implementation into an internal reusable Responses adapter. Keep OpenAI and Meta as thin provider wrappers supplying their own name, endpoint, credential resolution, and error wording. The shared adapter continues to serialize messages, images, tools, streaming events, retries, and terminal status.

Meta uses stateless Responses requests with `store: false` and `include: ["reasoning.encrypted_content"]`. When reasoning summaries are requested, send `reasoning.summary: "auto"` without forcing an effort. Capture replayable response output items in output order. For Meta tool turns, retain assistant message items and their `phase: "commentary"` alongside reasoning and function calls; on the next request, replay those items before function-call outputs and suppress normalized duplicates. Older session state falls back to a provider-native assistant commentary message and reconstructed function calls.

The CLI remains configuration-driven. It consumes the exact published provider package 0.1.4 and documents Muse Spark 1.1 as the initial Meta model rather than hardcoding a model allowlist.

## Cross-repository changes

| Repository | Change |
|------------|--------|
| propio-providers | Add Meta config/factory/public exports, shared Responses adapter, Meta provider, tests, docs, metadata, and publish version 0.1.4 after review and validation. |
| propio-agent | Consume the exact published provider 0.1.4, refresh shrinkwrap, document Meta configuration and session-persistence behavior, update sandbox credential passthrough, and publish version 1.1.4 after review and validation. |

## Risks and mitigations

| Risk | Mitigation |
|------|------------|
| Shared Responses refactor regresses OpenAI | Preserve the existing OpenAI public class and run its complete unit/integration coverage against the shared adapter. |
| Meta rejects malformed continuation order | Replay exact completed output items, preserve commentary phases, and test reasoning/message/function-call/tool-output ordering. |
| Credentials leak to the wrong service | Resolve only the namespaced `META_API_KEY` for Meta, do not fall back to `MODEL_API_KEY`, redact secrets from errors, and assert the fixed Meta host in tests. |
| Cross-package release ordering produces an invalid agent artifact | Validate first with a local provider tarball, publish provider 0.1.4 after authorization, install that exact published artifact into the agent shrinkwrap, rerun all agent checks and package smoke tests, then publish agent 1.1.4 after separate authorization. |

## Alternatives considered

- OpenRouter-only configuration was rejected in favor of a direct Meta provider.
- Chat Completions was rejected because it cannot preserve reasoning across tool turns.
- Duplicating the OpenAI provider was rejected in favor of a shared Responses adapter.
- A Muse-only allowlist was rejected so future Meta model IDs remain configuration-driven.

## Release outcome

- Provider pull request `feat: add Meta Muse Spark provider` was merged and `@propio-ai/providers@0.1.4` was published.
- Agent pull request `feat: add Meta Muse Spark agent support` was merged and `@propio-ai/agent@1.1.4` was published.
- No release tags were created because neither repository's documented npm release workflow required one.
