---
description: Diagnose a gh stack environment -- extension version, worktree state, remotes, rerere, and skill drift
argument-hint: No arguments
allowed-tools: Bash, Read
---

# gh stack doctor

Diagnose the `gh stack` environment before blaming the stack. Every check here corresponds
to a failure mode that produces a misleading error message.

## Instructions

Run these and report the results as a table. All are read-only.

```bash
gh extension list | grep -i gh-stack || echo "gh-stack extension NOT INSTALLED"
gh stack --version
git --version
git rev-parse --git-dir
git rev-parse --git-common-dir
git remote -v
git config --get remote.pushDefault || echo "(unset)"
git config --get rerere.enabled || echo "(unset)"
git config --show-origin --get-all rerere.enabled || echo "(no scope sets rerere.enabled)"
```

Then the stack state, read from the **common** git dir, which every worktree shares. Do
not use `git rev-parse --git-path gh-stack`: git redirects only a fixed allowlist of
filenames to the common dir, `gh-stack` is not on it, and the call returns a
worktree-local path where nothing is.

```bash
COMMON="$(git rev-parse --git-common-dir)"
test -f "$COMMON/gh-stack" && python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(json.dumps(d,indent=2))" "$COMMON/gh-stack" || echo "no stack state at $COMMON/gh-stack"
test -f "$COMMON/gh-stack-rebase-state" && echo "STACK REBASE IN PROGRESS" || echo "no stack rebase in progress"
```

In a linked worktree only (`--git-dir` differs from `--git-common-dir`), also check for a
private entry. In the main checkout the two dirs are the same, and this finds the real
state file:

```bash
ls -la "$(git rev-parse --git-dir)/gh-stack" 2>/dev/null || echo "no worktree-private gh-stack entry (expected)"
```

Finally the full report:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/gh_stack_status.py" --text --no-prs
```

## What to flag

| Observation | Meaning |
|---|---|
| `--git-dir` differs from `--git-common-dir` | Linked worktree. Normal on v0.2.0 and later: state is shared, so no action is needed. On an older extension, stacks are private to each worktree; recommend `gh extension upgrade stack`. |
| A `gh-stack` entry exists in a linked worktree's own git dir | Leftover from an old workaround, usually a symlink. On v0.2.0 and later it breaks `gh stack` in that worktree. Recommend the user remove it; do not remove it yourself. |
| Git older than 2.36 in a repo with linked worktrees | gh-stack cannot run `rebase`, `sync`, or `modify` across worktrees. Recommend a Git upgrade. |
| `gh-stack-rebase-state` exists | A stack rebase stopped on a conflict, possibly in another worktree. Do not start another rebase. The `Conflict worktree:` line from the failed rebase, or the record's `worktrees.owners`, names where to resolve it. |
| `rerere.enabled` unset or `false` | The check above reads the effective value across all scopes, so `true` from global config needs no action. Otherwise recommend `git config --global rerere.enabled true`. Never set it in `.git/config`. |
| `rerere.enabled` set in `.git/config` and in a global or system file | The repo-local entry shadows the user's real preference. Name both origins and suggest `git config --local --unset rerere.enabled` for the user to run. |
| More than one remote and `remote.pushDefault` unset | `checkout`, `modify`, and `trunk` resolve a remote and have no `--remote` flag. Recommend setting `remote.pushDefault`. |
| Installed extension version differs from 0.3.0 | The skill and script were verified against 0.3.0. Re-check `gh stack --help` before relying on any subcommand. Below 0.2.0, stack state is private to each worktree. |

Also compare versions three ways when anything looks wrong: the installed extension
(`gh stack --version`), the subcommands actually present (`gh stack --help`), and, if
GitHub's official skill is installed, its `metadata.version`. The skill in the v0.3.0
release pins 0.2.0, so it describes an older version than what is installed, and nothing
warns about it.

Report findings and recommended commands. **Do not apply fixes**: anything under `.git/`
and any config change is the user's call.
