---
description: Preflight a gh stack, show exactly which PRs would be created or updated, get approval, then submit
argument-hint: Optional flags to pass through (e.g., "--open" to submit ready-for-review instead of draft)
allowed-tools: Bash, Read, AskUserQuestion
---

# gh stack submit

Push every branch in the stack and create or update its pull requests. This writes to the
remote and is the point of no return for review visibility, so it runs behind explicit
approval.

## Instructions

### 1. Preflight

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/gh_stack_status.py" --strict --for submit
```

Exit 2 means blockers apply. **Stop and report them.** Do not attempt to clear them
yourself: the common ones are a dirty working tree, a branch needing a rebase, and PR base
drift, and each fix changes what would be submitted.

### 2. Build the plan

From the JSON, state plainly:

- Every branch bottom to top, with its parent.
- For each: whether submit would **create** a new PR (no `pr` object) or **update** an
  existing one (`pr.number` present, and whether `pr.base_ref` would change).
- That `submit` without `--open` creates new PRs as **drafts**, and with `--auto` uses
  **auto-generated titles from commit messages**.
- That an agent-run `submit` is non-interactive, which implies `--auto` behaviour: the
  single-screen title editor is skipped.

### 3. Get approval

Use AskUserQuestion. Offer:

- **Submit** -- proceed as planned.
- **Submit ready-for-review** -- add `--open` (only offer this if the user's arguments did
  not already specify it).
- **Fix blockers first** -- stop and address what preflight found.
- **Cancel**.

Never skip this step, even if the user's original message sounded like approval. The plan
they are approving is the resolved branch-and-PR list, which they have not seen until now.

### 4. Submit

Run the bare command so the harness permission prompt describes the real operation. Do not
wrap it in a script or a shell function.

```bash
gh stack submit --auto $ARGUMENTS
```

### 5. Verify

`submit` pushes branches individually and **is not atomic**: a partial failure can leave
some branches updated and others not, with PR bases pointing at branches that did not move.
Re-read state afterwards rather than trusting the exit code:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/gh_stack_status.py" --text
```

Report each PR number and URL, and flag any remaining `PR_BASE_DRIFT`.

## Never

- **Never run `gh stack merge`** as part of this command. It is a separate, irreversible
  operation: with no argument it merges the *entire* stack, it has no dry-run, and with no
  method flag it uses the last-used merge method. It belongs behind its own approval.
- **Never run `gh pr create`** for a branch in a stack. It creates an unstacked PR that
  `submit` then has to reconcile.
- **Never `gh pr merge`** a stacked PR. It does not work on stacks.
