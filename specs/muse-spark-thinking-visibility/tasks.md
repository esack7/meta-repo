# Tasks: muse-spark-thinking-visibility

## Checklist

- [x] Review requirements and design
- [x] Run prepare-spec and confirm worktrees
- [x] Implement changes in specs/muse-spark-thinking-visibility/repos/ worktrees (not reference clones)
- [x] Verify acceptance criteria
- [x] Open pull requests per repository
- [x] Run close-spec when worktrees are no longer needed

## Implementation tasks

- [x] In `propio-providers`, extend Responses stream state with output-item
      phase metadata needed to classify Meta commentary deltas.
- [x] In `propio-providers`, emit Meta commentary text as `thinking_delta` and
      keep final output text as `assistant_text`.
- [x] In `propio-providers`, preserve reasoning-summary deltas and encrypted
      reasoning/commentary/function-call replay items without duplication or
      reordering.
- [x] Add provider unit tests for multi-chunk summaries, phase-aware commentary,
      final answer separation, parallel tool calls, and negative encrypted-data
      visibility.
- [x] Update the Meta live integration trace to observe summary and thinking
      events and validate returned visible events without making optional
      provider output a flaky requirement.
- [x] In `propio-agent`, accumulate every provider reasoning-summary chunk for
      each request and combine summaries across tool-loop iterations.
- [x] Change turn-summary selection so a non-empty provider summary takes
      precedence over the synthesized agent fallback.
- [x] Feed provider summary/commentary deltas into the interactive thinking
      presentation without duplicating the retained end-of-turn summary.
- [x] Preserve established behavior for interactive TTY, plain, non-TTY,
      non-interactive, and JSON output modes.
- [x] Add agent-loop tests for multi-chunk and multi-iteration accumulation,
      provider precedence, and generic fallback behavior.
- [x] Add terminal-renderer tests for live Meta feedback around tool calls and
      for summary visibility in interactive, plain, and JSON modes.
- [x] Update user-facing documentation for Muse Spark reasoning visibility,
      limitations, and the `--show-reasoning-summary` / `--show-trace` flags.

## Verification

- [x] Run `npm run build` in `propio-providers`.
- [x] Run `npm test` in `propio-providers`.
- [x] Run `npm run format:check` in `propio-providers`.
- [x] Run `npx fallow audit` in `propio-providers`.
- [x] Run the targeted Meta live integration test when credentials and network
      access are available; otherwise record that it was skipped.
- [x] Run `npm run build` in `propio-agent`.
- [x] Run `npm test` in `propio-agent`.
- [x] Run `npm run format:check` in `propio-agent`.
- [x] Run `npx fallow audit` in `propio-agent`.
- [ ] Manually verify an interactive Muse Spark tool-calling turn shows visible
      commentary/summary before the final answer when Meta returns it.
- [ ] Manually verify `propio --show-reasoning-summary` and
      `propio --show-trace` prefer the Meta-provided summary and fall back
      cleanly when no provider summary is returned.
- [x] Verify JSON and plain/non-TTY output do not expose encrypted continuation
      state or mix thinking text into the final response.
