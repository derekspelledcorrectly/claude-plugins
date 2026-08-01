---
name: gh-stack-expert
description: Drive GitHub's native stacked pull requests via the `gh stack` extension (github/gh-stack) from a non-interactive agent session. Use when (1) a repo's PRs are stacked with `gh stack` or the user asks to start, view, extend, rebase, or land one, (2) the user says "gh stack", "gs", "stack this change", "add a layer", or names a stack number or stacked PR, (3) a `gh stack` command failed, hung, or reported a branch is "not part of a stack". Triggers include "gh stack", "gh-stack", "native stacked PRs", "GitHub stacks", "stack view --json", "gh stack rebase". NOT for git-town (use the git-town skill) and NOT for the pr-stack planning plugin.
---

# Driving `gh stack` as an agent

`gh stack` is a **gh extension** (`github/gh-stack`), not part of gh core. Upgrading gh does
not upgrade it. Everything here was verified against **v0.1.0**.

GitHub publishes an exhaustive 891-line official skill for this tool
(`gh skill install github/gh-stack --agent claude-code --scope user`). It is good and it owns
the mechanics. This skill is deliberately smaller and covers what GitHub structurally cannot
know: your machine, your permissions, and a set of behaviours their skill gets wrong.

## First move, always

Never infer stack state. Read it:

```bash
gh stack view --json
```

