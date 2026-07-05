# claude-skills-sw-team
Skills to make claude act like an agile SW development team

## Skills

- **sw-team-product-manager** — Refines a GitHub issue and, if needed, breaks it down into small, agile sub-issues ready for implementation. Asks the user to clarify anything ambiguous rather than guessing. Run this first.
- **sw-team-manager** — Implementation orchestrator. Takes a GitHub issue (or a set of sub-issues), plans parallel vs. sequential work, and dispatches sub-agents to implement, test, and close each one.

Typical flow: refine an issue with `sw-team-product-manager`, then hand the resulting issue(s) to `sw-team-manager` for implementation.

## Issue ↔ code traceability

Issues and code are linked through the commit messages, in both directions:

- **Issue → code:** every implementation commit ends with `Closes #N` (plus `Refs #M` for issues it touches without resolving), and the closing comment on the issue states the commit SHA and branch. Once pushed, GitHub also links the commit into the issue's timeline automatically.
- **Code → issues:** derived from git history on demand — no ticket annotations in source files (they bloat and go stale).

Note that a SHA written into an issue comment can go stale if history is rewritten before pushing (rebase, squash-merge); the `Closes #N` text in the commit message survives rewrites and is the durable link. So treat the commit message as the source of truth and the SHA in the comment as a convenience.

Useful queries:

```bash
# Which files did a commit modify?
git show --stat <sha>

# Which commits touched a file (following renames)?
git log --follow --oneline -- path/to/file

# Which issues contributed to a file?
git log --follow --format='%s%n%b' -- path/to/file | grep -oE '#[0-9]+' | sort -u

# All commits for a given issue
git log --oneline --grep='#42'
```

## Recommended models

Cost-tiered routing: run the biggest model where the context exploration and judgment happens, the smallest where the work is well-specified.

| Role | Model | Why |
|---|---|---|
| `sw-team-product-manager` | sonnet or fable/opus | Explores the largest context (issue history, codebase, user intent) and its decisions steer everything downstream — including each issue's model recommendation. |
| `sw-team-manager` | sonnet | Mostly plans, dispatches, and verifies; doesn't write code itself. |
| Implementation sub-agents | haiku or sonnet (per issue) | Chosen automatically from the `## Model recommendation` section the product manager writes into each issue; defaults to sonnet if absent. |

The skills only control the sub-agent tier: the model for the product manager and manager is whatever the session invoking the skill runs on (set via `/model`). If verification of an implementation fails, `sw-team-manager` mandatorily escalates that issue one tier up (haiku → sonnet → opus) before involving you.
