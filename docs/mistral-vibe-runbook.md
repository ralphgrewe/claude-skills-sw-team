# Mistral Vibe runbook (Phase 1 — manual validation)

This is the manual cycle for [#2 — Integrate Mistral Vibe CLI as
Implementer](https://github.com/ralphgrewe/claude-skills-sw-team/issues/2).
At this stage nothing is wired into `sw-team-manager` or
`sw-team-product-manager` — an operator runs `scripts/mistral-implement.sh`
by hand against a hand-picked issue and records what happened. The goal is
to gather enough evidence to decide go/no-go on Phase 2.

## Prerequisites

- [Vibe CLI](https://github.com/mistralai/mistral-vibe) installed and on
  `PATH` (`vibe`).
- `MISTRAL_API_KEY` set in the environment — already configured in this
  environment, no setup needed.
- [`gh`](https://cli.github.com/) installed and authenticated against this
  repo (used only to *read* the issue; the script never writes to GitHub).
- A clean working tree in the target repo, so any commit Vibe makes is easy
  to inspect and, if needed, revert.

## Picking a suitable issue

Pick issues the same way `sw-team-product-manager` would recommend `haiku`
for: small, self-contained, fully-specified, touching one file or a small
cluster of files, with no cross-file design decisions. Good candidates for
this validation round:

- Single-file scripts or docs with an explicit spec (similar in shape to
  #3 itself).
- Small, mechanical changes with clear acceptance criteria.

Avoid issues that require exploring unfamiliar parts of the codebase,
making architectural calls, or touching multiple modules — those aren't a
fair test of Vibe's baseline capability and burn budget on a run that's
likely to fail for reasons unrelated to Vibe itself.

## Running the script

```bash
scripts/mistral-implement.sh <issue-number> [repo-path]
```

- `repo-path` defaults to the current directory.
- The script fetches the issue's title and body via `gh`, builds a prompt
  modeled on `sw-team-manager`'s dispatch template, and runs
  `vibe --prompt "..." --auto-approve` with the guardrails defined at the
  top of the script (`MAX_TURNS`, `MAX_PRICE`). Adjust those two variables
  there if a run needs more headroom — don't pass ad hoc flags around them.
- The script makes **no GitHub writes**: no comments, no labels, no closes,
  no pushes. Everything after the run — reviewing the diff, deciding
  success/failure, updating the issue — is manual.

## After each run

1. Inspect the commit the script reports (`git show <sha>`, `git diff
   <sha>~1 <sha>`) in the target repo. Check that it actually implements
   the issue, that tests were added/updated, and that they pass.
2. If the script reports "no commit," read Vibe's raw output for its
   stated reason (usually an open question it couldn't resolve, or it ran
   out of turns/budget).
3. Comment on [#2](https://github.com/ralphgrewe/claude-skills-sw-team/issues/2)
   recording:
   - Which issue was attempted, and the commit SHA (or "no commit").
   - Success or failure, and why.
   - Diff quality — would you have accepted this from a haiku sub-agent?
     Any design smells a `sonnet` design review would have flagged?
   - Cost and turns used (from Vibe's reported output).
   - Any prompt adjustments the script's template needs based on this run.
4. If the commit looks good, it's still safe to leave it local and unpushed
   — this is a validation run, not a real implementation dispatch. Discard
   or push it at your discretion; either way, record the outcome on #2
   before moving to the next candidate issue.

Repeat for 2–3 issues before deciding.

## Go/no-go gate

After the validation runs are recorded on #2, make an explicit go/no-go
call and post it as a comment on #2, covering:

- **Go or no-go** on proceeding to Phase 2 (#4).
- **Skill-layout decision**: extend `sw-team-manager` to dispatch `Model:
  mistral` issues via Vibe, or introduce a separate `sw-mistral-implementer`
  skill. The default hypothesis is extending `sw-team-manager` — only
  deviate if the validation runs surfaced a concrete reason Vibe needs
  different orchestration (e.g. materially different prompting,
  verification, or escalation handling than the Claude sub-agent flow).

Phase 2 (#4) is blocked on this gate; do not start it before the go/no-go
comment is on #2.
