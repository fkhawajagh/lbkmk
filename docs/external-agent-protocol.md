---
title: External Agent Protocol
version: "1.11"
date: 2026-05-22
updated: 2026-06-01
status: active
---

> **Document Version: 1.11** | Updated 2026-06-01

# External Agent Protocol

Standing rules for any external agent (Claude- or Kimi-driven) executing an implementation plan in this repository under the control of a separately-orchestrated session (i.e., not the main interactive lbkmk session that hands off the plan).

Every implementation plan handed to an external agent must end with a line of the form:

> Follow the standing External Agent Protocol at `docs/external-agent-protocol.md` in addition to the task-specific instructions above.

The plan author is responsible for that pointer; the agent is responsible for reading and applying everything below.

---

## 1. Purpose and Scope

This protocol exists because:

- External agents work without the main session's conversational context — they cannot infer judgment calls from prior discussion.
- The main session orchestrator runs an Opus-tier review pipeline (build-validator + integration-reviewer + code-reviewer) before any merge. The protocol's job is to make the agent's output reach that pipeline in a reviewable state, not to skip ahead of it.
- Patterns that fail review repeatedly — overly broad rescues, stale references after renames, UX/code contradictions, cross-module style drift — are mechanical and preventable if the agent runs the right end-of-work passes.

The protocol applies to every external-agent plan: feature work, refactors, documentation sweeps, audit response, dependency adoptions. Adjust the depth (a 1-task doc sweep does not need a cross-module consistency diff) but do not skip the closing protocol.

---

## 2. Operating Constraints

### 2.1 Worktree scope

All file operations, all shell commands, all `git` invocations must stay inside the worktree the plan specifies. Do not edit, delete, or commit files outside the worktree. Do not run `rm` on paths outside the worktree root. Do not commit to `main` or any other branch.

If a command might affect the main repo or another worktree, stop and surface it in a status report instead of running it.

### 2.2 Start in the worktree

Before any `mix`, `git`, `grep`, or other shell command, `cd` to the worktree the plan specifies and confirm:

```bash
cd /path/to/.worktrees/<branch-name>
pwd
git branch --show-current
```

The Claude Code Bash tool preserves the working directory across calls, so a single `cd` at session start keeps every subsequent command rooted in the worktree. `mix` and `git` both behave correctly from there; running them from the parent repo root reads the wrong tree's HEAD and produces misleading output. Agents that skip this step routinely fail to find files, run `git log` on the wrong branch, and exhaust review cycles on artefacts of cwd confusion.

Do not `cd` out of the worktree mid-session. If a command appears to need a path outside the worktree, that's a §2.1 violation — surface in a status report.

### 2.3 No `git push`, no `gh pr create`

Final commits stay local. The main session orchestrator pushes the branch and opens the PR after running the Opus review pipeline. An external agent that pushes prematurely bypasses that gate.

### 2.4 No `Co-Authored-By` trailer

Commit messages must not include a `Co-Authored-By: Claude` (or any AI-attribution) trailer. Global preference — see the user's `~/.claude/CLAUDE.md`.

### 2.5 No `git add` of gitignored paths

`docs/.context/` is gitignored intentionally. Status reports, checkpoint files, code-review feedback, segment slices, gate state, and `kimi-run-*.log` files live there as local-only worktree artefacts. The orchestrator reads them locally before merge; they are not part of the PR's diff. Do not `git add` or `git add -f` any file under `docs/.context/`. This applies to:

- `docs/.context/<feature>/final-status.md`
- `docs/.context/<feature>/checkpoint-*.md`
- `docs/.context/<feature>/checkpoint-*-feedback.md`
- `docs/.context/<feature>/code-review-feedback*.md`
- `docs/.context/<feature>/kimi-run-*.log`
- `docs/.context/<feature>/slice-seg-*.md`
- `docs/.context/<feature>/review-seg-*.verdict`
- `docs/.context/<feature>/approval-seg-*`
- `docs/.context/<feature>/checkpoint-seg-*.md`
- `docs/.context/<feature>/logs/activity.log` and `docs/.context/<feature>/logs/*.log`
- any other file the orchestrator may add to that directory between dispatches

