# `gh stack` subcommand digest (v0.3.0)

Lookup reference. Flags and usage strings below were dumped from `gh stack <cmd> --help` on
extension **v0.1.0** (gh 2.96.0, macOS), and every flag table was re-checked on **v0.3.0**.
Behavior notes come from v0.1.0 testing unless they name a later version. Groupings match
`gh stack --help`.

Every subcommand also accepts `-h, --help`; it is omitted from the flag tables.

Legend:

- **TUI**: behaviour when attached to a real terminal.
- **Net**: whether the command contacts the network.

Two behaviours apply to every subcommand and are not repeated per entry:

- Status messages (`✓ ✗ ⚠ ℹ`) go to **stderr**, including success messages. Only
  `view --json` writes data to **stdout**.
- An unrecognised subcommand prints the root help to stdout and exits **0**. Never treat a
  bare exit 0 as proof a subcommand ran.

---

## Stack management

### `init`

Create a stack, creating or adopting branches bottom to top.

```
gh stack init [branches...] [flags]
```

| Flag | Description |
|------|-------------|
| `-b, --base string` | Trunk branch for stack (defaults to default branch) |

| Property | Value |
|---|---|
| Positional | Branch names, bottom to top. Optional to the parser, required in practice |
| TUI | Prompts once (see gotchas). With branch names supplied that prompt is the only one |
| Net | No. Works in a repo with no remote configured at all |

Gotchas:

- **Branch names are positional.** There is no `--adopt` in the flag list, but the flag is
  still accepted as a deprecated no-op and warns:
  `⚠ The --adopt flag is deprecated. Existing branches are now adopted automatically.`
  It then proceeds normally. Use the positional form.
- Existing branches are adopted, missing ones are created from the trunk. Checks out the last
  branch in the list.
- Names are used verbatim. Slashes are kept, nothing is prefixed.
- Without branch names in a non-interactive terminal: exit **5**,
  `✗ interactive input required; provide branch names as arguments`. It does not hang.
- On a branch already in a stack: exit **5**,
  `✗ current branch "<name>" is already part of a stack`.
- One repo can hold multiple independent stacks, each with its own trunk.

### `add`

Add a branch on top of the current stack.

```
gh stack add [branch] [flags]
```

| Flag | Description |
|------|-------------|
| `-A, --all` | Stage all changes including untracked files |
| `-m, --message string` | Create a commit with this message |
| `-u, --update` | Stage changes to tracked files only |

| Property | Value |
|---|---|
| Positional | Branch name. Optional to the parser |
| TUI | Prompts for a branch name when omitted |
| Net | No |

Gotchas:

- **Only works from the topmost branch.** From anywhere else: exit **5**,
  `✗ can only add branches to the top of the stack; run `gh stack top` then `gh stack add``.
  Note the wording is "to the top"; upstream docs quote "on top", so match loosely if
  string-matching.
- `-A` and `-u` are mutually exclusive.
- With `-m` and no branch name, the name is generated as a date-and-slug, for example
  `gh stack add -Am "feat: add c"` produced `07-31-feat_add_c`.
- Without `-A`/`-u`, uncommitted changes carry over to the new branch. That is ordinary git
  behaviour; the working tree is untouched.
- With no branch name in a non-interactive terminal it fails messily rather than cleanly:
  exit **1**, `could not read branch name: failed to set terminal mode: operation not
  supported by device`.
- From a branch outside any stack, v0.1.1 and later offer to start a new stack in a
  terminal. Without one it exits **2**, `✗ current branch "<b>" is not part of a stack`,
  and does not hang (observed on v0.3.0).

### `checkout`

Switch to a stack by stack number, PR number, PR URL, or branch name.

```
gh stack checkout [<stack-number> | <pr-number> | <pr-url> | <branch>] [flags]
```

| Flag | Description |
|------|-------------|
| `--print-path` | Print the target worktree path (requires an explicit target) |

