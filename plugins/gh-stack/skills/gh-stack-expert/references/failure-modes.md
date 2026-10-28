# `gh stack` failure modes and state inspection (v0.3.0)

Diagnostic reference. Everything marked observed was reproduced against extension **v0.1.0**
(gh 2.96.0, git 2.55.0, macOS) in throwaway repos. Worktree, rebase-state, and exit-7
behavior was re-observed on **v0.3.0**. Anything requiring a live remote or real pull
requests is marked **UNVERIFIED**.

---

## Exit codes

| Code | Meaning | Status | Observed trigger and stderr |
|---|---|---|---|
| 0 | Success | Observed | Also returned by an unrecognised subcommand, which prints root help to stdout |
| 1 | Generic error | Observed | `gh stack view --nonexistent-flag` -> `unknown flag: --nonexistent-flag`; `gh stack push` with no remotes -> `✗ no remotes configured`; `gh stack switch` non-interactive -> `✗ switch requires an interactive terminal`; `gh stack rebase --abort` with nothing running -> `✗ no rebase in progress` |
| 2 | Not in a stack, or stack not found | Observed | `✗ current branch "main" is not part of a stack`; `✗ no locally tracked stack found for "<name>"`; in the worktree that holds a rebase conflict, `✗ failed to get current branch: git: not on any branch` (v0.1.0 said `failed to run git:`) |
| 3 | Rebase conflict | Observed | `gh stack rebase --no-trunk` with a real conflict |
| 4 | GitHub API failure | Observed | `gh stack submit --auto` with no remote -> `✗ failed to create GitHub client: determining repository: unable to determine current repository, no git remotes configured for this repository` |
| 5 | Invalid arguments or flags | Observed | `gh stack down abc` -> `✗ invalid number "abc"`; `add` from mid-stack -> `✗ can only add branches to the top of the stack`; `init` on an existing stack -> `✗ current branch "<x>" is already part of a stack`; `init` with no args non-interactively -> `✗ interactive input required; provide branch names as arguments` |
| 6 | Disambiguation required | Observed | `view --json` on a trunk shared by two stacks |
| 7 | Rebase already in progress | Observed (v0.3.0) | A second `gh stack rebase` from a worktree other than the conflicted one -> `✗ a rebase operation is already in progress (<common-dir>/gh-stack-rebase-state)`, then `Operation started in worktree <path>`. In the conflicted worktree itself the detached-HEAD check fires first and returns **2** |
| 8 | Stack locked by another process | Observed | `✗ another process is currently editing the stack — try again later` |
| 9 | Stacked PRs not enabled for repository | **UNVERIFIED** | Requires a repository without the feature |
| 10 | Modify session interrupted | **UNVERIFIED** | Requires interrupting the `modify` TUI |

### Exit codes are not consistent for the same condition

On a trunk that belongs to two stacks, the same root cause produces different codes:

```
$ gh stack view --json
EXIT=6
✗ branch "main" belongs to multiple stacks; checkout a non-trunk branch first

$ gh stack up
EXIT=2
✗ branch "main" belongs to multiple stacks; use an interactive terminal to select one

$ gh stack top
EXIT=2
✗ branch "main" belongs to multiple stacks; use an interactive terminal to select one
```

**Branch on stderr text as well as the exit code.** Matching `belongs to multiple stacks` is
more reliable than matching code 6. Likewise, code 2 covers at least three unrelated
conditions (no stack, stack not found, detached HEAD), so the code alone does not identify the
problem.

---

## `view --json` schema

`--json` is a boolean flag, not a field selector. There is no `--jq` and no `--template`, and
no other subcommand emits JSON. Data goes to stdout; status messages go to stderr.

Observed on a three-branch stack with no PRs:

```json
{
  "trunk": "main",
  "currentBranch": "feat-c",
  "branches": [
    {
      "name": "feat-a",
      "base": "edaca4531d2c05f5435bdfd11ed9c225d5772a10",
      "isCurrent": false,
      "isMerged": false,
      "isQueued": false,
      "needsRebase": false
    },
    {
      "name": "feat-b",
      "base": "24cef3f870d8bbd566d3b6d009dc725c03086332",
      "isCurrent": false,
      "isMerged": false,
      "isQueued": false,
      "needsRebase": false
    },
    {
      "name": "feat-c",
      "base": "29efd41ec91e613456e0667e66af72f9e5e1a2f8",
      "isCurrent": true,
      "isMerged": false,
      "isQueued": false,
      "needsRebase": false
    }
  ]
}
```

