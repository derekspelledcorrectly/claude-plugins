---
description: Show the current gh stack -- branches, PR state, and anything blocking the next operation
argument-hint: Optional operation to gate on (e.g., "rebase", "submit", "add")
allowed-tools: Bash, Read
---

# gh stack status

Report the state of the stack in the current repository.

## Instructions

Run the status script. It is read-only and never mutates the repo.

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/gh_stack_status.py" --text
```

If the user named an operation in `$ARGUMENTS` (one of `commit`, `add`, `rebase`, `sync`,
`submit`, `navigate`), gate on it so severities are scored for that operation:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/gh_stack_status.py" --text --for <operation>
```

Add `--no-prs` if the PR overlay fails or the user wants a purely offline answer. The
topology half needs no network.

## Reporting

Summarise for the user:

1. The stack bottom to top, marking the checked-out branch and the trunk.
2. Any branch whose PR base has drifted from its local parent, or that needs a rebase.
3. Every blocker, each with its `fix` line. Do not paraphrase the fixes away: they are
   exact commands.

If the script exits 1, read the `error` field from the JSON on stdout and explain it.
Two errors have specific, non-obvious causes worth naming:

- **"is not part of any tracked stack"** while inside a linked worktree means gh stack's
  state is worktree-private, not that the branch is unstacked. The script reports
  `WORKTREE_STATE_INVISIBLE` with the symlink fix.
- **"HEAD is detached"** also occurs mid-rebase. During a rebase conflict every `gh stack`
  command fails with exit 2, including `view --json`. See `references/failure-modes.md`.

Do not run any mutating `gh stack` command as part of this report.