**There is no `--remote` flag**; it relies on `remote.pushDefault`.

| Property | Value |
|---|---|
| Positional | One target. Optional to the parser |
| TUI | With no argument, first offers a remote stack that contains the current branch, then opens a searchable picker of local and remote stacks |
| Net | When resolving a stack number, PR number, or PR URL, and when a branch name is not tracked locally. A locally tracked branch name is offline |

Gotchas:

- Resolution order for a bare number: **stack number first**, then locally tracked PR number,
  then a PR number discovered from GitHub, then a branch name. Stack and PR numbers never
  overlap.
- A branch name resolves against locally tracked stacks first. Since v0.1.1, an untracked
  name is then looked up in active stacks on GitHub, and a match is **pulled down and
  tracked locally**. That writes local state and fetches branches. Success looks like:
  ```
  ✓ Switched to feat-b
  Stack: (main) <- feat-a <- feat-b <- feat-c
  ```
- Unknown branch with no remote match: exit **2**,
  `✗ no locally tracked stack found for "<name>"`. The remote lookup is best-effort, so a
  network failure falls through to the same error.
- A target branch checked out in another worktree: exit **5** with a `cd <path>` hint.
  `--print-path` prints that path instead.
- No argument in a non-interactive terminal: exit **1**,
  `✗ no target specified; provide a branch name or PR number, or run interactively to select a stack`.
- UNVERIFIED (documented upstream, not reproduced here): `checkout <pr-number>` when a
  different local stack already exists on those branches triggers a conflict prompt that no
  flag bypasses. Documented mitigation is `gh stack unstack --local` first.

### `modify`

Restructure the current stack.

```
gh stack modify [flags]
```

| Flag | Description |
|------|-------------|
| `--abort` | Abort the modify session and restore the stack to its pre-modify state |
| `--continue` | Continue after resolving conflicts |

| Property | Value |
|---|---|
| Positional | None |
| TUI | Yes, entirely. Non-interactive: exit **1**, `✗ modify requires an interactive terminal` |
| Net | No |

Gotchas:

- `--abort` and `--continue` are themselves scriptable. `--abort` with no session in progress
  exits **0** with `No modify session to abort`, unlike `rebase --abort`, which exits 1.
- Documented preconditions: an active local stack, a clean working tree, no in-progress
  rebase, no PR queued for merge, and linear history.
- Scriptable substitute for restructuring: `gh stack unstack` then `gh stack init` with the
  branches in the desired order.

### `unstack`

Remove a stack from local tracking and unstack it on GitHub. Alias: `delete`.

```
gh stack unstack [<stack-number>] [flags]
```

| Flag | Description |
|------|-------------|
| `--local` | Only delete the stack locally |

| Property | Value |
|---|---|
| Positional | Stack number, optional |
| TUI | No |
| Net | Yes, unless `--local` |

Gotchas:

- Removes the grouping only. Pull requests and branches are never deleted.
- With a stack number it works from anywhere in the repo, tracked locally or not, via the API.
- `--local` never contacts GitHub. Combining `--local` with a number that is not tracked
  locally is an error.
- GitHub decides what can be unstacked. PRs queued for merge or with auto-merge enabled stay
  stacked, and the stack is kept on GitHub. Since v0.3.0, merged PRs that GitHub keeps no
  longer stop the local removal.

### `view`

Show the current stack.

```
gh stack view [flags]
```

| Flag | Description |
|------|-------------|
| `--json` | Output stack data as JSON |
| `-s, --short` | Show compact output |

| Property | Value |
|---|---|
| Positional | None |
| TUI | **Bare `view` only.** `--short` and `--json` both run to completion under a TTY |
| Net | Only to populate PR state |

Gotchas:

- `--json` is a **boolean flag**, not gh's field selector. There is no `--jq` and no
  `--template`. Pipe to `jq` yourself. No other subcommand emits JSON.