The same rule applies to any other gitignored path — `docs/.handoff/` (session handoffs), `.env*` other than `.env.example`, `_build/`, `deps/`. Session handoffs and final-status reports are gitignored bridges, not committed artefacts: write them under `docs/.handoff/` or `docs/.context/<feature>/` and never `git add` them. If something must be visible on `main` after merge, it belongs in the PR description or a tracked doc the plan names — not a handoff.

If a write to a gitignored path is needed (e.g. updating `final-status.md` mid-task), make the edit and do NOT stage or commit it. Reaching for `git add -f` to bypass `.gitignore` is a protocol violation regardless of the file's contents — stop and surface it in the status report.

---

## 3. In-Flight Checkpoints

Plan docs designate checkpoint tasks (e.g., "Task 4: status report — STOP for orchestrator review"). At each checkpoint:

1. Write a brief status note to a designated checkpoint file (the plan specifies the path).
2. Stop. Do not start the next task.
3. Wait for the orchestrator to either approve and resume, or write a feedback file you must read before continuing.

Checkpoints exist because a pattern propagated across 4 modules is much harder to correct than the same pattern caught after 1 module. End-of-work review alone is insufficient for any plan with more than ~3 substantive implementation tasks.

If the plan does not include checkpoints and the work has 4+ substantive tasks, propose adding them in the status report after Task 1 — do not silently proceed.

### 3.1 Checkpoint files separate self-applied fixes from original task work

The checkpoint status report has two audiences: the orchestrator (deciding what to review) and the agent on resume (regaining context). When the agent self-applies a fix between the original implementation and the checkpoint write, the checkpoint file separates the original Tasks N work from the post-Tasks-N self-fix in distinct sections. The orchestrator can then review the self-fix on its own merits without re-deriving what changed. A "Code Review Finding (Post-Checkpoint)" subsection naming the affected files, the symptom, and the chosen fix is the canonical shape.

### 3.2 Segment-dispatched plans make the checkpoint structural

For a plan dispatched in segment slices (`bin/dispatch-kimi --segment N <plan> <worktree>`), the "STOP at the checkpoint" guarantee is structural, not a soft instruction. The agent physically receives only the current segment's slice (`docs/.context/<branch>/slice-seg-N.md`), so there is no later task in context to drift into. Each segment ends by writing its own checkpoint report to `docs/.context/<branch>/checkpoint-seg-N.md`: the per-segment form of §3, citing that segment's commit range.

Advancing to segment N requires, for segment N-1, a sha-pinned PASS review verdict and an approval, both pinned to the current branch HEAD; the dispatcher's gate refuses the next segment until the orchestrator records them. Re-opening segment N invalidates all review and approval state from N forward. The agent does not manage the gate: it implements one slice, writes `checkpoint-seg-N.md`, and stops. See §15.4 for the dispatcher modes.

---

## 4. Code Quality Rules

### 4.1 Narrow error handlers

`rescue Postgrex.Error`, `rescue _`, bare `try/catch`, untargeted `ON CONFLICT DO NOTHING`, swallowed `case` defaults — these widen the failure mode the code claims to handle. They mask real bugs by retrying or ignoring errors they were never meant to handle.

Rules:

- `rescue` clauses match a specific exception module. Check field-level conditions (e.g., SQLSTATE) inside the body and `reraise e, __STACKTRACE__` if the condition does not match.
- `ON CONFLICT` targets the specific index that can legitimately collide.
- `case` statements that need a default arm should match a tagged tuple or atom, not `_`.

