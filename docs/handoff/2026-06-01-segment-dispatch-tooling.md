# Segment-dispatch tooling carry-over from iris (iteration 1)

**Date:** 2026-06-01
**Branch:** chore/segment-dispatch-tooling
**PR:** to be opened from this branch (offered at session end)
**Base commit:** b842848 (main — "Merge pull request #1 from .../chore/adopt-iris-workflow-patterns")
**Author:** Farouk Khawaja

## Summary

First iteration of an iterative effort to carry over reusable ideas, skills, and workflows from the iris project (`~/src/iris`) into lbkmk. This iteration ports the **segment-gated external-agent dispatch tooling** and backports the **External Agent Protocol** to track iris v1.11. The earlier `chore/adopt-iris-workflow-patterns` PR (#1, already on main) landed the first round of iris adoption — the v1.0 protocol and the 159-line dispatcher this iteration extends.

## What shipped

- **`bin/wf-log`, `bin/wf-extract-segment`** (new) — framework-agnostic helpers copied verbatim from iris. `wf-log` owns the activity-log and sha-pinned verdict/approval formats; `wf-extract-segment` cuts a numbered segment from a `## Segment N` plan and validates segment structure (contiguous from 1, no gaps/dupes).
- **`bin/dispatch-kimi`** (replaced, 159 → 513 lines) — the segment-capable dispatcher: adds `--segment N`, `--review --segment N`, and `--plan` modes alongside the original `initial`/`--review`. Segment mode purges review/approval state for segments ≥ N, gates on the prior segment's HEAD-pinned PASS verdict + approval, cuts the slice, and hands the agent only that slice so a run cannot skip a checkpoint. `WF_DRY_RUN=1` exits after purge/gate/cut as a test seam. De-iris edits: kickoffs target "the lbkmk project"; header comment repointed to protocol §3.2/§15.4; `WF_DRY_RUN` comment softened (no `test/bin/run.sh` yet). **`Read AGENTS.md` kickoff lines kept unchanged** — AGENTS.md is the external-agent doc, not a path to rewrite.
- **`AGENTS.md`** (new) — agent-tailored operative subset of CLAUDE.md for non-Claude agents (Kimi reads this on dispatch). De-iris'd to lbkmk identity/stack (Phoenix + Ecto, Ash explicitly out), worktree-scope hard rule, conventional-commit/US-English rules, Open Questions gate, idempotency-at-ingress, handoff convention, protocol pointer.
- **`docs/external-agent-protocol.md`** (v1.0 → v1.11) — backported generic sections §2.5 (no `git add` of gitignored paths), §3.2 (segment checkpoints are structural), §9.7 (keep mermaid current), §15.2 (rewritten — AGENTS.md authoritative for Kimi), §15.4 (segment-sliced dispatch). Iris's Ash/Gusto/Clerk sections intentionally omitted (see new §14 changelog). AGENTS.md added to §13 references.

Commits: `56914da` (tooling), `19d80ca` (AGENTS.md), `24b7f9f` (protocol).

## Build / test status

No application build pipeline exists yet (no `mix.exs`). Verification performed:

- `zsh -n` parse check on all three scripts → all parse OK.
- Protocol structure: version 1.11, new sections at correct positions, no duplicate section numbers.
- End-to-end functional verification via `WF_DRY_RUN=1` (9/9 checks passed): `wf-extract-segment --validate` (good→0, gap→65), segment extraction (shared-context + Segment N, correctly excludes other segments), dry-run cut creates `slice-seg-N.md`, gate refuses with missing approval (66), gate refuses on stale sha (66), gate passes only with HEAD-pinned PASS verdict + approval (0), `wf-log` verdict/approval/activity writes succeed.

All gitignored verification artefacts (`docs/.context/`) were removed before commit; working tree clean.

## What's next

- **Open the PR** for this branch (offered; not yet created).
- **Later carry-over iterations** (from the same iris-adoption effort, deliberately deferred this round):
  - **C** — document frontmatter + controlled-vocabulary tag scheme for lbkmk docs.
  - **D** — ADR pattern: create `docs/decisions/` with the dated `YYYY-MM-DD-<name>.md` format (iris has it; lbkmk does not).
  - **E** — project-status tracking (YAML + JSON Schema + verify task). Heavier; lbkmk currently uses the ad-hoc "synthesize from sources" status query in CLAUDE.md. Revisit whether it's worth adopting once phases/app code exist.
  - **F/G** (when `mix.exs` lands) — re-implement iris's transactional-outbox / audit-attribution *patterns* in plain Ecto (not Ash); consider a project `phoenix dev-server` skill.

## Related open issues

Not yet checked against `gh issue list` at write time. One candidate follow-up surfaced this session (see carry-overs): porting iris's dispatch-tooling test suite (`test/bin/run.sh`). New findings during later carry-over iterations belong in new issues with the appropriate label per "Tracking Deferred Work" in CLAUDE.md.

## Open questions / carry-overs

- **Dispatch-tooling test suite — DEFERRED.** Iris has a `test/bin/run.sh` exercising the gate/purge/cut logic; it was not ported (out of scope for iteration 1). The `WF_DRY_RUN=1` seam is preserved in `bin/dispatch-kimi` specifically so that suite can be added later. Candidate for a `tech-debt`/`enhancement` GitHub issue.
- **`--plan` mode dependency — NEXT/INFO.** `bin/dispatch-kimi --plan` expects writing-plans lessons at `~/.claude/skills/writing-plans/lessons/`; it warns (does not fail) if absent. Matches CLAUDE.md "Authoring plans".

## References

- Source: iris project — `~/src/iris/bin/{dispatch-kimi,wf-log,wf-extract-segment}` and `~/src/iris/docs/external-agent-protocol.md` (v1.11), `~/src/iris/AGENTS.md`.
- Memory: `feedback_agents_md_for_kimi.md` — AGENTS.md (external-agent doc) vs CLAUDE.md (Claude's); do not conflate.
- Prior thread: PR #1 `chore(workflow): adopt iris workflow patterns (tier 1 + tier 2)` (merged to main).
