#!/usr/bin/env python3
"""Aggregate haiku-first model-routing evidence across GitHub issues.

Scans closed issues (via the `gh` CLI) for the "Claude-Model-Escalation",
"Ralph-Haiku-Downgraded", "Claude-Haiku-Solved", "Claude-Sonnet-Solved", and
"Claude-Opus-Solved" labels and prints a plain-text statistics report on how
often haiku-first dispatch actually held up. See CLAUDE.md's "GitHub labels as
state/evidence tracking" section for what each label means, and issue #6 for
the full spec this script implements.

Usage: escalation-stats.py [--repo OWNER/REPO ...]
  No --repo: scans every repo under the authenticated gh account.
  --repo (repeatable): restrict the scan to the named repos instead.

Read-only: makes no GitHub writes, relies on the operator's existing
`gh auth login` session.
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys

ESCALATION_LABEL = "Claude-Model-Escalation"
DOWNGRADE_LABEL = "Ralph-Haiku-Downgraded"
HAIKU_SOLVED_LABEL = "Claude-Haiku-Solved"
SONNET_SOLVED_LABEL = "Claude-Sonnet-Solved"
OPUS_SOLVED_LABEL = "Claude-Opus-Solved"

ISSUES_PER_REPO_LIMIT = 1000
PER_PAGE = 100

# Escalation comments vary in wording but always name two tiers joined by an
# arrow, e.g. "Model escalation: haiku → sonnet." or "Escalating sonnet -> opus."
TIER_RE = re.compile(
    r"\b(haiku|sonnet|opus)\b\s*(?:→|->|-+>)\s*\b(haiku|sonnet|opus)\b",
    re.IGNORECASE,
)


def die(msg: str) -> None:
    print(f"Error: {msg}", file=sys.stderr)
    sys.exit(1)


def check_gh_available_and_authed() -> None:
    if shutil.which("gh") is None:
        die("required command 'gh' not found on PATH. Install: https://cli.github.com/")
    proc = subprocess.run(["gh", "auth", "status"], capture_output=True, text=True)
    if proc.returncode != 0:
        die("'gh' is not authenticated. Run 'gh auth login' first.\n" + proc.stderr.strip())


def gh_json(args: list[str]):
    """Run a `gh` command, parse stdout as JSON. Returns (data, None) or (None, error)."""
    proc = subprocess.run(["gh"] + args, capture_output=True, text=True)
    if proc.returncode != 0:
        return None, (proc.stderr.strip() or f"gh exited {proc.returncode}")
    try:
        return json.loads(proc.stdout), None
    except json.JSONDecodeError as e:
        return None, f"could not parse gh output as JSON: {e}"


def list_scope_repos() -> list[str]:
    data, err = gh_json(["repo", "list", "--json", "nameWithOwner", "--limit", "1000"])
    if data is None:
        die(f"could not list repositories for the authenticated account: {err}")
    return [r["nameWithOwner"] for r in data]


def fetch_closed_issues(repo: str):
    """Return (issues, truncated, error) for a repo's closed issues (PRs excluded upstream by caller)."""
    max_pages = max(1, ISSUES_PER_REPO_LIMIT // PER_PAGE)
    issues: list[dict] = []
    for page in range(1, max_pages + 1):
        data, err = gh_json(
            ["api", f"repos/{repo}/issues?state=closed&per_page={PER_PAGE}&page={page}"]
        )
        if data is None:
            return None, False, err
        issues.extend(data)
        if len(data) < PER_PAGE:
            return issues, False, None
    return issues, True, None


def fetch_comments_text(repo: str, number: int):
    data, err = gh_json(["api", f"repos/{repo}/issues/{number}/comments?per_page=100"])
    if data is None:
        return None, err
    return "\n".join(c.get("body") or "" for c in data), None


def validate_repo_arg(value: str) -> str:
    parts = value.split("/")
    if len(parts) != 2 or not all(parts):
        die(f"--repo must be in OWNER/REPO form, got '{value}'")
    return value


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Print aggregate haiku-first model-routing escalation statistics across GitHub issues."
    )
    parser.add_argument(
        "--repo",
        action="append",
        dest="repos",
        metavar="OWNER/REPO",
        help="Restrict the scan to this repo (repeatable). Default: every repo under the authenticated gh account.",
    )
    args = parser.parse_args()

    if args.repos:
        for r in args.repos:
            validate_repo_arg(r)

    check_gh_available_and_authed()

    repos = args.repos if args.repos else list_scope_repos()

    scanned: list[tuple[str, bool]] = []
    skipped: list[tuple[str, str]] = []
    implemented_total = 0
    haiku_to_sonnet = 0
    sonnet_to_opus = 0
    downgraded = 0
    downgraded_then_escalated = 0
    haiku_solved = 0
    sonnet_solved = 0
    opus_solved = 0
    unparseable: list[str] = []

    for repo in repos:
        issues, truncated, err = fetch_closed_issues(repo)
        if issues is None:
            skipped.append((repo, err or "unknown error"))
            continue
        scanned.append((repo, truncated))

        for issue in issues:
            if issue.get("pull_request") is not None:
                continue  # the issues endpoint also returns PRs
            if issue.get("state_reason") != "completed":
                continue
            sub_total = (issue.get("sub_issues_summary") or {}).get("total", 0)
            if sub_total:
                continue  # parent/tracking issue, not a leaf

            implemented_total += 1
            number = issue["number"]
            labels = {lbl["name"] for lbl in issue.get("labels", [])}
            has_escalation = ESCALATION_LABEL in labels
            has_downgrade = DOWNGRADE_LABEL in labels

            if has_downgrade:
                downgraded += 1
            if has_downgrade and has_escalation:
                downgraded_then_escalated += 1

            if HAIKU_SOLVED_LABEL in labels:
                haiku_solved += 1
            if SONNET_SOLVED_LABEL in labels:
                sonnet_solved += 1
            if OPUS_SOLVED_LABEL in labels:
                opus_solved += 1

            if has_escalation:
                text, cerr = fetch_comments_text(repo, number)
                if text is None:
                    unparseable.append(f"{repo}#{number} (could not fetch comments: {cerr})")
                    continue
                pairs = {(a.lower(), b.lower()) for a, b in TIER_RE.findall(text)}
                matched_any = False
                if ("haiku", "sonnet") in pairs:
                    haiku_to_sonnet += 1
                    matched_any = True
                if ("sonnet", "opus") in pairs:
                    sonnet_to_opus += 1
                    matched_any = True
                if not matched_any:
                    unparseable.append(f"{repo}#{number}")

    def pct(n: int) -> float:
        return (n / implemented_total * 100) if implemented_total else 0.0

    print("Escalation statistics (haiku-first model-routing evidence)")
    print("=" * 60)
    scope_desc = f"{len(scanned)} repo(s) scanned"
    if skipped:
        scope_desc += f", {len(skipped)} skipped"
    print(scope_desc)
    for repo, truncated in scanned:
        if truncated:
            print(f"  note: {repo} hit the {ISSUES_PER_REPO_LIMIT}-issue fetch limit; results may be incomplete")
    for repo, reason in skipped:
        print(f"  skipped: {repo} ({reason})")
    print()
    print(f"Implemented issues (closed, completed, leaf): {implemented_total}")
    print()
    print("Escalation buckets (% of implemented total; not mutually exclusive):")
    print(f"  haiku -> sonnet:                 {haiku_to_sonnet} ({pct(haiku_to_sonnet):.1f}%)")
    print(f"  sonnet -> opus:                  {sonnet_to_opus} ({pct(sonnet_to_opus):.1f}%)")
    print()
    print("Tier-solved buckets (% of implemented total; not mutually exclusive with escalation buckets):")
    print(f"  haiku solved:                    {haiku_solved} ({pct(haiku_solved):.1f}%)")
    print(f"  sonnet solved:                   {sonnet_solved} ({pct(sonnet_solved):.1f}%)")
    print(f"  opus solved:                     {opus_solved} ({pct(opus_solved):.1f}%)")
    print()
    print("Manual downgrade bucket:")
    print(f"  {DOWNGRADE_LABEL}:      {downgraded} ({pct(downgraded):.1f}%)")
    print()
    print("Downgraded-then-escalated bucket:")
    print(f"  both labels present:             {downgraded_then_escalated} ({pct(downgraded_then_escalated):.1f}%)")
    if unparseable:
        print()
        print(f"Notes: {len(unparseable)} issue(s) carried {ESCALATION_LABEL} but no tier-pair could be parsed:")
        for note in unparseable:
            print(f"  - {note}")


if __name__ == "__main__":
    main()
