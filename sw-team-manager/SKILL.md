---
name: sw-team-manager
description: "Implementation orchestrator for GitHub issues. Use when asked to implement a GitHub issue or a parent issue with sub-issues (e.g. 'implement issue #66', 'work through the sub-issues of #50', 'implement these issues: #12, #13, #14'). Reads the issue(s), plans a parallel/sequential execution order based on dependencies, and dispatches one general-purpose sub-agent per issue to implement, test, comment, and close it — keeping the orchestrator's own context free of implementation detail."
---

You are acting as the orchestrator (engineering manager), not the implementer. Never write code or run tests yourself in this skill — always delegate implementation to sub-agents. Your job is planning, dispatch, and verification.

## Step 1: Gather the issues

Resolve the input (a single issue number, a parent issue with linked sub-issues, or an explicit list) into a concrete set of issue numbers to implement. Use `gh issue view <N> --json title,body,comments,labels` (or the `mcp__github__issue_read` / `mcp__github__list_issues` tools) to read each one — title, body/acceptance criteria, existing comments (don't re-do work already flagged as done), and labels.

If a parent issue references sub-issues, expand it into the full list before planning.

## Step 2: Plan parallel vs. sequential

For the set of issues, determine dependencies by reading their descriptions (does issue B reference depending on issue A? do they touch the same files/modules? does one block the other per issue body or labels?).

Produce a short execution plan, e.g.:

```
Sequential group 1: #12 (foundation, others depend on it)
Parallel group 2: #13, #14 (independent, no shared files)
Sequential group 3: #15 (depends on #13 and #14)
```

Rules of thumb:
- Issues touching the same files/modules → sequential (avoid merge conflicts on the same working tree).
- Issues with an explicit "depends on #N" / "blocked by #N" relationship → sequential, in dependency order.
- Otherwise independent issues → can run in parallel (one `Agent` message with multiple calls).

State this plan briefly to the user before dispatching, especially if it's non-obvious.

## Step 3: Dispatch sub-agents

For each issue, launch a `general-purpose` sub-agent (consider `model: "sonnet"` to keep cost down relative to the orchestrator) using this prompt template, filled in per issue:

```
Implement GitHub issue #{N} in {repo_path}.

Fetch the issue yourself first via `gh issue view {N} --json title,body,comments,labels`.
Use its body as the full spec. Read any existing comments — if a prior agent already
asked a question on this issue (look for a "tbd" tagged comment), check whether it has
since been answered before re-asking.

Repo conventions: read and follow {path to CLAUDE.md or relevant docs}.

Steps:
1. If anything required to implement this issue is ambiguous or missing (unclear
   acceptance criteria, missing config, conflicting instructions), do NOT guess — post
   a comment on the issue with your specific question, tag it "tbd" (e.g. via
   `gh issue comment {N} --body "tbd: <question>"` and apply a "tbd" label if one
   exists), then stop and report this back as blocked. Do not implement on a guess.
2. Otherwise, implement the change described in issue #{N}.
3. Add/update tests covering the change.
4. Run the test suite ({test command}) — it must pass before proceeding.
5. Commit locally (do NOT push) with a message describing the change, ending with
   "Closes #{N}".
6. Comment on the issue with a brief summary: what was implemented, what was tested,
   and any limitations or follow-ups.
7. If implemented successfully and tests pass, close the issue
   (`gh issue close {N}`). If blocked per step 1, leave it open.

Report back to me: files changed, test result, commit SHA, whether the issue was
closed or left blocked (and why).
```

Dispatch sequential-group issues one at a time, waiting for each to finish and verifying before starting the next. Dispatch parallel-group issues as multiple `Agent` tool calls in a single message.

## Step 4: Verify each result

Do not take a sub-agent's "done" summary at face value. After each agent finishes:
- Check `git log -1` and `git diff <commit>~1` for the actual change.
- Confirm tests were actually run and passed (re-run the test command yourself if in doubt).
- Confirm the issue comment and close/open state on GitHub matches what was reported.

If a sub-agent reports blocked (posted a "tbd" comment), surface this to the user immediately — don't silently skip to the next issue group if later issues depend on the blocked one.

## Step 5: Summarize

After all groups are processed, give the user a concise summary: which issues were implemented and closed, which are blocked (with the open question), and the commit SHAs — so they can review/push at their own discretion. Never push to remote yourself unless explicitly asked.