- `--json` wins when combined with `--short`.
- Under a pipe, bare `view` prints a static tree and exits 0. Under a TTY it is a TUI that
  stalls on `Loading stack...`. `--short` is safe either way but is not machine readable.
- Icons in human output: `✓` merged, `◎` queued, `○` open, `⚠` needs rebase, `●` current,
  `»` current in `--short`. Human output renders top to bottom; the JSON array is bottom to
  top.

Schema and parsing traps: see `failure-modes.md`.

---

## Remote operations

### `link`

Group PRs into a stack on GitHub without any local tracking state.

```
gh stack link <stack-number | branch-or-pr> <branch-or-pr> [<branch-or-pr>...] [flags]
```

| Flag | Description |
|------|-------------|
| `--base string` | Base branch for the bottom of the stack (defaults to the repository default branch) |
| `--no-atomic` | Disable atomic pushes (also set by `GH_STACK_NO_ATOMIC`) |
| `--open` | Mark new and existing PRs as ready for review |
| `--remote string` | Remote to push to (defaults to auto-detected remote) |

| Property | Value |
|---|---|
| Positional | Two or more targets, bottom to top; or a stack number followed by additions |
| TUI | No |
| Net | Yes. Pushes branch arguments and creates PRs |

Gotchas:

- Intended for branches managed by other tools (jj, Sapling, git-town). Creates and modifies
  no local state.
- A numeric first argument is treated as a stack number only if such a stack exists;
  otherwise it is a PR number, then a branch name.
- Additive only. Existing PRs are never removed from a stack.
- Existing PRs whose base does not match the expected chain are corrected automatically.

### `merge`

Merge some or all of a stack of pull requests.

```
gh stack merge [<stack-number> | <pr-number>] [flags]
```

| Flag | Description |
|------|-------------|
| `--merge` | Merge with a merge commit |
| `--merge-method string` | Merge method to use: merge, squash, or rebase |
| `--rebase` | Rebase and merge |
| `--squash` | Squash and merge |
| `-y, --yes` | Merge without prompting for confirmation |

| Property | Value |
|---|---|
| Positional | Stack number or PR number, optional |
| TUI | Wizard in a terminal. **Skipped entirely in a non-interactive terminal** |
| Net | Yes |

Mechanics (see SKILL.md before running this at all):

- No argument uses the stack containing the current branch. A bare number is tried as a stack
  number first, then a PR number.
- A PR number merges everything **up to and including** that PR. Everything below the
  selection is always included. There is no way to merge a middle PR alone.
- With no method flag it uses the **last-used merge method**, which is implicit sticky state.
- **There is no dry-run or preview flag.**
- Pre-merge it checks only that PRs are open and not drafts. Branch protection and repository
  rules are evaluated server-side at merge time.
- All-or-nothing across the selected PRs. If the base branch uses a merge queue, the stack is
  enqueued instead of merged.

### `push`

Push active branches in the current stack to the remote.

```
gh stack push [flags]
```

| Flag | Description |
|------|-------------|
| `--no-atomic` | Disable atomic pushes (also set by `GH_STACK_NO_ATOMIC`) |
| `--remote string` | Remote to push to (defaults to auto-detected remote) |

| Property | Value |
|---|---|
| Positional | None |
| TUI | No |
| Net | Yes |

Gotchas:

- Per-branch `--force-with-lease` checks with **atomic** updates by default since v0.3.0.
  Every branch updates or none does. With `--no-atomic` or `GH_STACK_NO_ATOMIC=1`, one
  branch can update while another is rejected.
- Merged and queued branches are skipped automatically.
- Does not create or update pull requests.
- No remotes configured: exit **1**, `✗ no remotes configured`.

### `rebase`

Cascading rebase across the stack.

```
gh stack rebase [branch] [flags]
```