Example — correct Elixir rescue narrowing (note: Elixir's `rescue` does not pattern-match struct fields, so the SQLSTATE check is body-side):

```elixir
try do
  Repo.insert_all("...", [row], on_conflict: :nothing)
rescue
  e in Postgrex.Error ->
    if e.postgres[:code] == :deadlock_detected do
      Process.sleep(10)
      Repo.insert_all("...", [row], on_conflict: :nothing)
    else
      reraise e, __STACKTRACE__
    end
end
```

### 4.2 Verify before claim

Every assertion of the form "X passes" / "tests are green" / "compile is clean" must be backed by command output from the **final commit on the branch**, not from an earlier commit during implementation. Re-run the relevant command at HEAD before reporting done.

This is the rule that catches "the test failed after I made the last edit but I claimed everything passed because it passed three commits ago."

### 4.3 No silent error suppression

Catching exceptions to keep tests green, removing assertions to make them pass, skipping a test because it is flaky — all of these are defects, not fixes. Surface flakiness, surface unexpected errors, surface broken assertions in the status report. The orchestrator decides whether to skip / fix / defer.

### 4.4 Roll back every migration before committing

After running migrations, run `mix ecto.rollback` to confirm `down/0` works, then re-apply with `mix ecto.migrate` to restore. Migrations that cannot roll back must not be committed without explicit orchestrator approval. This catches the irreversible-migration class of bug before it lands on `main`.

### 4.5 Self-applied fixes get a fresh §9.4 Self-Opus pass

When a review at a checkpoint surfaces an issue and the agent applies a self-fix before the orchestrator responds, the fix gets a separate §9.4 Self-Opus pass before it lands in the checkpoint file. The pass that covered the original implementation does not transfer — the fix's failure modes are not the original's. Treat the self-fix as new work, not a touch-up. The most common defect class here is the fix that *narrows* a problem in one direction while introducing a new failure mode in another (e.g., a "scope tighter" change that now raises on previously-tolerated input).

### 4.6 "Pre-existing" claims require `git diff` evidence

Any finding the agent labels "pre-existing" must be backed by command output showing that the offending line exists on `origin/main`. Acceptable evidence:

```bash
git fetch origin main
git diff origin/main -- <path-to-offending-file>
# or
git log origin/main -- <path-to-offending-file> -1 --oneline
```

If the line does not appear on `origin/main`, it was introduced by this branch and must be fixed in this round, not deferred.

This rule extends §4.2 (Verify before claim) to the specific failure mode where "pre-existing" becomes a way to defer blame for findings the agent's own commits introduced. The rule applies to every static-analysis finding (credo, dialyzer, lint), every test failure, every type-checker diagnostic, and any other surfaced defect class. "Pre-existing" is a verifiable claim, not a deferral hint.

### 4.7 No stub tests with `assert true` + coverage-claim comments

Do not write `test "..." do assert true end` blocks with a comment claiming the real coverage lives elsewhere. The pattern looks like documentation but actually adds noise: the test runs as a pass, contributes to the test count, and invites future readers to assume the named behaviour is verified. Worse, if the cited test file is renamed, refactored, or never actually exercised the claim, the stub silently lies.

If real coverage lives in a sibling test file, link to it via a `@moduledoc` line on the cited file (or a top-of-file comment) — not via a fake test block. Verify the link by opening the cited file and confirming the named behaviour is actually tested before adding the link.

The acceptable forms are:

1. **A real behaviour test** — exercises the named claim against the module's actual semantics.
2. **A unit test of the module's structural contract** — e.g., an `atomic/3`-style shape assertion that would survive a refactor.
3. **No test block, with a `@moduledoc` link to the consuming module's test file** — readers learn where to look without a fake green check.

This rule applies to all stub-test patterns, not just `assert true`: `assert is_atom(:ok)`, `:ok`, `skip "covered elsewhere"`, and any other no-op assertion that exists only to document a coverage claim.

---

## 5. Style Rules

### 5.1 Match existing patterns mechanically

When applying the same pattern P to N modules (or N schemas, N tests, N migrations), the result must be **identical modulo module-specific content**. Identical comment headers. Identical block ordering. Identical prose in explanatory comments.

The cheapest way to enforce this: implement Module 1, then for Modules 2..N copy the relevant blocks verbatim and only change names, not style.

Reviewer-detected style drift is the single most common low-severity finding. It is mechanical to prevent.

### 5.2 Do not paraphrase repeated logic

When the same explanatory comment appears across N modules, copy-paste it verbatim. Diverging prose for the same logic produces reviewer friction and obscures whether the divergence is intentional.

### 5.3 Follow the project formatter and linter

The canonical build pipeline lives in `CLAUDE.md` → "Build Validation Commands" once that section is populated. Until it is, the working assumption for Phoenix code is `mix format --check-formatted` and `mix credo --strict`. Do not commit code that fails either. If credo's suggestion seems wrong, surface it in the status report — do not add `# credo:disable-for-this-file` to silence it.

### 5.4 US English in all prose

Code, comments, commit messages, documentation, status reports — all US English. Exception: Elixir's `@behaviour` keyword and the prose around it (use British spelling `behaviour`/`behaviours`/`behavioural` to match the language keyword and Elixir community convention).

### 5.5 No Claude / AI references

Code, commit messages, documentation, status reports — none of these reference Claude, AI, an LLM, or a model. Author identity is not relevant to the project record.

### 5.6 Shared test fixtures get moduledocs that name every consumer

When a test fixture (helper, factory, builder) is used by multiple test files, its moduledoc lists all consumers by module name. When a test file's moduledoc mentions a fixture, it must accurately reflect the fixture's current shape (data layer, sandbox requirements, etc.). Repurposing a fixture without updating both ends produces stale docs that mislead the next reader.

Concrete check: after renaming or restructuring a shared fixture, `git grep -n '<fixture module name>' test/` and skim every match for "ETS-backed," "no database," "single-purpose" — any wording that the change just falsified.

---

## 6. Security Rules

### 6.1 No raw SQL via string interpolation

Composable queries via `Ecto.Query` with the `^` pin operator. If raw SQL is unavoidable, use `Repo.query/2` with the bindings list. Never interpolate user input into a SQL string.

### 6.2 No hardcoded secrets

All secrets live in `config/runtime.exs` and are read from environment variables via `System.fetch_env!/1`. Never check secrets into source. If a secret accidentally lands in a commit, surface it in the status report — the orchestrator handles rotation, not the agent.

---

## 7. UX Rules (LiveView work)

### 7.1 Sweep for stale "coming soon" placeholders

After shipping a feature, run `grep -rn 'coming soon\|coming in Phase\|placeholder\|TBD\|not yet' lib/lbkmk_web` and update any user-facing copy that contradicts the shipped behaviour. Example: an overflow menu item that says "Archive — coming in Phase 3" sitting next to a Delete button that now archives is a contradiction the user will hit immediately.

### 7.2 Confirmation modal copy matches actual behaviour

If the operation is reversible (e.g., soft-delete), the modal should not say "cannot be undone." If the user-visible button label stays "Delete" while the behaviour is soft-delete, the modal copy should clarify the recovery surface ("An administrator can restore it from the admin console").

### 7.3 Mock before implementing

For new LiveView pages, popups, or alerts — mock with the `huashu-design` skill or an HTML prototype before implementing the real page. The mock surfaces design decisions cheaply.

---

## 8. Plan Adherence

### 8.1 Baked-in decisions are non-negotiable

Plan docs call out specific decisions ("Option A", "no LiveView Archived tab", "owner-only authorization", etc.). These are not suggestions. If a deviation seems necessary, **stop and write a status report** — do not decide unilaterally. The orchestrator and user made these decisions for reasons the agent does not have visibility into.

### 8.2 Document every deviation explicitly

If implementation forces a departure from the plan, record the deviation in three places:

- The commit message that introduces the workaround
- The handoff doc (with a "Deviations from original plan" section)
- The closing status report

### 8.3 Surface unknown-unknowns

If the plan doc has internal inconsistencies, missing context, or instructions that don't compile against the current code state — stop and write a status report. Do not guess.

### 8.4 Verify plan claims about library internals before relying on them

Plan docs often cite library behaviour ("the change has no `atomic/3` callback, so X" or "the library's transformer names the version resource Y"). Before relying on these in implementation, verify against the dep source under `deps/`. If the plan's claim is wrong, document the actual behaviour in the commit message and in the checkpoint file under "Deviations from Plan." Do not silently work around incorrect plan claims — the orchestrator needs to know the plan needs editing for the next agent who reads it.

Quick discipline: grep the cited file under `deps/<lib>/lib/...` and confirm the claim line-for-line before writing code that depends on it.

### 8.5 Plan style: prefer spec-style over pre-written code bodies

Plans handed to external agents (Kimi or external Claude sessions) should be **specification-style**: state behaviour, data contracts (as tables), and behavioural test cases (name + assertion in prose). Avoid pre-writing module bodies and test bodies in the plan.

The implementer translates spec → code. The reviewer evaluates code against spec. This separation forces engagement from both roles. Pre-written code bodies cause implementers to transcribe and reviewers to diff-match, neither of which catches semantic defects.

Plan authors should use the `writing-plans` skill to produce plans — it applies plan-quality lessons automatically via a fresh Opus subagent.

---

## 9. Self-Review Checklist

Before declaring done, run all six passes. They are mechanical and high-leverage.

### 9.1 Cross-module consistency diff

When the work applied the same pattern to N modules / schemas / tests / migrations, paste the relevant blocks side-by-side and confirm they are identical modulo module-specific content. Drift between them is the most common reviewer finding and is mechanical to catch.

Tooling: `git diff main..HEAD -- lib/lbkmk/<context>/` and read for visual symmetry.

### 9.2 Stale-reference sweep

After renaming or removing any symbol — function name, schema field, route, etc. — run:

```bash
grep -rn '<old_name>' lib test docs priv
```

Fix every stale reference, including in comments, docstrings, and test descriptions. A renamed function that still appears in a `describe` block label is reviewer friction; an old function name in a comment is wrong documentation.

### 9.3 UX / code contradiction sweep

For LiveView / user-facing work, after shipping the feature:

```bash
grep -rn 'coming soon\|coming in Phase\|placeholder\|TBD\|not yet\|will be' lib/lbkmk_web
```

Resolve any contradictions between shipped behaviour and stale "coming soon" placeholders.

### 9.4 Self-Opus pass

Before reporting done, write down 3–5 concerns a senior reviewer (Opus-tier) would raise about the work. Be specific and unkind:

- Overly broad error handlers, missing re-raise paths
- Race conditions in test setup
- Forward-compat issues (untargeted `ON CONFLICT`, untyped `rescue`, etc.)
- UX/code contradictions
- Missing test cases for edge behaviour
- Migration safety / rollback gaps

Address them inline if the fix is mechanical. Otherwise surface them in the status report for the orchestrator to weigh.

### 9.5 Tests must demonstrably exercise their claimed contract

When a test's docstring or moduledoc claims to verify a specific code path ("rollback inside `X`", "atomicity of the bulk write", "channel SKU mapping for product Y"), the test must actually invoke that code path. Re-read each test against its claim during §9.4 Self-Opus: trace the lifecycle, the sandbox state, the setup. A test named `rollback_inside_X` that, due to setup or shared-state, never enters `X` is worse than no test — it gives false confidence and survives review because the assertion still passes against a weaker contract.

Cheapest catch: read the test as if you've never seen the code under test. Does the setup make `X` reachable? Does the assertion distinguish "the contract held" from "the contract was bypassed"?

### 9.6 `git grep` for both the old AND the new symbol after a rename

Section §9.2 covers the old name (sweep for stale references to the deleted symbol). The complement: after renaming `foo → bar`, also run `git grep -n 'bar' lib test docs` to confirm the new symbol is referenced where it should be — and that comments / docstrings / test descriptions around the new name still accurately describe the renamed function's current behaviour. Catches the "renamed the function but the moduledoc still describes the old behaviour" failure mode.

### 9.7 Keep mermaid diagrams current

If your change alters something a mermaid diagram in a design or plan doc depicts — a state machine, entity relationship, sequence/data flow, or dependency the diagram shows — update the diagram in the same change so it matches the code. If the stale diagram lives in a doc outside your task scope, flag it in your status report (§12 → Self-Review Concerns) rather than leaving it silently drifted. A passing build never catches a diagram that has drifted from the code.

---

## 10. Branch Hygiene

### 10.1 Merge `main` into the branch before declaring done

```bash
git fetch origin main
git merge --no-edit origin/main
```

Surface any conflicts in the status report. The merge ensures the GitHub PR diff renders correctly and does not show spurious deletions from files that landed on main during the work.

If the merge fails or conflicts are non-trivial, stop and write a status report. Do not force-resolve.

### 10.2 Refresh handoff / WIP docs at end of work

If the plan instructed writing a WIP handoff at an intermediate state, refresh it at the end to reflect the delivered state. Don't leave a "7/10 tasks, 2 failures remain" header on 10/10 success — that's the version that lands on `main` at merge.

### 10.3 Final build pass

After the merge and any cleanup commits, re-run the canonical build pipeline once more from HEAD. The exact commands live in `CLAUDE.md` → "Build Validation Commands" (until that section is populated, default to the standard Phoenix chain: `mix deps.get`, `mix compile --warnings-as-errors`, `mix format --check-formatted`, `mix credo --strict`, `mix test --trace`). Every step must pass. Test counts must match or exceed the baseline. The status report cites these results, not earlier ones.

### 10.4 Clean working tree check

After `final-status.md` is written, run `git status` in the worktree. If anything is uncommitted (modified files, untracked files outside `.gitignore`), either commit it as a clean follow-up commit or revert it. Do NOT leave a dirty tree going into the orchestrator's closing review pipeline.

A dirty tree at handoff produces inconsistent review state: the build pipeline runs against the on-disk version while the review pipeline diffs the branch, and the two disagree. Catch it before the orchestrator does.

### 10.5 Write `final-status.md` AFTER all task commits land

Write the status report only after every task commit has landed, not as part of the last task's commit. The SHA list in the status report should reflect `git log` at the moment the report is written. Writing it during the final task means the final task's own commit SHA isn't known yet, producing stale SHA references that confuse future readers.

---

## 11. Closing Protocol

Final steps once the implementation tasks, self-review passes, and branch hygiene are all done:

1. **Do NOT run `git push`.**
2. **Do NOT run `gh pr create`.**
3. **Do NOT edit anything outside the worktree.**
4. Write the status report (see section 12).
5. Stop.

The orchestrator runs the Opus review pipeline (build-validator + integration-reviewer + code-reviewer at Opus tier — see `~/.claude/CLAUDE.md` "Model Routing Policy"), addresses any findings, then pushes and opens the PR.

---

## 12. Status Report Format

Write the status report to the path the plan specifies (typically `docs/.handoff/YYYY-MM-DD-<branch-slug>.md`, gitignored — do not commit it). Use this skeleton:

```markdown
# Status Report: <plan title>

**Branch:** <branch name>
**Worktree:** <absolute path>
**Date:** YYYY-MM-DD
**Status:** <X of N tasks complete> — <one-line summary>

## Commits

<git log --oneline origin/main..HEAD output>

## Test / Build Verification

(See CLAUDE.md → Build Validation Commands for the canonical pipeline. Default Phoenix chain below.)

- mix deps.get: PASS / FAIL (paste output if FAIL)
- mix compile --warnings-as-errors: PASS / FAIL
- mix format --check-formatted: PASS / FAIL
- mix credo --strict: PASS / FAIL
- mix test --trace: <count> tests, <count> failures, <count> skipped

## Deviations From Plan

<list every deviation with explanation; or "None">

## Self-Review Concerns

<3-5 concerns from the Self-Opus pass; or "None identified">

## Open Questions

<anything that needs orchestrator input>

## Files Modified

<git diff --name-only origin/main..HEAD output>
```

The status report is the orchestrator's primary input for deciding what to review and what to fix. Be specific, be honest about what is incomplete or uncertain, and surface concerns the agent identified itself — those are the most valuable items in the report.

---

## 13. References

- `CLAUDE.md` (project) — project identity, stack, conventions
- `AGENTS.md` (repo root) — agent-side operative subset of `CLAUDE.md` for non-Claude external agents
- `~/.claude/CLAUDE.md` (user global) — Core Principles, Code Style, Security, Trust Boundary, Model Routing Policy
- `~/.dotfiles/rules/elixir/coding-style.md` — Elixir-specific style rules (if/when an Elixir codebase exists)
- `docs/.handoff/README.md` — handoff document convention and skeleton
- `docs/shared-context-template.md` — per-feature context.md template

---

## 14. Updating This Protocol

This document is the single source of truth for external-agent behaviour. Plan docs reference it; agents are expected to read it once and apply it everywhere.

To add a rule:

1. Add it to the relevant section above.
2. Bump the document version (top of file).
3. Update `CLAUDE.md` if the rule affects ongoing lbkmk conventions, not just external-agent execution.
4. Commit on a separate PR — protocol changes should not be bundled with implementation work.

### Changelog

- **1.11 (2026-06-01)** — Backported the generic sections from the Iris external-agent protocol v1.11 needed to support segment-dispatched plans: §2.5 (no `git add` of gitignored paths), §3.2 (segment-dispatched plans make the checkpoint structural), §9.7 (keep mermaid diagrams current), §15.2 (rewritten — `AGENTS.md` is authoritative for Kimi), and §15.4 (segment-sliced dispatch). The version jumps from 1.0 to 1.11 to track the Iris source version. Iris's Ash/Gusto/Clerk-specific sections (Iris §2.5 `authorize?: false`, §4.4 `mix ash.codegen` migrations, §4.6 `Ash.Changeset` helpers, §4.7 `Ash.read_one!`, §6.1–6.4 and §6.7 Ash security rules) are intentionally omitted — lbkmk does not use Ash. Section numbers are lbkmk's own and do not all line up with Iris's.
- **1.0 (2026-05-22)** — Initial lbkmk external-agent protocol.

---

## 15. Kimi-Specific Notes

Most of this protocol is model-agnostic. The rules below address Kimi-only mechanics that surface during dispatch via `bin/dispatch-kimi`.

### 15.1 Skill naming

In Kimi, plugin skills use hyphens, not colons:

- Claude form: `superpowers:executing-plans`
- Kimi form: `superpowers-executing-plans`

When a plan references a skill by its canonical Claude form, Kimi's harness resolves it — no rewriting in the plan required.

### 15.2 AGENTS.md is authoritative for Kimi

`AGENTS.md` at the repo root mirrors the operative subset of `CLAUDE.md` for non-Claude agents, and the `bin/dispatch-kimi` kickoff instructs Kimi to read it on dispatch. If `AGENTS.md` and `CLAUDE.md` diverge in ways that affect the task at hand, surface the divergence in the status report — do not pick one and proceed silently. The orchestrator decides whether to reconcile the docs or adjust the task.

### 15.3 Tool surface differences

Kimi's tool set is distinct from Claude Code's. The protocol mandates behaviour — worktree scope, status report, no push, no PR — not specific tools. If a plan task assumes a Claude-specific tool (e.g., an `Agent` subdispatch, a particular MCP server, a Claude-only skill), surface the gap in the status report rather than improvising an equivalent.

### 15.4 Segment-sliced dispatch

For large plans, the orchestrator dispatches one segment at a time so a single run cannot skip a checkpoint (§3.2). The relevant `bin/dispatch-kimi` modes:

- `bin/dispatch-kimi --segment N <plan> <worktree>` dispatches only segment N: it purges review/approval state for segments at or after N, gates on segment N-1's approval (for N greater than 1), cuts `[shared-context] + [Segment N]` into `docs/.context/<branch>/slice-seg-N.md`, and hands the agent only that slice.
- `bin/dispatch-kimi --review --segment N <feedback> <worktree>` re-dispatches segment N with review feedback, reusing the existing `slice-seg-N.md`. Plain `--review` without `--segment` is not accepted.

A segmented plan is a single file whose tasks are grouped under `## Segment N` headings, contiguous from 1 (the dispatcher validates this and refuses a plan with gaps or duplicates). Per-segment artefacts live under `docs/.context/<branch>/`: the slice (`slice-seg-N.md`), the gate state (`review-seg-N.verdict`, `approval-seg-N`), the checkpoint report (`checkpoint-seg-N.md`), and run/activity logs under `docs/.context/<branch>/logs/`. All are gitignored (§2.5). Each segment requires the agent to write `checkpoint-seg-N.md` after its commits land and STOP, exactly as §3 specifies, scoped to that segment.
