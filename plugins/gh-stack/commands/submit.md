---
description: Preflight a gh stack and prepare the exact submit command for the user to run
argument-hint: Optional flags to include in the prepared command (e.g., "--open" for ready-for-review instead of draft)
allowed-tools: Bash, Read
---

# gh stack submit (prepare)

Do everything up to the remote write, then hand the command over.

**You do not run `gh stack submit`.** It pushes branches and creates or updates pull
requests, which is the user's call, not yours. This command exists so that when they make
that call they are looking at a resolved plan instead of guessing. Preparation is the whole
job here, and it is genuinely the useful part.

## Instructions

### 1. Preflight

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/gh_stack_status.py" --strict --for submit
```

Exit 2 means blockers apply. Report them with their `fix` lines and stop. Do not clear them
silently: the common ones are a dirty working tree, a branch needing a rebase, and PR base
drift, and each one changes what would be submitted.

Local fixes are yours to offer (`gh stack rebase --upstack` is local and rewrites only local
branches). Anything that touches the remote is not.

### 2. Resolve the plan

From the JSON, state precisely what a submit would do:

- Every branch bottom to top, with its parent.
- For each: **create** a new PR (no `pr` object) or **update** an existing one
  (`pr.number` present), and whether `pr.base_ref` would change.
- That without `--open`, new PRs are created as **drafts**.
- That `--auto` generates titles from commit messages rather than opening the editor.

Name the branches and PR numbers explicitly. "It would submit the stack" is not a plan.

### 3. Hand it over

Print the exact command, on its own line, ready to paste:

```
gh stack submit --auto $ARGUMENTS
```

Say plainly that they need to run it, and why: it pushes to the remote, which is theirs to
authorize. Do not run it, do not offer to run it, and do not suggest a variant that would
evade the restriction.

Mention one property they should know before running it: **submit is not atomic.** It pushes
branches individually, so a partial failure can leave some branches updated and others not,
with PR bases pointing at branches that did not move. The fix is to re-run the same command,
not to escalate to a force push.

### 4. Offer to verify afterwards

Once they say it has run, re-read state rather than assuming it worked:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/gh_stack_status.py" --text
```

Report each PR number and URL, and flag any remaining `PR_BASE_DRIFT`.

## Never

- **Never run `gh stack submit`, `push`, `sync`, `link`, `unstack`, or `merge`.** All six
  write to GitHub and all six are the user's.
- **Never route around a denial** by rephrasing the command, splitting it across calls, or
  reaching for `gh api` to do the same thing.
- **Never run `gh pr create`** for a branch in a stack. It creates an unstacked PR that a
  later submit then has to reconcile.
- **Never `gh pr merge`** a stacked PR. It does not work on stacks.