| Flag | Description |
|------|-------------|
| `--abort` | Abort rebase and restore all branches |
| `--accept-base-change` | Rebase onto a retargeted base even if the old base did not merge |
| `--committer-date-is-author-date` | Set the committer date to the author date during rebase |
| `--continue` | Continue rebase after resolving conflicts |
| `--downstack` | Only rebase branches from trunk to current branch |
| `--no-trunk` | Skip trunk, only rebase stack branches onto each other |
| `--preserve-dates` | Alias for `--committer-date-is-author-date` |
| `--remote string` | Remote to fetch from (defaults to auto-detected remote) |
| `--upstack` | Only rebase branches from current branch to top |

| Property | Value |
|---|---|
| Positional | Target branch, defaults to current |
| TUI | No |
| Net | Yes, except with `--no-trunk` |

Gotchas:

- `--no-trunk` is the only fully offline mode. It skips the fetch and the trunk rebase and
  performs inter-branch rebases only.
- `--continue` works non-interactively after `git add`.
- `--abort` with nothing in progress: exit **1**, `✗ no rebase in progress`.
- **A dirty tree is refused (v0.3.0).** Any modified, staged, or untracked file in an
  affected worktree stops the rebase before it starts: exit **1**,
  `✗ uncommitted changes in worktree <path>; commit or stash them before continuing`.
  v0.1.0 did not check.
- Merged PRs are handled with `--onto` so commits replay onto the merge target. Since
  v0.3.0 the boundary is the commit GitHub actually merged, so a stale local copy of a
  merged branch no longer replays already-merged commits.
- **Base retargeting (v0.3.0).** When a stack's base branch is deleted, GitHub retargets
  the stack to the default branch, and `rebase` follows it. If the old base never merged,
  following it drops that base's commits from the stack. The command asks first, or
  proceeds silently with `--accept-base-change`. UNVERIFIED: behavior without a terminal;
  it needs a live retargeted stack to reproduce.
- With branches spread across worktrees, each branch is rebased in the checkout that holds
  it. The clean-tree check covers every affected worktree, not only yours. Requires Git
  2.36 or later.

Conflict handling: see `failure-modes.md`.

### `submit`

Push all branches and create or update PRs plus the stack on GitHub.

```
gh stack submit [flags]
```

| Flag | Description |
|------|-------------|
| `--auto` | Use auto-generated PR titles without prompting |
| `--no-atomic` | Disable atomic pushes (also set by `GH_STACK_NO_ATOMIC`) |
| `--open` | Mark new and existing PRs as ready for review |
| `--remote string` | Remote to push to (defaults to auto-detected remote) |

| Property | Value |
|---|---|
| Positional | None |
| TUI | Full-screen editor unless `--auto` or a non-interactive terminal |
| Net | Yes |

Gotchas:

- Sequence: push branches, create PRs for included branches, update base branches on existing
  PRs, then create or update the stack object.
- Draft polarity differs by path. With `--auto`, new PRs are **drafts** unless `--open`. In
  the interactive editor they default to ready for review.
- Title generation: a single commit uses its subject as the title and its body as the PR body;
  multiple commits humanise the branch name.
- **No flag sets a custom PR title or body.** Use `gh pr edit` afterwards.
- The branch push is atomic by default since v0.3.0. **PR updates are not atomic.** A
  failure after the push can leave some PRs created or retargeted and others not. Rerun
  the same command.
- No remote: exit **4**, `✗ failed to create GitHub client: determining repository: unable to
  determine current repository, no git remotes configured for this repository`.

### `sync`

Fetch, rebase, push, and sync PR state for the current stack.

```
gh stack sync [flags]
```

| Flag | Description |
|------|-------------|
| `--accept-base-change` | Rebase onto a retargeted base even if the old base did not merge |
| `--no-atomic` | Disable atomic pushes (also set by `GH_STACK_NO_ATOMIC`) |
| `--prune` | Delete local branches for merged PRs |
| `--remote string` | Remote to fetch from and push to (defaults to auto-detected remote) |

