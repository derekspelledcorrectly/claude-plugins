# gh-stack Plugin

Drive GitHub's native stacked pull requests (the `github/gh-stack` gh extension) from a
non-interactive agent session.

## Commands

| Command | Purpose |
|---------|---------|
| `/gh-stack:status [operation]` | Show the stack, PR state, and anything blocking the next operation |
| `/gh-stack:doctor` | Diagnose the environment: extension version, worktree visibility, remotes, rerere, skill drift |
| `/gh-stack:submit [flags]` | Preflight, show the resolved PR plan, get approval, then submit |

## Skill

`gh-stack-expert` covers the operational core plus the things GitHub's own skill cannot
know: worktree-private state, the permission wall around pushing, the sandbox rule, the
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
- **Heads.** The `head` key is `omitempty` and, as of v0.1.0, is not emitted at all. The
  script resolves heads with `git rev-parse` instead of trusting the key.
- **Identity.** Sitting on trunk is a valid state in which no branch reports `isCurrent`.
  Off-stack and detached HEAD both exit 2 with different messages.
- **Visibility.** In a linked worktree, `gh stack view --json` exits 2 claiming the branch
  is not part of a stack. The script falls back to the state file in the *common* git dir
  and reports the whole stack correctly, plus the fix.
- **Safety.** Nothing in `gh stack` refuses a dirty working tree.

## Relationship to GitHub's official skill

GitHub publishes an exhaustive 891-line skill for this tool:

```bash
gh skill install github/gh-stack --agent claude-code --scope user
```

It is good and it owns the mechanics. This plugin does not vendor it, because a frozen copy
inherits upstream's bugs permanently: a fork taken shortly before extension v0.1.0 would
still be insisting `gh stack merge` does not exist. This plugin's skill stands alone but
stays deliberately smaller, and documents where upstream is currently wrong.

## Dependencies

- `gh` with the `github/gh-stack` extension. Verified against **v0.1.0**.
- Python 3 (stdlib only).
- `gh extension upgrade stack` is a **user** action; agents cannot install extensions here.

## Key principles

- Always `gh stack view --json`. Bare `gh stack view` is a TUI and hangs under a TTY.
- Never trust exit 0 alone: an unknown subcommand prints the root help and exits 0.
- Never `2>&1`. Data goes to stdout, status to stderr.
- `submit`, `push`, `sync`, `link`, `unstack`, and `merge` write to the remote and require
  explicit user approval. The `git push` deny rule does not cover them, because they are
  `gh`, not `git`.
- `gh stack merge` with no argument merges the entire stack, has no dry-run, and uses your
  last-used merge method. Treat it like `git push`.
- Agents never restructure a stack. `modify` and `switch` need a TTY; hand those to a human.