### Fields

| Field | Type | Notes |
|---|---|---|
| `trunk` | string | Branch name of the stack's trunk. Not a member of `branches` |
| `currentBranch` | string | Checked-out branch |
| `branches[].name` | string | Branch name |
| `branches[].base` | string | **Commit SHA, not a branch name.** The parent's tip as of the last stack operation |
| `branches[].head` | string | **`omitempty`.** Absent until a stack operation records it. Absent right after `init` and `add`; present after `rebase` |
| `branches[].isCurrent` | bool | |
| `branches[].isMerged` | bool | Requires PR state, so it needs the network to be meaningful |
| `branches[].isQueued` | bool | PR is in a merge queue |
| `branches[].needsRebase` | bool | See the transitivity trap below |
| `branches[].pr` | object | **`omitempty`.** Renders only when a PR exists |

### Traps

1. **`base` is a SHA, not a branch name.** Do not print it as a parent name or compare it to
   branch names.
2. **Parentage is only recoverable from array order.** The array is ordered bottom to top and
   there is no explicit parent pointer. The parent of `branches[i]` is `branches[i-1]`, and the
   parent of `branches[0]` is `trunk`. Human output renders top to bottom, the reverse of the
   array, so do not mix the two orders.
3. **`head` is `omitempty`.** Never assume it exists. Use `git rev-parse <branch>` when you
   need a reliable tip.
4. **`pr` is `omitempty`** (struct tag `json:"pr,omitempty"` in the binary). It renders only
   when PRs exist. Upstream documents the shape as
   `{"number": 42, "url": "https://github.com/owner/repo/pull/42", "state": "MERGED"}` with
   `state` in `OPEN`, `MERGED`, `QUEUED`. **UNVERIFIED: we never observed a populated `pr`
   object.** All testing used scratch repos with fake remotes and no pull requests. Treat both
   the presence and the exact shape as unconfirmed, and guard every access
   (`.pr.url // empty`).
5. The wrapper object has no schema version. The on-disk state file does
   (`schemaVersion: 1`).

Useful queries, all guarded:

```bash
gh stack view --json | jq -r '.currentBranch'
gh stack view --json | jq -r '.branches[].name'
gh stack view --json | jq -r '.branches[] | select(.pr.state? == "OPEN") | .pr.url // empty'
gh stack view --json | jq -e '[.branches[].needsRebase] | any' >/dev/null && echo stale
```

---

## `needsRebase` is not transitive

**It is set only on the immediate child of the branch that moved.** Branches further up are
equally stale but report `false`.

Observed after committing to the bottom branch `feat-a` of `main <- feat-a <- feat-b <- feat-c`:

```json
[{"name":"feat-a","needsRebase":false},
 {"name":"feat-b","needsRebase":true},
 {"name":"feat-c","needsRebase":false}]
```

`feat-c` is stale in reality. Treat **any** `needsRebase: true` as "the entire upstack is
stale", never as a per-branch list of what to fix.

### Recomputing staleness with plain git

Walk consecutive pairs and ask whether the parent is an ancestor of the child:

```bash
f="$(git rev-parse --git-common-dir)/gh-stack"

jq -r '.stacks[0] | [.trunk.branch] + [.branches[].branch] | .[]' "$f" \
  | awk 'NR>1 {print prev, $0} {prev=$0}' \
  | while read -r parent child; do
      git merge-base --is-ancestor "$parent" "$child" \
        || printf '%s needs rebase onto %s\n' "$child" "$parent"
    done
```

This reports every stale branch, not just the first one.

---

## Rebase conflict recovery

### The conflict

```
$ gh stack rebase --no-trunk
EXIT=3
Stack detected: (main) <- feat-a <- feat-b <- feat-c
Rebasing branches in order, starting from feat-b to feat-c
⚠ Rebasing feat-b onto feat-a — conflict

Conflicted files:
  C shared.txt

To resolve:
  1. Open each conflicted file and look for conflict markers:
     <<<<<<< HEAD  (incoming changes from feat-a)
     =======
     >>>>>>>  (changes being rebased)
  2. Edit the file to keep the desired changes and remove the markers
  3. Stage resolved files: `git add <file>`
  4. Continue:  `gh stack rebase --continue`

Resolve conflicts on feat-b, then run `gh stack rebase --continue`
Or abort this operation with `gh stack rebase --abort`
```