| Property | Value |
|---|---|
| Positional | None |
| TUI | Prompts only when local and remote stacks have diverged |
| Net | Yes |

Documented sequence: fetch, reconcile the remote stack, fast-forward trunk, cascade rebase,
push, sync PR state, then link open PRs into a stack once two or more PRs exist.

Gotchas:

- `push`, `sync`, and `submit` share one push behavior since v0.3.0: atomic by default,
  partial with `--no-atomic` or `GH_STACK_NO_ATOMIC=1`.
- A clean "remote is ahead" update applies automatically. A genuine divergence prompts in a
  terminal and **aborts in a non-interactive one**, exiting successfully with
  `ℹ Sync aborted — no changes were made`. Exit 0 does not mean the stack synced.
- Distinguish the final message: `✓ Stack synced` means the GitHub stack object matches local;
  `✓ Branches synced` means branches were pushed but no stack object was created or updated.
- Never opens PRs. Use `submit`.
- On rebase conflict it restores all branches and exits **3**.
- Follows a retargeted base exactly as `rebase` does, including the confirmation before
  dropping commits from an unmerged old base.
- Pruning happens non-interactively only when `--prune` is passed.
- No remotes: exit **1**, `✗ no remotes configured`.

---

## Navigation

All five are offline, non-interactive, and skip merged branches. Each takes
`--print-path`, which prints the target's worktree path instead of failing on a branch
held by another worktree.

| Command | Purpose | Positional |
|---|---|---|
| `gh stack up [n]` | Move `n` branches away from trunk (default 1) | Count |
| `gh stack down [n]` | Move `n` branches toward trunk (default 1) | Count |
| `gh stack top` | Jump to the branch furthest from trunk | None |
| `gh stack bottom` | Jump to the branch closest to trunk | None |
| `gh stack trunk` | Jump to the trunk branch | None |

Observed output:

```
$ gh stack down          ✓ Checked out feat-b, 1 branch down
$ gh stack down 2        ✓ Checked out feat-a, 2 branches down
$ gh stack top           Already at the top of the stack      (exit 0)
$ gh stack up            ✓ Switched to feat-a                 (from trunk, enters the stack)
```

Gotchas:

- Counts clamp to the stack bounds. Overshooting is not an error; it exits **0** with
  `Already at the top of the stack` or `Already at the bottom of the stack`.
- `down 0` reports `Already at the bottom of the stack`.
- A non-numeric count: exit **5**, `✗ invalid number "abc"`.
- `up` from the trunk enters the stack at the bottom.
- On a trunk shared by two stacks, these exit **2** while `view --json` exits 6. See
  `failure-modes.md`.
- A target branch checked out in another worktree: exit **5**,
  `Branch "<b>" is already checked out in another worktree`, plus a `cd <path>` hint.
  Observed with `bottom`. Expect the same from the other navigation commands.

### `switch`

Interactive picker for branches in the current stack.

```
gh stack switch [flags]
```

No flags beyond `--help`. Non-interactive: exit **1**,
`✗ switch requires an interactive terminal`.

Scriptable equivalents: `up`, `down`, `top`, `bottom`, or `checkout <branch>`.

---

## Utilities

### `alias`

Install a wrapper script that forwards to `gh stack`.

```
gh stack alias [name] [flags]
```

| Flag | Description |
|------|-------------|
| `--remove` | Remove a previously created alias |

| Property | Value |
|---|---|
| Positional | Alias name, defaults to `gs` |
| TUI | No |
| Net | No |

Writes an executable wrapper into `~/.local/bin/`. That location is outside chezmoi's
management.

### `feedback`

Open a GitHub Discussion in the gh-stack repository to submit feedback.

```
gh stack feedback [title] [flags]
```

No flags beyond `--help`. Takes an optional pre-filled title. Opens a browser.
