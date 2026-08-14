# Design: muse-spark-thinking-visibility

## Overview

Expose Muse Spark 1.1 reasoning summaries and commentary as useful thinking
feedback in the Propio CLI. The provider will distinguish commentary from final
answer text, and the agent will accumulate and render the provider's complete
summary while retaining a generic fallback for providers that expose no
summary.

## Approach

### Provider event classification

Extend the shared Responses API stream state so the Meta profile can associate
`response.output_text.delta` events with the output item's phase. When an
assistant message is introduced with `phase: "commentary"`, route its text
deltas to `thinking_delta`. Route final answer text to `assistant_text` as it is
today.

Continue to emit `response.reasoning_summary_text.delta` as
`reasoning_summary`. Do not translate encrypted reasoning items into visible
events. Completed reasoning, commentary, and function-call items remain stored
as provider-private continuation state and replayed in output-index order.

The phase-aware behavior is enabled by the Meta provider profile so the shared
OpenAI Responses implementation does not accidentally reclassify output for
providers that do not use Meta's commentary semantics.

### Agent summary accumulation and selection

Treat provider reasoning-summary events as streamed deltas:

1. Concatenate all summary chunks from one provider request without inserting
   artificial whitespace.
2. Preserve summaries from successive tool-loop iterations in chronological
   order, separating complete iteration summaries at a stable boundary.
3. Use the resulting provider summary as the turn summary whenever it is
   non-empty.
4. Fall back to the existing synthesized agent summary only when the provider
   supplied no usable summary.

Forward provider summary deltas to the existing live thinking presentation, or
an equivalently explicit live-summary event, without rendering the final
end-of-turn summary twice. Meta commentary already normalized as
`thinking_delta` uses the same presentation.

### Output-mode behavior

Interactive TTY mode renders provider commentary and summary deltas using the
existing `Thinking` transcript style, preserving tool-call and final-answer
boundaries. The established `--show-reasoning-summary` and `--show-trace` flags
control the retained end-of-turn summary.

JSON output includes the final accumulated summary only when summary visibility
is requested, preserving the existing response schema. Plain and non-TTY modes
must preserve their stable final-response output and use the retained summary
path rather than mixing live deltas into answer text.

### Verification strategy

Add deterministic provider tests with realistic Meta Responses events,
including `output_item.added`, multiple output-text deltas, completed commentary,
encrypted reasoning, parallel calls, and final answer output. Add agent and
renderer tests for multi-chunk accumulation, multiple tool-loop iterations,
provider precedence, fallback summaries, and TTY/plain/JSON behavior.

Update the credential-gated Meta integration trace to record summary and
thinking events. Because Meta may omit optional visible summaries for some
prompts, validate any returned visible events structurally while continuing to
require encrypted replay state, successful tool continuation, and a final
answer.

## Cross-repository changes

| Repository | Change |
|------------|--------|
| `propio-providers` | Track Meta commentary phase during Responses API streaming; emit commentary as `thinking_delta`; retain reasoning summaries as typed deltas; preserve encrypted replay ordering; strengthen unit and live integration coverage. |
| `propio-agent` | Accumulate complete provider summaries across chunks and iterations; prefer provider summaries; render live Meta feedback through the thinking UI; preserve plain/JSON contracts; add orchestration and renderer tests. |

## Risks and mitigations

| Risk | Mitigation |
|------|------------|
| Commentary is mistaken for final answer text or shown twice. | Track output phase by output index, route only Meta commentary to thinking, and test commentary before parallel tools and final text after tool results. |
| Raw or encrypted chain-of-thought is exposed. | Only render explicit summary/commentary events; keep encrypted reasoning exclusively in provider-private replay state and add negative assertions. |
| Summary chunks are concatenated incorrectly. | Concatenate deltas verbatim within a request and use an explicit boundary only between completed tool-loop iterations. |
| Provider behavior changes for OpenAI or other Responses-compatible APIs. | Gate commentary classification on the Meta profile and run shared provider regression tests. |
| Plain or machine-readable output becomes unstable. | Keep live thinking on the interactive transcript path and verify plain, non-TTY, and JSON behavior separately. |
| Meta omits optional summaries for some prompts. | Render commentary when available and retain the generic agent summary as a documented fallback; do not fabricate provider reasoning. |
| Replay ordering breaks Meta tool continuation. | Preserve completed items unchanged by output index and retain existing live integration assertions for encrypted reasoning and function calls. |

## Alternatives considered

- Map every Responses API output-text delta to thinking. Rejected because it
  would misclassify final answers and affect non-Meta providers.
- Display encrypted `reasoningContent`. Rejected because it is opaque,
  provider-private continuation state and may contain sensitive conversation
  content.
- Only recommend `--show-trace`. Rejected because the current agent replaces
  provider summaries with a generic sentence and does not provide live Muse
  feedback.
- Generate a second model-authored reasoning explanation after each turn.
  Rejected because it adds latency and cost and would be a post-hoc explanation,
  not the provider-supplied summary/commentary.