That is the only machine-readable form and the only one safe to run unattended. For a fuller
picture (parent branch names, position, dirty state, blockers) use the bundled script:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/gh_stack_status.py"
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/gh_stack_status.py" --strict --for rebase
```

## Hard rules

**Never trust exit 0 alone.** An unknown subcommand prints the root help to stdout and exits
**0**. `gh stack bogus` looks exactly like success. Before using any subcommand you are not
certain exists on the installed version, confirm it appears in `gh stack --help`, or check
stdout for the literal `Usage:\n  gh stack [command]`.

**Never `2>&1`, never pipe to `head`/`tail`.** Data goes to stdout, all human-readable status
goes to stderr. Merging them corrupts the JSON; piping loses the exit code.

**Never run these:**

| Command | Why |
|---|---|
| `gh stack view` (bare) | TUI. Hangs forever under a TTY. Always `--json`. (`--short` is safe but human-only, see below.) |
| `gh stack switch`, `gh stack modify` | Require an interactive terminal. They refuse rather than hang, but there is no non-interactive path. |
| `gh stack alias` | Installs a `gs` wrapper that collides with the existing `alias gs='gh stack'`. |
| `gh stack feedback` | Opens a browser. |
| `gh extension install/upgrade` | Denied by permission policy. Upgrading `gh stack` is a user action. |

**Never run these without explicit user approval** (they write to the remote, and the
`Bash(git push:*)` deny rule does not cover them because they are `gh`, not `git`):
`gh stack submit`, `push`, `sync`, `link`, `unstack`, `merge`.

**Sandbox:** `gh` is handled through `sandbox.excludedCommands`. Do not pass
`dangerouslyDisableSandbox` for it. Note that `gh stack`'s local operations (`init`, `add`,
`view --json`, `rebase`, navigation) are fully offline and need no network at all.

## `gh stack merge` is the sharpest edge in the tool

Read this before ever invoking it:

- **No argument merges the entire stack** containing the current branch.
- A bare number is tried as a **stack number first**, then as a PR number.
- Everything below your selection is **always** included. Merging only a middle PR is impossible.
- **There is no dry-run.** No `--dry-run`, no `--preview`, no `-n`. The interactive wizard is
  the only preview, and non-interactive use is precisely what removes it.
- `--yes` is **not** a safety catch. A non-interactive terminal skips the wizard anyway, so
  `--yes` is redundant there.
- With no method flag it uses your **last-used merge method**: sticky, invisible, unknowable.

Treat it exactly like `git push`. When the user asks to land a stack, resolve and echo the
scope (which PRs, which method) and get confirmation, because the command will not ask.

## Worktrees: stack state is private to the git dir

**This is the failure you are most likely to hit and least likely to diagnose.**

`gh stack` stores state in a file named `gh-stack` inside the git dir. In a linked worktree
that is `.git/worktrees/<name>/`, not the shared `.git/`. So a stack created in the main
checkout is invisible from a worktree and vice versa, and the symptom is misleading:

```
$ gh stack view --json     # in a worktree, on a branch that IS in a stack
✗ current branch "feat-one" is not part of a stack     exit=2
```

Two traps around the fix:

- **`git rev-parse --git-path gh-stack` is wrong.** It resolves into the worktree's own
  gitdir, because git redirects only a fixed allowlist of known filenames to the common dir
  and `gh-stack` is not on it. Use `git rev-parse --git-common-dir` explicitly.
- **`GIT_DIR=$(git rev-parse --git-common-dir) gh stack ...` is dangerous.** It reports the
  *primary checkout's* current branch while you sit in the worktree on a different one. An
  agent that "fixes" it this way will operate on the wrong tree.

The correct fix, which the user should run (it writes into `.git/`):

```bash
ln -s "$(git rev-parse --git-common-dir)/gh-stack" "$(git rev-parse --git-dir)/gh-stack"
```

This restores **visibility, not full operability**. Branches checked out in another worktree
still cannot be navigated to (`fatal: 'feat-two' is already used by worktree at ...`).

## The core loop

```bash
gh stack init base-branch next-branch      # positional; existing branches adopted automatically
git config rerere.enabled true             # init does NOT set this non-interactively; see below
gh stack top                               # add only works from the top (exit 5 otherwise)
git add <specific paths> && git commit -m "..."
gh stack add next-layer
```

**`gh stack add -m "msg"` silently no-ops without staged changes.** Exit 1, and the branch is
*not created*. If that error scrolls past, every position assumption afterwards is off by one.
Stage explicitly first, or pass `-A`/`-u` deliberately.

**A dirty working tree is never a gate.** Nothing in `gh stack` refuses one. Uncommitted
changes follow you across `up`/`down`/`checkout`/`add`, and `gh stack rebase` will cascade
across multiple branches with a dirty tree and exit 0. Commit or stash before navigating.

### Review feedback on a mid-stack PR

The fix goes in the branch it belongs to, never patched from above:

```bash
gh stack checkout <branch>     # or gh stack down
# edit, git add, git commit
gh stack rebase --upstack      # replay everything above onto the fix
```

### Navigation, and the git-town inversion

| | toward trunk | away from trunk |
|---|---|---|
| `gh stack` | `down`, `bottom` | `up`, `top` |
| **git-town** | **`up`** | **`down`** |

They are opposite. When the target matters, use `gh stack checkout <branch>` and name it
explicitly rather than counting steps. Merged branches are silently skipped by navigation, so
`up` can jump two positions and step-counting drifts.

## rerere

`gh stack init` prompts to enable `rerere` when a human is present (default yes), and
**silently skips it when run non-interactively**, leaving `rerere.enabled` unset. An
agent-initialized stack therefore has no rerere unless you set it yourself.

It is worth enabling: stacking rebases the same branches over the same conflicts repeatedly,
so one recorded resolution covers the whole stack instead of one hand-resolve per layer.

The hazard is that rerere keys on the **conflict text, not the intent**. Resolve a conflict
wrong once and it is replayed silently at every layer above, with no conflict shown. When a
resolution looks wrong, `git rerere forget <path>`.

## When NOT to stack

Stacking is not free: CI multiplies per layer, review serializes, and merge fates couple. Do
not stack when the change fits in one PR, when the pieces are genuinely independent (use
parallel branches), or when the work spans repos or forks (unsupported).

**Check the repo's own policy first.** Some repos mandate a single branch per task landed via
squash-merge, and explicitly forbid stacking. Read `CLAUDE.md` before starting a stack.

## Version drift

This tool moves fast and its documentation lags in both directions. Check three things when
anything looks wrong:

```bash
gh extension list | grep gh-stack   # installed version
gh stack --help                     # does the subcommand you want actually exist?
```

and, if GitHub's official skill is installed, whether its `metadata.version` matches the
installed extension. It currently pins 0.0.9 while the extension is 0.1.0, so for the first
time the skill describes an *older* version than what is installed. Nothing warns about this.

Known upstream-skill inaccuracies as of extension v0.1.0: it claims `init` auto-enables
`rerere` (it does not), it claims `view --short` is unusable by agents (it exits 0 fine), it
lists exit 7 for "rebase already in progress" (unreachable; the detached-HEAD check returns 2
first), and it misquotes the exit-5 message.

## Reference files

| File | When to read |
|---|---|
| [references/commands.md](references/commands.md) | Full subcommand digest: flags, interactivity, whether it touches the network |
| [references/failure-modes.md](references/failure-modes.md) | Exit codes, rebase-conflict recovery, the JSON schema and its gaps |
| [references/vs-git-town.md](references/vs-git-town.md) | Concept mapping to git-town and Graphite, and how to coexist with git-town in one repo |
