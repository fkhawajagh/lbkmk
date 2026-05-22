# Session Handoff Documents

This directory holds **session-end handoff documents** — short notes that let the next session (whether human or AI) pick up where the previous one left off without re-deriving the state from scratch.

## Why this exists

Process artifacts during feature development live in `docs/.context/{feature}/` and are **gitignored** by design (the multi-agent pipeline writes arch-reviews, integration checkpoints, and task-discovery notes there, and most of that is genuinely transient). The downside: when a worktree gets cleaned up after merge, anything in `.context/` goes with it — including session handoffs that were meant to survive.

A handoff written here lives on `main` permanently, so a future session can find it by glob no matter what happened to the originating worktree.

## When to write one

Write a handoff before you wrap a session if any of these apply:

- A PR has merged and the worktree is about to be deleted.
- Work is mid-flight and you want the next session to resume from a known state.
- Decisions were made in conversation that aren't captured in the plan doc, the PR description, or memory.
- You discovered something non-obvious during the work (a library gotcha, a config trap, a framework version-specific behavior, an external-API quirk) that future sessions would benefit from knowing.

Do **not** write a handoff for:

- Trivial fixes or one-line edits — the commit message is enough.
- Work that's fully captured in the PR description and the plan doc already. Don't duplicate; link.
- Lessons that belong in CLAUDE.md (project-wide conventions) or in the memory system (user preferences, recurring traps). Those have better homes.

## Where it fits with other systems

| Mechanism | Lifetime | Scope |
|---|---|---|
| **`docs/handoff/`** (this directory) | Permanent | Session-to-session continuity. One file per major work unit. |
| `docs/.context/{feature}/` | Until worktree deletion | Multi-agent pipeline artifacts (arch-review, integration checkpoints, task-discovery). Gitignored. |
| `docs/plans/...` | Permanent | Forward-looking plans before work begins. Versioned. |
| PR description | Permanent on GitHub | Summary of what shipped. Reviewable. |
| GitHub issues | Permanent on GitHub | Deferred work, open questions, tech debt. See "Tracking Deferred Work" in `CLAUDE.md`. |
| `CLAUDE.md` | Permanent | Project-wide conventions and tech stack rules. |
| Memory system | Permanent, cross-session | User preferences, recurring traps, project state snapshots. |

Rough order of preference when something is worth recording:

1. If it's a project-wide rule → `CLAUDE.md`.
2. If it's a future-session preference or trap → memory.
3. If it's an open question blocking future work → `docs/domain-model.md` §§7-8.
4. If it's deferred work → GitHub issue (see "Tracking Deferred Work").
5. If it belongs in the PR → PR description.
6. Otherwise, if it's session-continuity information → here.

## Filename convention

```
YYYY-MM-DD-<branch-or-topic-slug>.md
```

Examples:

- `2026-06-01-ingestion-pipeline-design.md`
- `2026-06-03-squarespace-webhook-spike.md`
- `2026-06-15-incident-xero-rate-limit.md`

The date prefix sorts chronologically when `ls` is run against the directory. The slug is the branch name minus the leading `feat-`/`fix-`/`chore-` prefix when possible, or a short topic when not branch-tied.

## Document structure

Use this skeleton. Trim sections that don't apply.

```markdown
# <Title>

**Date:** YYYY-MM-DD
**Branch:** <branch-name> (or n/a)
**PR:** #<number> (link), <status: open | merged | abandoned>
**Base commit:** <short SHA of main when work started>
**Author:** <name>

## Summary

One paragraph: what this work is, and the punchline of where things stand.

## What shipped (or is in flight)

Bullet list of the actual changes. Reference files and line ranges where it helps.

## Build / test status

The pipeline result at handoff time. Be specific: test count, format/credo state, prod-compile state. Future sessions will trust these numbers, so cite the commands you actually ran.

## What's next

The concrete next action(s) for the following session. Avoid open-ended "consider X" prose — name the file, the function, the sub-phase.

## Related open issues

GitHub issues whose `Trigger to act` condition would match the next action. The next session must consult these before resuming — any open item whose trigger fires should be addressed as part of the work, not skipped.

Include this section even when no issues currently match. That tells the next session where to look and where to file new follow-up items if any surface during the work.

Example:

- #42 (`tech-debt`) — refactor of `lib/lbkmk/ingest/squarespace.ex` may trigger if the next session adds webhook signature verification.
- No matches against current `enhancement` issues; new findings during ingestion work belong in new issues with the appropriate label.

## Open questions / carry-overs

Anything deferred that doesn't fit the GitHub-issue shape — e.g., decisions pending on owner input, or open architectural questions. Tag each with a status: BLOCKED (waiting on external input), DEFERRED (intentionally pushed to a later phase), or NEXT (the next session should tackle this).

## References

- Plan doc: `docs/plans/...`
- Memory: `[[memory-slug]]` entries that informed this work
- PR: link
- Prior handoffs: link if this continues a thread
```

## What NOT to put here

- Secrets, credentials, or production keys. Treat every file in this directory as world-readable (`docs/` is in the public repo).
- Long verbatim tool output, test logs, or diffs — link to the PR or to the commit SHA instead.
- Memory-system entries duplicated. If it belongs in memory, write it there and link from the handoff.
- Speculation about future work that hasn't been agreed. Future-work belongs in plan docs.

## Maintenance

Handoffs are append-only artifacts. Don't rewrite past handoffs to reflect later understanding — they are a record of what was known at the time. If a later session discovers a past handoff is wrong or misleading, write a new handoff that corrects it and links back.

Stale handoffs (older than ~6 months and entirely superseded) may be moved to `docs/handoff/archive/` if the directory grows unwieldy. Don't delete them.
