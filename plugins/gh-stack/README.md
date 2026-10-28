# gh-stack Plugin

Drive GitHub's native stacked pull requests (the `github/gh-stack` gh extension) from a
non-interactive agent session.

## Commands

| Command | Purpose |
|---------|---------|
| `/gh-stack:status [operation]` | Show the stack, PR state, and anything blocking the next operation |
| `/gh-stack:doctor` | Diagnose the environment: extension version, worktree state, remotes, rerere, skill drift |
| `/gh-stack:submit [flags]` | Preflight, resolve the PR plan, and hand you the exact submit command to run |

## Skill

`gh-stack-expert` covers the operational core plus the things GitHub's own skill cannot
know: worktree behavior, the permission wall around pushing, the sandbox rule, the
never-run list, and version drift.

## Script

`scripts/gh_stack_status.py` emits the stack as JSON, and with `--strict --for <op>` becomes
a gate. Read-only; it never writes to the stack state, the lock, or the index.

```bash
python3 scripts/gh_stack_status.py                      # JSON
python3 scripts/gh_stack_status.py --text               # human-readable
python3 scripts/gh_stack_status.py --no-prs             # offline, topology only
python3 scripts/gh_stack_status.py --strict --for rebase  # exit 2 if blocked
```

It exists because `gh stack view --json` cannot answer several questions an agent must
answer before acting:

- **Parentage.** `base` is a commit SHA, not a branch name. The parent is recoverable only
  from array order, which is the reverse of the order `--short` prints.
- **Heads.** The `head` key is `omitempty`. It is absent after `init` and `add` until a
  rebase records it. The script resolves heads with `git rev-parse` instead of trusting
  the key.
- **Identity.** Sitting on trunk is a valid state in which no branch reports `isCurrent`.
  Off-stack and detached HEAD both exit 2 with different messages.
- **Ambiguity.** On a trunk shared by two stacks, `gh stack view --json` exits 6 and names
  neither. The script reads the state file in the *common* git dir and names the
  candidate stacks in its error.
- **Safety.** `gh stack rebase` refuses a dirty tree only when it runs, and navigation
  does not check at all. A rebase stopped in another worktree is invisible to
  `view --json`. The script reports both as blockers before you act. It checks
  dirtiness in the current worktree only; gh still refuses a dirty one elsewhere.

## Relationship to GitHub's official skill

GitHub publishes an official skill for this tool:

```bash
gh skill install github/gh-stack --agent claude-code --scope user
```

It is good and it owns the mechanics. This plugin does not vendor it, because a frozen copy
inherits upstream's bugs permanently: a fork taken shortly before extension v0.1.0 would
still be insisting `gh stack merge` does not exist. This plugin's skill stands alone but
stays deliberately smaller, and documents where upstream is currently wrong.

## Dependencies

- `gh` with the `github/gh-stack` extension. Verified against **v0.3.0**. Worktree support
  needs v0.2.0 or later and Git 2.36 or later.
- Python 3 (stdlib only).
- `gh extension upgrade stack` is a **user** action; agents cannot install extensions here.

## Key principles

- Always `gh stack view --json`. Bare `gh stack view` is a TUI and hangs under a TTY.
- Never trust exit 0 alone: an unknown subcommand prints the root help and exits 0.
- Never `2>&1`. Data goes to stdout, status to stderr.
- `submit`, `push`, `sync`, `link`, `unstack`, and `merge` all push code to GitHub or change
  state there. **Agents never run them.** The plugin prepares the command and hands it to the
  user. Note the `git push` deny rule does not cover them, because they are `gh`, not `git`,
  so they need their own deny entries.
- `gh stack merge` with no argument merges the entire stack, has no dry-run of any kind, and
  uses your last-used merge method. `--yes` is not a safety catch: non-interactive callers
  skip the confirmation wizard regardless.
- Agents never restructure a stack. `modify` and `switch` need a TTY; hand those to a human.