All of that is on **stderr**. Conflicted paths are parseable as lines matching
`^  C (.+?)( \(lines .*\))?$`. Since v0.3.0 each path can carry a `(lines N–M)` suffix.

When the conflicted branch is checked out in another worktree, the conflict happens
**there**, and stderr says so:

```
⚠ Rebasing feat-two onto feat-one — conflict
Conflict worktree: /repo-wt
Resolve and stage files in that worktree; continuation may be run from any worktree.
```

### `gh stack` fails in the conflicted worktree, and only there

HEAD is detached in the worktree that holds the conflict, and every subcommand run there
fails the same check:

```
$ gh stack view --json        EXIT=2  ✗ failed to get current branch: git: not on any branch
$ gh stack rebase --no-trunk  EXIT=2  (same)
$ gh stack add zzz            EXIT=2  (same)
```

**From any other worktree, `view --json` exits 0** and shows an ordinary stack with
`needsRebase: true`. Nothing in that output says a rebase is mid-flight. Detect the state
out of band:

```bash
# Is a stack rebase in progress, in any worktree?
test -f "$(git rev-parse --git-common-dir)/gh-stack-rebase-state"

# Which files are conflicted? Run this in the conflict worktree.
git diff --name-only --diff-filter=U
```

`git branch --show-current` returns empty while detached.

### `gh-stack-rebase-state`

Lives in the common git dir. Present only during a conflict, removed on completion or
abort. Observed on v0.3.0, abridged:

```json
{
  "phase": "conflict",
  "worktrees": {
    "origin": { "path": "/repo", "id": "." },
    "owners": {
      "feat-one": { "path": "/repo" },
      "feat-two": { "path": "/repo-wt", "id": "worktrees/wt" }
    },
    "pending": "feat-two"
  },
  "stackTrunk": "main",
  "stackBranches": ["feat-one", "feat-two"],
  "currentBranchIndex": 1,
  "conflictBranch": "feat-two",
  "remainingBranches": null,
  "originalBranch": "feat-one",
  "originalRefs": {
    "feat-one": "27d6ec6f5d0bacbca1e9967187b10ca72368b771",
    "feat-two": "daf9e11c04a463b906a6c31f3069819915987afa"
  },
  "ontoOldBase": "daf9e11c04a463b906a6c31f3069819915987afa",
  "noTrunk": true
}
```

| Field | Meaning |
|---|---|
| `phase` | `conflict` while stopped |
| `worktrees.owners` | Which checkout holds each branch. The conflict branch's entry is where to resolve |
| `worktrees.origin` | Checkout the rebase was started from |
| `conflictBranch` | Branch currently being rebased |
| `remainingBranches` | Branches not yet processed. `null` when none remain |
| `originalBranch` | Branch to return to when the rebase finishes |
| `originalRefs` | Pre-rebase tip of every branch. This is the undo record `--abort` uses |
| `originalStack` | Full stack definition before the rebase (omitted above) |
| `ontoOldBase` | Previous base of the conflicting branch |
| `noTrunk` | Whether `--no-trunk` was in effect |

Git keeps its own `rebase-merge/` directory and `REBASE_HEAD` in the conflict worktree's
private git dir.

### Continue

```
$ git add shared.txt
$ gh stack rebase --continue
EXIT=0
Continuing rebase of stack, resuming from feat-b to feat-c
✓ Rebased feat-b onto feat-a
✓ Rebased feat-c onto feat-b
All branches in stack rebased locally (without trunk)
To push up your changes and open/update the stack of PRs, run `gh stack submit`
```

Works non-interactively and from any worktree. Returns to `originalBranch`. If another
conflict occurs, repeat.

### Abort

`gh stack rebase --abort` restores every branch from `originalRefs`. With nothing in progress
it exits **1** with `✗ no rebase in progress`.

### Conflict detection can produce a false negative

`git diff --name-only --diff-filter=U` returns **empty** when a previously recorded rerere
resolution has been auto-applied and staged. In that state a halt looks like a clean stop and
`gh stack rebase` can exit **0** having committed a replayed resolution. Do not treat an empty
unmerged list as proof that no conflict occurred, and do not treat exit 0 from
`gh stack rebase` as proof either. See SKILL.md on rerere.

---

## Reading stack state with plain git

