# Session Handoff Documents

This directory holds **session-end handoff documents** — short notes that let the next session (human or AI) pick up where the previous one left off without re-deriving the state from scratch.

## Gitignored by design

A handoff is a **bridge between sessions, not a committed artifact.** Everything in this directory is gitignored **except this README** (the convention itself, committed so it travels with the repo). `.gitignore` carries `docs/.handoff/*` with a `!docs/.handoff/README.md` negation.

Write handoffs to the **primary checkout's** `docs/.handoff/` — the main working copy at the repo root, not a feature worktree — so:

- every session reads the same location regardless of which worktree it ran in, and
- the doc survives a feature worktree's deletion after merge.

Do **not** `git add` a handoff, and never `git add -f` to force one in — that is a protocol violation (see the `external-agent-protocol` skill's `rules/operating-constraints.md`, the no-`git add`-of-gitignored rule).

This is distinct from `docs/.context/{feature}/` (the multi-agent pipeline's transient per-feature process artifacts), which is also gitignored but scoped to a single feature worktree.

## When to write one

Write a handoff before wrapping a session if any of these apply:

- A PR has merged and the worktree is about to be deleted.
- Work is mid-flight and you want the next session to resume from a known state.
- Decisions were made in conversation that aren't captured in the plan doc, the PR description, or memory.
- You discovered something non-obvious (a library gotcha, a config trap, an external-API quirk) future sessions would benefit from.

Do **not** write a handoff for:

- Trivial fixes or one-line edits — the commit message is enough.
- Work fully captured in the PR description and plan doc — don't duplicate; link.
- Lessons that belong in `CLAUDE.md` (project-wide conventions) or the memory system (user preferences, recurring traps). Those have better homes.

## Where it fits with other systems

| Mechanism | Lifetime | Committed? | Scope |
|---|---|---|---|
| **`docs/.handoff/`** (this dir) | Until superseded | No (README only) | Session-to-session continuity; primary checkout. |
| `docs/.context/{feature}/` | Until worktree deletion | No | Per-feature multi-agent pipeline artifacts. |
| `docs/plans/...` | Permanent | Yes | Forward-looking plans before work begins. |
| PR description | Permanent on GitHub | n/a | Summary of what shipped. |
| GitHub issues | Permanent on GitHub | n/a | Deferred work, open questions, tech debt. |
| `CLAUDE.md` | Permanent | Yes | Project-wide conventions and stack rules. |
| Memory system | Permanent, cross-session | n/a | User preferences, recurring traps. |

Rough order of preference when something is worth recording:

1. Project-wide rule → `CLAUDE.md`.
2. Future-session preference or trap → memory.
3. Open question blocking future work → `docs/domain-model.md` §§7-8.
4. Deferred work → GitHub issue.
5. Belongs in the PR → PR description.
6. Otherwise, session-continuity information → here.

## Cross-machine

Because handoffs are gitignored, they do **not** travel via git or `main`. To move a handoff to another machine, use the `dotfiles-sync` skill — it is not synced automatically.

## Filename convention

```
YYYY-MM-DD-<branch-or-topic-slug>.md
```

The date prefix sorts chronologically. The slug is the branch name minus the leading `feat-` / `fix-` / `chore-` / `docs-` prefix, or a short topic when not branch-tied.

## Document structure

Use this skeleton. Trim sections that don't apply.

```markdown
# <Title>

**Date:** YYYY-MM-DD
**Branch:** <branch-name> (or n/a)
**PR:** #<number> (link), <status: open | merged | abandoned | in-flight>
**Base commit:** <short SHA of main when work started>
**Author:** <name>

## On resume — do this first
Orient (git worktree list; git branch --show-current; git status; git log),
then sync onto latest main (fetch + rebase; force-with-lease if the branch
has an open PR), then continue with the next sequence.

## What shipped
Bullet list of actual changes. Reference file:line where it helps.
Final test/build state belongs here — cite the exact commands run.

## Deferred items / known issues
Inline, with file:line and a fix recommendation each.
Do NOT link to gitignored docs the next agent can't read — inline instead.

## Recommended next sequence
Concrete commit-level plan for follow-up work. Name the file, function, or task.

## Worktree + branch state
Where the next session should start (path, branch, base commit).

## Reviews that ran
Verdict from each (build-validator, integration-reviewer, code-reviewer, etc.).

## Carry-overs / References
- Plan doc / PR links / memory slugs / prior handoffs that continue a thread.

## Next-phase pointer
What comes after this work unit completes.
```

## What NOT to put here

- Secrets, credentials, or production keys. Even though this dir is gitignored, treat it as potentially synced (via `dotfiles-sync`).
- Long verbatim tool output, test logs, or diffs — link to the PR or commit SHA instead.
- Memory-system entries duplicated. If it belongs in memory, write it there and link from the handoff.
- Speculation about future work that hasn't been agreed. Future work belongs in plan docs.

## Maintenance

Handoffs are append-only records of what was known at the time — don't rewrite an earlier one to reflect later understanding; write a new one that supersedes it and links back. Since they are gitignored and local, prune superseded handoffs freely.
