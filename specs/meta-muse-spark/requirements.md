# Requirements: meta-muse-spark

## Summary

Add and release a first-class Meta Model API provider for Muse Spark 1.1 across the provider library and CLI.

## Goals

- Add a config-driven `meta` provider type to `@propio-ai/providers`.
- Support Meta's streamed Responses API at `https://api.meta.ai/v1/responses` with explicit `apiKey` or namespaced `META_API_KEY` authentication.
- Support Muse Spark 1.1 text, image, function-tool, reasoning-summary, retry, cancellation, and typed-error behavior through the existing provider contract.
- Preserve encrypted reasoning, assistant commentary phases, and function-call output items across stateless tool-call turns.
- Document `muse-spark-1.1` with a 1,048,576-token context window in the provider library and Propio CLI.
- Release provider version 0.1.4 and agent version 1.1.4 through reviewed pull requests and public npm publication.

## Non-goals

- Video or PDF inputs, built-in Meta web search, structured output, prompt caching, or explicit reasoning-effort configuration.
- Server-managed conversations through `previous_response_id`.
- A custom Meta API base URL.
- Creating release tags; neither repository's documented release workflow required one.
- Additional provider or agent releases beyond `@propio-ai/providers@0.1.4` and `@propio-ai/agent@1.1.4`.

## Acceptance criteria

- [x] `MetaProviderConfig` is public, part of `ProviderConfig`, and factory-created for `type: "meta"`.
- [x] Meta credentials prefer config `apiKey`, then `META_API_KEY`; the generic `MODEL_API_KEY` is not accepted, and missing credentials produce a typed authentication error.
- [x] Requests stream from Meta's Responses endpoint with `store: false` and encrypted reasoning included.
- [x] Tool loops replay reasoning, assistant commentary, function calls, and matching tool outputs once and in provider order.
- [x] Future configured Meta model IDs work without an allowlist; Muse Spark 1.1 reports a 1,048,576-token context window.
- [x] Provider unit tests, build, formatting check, and Fallow audit pass.
- [x] A credential-gated Meta integration test covers assistant text and a complete tool round.
- [x] Agent metadata, provider dependency/shrinkwrap, configuration schema, sandbox credential passthrough, and Meta example are updated and validated.
- [x] The provider and agent pull requests are merged into their default branches.
- [x] `@propio-ai/providers@0.1.4` and `@propio-ai/agent@1.1.4` are published publicly after their release gates passed.

## Affected repositories

<!-- Confirmed names are listed in repos.txt -->

## Open questions

- None. Both package publications were completed after separate explicit authorization.
