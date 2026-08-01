#!/usr/bin/env python3
"""Report the state of a `gh stack` stack as JSON, and optionally gate on it.

`gh stack view --json` is the only machine-readable view the extension offers, and it
leaves an agent unable to answer several questions it must answer before acting:

  * Parentage. `base` is a commit SHA, not a branch name. The parent is recoverable
    only from array order, which is the opposite of the order `--short` prints.
  * Identity. Sitting on trunk is a valid state in which no branch reports
    `isCurrent`, and it is indistinguishable from being off-stack without checking
    `trunk` explicitly. Detached HEAD and off-stack both exit 2 with different text.
  * Visibility. Stack state lives in a file named `gh-stack` inside the git dir. In a
    linked worktree that resolves to `.git/worktrees/<name>/`, so a stack created in
    the main checkout is invisible and `view --json` exits 2 claiming the branch is
    not part of a stack. `git rev-parse --git-path gh-stack` does NOT correct for
    this: git redirects only a fixed allowlist of filenames to the common dir, and
    `gh-stack` is not on it. This script uses `--git-common-dir` explicitly.
  * Safety. Nothing in `gh stack` refuses a dirty working tree, and uncommitted
    changes follow you across navigation.

This script answers all of that in one JSON blob, and with --strict turns the report
into a gate. It never writes: not to the stack state, not to the lock, not to the
index. Reporting only.

Exit codes:
    0    report produced (blockers may be present unless --strict)
    1    script or environment failure; JSON with "ok": false still on stdout
    2    --strict and at least one blocker applies to the requested operation
    130  interrupted
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

SCHEMA = 1

# The extension version this script was written and tested against. A mismatch is a
# warning, not a failure: gh-stack is pre-1.0 and its JSON shape has already changed
# once between releases.
TESTED_AGAINST = "0.1.0"

# Operations a caller can gate on. A blocker lists the operations it blocks; a
# blocker with an empty set is advisory everywhere (a warning).
OPS = ("commit", "add", "rebase", "sync", "submit", "navigate")
ALL_OPS = frozenset(OPS)
MUTATING = frozenset({"rebase", "sync", "submit"})


@dataclass
class Finding:
    """A blocker or warning. `blocks` is the set of operations it is fatal for."""

    code: str
    message: str
    fix: str = ""
    blocks: frozenset[str] = field(default_factory=frozenset)

    def as_dict(self, op: str | None) -> dict:
        applies = bool(self.blocks) if op is None else op in self.blocks
        return {
            "code": self.code,
            "severity": "block" if applies else "warn",
            "message": self.message,
            "fix": self.fix,
        }


class Fatal(Exception):
    """Environment problem that makes any report impossible."""


def run(
    args: list[str], cwd: Path, check: bool = False
) -> subprocess.CompletedProcess[str]:
    """Run a command, capturing stdout and stderr separately.

    Never merge the streams: `gh stack` writes data to stdout and all human-readable
    status to stderr, so `2>&1` corrupts the JSON.
    """
    proc = subprocess.run(
        args, cwd=cwd, capture_output=True, text=True, check=False
    )
    if check and proc.returncode != 0:
        raise Fatal(f"{' '.join(args)} failed ({proc.returncode}): {proc.stderr.strip()}")
    return proc


def git(args: list[str], cwd: Path, check: bool = False) -> str:
    return run(["git", *args], cwd, check=check).stdout.strip()


# --------------------------------------------------------------------------- env


def gh_stack_version(cwd: Path) -> str | None:
    """Return the installed extension version, or None if it is not installed.

    `gh stack --version` prints "gh stack version 0.1.0". Note that an unknown
    subcommand exits 0 with the root help, so exit status alone proves nothing here.
    """
    proc = run(["gh", "stack", "--version"], cwd)
    if proc.returncode != 0:
        return None
    parts = proc.stdout.split()
    return parts[-1] if parts else None


@dataclass
class Worktree:
    path: str
    git_dir: str
    common_dir: str
    is_linked: bool
    state_file: str
    state_visible: bool


def inspect_worktree(cwd: Path) -> Worktree:
    git_dir = Path(git(["rev-parse", "--absolute-git-dir"], cwd, check=True))
    common_raw = git(["rev-parse", "--git-common-dir"], cwd, check=True)
    common_dir = Path(common_raw)
    if not common_dir.is_absolute():
        common_dir = (cwd / common_dir).resolve()
    is_linked = git_dir != common_dir
    # gh-stack reads state from its own git dir, so in a linked worktree it looks in
    # the worktree-private path and finds nothing.
    return Worktree(
        path=str(cwd),
        git_dir=str(git_dir),
        common_dir=str(common_dir),
        is_linked=is_linked,
        state_file=str(common_dir / "gh-stack"),
        state_visible=(git_dir / "gh-stack").exists(),
    )


# ------------------------------------------------------------------------- state


def read_view_json(cwd: Path) -> tuple[dict | None, str]:
    """Primary source: `gh stack view --json`. Returns (payload, stderr)."""
    proc = run(["gh", "stack", "view", "--json"], cwd)
    if proc.returncode != 0 or not proc.stdout.strip():
        return None, proc.stderr.strip()
    try:
        payload = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return None, "gh stack view --json returned unparseable output"
    if "branches" not in payload or "trunk" not in payload:
        return None, "gh stack view --json returned an unexpected shape"
    return payload, ""


def read_state_file(wt: Worktree, current: str) -> tuple[dict | None, list[Finding]]:
    """Fallback: parse the on-disk state file from the *common* git dir.

    This is the only way to answer two cases `gh stack` refuses outright: a linked
    worktree whose private git dir has no state, and a trunk shared by two stacks
    (where `view --json` exits 6 and tells you nothing about the candidates).
    """
    findings: list[Finding] = []
    path = Path(wt.state_file)
    if not path.exists():
        return None, findings
    try:
        raw = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        raise Fatal(f"could not read stack state at {path}: {exc}") from exc

    if raw.get("schemaVersion") != SCHEMA:
        findings.append(
            Finding(
                "STATE_SCHEMA_UNKNOWN",
                f"stack state schemaVersion is {raw.get('schemaVersion')!r}, expected {SCHEMA}",
                "Treat the parsed result as advisory; re-check against gh stack view --json.",
            )
        )

    stacks = raw.get("stacks") or []
    owning = [
        s
        for s in stacks
        if current in {b.get("branch") for b in s.get("branches", [])}
    ]
    if not owning:
        rooted = [s for s in stacks if (s.get("trunk") or {}).get("branch") == current]
        if len(rooted) > 1:
            names = [
                [b.get("branch") for b in s.get("branches", [])] for s in rooted
            ]
            findings.append(
                Finding(
                    "AMBIGUOUS_TRUNK",
                    f"{current!r} is the trunk of {len(rooted)} stacks: {names}",
                    "Check out a non-trunk branch to disambiguate.",
                    ALL_OPS,
                )
            )
        return None, findings

    stack = owning[0]
    trunk = (stack.get("trunk") or {}).get("branch", "")
    branches = [
        {
            "name": b.get("branch", ""),
            "base": b.get("base", ""),
            "isCurrent": b.get("branch") == current,
            "isMerged": False,
            "isQueued": None,
            "needsRebase": None,
        }
        for b in stack.get("branches", [])
    ]
    return {"trunk": trunk, "currentBranch": current, "branches": branches}, findings


# ---------------------------------------------------------------------- assembly


def enrich(branches: list[dict], trunk: str, cwd: Path) -> list[dict]:
    """Resolve what `gh stack view --json` leaves out.

    Parentage comes from array order (index 0's parent is trunk), because `base` is a
    commit SHA. `head` is omitempty and is simply absent for a branch with no commits
    of its own, so always resolve it with git rather than trusting the key.
    """
    out: list[dict] = []
    for i, b in enumerate(branches):
        name = b.get("name", "")
        parent = trunk if i == 0 else branches[i - 1].get("name", "")
        head = git(["rev-parse", "--verify", "--quiet", name], cwd) or None
        ahead = behind = None
        if head and parent:
            counts = git(
                ["rev-list", "--left-right", "--count", f"{parent}...{name}"], cwd
            )
            if counts:
                try:
                    behind_s, ahead_s = counts.split()
                    behind, ahead = int(behind_s), int(ahead_s)
                except ValueError:
                    pass

        needs_rebase = b.get("needsRebase")
        if needs_rebase is None and head and parent:
            # Transcribed from `gh stack rebase --help`: each branch must have the tip
            # of the layer below it in its history. Note gh only sets needsRebase on
            # the immediate child, never transitively.
            parent_tip = git(["rev-parse", "--verify", "--quiet", parent], cwd)
            if parent_tip:
                rc = run(
                    ["git", "merge-base", "--is-ancestor", parent_tip, head], cwd
                ).returncode
                needs_rebase = rc != 0

        out.append(
            {
                "name": name,
                "position": i + 1,
                "parent": parent,
                "head": head,
                "base": b.get("base"),
                "is_current": bool(b.get("isCurrent")),
                "is_merged": bool(b.get("isMerged")),
                "is_queued": b.get("isQueued"),
                "needs_rebase": needs_rebase,
                "ahead_of_parent": ahead,
                "behind_parent": behind,
                "pr": b.get("pr"),
            }
        )
    return out


def overlay_prs(branches: list[dict], cwd: Path, repo: str | None) -> list[Finding]:
    """Attach live PR state. `view --json`'s own `pr` object is omitempty and its
    isMerged/isQueued flags are only as fresh as the last sync."""
    findings: list[Finding] = []
    args = [
        "gh", "pr", "list", "--state", "all", "--limit", "100", "--json",
        "number,headRefName,baseRefName,state,isDraft,mergeable,mergeStateStatus,reviewDecision,url",
    ]
    if repo:
        args += ["--repo", repo]
    proc = run(args, cwd)
    if proc.returncode != 0:
        findings.append(
            Finding(
                "PR_LOOKUP_FAILED",
                f"could not list pull requests: {proc.stderr.strip()[:200]}",
                "Re-run with --no-prs for offline topology only.",
            )
        )
        return findings

    try:
        prs = json.loads(proc.stdout or "[]")
    except json.JSONDecodeError:
        findings.append(Finding("PR_LOOKUP_FAILED", "gh pr list returned unparseable JSON"))
        return findings

    by_head: dict[str, dict] = {}
    for pr in prs:
        by_head.setdefault(pr["headRefName"], pr)

    for b in branches:
        pr = by_head.get(b["name"])
        if not pr:
            continue
        b["pr"] = {
            "number": pr["number"],
            "state": pr["state"],
            "is_draft": pr["isDraft"],
            "base_ref": pr["baseRefName"],
            "mergeable": pr.get("mergeable"),
            "merge_state_status": pr.get("mergeStateStatus"),
            "review_decision": pr.get("reviewDecision") or None,
            "url": pr["url"],
        }
        b["pr_base_matches_parent"] = pr["baseRefName"] == b["parent"]
        if pr["state"] == "OPEN" and not b["pr_base_matches_parent"]:
            findings.append(
                Finding(
                    "PR_BASE_DRIFT",
                    f"PR #{pr['number']} ({b['name']}) is based on {pr['baseRefName']!r}, "
                    f"but the local stack says its parent is {b['parent']!r}",
                    "Run `gh stack submit` to reconcile PR bases, after reviewing the plan.",
                    frozenset({"submit"}),
                )
            )
    return findings


def collect_findings(report: dict, wt: Worktree, cwd: Path) -> list[Finding]:
    findings: list[Finding] = []
    branches = report["branches"]

    if report["dirty"]:
        findings.append(
            Finding(
                "DIRTY_WORKTREE",
                f"{report['modified_files']} modified, {report['untracked_files']} untracked",
                "Commit or stash first. Nothing in gh stack refuses a dirty tree, and "
                "uncommitted changes follow you across navigation.",
                MUTATING | {"navigate"},
            )
        )

    if report["on_trunk"]:
        findings.append(
            Finding(
                "ON_TRUNK",
                f"checked out on trunk ({report['trunk']!r}), not a stack branch",
                "gh stack checkout <branch>, or gh stack top.",
                frozenset({"commit", "add"}),
            )
        )

    top = branches[-1]["name"] if branches else None
    if top and report["current_branch"] != top and not report["on_trunk"]:
        findings.append(
            Finding(
                "NOT_AT_TOP",
                f"on {report['current_branch']!r}; gh stack add only works from the top ({top!r})",
                "gh stack top",
                frozenset({"add"}),
            )
        )

    if any(b["needs_rebase"] for b in branches):
        stale = [b["name"] for b in branches if b["needs_rebase"]]
        findings.append(
            Finding(
                "NEEDS_REBASE",
                f"branches not on top of their parent: {stale}",
                "gh stack rebase --upstack",
                frozenset({"submit"}),
            )
        )

    if any(b["is_merged"] for b in branches):
        findings.append(
            Finding(
                "MERGED_BRANCH_PRESENT",
                "the stack still contains merged branches; navigation silently skips them, "
                "so step counting drifts",
                "gh stack sync --prune (writes to the remote; get approval first).",
            )
        )

    if wt.is_linked and not wt.state_visible:
        findings.append(
            Finding(
                "WORKTREE_STATE_INVISIBLE",
                "this is a linked worktree and gh stack's state is not visible from it",
                f'ln -s "{wt.state_file}" "{wt.git_dir}/gh-stack"   '
                "(restores visibility only; branches held by another worktree still "
                "cannot be checked out. Never use GIT_DIR= to work around this: it "
                "reports the primary checkout's branch.)",
                ALL_OPS,
            )
        )

    return findings


# ------------------------------------------------------------------------- main


def build(cwd: Path, want_prs: bool, repo: str | None) -> tuple[dict, list[Finding]]:
    findings: list[Finding] = []

    if git(["rev-parse", "--is-inside-work-tree"], cwd) != "true":
        raise Fatal(f"{cwd} is not inside a git working tree")

    version = gh_stack_version(cwd)
    if version is None:
        raise Fatal(
            "the gh-stack extension is not installed "
            "(install it with: gh extension install github/gh-stack)"
        )
    if version != TESTED_AGAINST:
        findings.append(
            Finding(
                "GH_STACK_VERSION_UNTESTED",
                f"gh stack {version} is installed; this script was verified against {TESTED_AGAINST}",
                "Re-check `gh stack view --json` output shape if anything looks wrong.",
            )
        )

    wt = inspect_worktree(cwd)
    current = git(["symbolic-ref", "--quiet", "--short", "HEAD"], cwd)
    if not current:
        raise Fatal("HEAD is detached; check out a branch first")

    payload, view_err = read_view_json(cwd)
    source = "gh-stack-view"
    if payload is None:
        payload, extra = read_state_file(wt, current)
        findings.extend(extra)
        source = "git-state-file"
        if payload is None:
            raise Fatal(view_err or f"{current!r} is not part of any tracked stack")

    trunk = payload["trunk"]
    branches = enrich(payload["branches"], trunk, cwd)

    porcelain = [
        line for line in git(["status", "--porcelain"], cwd).splitlines() if line
    ]
    untracked = sum(1 for line in porcelain if line.startswith("??"))

    current_entry = next((b for b in branches if b["is_current"]), None)
    report = {
        "ok": True,
        "schema": SCHEMA,
        "source": source,
        "gh_stack_version": version,
        "trunk": trunk,
        "current_branch": current,
        "on_trunk": current == trunk,
        "position": current_entry["position"] if current_entry else 0,
        "worktree": {
            "path": wt.path,
            "is_linked": wt.is_linked,
            "state_visible": wt.state_visible,
            "state_file": wt.state_file,
        },
        "dirty": bool(porcelain),
        "modified_files": len(porcelain) - untracked,
        "untracked_files": untracked,
        "branches": branches,
    }

    if want_prs:
        findings.extend(overlay_prs(branches, cwd, repo))

    findings.extend(collect_findings(report, wt, cwd))
    return report, findings


def render_text(report: dict, findings: list[Finding], op: str | None) -> str:
    lines = [
        f"stack on {report['trunk']} "
        f"(gh stack {report['gh_stack_version']}, source: {report['source']})"
    ]
    for b in reversed(report["branches"]):
        marker = "*" if b["is_current"] else " "
        bits = []
        if b["pr"]:
            bits.append(f"#{b['pr']['number']} {b['pr']['state'].lower()}")
        if b["needs_rebase"]:
            bits.append("needs-rebase")
        if b["is_merged"]:
            bits.append("merged")
        if b["ahead_of_parent"] is not None:
            bits.append(f"+{b['ahead_of_parent']}")
        suffix = f"  [{', '.join(bits)}]" if bits else ""
        lines.append(f"  {marker} {b['position']}. {b['name']}{suffix}")
    lines.append(f"  {'*' if report['on_trunk'] else ' '} 0. {report['trunk']} (trunk)")

    if report["dirty"]:
        lines.append(
            f"\ndirty: {report['modified_files']} modified, "
            f"{report['untracked_files']} untracked"
        )
    for f in findings:
        d = f.as_dict(op)
        lines.append(f"\n[{d['severity']}] {d['code']}: {d['message']}")
        if d["fix"]:
            lines.append(f"    fix: {d['fix']}")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Report gh stack state as JSON, and optionally gate on it."
    )
    parser.add_argument("--text", action="store_true", help="human-readable rendering")
    parser.add_argument(
        "--no-prs",
        action="store_true",
        help="skip the PR overlay; fully offline, runs inside the sandbox",
    )
    parser.add_argument(
        "--strict", action="store_true", help="exit 2 if any blocker applies"
    )
    parser.add_argument(
        "--for",
        dest="op",
        choices=OPS,
        help="which operation to gate on; selects which findings count as blocking",
    )
    parser.add_argument("--repo", help="OWNER/REPO for the PR overlay")
    parser.add_argument(
        "-C", dest="directory", default=".", help="operate on this repository directory"
    )
    args = parser.parse_args(argv)

    cwd = Path(args.directory).resolve()
    try:
        report, findings = build(cwd, want_prs=not args.no_prs, repo=args.repo)
    except Fatal as exc:
        print(json.dumps({"ok": False, "schema": SCHEMA, "error": str(exc)}, indent=2))
        print(f"error: {exc}", file=sys.stderr)
        return 1

    rendered = [f.as_dict(args.op) for f in findings]
    report["blockers"] = [f for f in rendered if f["severity"] == "block"]
    report["warnings"] = [f for f in rendered if f["severity"] == "warn"]

    if args.text:
        print(render_text(report, findings, args.op))
    else:
        print(json.dumps(report, indent=2))

    if args.strict and report["blockers"]:
        return 2
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
