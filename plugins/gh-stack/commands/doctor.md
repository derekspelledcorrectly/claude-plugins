---
description: Diagnose a gh stack environment -- extension version, worktree visibility, remotes, rerere, and skill drift
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
git rev-parse --git-dir
git rev-parse --git-common-dir
git remote -v
git config --get remote.pushDefault || echo "(unset)"
git config --get rerere.enabled || echo "(unset)"
```

Then the stack state file, read from the **common** git dir. Do not use
`git rev-parse --git-path gh-stack`: git redirects only a fixed allowlist of filenames to
the common dir, `gh-stack` is not on it, and the call silently returns a worktree-local
path.

```bash
STATE="$(git rev-parse --git-common-dir)/gh-stack"
test -f "$STATE" && python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(json.dumps(d,indent=2))" "$STATE" || echo "no stack state at $STATE"
```

Finally the full report:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/gh_stack_status.py" --text --no-prs
```

## What to flag

| Observation | Meaning |
|---|---|
| `--git-dir` differs from `--git-common-dir` | Linked worktree. Stack state is private to this tree, so a stack created elsewhere is invisible and `gh stack` will claim the branch is not in a stack. |
| No `gh-stack` file in the worktree's own git dir | Confirms the above. Report the `ln -s` fix; do not apply it yourself. |
| `rerere.enabled` unset | `gh stack init` prompts for this interactively but silently skips it when run non-interactively, so agent-created stacks lack it. Recommend `git config rerere.enabled true`. |
| More than one remote and `remote.pushDefault` unset | `checkout`, `modify`, and `trunk` resolve a remote and have no `--remote` flag. Recommend setting `remote.pushDefault`. |
| Installed extension version differs from 0.1.0 | The skill and script were verified against 0.1.0. Re-check `gh stack --help` before relying on any subcommand. |

Also compare versions three ways when anything looks wrong: the installed extension
(`gh stack --version`), the subcommands actually present (`gh stack --help`), and, if
GitHub's official skill is installed, its `metadata.version`. That skill currently pins
0.0.9 while the extension is 0.1.0, so it describes an older version than what is
installed, and nothing warns about it.

Report findings and recommended commands. **Do not apply fixes**: the symlink writes into
`.git/`, and config changes are the user's call.
