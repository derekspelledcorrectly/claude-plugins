# `gh stack` failure modes and state inspection (v0.1.0)

Diagnostic reference. Everything marked observed was reproduced against extension **v0.1.0**
(gh 2.96.0, git 2.55.0, macOS) in throwaway repos. Anything requiring a live remote or real
pull requests is marked **UNVERIFIED**.

---

## Exit codes

| Code | Meaning | Status | Observed trigger and stderr |
|---|---|---|---|
| 0 | Success | Observed | Also returned by an unrecognised subcommand, which prints root help to stdout |
| 1 | Generic error | Observed | `gh stack view --nonexistent-flag` -> `unknown flag: --nonexistent-flag`; `gh stack push` with no remotes -> `✗ no remotes configured`; `gh stack switch` non-interactive -> `✗ switch requires an interactive terminal`; `gh stack rebase --abort` with nothing running -> `✗ no rebase in progress` |
| 2 | Not in a stack, or stack not found | Observed | `✗ current branch "main" is not part of a stack`; `✗ no locally tracked stack found for "<name>"`; during a rebase conflict, `✗ failed to get current branch: failed to run git: not on any branch` |
| 3 | Rebase conflict | Observed | `gh stack rebase --no-trunk` with a real conflict |
| 4 | GitHub API failure | Observed | `gh stack submit --auto` with no remote -> `✗ failed to create GitHub client: determining repository: unable to determine current repository, no git remotes configured for this repository` |
| 5 | Invalid arguments or flags | Observed | `gh stack down abc` -> `✗ invalid number "abc"`; `add` from mid-stack -> `✗ can only add branches to the top of the stack`; `init` on an existing stack -> `✗ current branch "<x>" is already part of a stack`; `init` with no args non-interactively -> `✗ interactive input required; provide branch names as arguments` |
| 6 | Disambiguation required | Observed | `view --json` on a trunk shared by two stacks |
| 7 | Rebase already in progress | **UNVERIFIED, likely unreachable** | Running `gh stack rebase` during a conflict returns **2**, not 7, because the detached-HEAD check fires first |
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
f=$(git rev-parse --git-path gh-stack)

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

All of that is on **stderr**. Conflicted paths are parseable as lines matching `^  C (.+)$`.

### Every `gh stack` command fails during a conflict

HEAD is detached while the rebase runs, and every subcommand bails on the same check:

```
$ gh stack view --json        EXIT=2  ✗ failed to get current branch: failed to run git: not on any branch
$ gh stack rebase --no-trunk  EXIT=2  (same)
$ gh stack add zzz            EXIT=2  (same)
```

`view --json` fails too, so **`gh stack` cannot report on its own conflict**. Detect and
inspect the state out of band:

```bash
# Is a stack rebase in progress?
test -f "$(git rev-parse --git-path gh-stack-rebase-state)"

# Which files are conflicted?
git diff --name-only --diff-filter=U
```

`git branch --show-current` returns empty while detached.

### `.git/gh-stack-rebase-state`

Present only during a conflict, removed on completion. Resolve the path with
`git rev-parse --git-path gh-stack-rebase-state`.

```json
{
  "currentBranchIndex": 1,
  "conflictBranch": "feat-b",
  "remainingBranches": ["feat-c"],
  "originalBranch": "feat-a",
  "originalRefs": {
    "feat-a": "d9520b210d0f2a186a0bcac5a05202c5e07efed4",
    "feat-b": "20016a3947eb6899741db2c5e1c59a85cb8dfe74",
    "feat-c": "8a00e85a8400ee1d6e2b82a86b37f75c8f30b40e"
  },
  "ontoOldBase": "20016a3947eb6899741db2c5e1c59a85cb8dfe74",
  "noTrunk": true
}
```

| Field | Meaning |
|---|---|
| `conflictBranch` | Branch currently being rebased |
| `remainingBranches` | Branches not yet processed |
| `originalBranch` | Branch to return to when the rebase finishes |
| `originalRefs` | Pre-rebase tip of every branch. This is the undo record `--abort` uses |
| `ontoOldBase` | Previous base of the conflicting branch |
| `noTrunk` | Whether `--no-trunk` was in effect |

Alongside it git keeps its own `rebase-merge/` directory and `REBASE_HEAD`.

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

Works non-interactively. Returns to `originalBranch`. If another conflict occurs, repeat.

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
git rev-parse --git-path gh-stack
```

**Use `--git-path`, not `--git-common-dir`.** State is stored per git-dir, and in a linked
worktree those differ:

```
--git-common-dir : /repo/.git                          -> the main checkout's stack
--git-path       : /repo/.git/worktrees/wt/gh-stack    -> this worktree's stack
```

Both files can exist at once, so `--git-common-dir` does not fail loudly; it silently returns
a different stack. Related paths: `git rev-parse --git-path gh-stack.lock` and
`git rev-parse --git-path gh-stack-rebase-state`.

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
f=$(git rev-parse --git-path gh-stack)

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

# Does this git-dir track any stack at all?
test -f "$f" && jq -e '.stacks | length > 0' "$f" >/dev/null
```

---

## Push atomicity differs between `push` and `sync`

As of v0.1.0 the two commands document different push semantics. Both statements below are
current.

| Command | Documented behaviour |
|---|---|
| `gh stack push` | "Uses explicit per-branch `--force-with-lease` checks. Updates are not atomic: a branch may update even if another branch is rejected. Fix the rejected branch and run the command again; branches already updated will be unchanged." |
| `gh stack sync` | "Pushes all branches atomically (using `--force-with-lease --atomic`)" |

Consequences:

- A failed `gh stack push` can leave the remote **partially updated**. Rerun after fixing the
  rejected branch; branches that already succeeded are unchanged.
- Do not assume a failed `push` left the remote untouched, and do not generalise `sync`'s
  atomicity to `push`.
- `submit` is also documented as not atomic: a later rejected push leaves earlier pushes and
  PR updates in place.
- Both skip merged and queued branches.
- UNVERIFIED: the exact rejection text when a `--force-with-lease` check fails. Reproducing it
  needs a live remote.

---

## Lock contention and exit 8

Mutating commands take an advisory `flock` on a zero-byte lock file beside the state file:

```bash
git rev-parse --git-path gh-stack.lock
```

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
