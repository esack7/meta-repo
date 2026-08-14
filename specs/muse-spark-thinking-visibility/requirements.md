# Requirements: muse-spark-thinking-visibility

## Summary

Expose Muse Spark 1.1 reasoning summaries and commentary as useful thinking feedback in the Propio CLI

## Goals

- Show user-visible reasoning feedback from the Meta `muse-spark-1.1` model in
  the Propio CLI when the Meta Model API supplies reasoning summaries or
  commentary.
- Keep Meta commentary visually distinct from the final assistant answer so
  users can follow long-running agent and tool workflows.
- Preserve complete provider reasoning summaries across streamed chunks and
  prefer them over Propio's generic synthesized turn summary.
- Retain the existing encrypted reasoning and completed-output replay behavior
  required for Meta tool-call continuation.
- Keep the shared provider event contract and terminal behavior consistent for
  other providers.

## Non-goals

- Exposing, decrypting, reconstructing, or inferring Muse Spark's private raw
  chain-of-thought.
- Guaranteeing visible reasoning text when the Meta Model API returns only
  encrypted reasoning and no summary or commentary.
- Changing Muse Spark reasoning effort, model selection, credentials, pricing,
  or Meta Model API behavior.
- Displaying provider-private `reasoningContent` or encrypted continuation
  payloads in normal output, JSON output, or diagnostic logs.
- Redesigning the complete Propio transcript or tool-call user interface.

## Acceptance criteria

- [x] Propio continues to request Meta reasoning summaries when visible
      reasoning is requested, without requesting or exposing raw
      chain-of-thought.
- [x] A Meta `response.reasoning_summary_text.delta` stream containing multiple
      chunks is retained in full and in order rather than keeping only the
      first non-empty chunk.
- [x] Meta assistant message output with `phase: "commentary"` is emitted as
      user-visible thinking/progress, while final answer text remains assistant
      output.
- [x] In an interactive TTY, Meta summary/commentary deltas are rendered through
      the existing thinking presentation before or between tool calls, and the
      final answer remains visually distinct.
- [x] `--show-reasoning-summary` and `--show-trace` show the complete
      provider-supplied turn summary when one exists; the generic agent summary
      is used only when the provider supplies no usable summary.
- [x] In JSON mode with reasoning-summary visibility enabled, the response
      includes the complete provider summary and reports `provider` as its
      source.
- [x] Plain, non-interactive, and non-TTY execution do not interleave reasoning
      text with the final response in a way that breaks the existing output
      contract; explicitly requested summaries remain available through the
      established summary output path.
- [x] Meta reasoning items, commentary items, and function calls are replayed in
      their original provider order across tool-call rounds, with no duplicate
      commentary or function calls.
- [x] Encrypted reasoning continuation data is never rendered to the user.
- [x] Provider and agent unit tests cover phase-aware commentary routing,
      multi-chunk summary accumulation, provider-summary precedence, fallback
      behavior, and output-mode behavior.
- [x] The existing Meta live integration scenario captures and validates
      summary/commentary events when returned, while continuing to validate
      encrypted reasoning replay and the final tool-assisted response.
- [x] Build, test, formatting, and Fallow checks pass in both affected
      repositories.

## Affected repositories

<!-- Confirmed names are listed in repos.txt -->

## Open questions

- None. The intended user-visible material is provider-supplied commentary and
  reasoning summaries, not raw chain-of-thought.
