# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A set of Claude Code **skills** that make Claude operate as an agile software team against GitHub issues. There is no application code, build system, or package manifest — the "product" is the `SKILL.md` prompt/procedure files themselves plus a small amount of shell tooling.

## Commands

- Test the Mistral Vibe dispatch script's guardrails (arg validation, missing-command checks, missing `MISTRAL_API_KEY`, bad repo path — no network calls, no GitHub auth, no Vibe spend):
  ```bash
  scripts/test-mistral-implement.sh
  ```
- There is no other lint/build/test step in this repo.

## Architecture

### The two core skills, and the flow between them

- **`sw-team-product-manager/SKILL.md`** — refines a raw GitHub issue: clarifies scope with the user (never guesses at ambiguity), and either leaves it as one refined issue or breaks it into small, independently-valuable sub-issues (`Blocked by #N` for explicit dependencies). Every issue it writes gets two mandatory sections appended to the body:
  - `## Entry points` — starting files/docs for the implementer, ending with a fixed disclaimer line that it's a hint, not a spec.
  - `## Model recommendation` — `Model: haiku|sonnet` plus a one-line reasoning. Haiku is the default; sonnet is only recommended when a *specific* difficulty is named (e.g., several files need designing together, or the root cause is genuinely still unknown). Opus is never recommended here — it's reached only via escalation.
- **`sw-team-manager/SKILL.md`** — the orchestrator. Never writes code itself. Resolves an issue (or parent + sub-issues) into a concrete work list, decides parallel vs. sequential (same files/module → sequential; explicit dependency → sequential in order; otherwise parallel via multiple `Agent` calls in one message), then dispatches one `general-purpose` sub-agent per issue using the `model` from the issue's `## Model recommendation` (defaults to `haiku` if absent).

Typical flow: `sw-team-product-manager` refines/splits an issue → `sw-team-manager` dispatches and verifies implementation.

### Verification and escalation (mandatory, not optional)

Because haiku is the default implementer, `sw-team-manager` never trusts a sub-agent's self-report. After each dispatch it:
1. Checks `git log -1` / `git diff <commit>~1` for the real change, confirms tests actually ran, and confirms the GitHub comment/close state matches what was reported (SHA, `Closes #{N}` in the commit message, comment structure).
2. Runs a **mandatory design review**: a separate `sonnet` sub-agent inspects the diff against the issue body for design/architecture problems only (not style) and ends with `DESIGN: OK` or `DESIGN: FLAWED` + findings. This exists specifically to catch quiet design debt that passes tests — the risk profile of a haiku-first default.
3. On any verification failure (bad diff, tests failed/skipped, mismatched issue state, `DESIGN: FLAWED`, or thrashing) — re-dispatches the **same issue one tier up** (haiku → sonnet → opus), never retries same-tier, never silently moves on. Failing at opus stops and surfaces to the user; this is a hard floor, not a suggestion.

Escalations and haiku successes are both recorded as labels (see below) because they're the evidence base for tuning the haiku/sonnet recommendation criteria over time — don't "fix" the bias back toward sonnet without that evidence.

### GitHub labels as state/evidence tracking

- `Claude` / `Claude-Edited` — an issue was created/edited by these skills.
- `Claude-Haiku-Solved` — design review passed at haiku tier (positive evidence for the haiku-first bias).
- `Claude-Model-Escalation` — verification failed and the issue was bumped a tier; the escalation comment records the from→to model and the one-line rejection reason. Query this label to see the accumulated evidence for what haiku actually fails at.

### Issue ↔ code traceability

No ticket annotations in source (they bloat and go stale). The link is one-directional-durable, via commit messages: every implementation commit ends with `Closes #N` (plus `Refs #M` for touched-but-not-resolved issues). This text survives history rewrites (rebase/squash) whereas a SHA pasted into an issue comment does not — treat the commit message as the source of truth. See `README.md` for the `git log`/`git show` recipes to derive issue↔file history on demand.

### Mistral Vibe integration (in-progress, phased)

Tracked under issue #2. Phase 1 is manual-only and lives in `scripts/mistral-implement.sh` + `docs/mistral-vibe-runbook.md`: an operator hand-picks a haiku-shaped issue, runs the script, and manually records success/failure/diff-quality/cost as a comment on #2. The script makes **no GitHub writes** (no comments, labels, closes, pushes) — everything after the Vibe run is manual review. Its cost/turn guardrails (`MAX_TURNS`, `MAX_PRICE`) live as variables at the top of the script, not as ad hoc flags. Phase 2 (wiring Vibe into `sw-team-manager` as a `Model: mistral` dispatch target, or a separate skill) is gated on an explicit go/no-go comment on #2 — don't start it without that.

### Model routing across the whole system (not just sub-agents)

The skills only control the sub-agent tier. The model running the `sw-team-product-manager` and `sw-team-manager` skills themselves is whatever the invoking session is set to (`/model`) — recommended as sonnet or better for both, since their judgment (refinement, planning, verification) steers everything downstream. See the table in `README.md` for the full cost-tiered rationale.

## Notes on repo layout

- `sw-team-manager/` and `sw-team-product-manager/` at repo root are the tracked source for the two skills.
- `.claude/skills/sw-team-product-manager/SKILL.md` is an **untracked** local copy (currently identical) — likely a local install/testing path. If you edit the product-manager skill, check whether this copy needs updating too, or whether it's stale.