Use this when `gh stack` cannot answer: during a conflict, on a detached HEAD, on a trunk
shared by two stacks, or when the extension is unavailable.

### Locating the file

```bash
echo "$(git rev-parse --git-common-dir)/gh-stack"
```

**Use `--git-common-dir`, not `--git-path`.** Since v0.2.0 one state file in the common git
dir serves every worktree. `--git-path gh-stack` resolves into a linked worktree's private
git dir, because git redirects only a fixed allowlist of filenames, and nothing is there.
Related files in the same directory: `gh-stack.lock`, `gh-stack-operation.lock`, and
`gh-stack-rebase-state`.

v0.2.0 migrated older per-worktree state files into the shared one automatically and kept
backups. A conflicting pair stops with guidance instead of merging.

### Schema

```json
{
  "schemaVersion": 1,
  "repository": "github.com:example/demo",
  "stacks": [
    {
      "trunk": { "branch": "main", "head": "<sha>" },
      "branches": [
        { "branch": "feat-a", "head": "<sha>", "base": "<sha>" },
        { "branch": "feat-b", "head": "<sha>", "base": "<sha>" }
      ]
    }
  ]
}
```

- `stacks` is an array. One repository can hold many independent stacks, each with its own
  trunk.
- Parentage is positional. Array order is stack order, bottom to top. There is no parent
  pointer.
- `base` is the parent's tip SHA as of the last stack operation, not a branch name.
- `head` appears only after an operation records it, so it is absent right after `init`.
- `repository` is written even when the repo has no remote.
- No git config keys and no refs are used. `git config --get-regexp 'stack|gh-stack'` returns
  nothing.

### Recipes

```bash
f="$(git rev-parse --git-common-dir)/gh-stack"

# Every stack, bottom to top
jq -r '.stacks[] | "trunk=\(.trunk.branch): " + ([.branches[].branch] | join(" <- "))' "$f"

# The stack containing the current branch
cur=$(git branch --show-current)
jq --arg b "$cur" '.stacks[] | select([.branches[].branch] | index($b))' "$f"

# Parent of a given branch, by array position
jq -r --arg b "$cur" '
  .stacks[] | select([.branches[].branch] | index($b)) |
  . as $s | ([$s.branches[].branch] | index($b)) as $i |
  if $i == 0 then $s.trunk.branch else $s.branches[$i-1].branch end' "$f"

# Does this repository track any stack at all?
test -f "$f" && jq -e '.stacks | length > 0' "$f" >/dev/null
```

---

## Push atomicity

Since v0.3.0, `push`, `sync`, and `submit` push every branch in one atomic
`--force-with-lease` update. Either every branch moves or none does. v0.1.0 documented
`push` and `submit` as non-atomic, so older notes and transcripts describe partial pushes.

| Setting | Behaviour |
|---|---|
| Default | Atomic. A rejected lease on one branch rejects the whole push |
| `--no-atomic` or `GH_STACK_NO_ATOMIC=1` | Per-branch. One branch can update while another is rejected |

Consequences:

- A failed default push leaves the remote branches untouched. Rerun after you fix the cause.
- **`submit`'s PR updates are still not atomic.** If the push succeeds and a later PR step
  fails, some PRs can be created or retargeted and others not. Rerun the same command.
- If the user has `GH_STACK_NO_ATOMIC` set, the old partial-push behaviour applies.
- All three skip merged and queued branches.
- UNVERIFIED: the exact rejection text when a `--force-with-lease` check fails. Reproducing it
  needs a live remote.

---

## Lock contention and exit 8

Mutating commands take an advisory `flock` on a zero-byte lock file beside the state file:

```bash
echo "$(git rev-parse --git-common-dir)/gh-stack.lock"
```

v0.2.0 added a second zero-byte file, `gh-stack-operation.lock`, in the same directory. The
same rules apply to it.

Observed with the lock held by another process:

```
$ gh stack view --short     EXIT=0     (reads do not take the lock)
$ gh stack add locktest     EXIT=8     ✗ another process is currently editing the stack — try again later
```

- Reads are unaffected. Only mutating commands contend.
- Upstream documents a five-second timeout before the command gives up. The failure returned
  promptly in testing; the exact timeout was not measured.
- Exit 8 is safe to retry. It means no work was done, not that the stack is damaged.
- The lock file persists on disk when idle. Its presence means nothing; only a held `flock`
  does. Never delete it to "clear" a stuck state.
