---
name: gh-stack-expert
description: Drive GitHub's native stacked pull requests via the `gh stack` extension (github/gh-stack) from a non-interactive agent session. Use when (1) a repo's PRs are stacked with `gh stack` or the user asks to start, view, extend, rebase, or land one, (2) the user says "gh stack", "gs", "stack this change", "add a layer", or names a stack number or stacked PR, (3) a `gh stack` command failed, hung, or reported a branch is "not part of a stack". Triggers include "gh stack", "gh-stack", "native stacked PRs", "GitHub stacks", "stack view --json", "gh stack rebase". NOT for git-town (use the git-town skill) and NOT for the pr-stack planning plugin.
---

# Driving `gh stack` as an agent

`gh stack` is a **gh extension** (`github/gh-stack`), not part of gh core. Upgrading gh does
not upgrade it. Everything here was verified against **v0.1.0**. The worktree behavior, the
dirty-tree rule, the exit-0 and `add -m` rules, and the rerere notes were re-verified on
**v0.3.0**. The base-change and upgrade-notifier rules come from the v0.3.0 `--help` and
release notes, and were not reproduced.

GitHub publishes an official skill for this tool, a compact core plus references
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

**Never run these at all. They are the user's to run, not yours:**

`gh stack submit`, `push`, `sync`, `link`, `unstack`, `merge`.

Every one of them either pushes code to GitHub or changes state there. Note that the
`Bash(git push:*)` deny rule does **not** cover them, because they are `gh`, not `git`; they
need their own deny entries, and on this machine they have them. Do not read a denial as a
prompt to rephrase the command, split it, or route around it with `gh api`.

When one of these is the right next step, do the preparation and then hand it over: resolve
exactly what would happen, print the precise command, and let the user run it. Everything up
to the remote write is yours; the remote write is theirs.

**Never pass `--accept-base-change`.** When GitHub retargets a stack because its base branch
was deleted, `rebase` and `sync` follow the new base. If the old base never merged, following
it drops that base's commits from every branch, and the flag skips the confirmation. If a
rebase reports a base change, stop and tell the user which base moved and whether it merged.

**Sandbox:** `gh` is handled through `sandbox.excludedCommands`. Do not pass
`dangerouslyDisableSandbox` for it. Note that `gh stack`'s local operations (`init`, `add`,
`view --json`, `rebase --no-trunk`, navigation) are fully offline and need no network at all.

Since v0.2.0 every `gh stack` call can start a background upgrade check against GitHub, at
most once a day. It never changes stdout or exit codes. Set `GH_STACK_NO_UPDATE_NOTIFIER=1`
to stop it, for example in a sandboxed command that has no network.

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

## Worktrees

Since v0.2.0 all stack state lives in the **common** git dir, and every worktree shares it.
A stack created in one checkout is visible from all of them, and `view --json` works from
any linked worktree. `rebase`, `sync`, and `modify` run each branch's change in the
checkout that holds that branch.

- **Never symlink `gh-stack` into a worktree's private git dir.** Older guidance said to do
  this. On v0.2.0 and later, the symlink breaks `gh stack` in that worktree.
- **Never use `GIT_DIR=... gh stack`.** It reports the primary checkout's current branch
  while you sit in a different worktree.
- **To read the state file directly, use `git rev-parse --git-common-dir`.** Do not use
  `--git-path gh-stack`. It resolves into the worktree's private git dir, where nothing is.
- **A branch checked out in another worktree cannot be navigated to.** `gh stack bottom`
  exits **5** with `Branch "<b>" is already checked out in another worktree` and prints a
  `cd <path>` hint, and your checkout does not change. Expect the same from the other
  navigation commands. `gh stack checkout <target> --print-path` prints that path without
  moving.
- **A rebase conflict lands in the worktree that holds the branch.** It is not necessarily
  your worktree. stderr names it on a `Conflict worktree: <path>` line. Resolve and stage
  in that worktree. `--continue` and `--abort` work from any worktree.
- **During that conflict, `view --json` from another worktree exits 0 and looks normal.**
  Only the conflicted worktree fails. Check for
  `"$(git rev-parse --git-common-dir)/gh-stack-rebase-state"` before you start a rebase.
- gh-stack never creates, removes, or stashes worktrees. Cross-worktree operations require
  Git 2.36 or later.

## The core loop

```bash
gh stack init base-branch next-branch      # positional; existing branches adopted automatically
gh stack top                               # add only works from the top (exit 5 otherwise)
git add <specific paths> && git commit -m "..."
gh stack add next-layer
```

**`gh stack add -m "msg"` silently no-ops without staged changes.** Exit 1, and the branch is
*not created*. If that error scrolls past, every position assumption afterwards is off by one.
Stage explicitly first, or pass `-A`/`-u` deliberately.

**A dirty working tree gates only `rebase`.** Since v0.3.0 `gh stack rebase` refuses any
modified, staged, or untracked file in every worktree it touches, with exit 1. Nothing
else checks. Uncommitted changes follow you across `up`/`down`/`checkout`/`add`, unless
git refuses the checkout because a change would be overwritten. Commit or stash before
navigating.

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

`gh stack init` prompts to enable `rerere` when a human is present (default yes). Without a
terminal it **skips the prompt**. It does not change or override existing config, and the
user's global config often already sets `rerere.enabled=true`.

Read the effective value before you say anything. With no scope flag, this command resolves
system, global, and local config:

```bash
git config --get rerere.enabled
```

If it prints `true`, say nothing about rerere. If it is unset or `false`, tell the user once
and suggest `git config --global rerere.enabled true` for them to run. **Never write
`.git/config` to enable it.** The sandbox blocks the write, and a repo-local value hides the
user's real preference.

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
installed extension. The v0.3.0 release ships a skill that pins 0.2.0, so it describes an
older version than what is installed. Nothing warns about this.

Known upstream-skill inaccuracies as of extension v0.3.0: it claims `init` enables `rerere`
(without a terminal it does not, though the user's global config often does), and it quotes
the exit-5 message as "on top of the stack" (the binary says "to the top"). Its exit 7 for
"rebase already in progress" is accurate only from a worktree other than the conflicted
one. In the conflicted worktree, `rebase` returns 2.

## Reference files

| File | When to read |
|---|---|
| [references/commands.md](references/commands.md) | Full subcommand digest: flags, interactivity, whether it touches the network |
| [references/failure-modes.md](references/failure-modes.md) | Exit codes, rebase-conflict recovery, the JSON schema and its gaps |
| [references/vs-git-town.md](references/vs-git-town.md) | Concept mapping to git-town and Graphite, and how to coexist with git-town in one repo |
