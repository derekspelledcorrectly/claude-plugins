# `gh stack` vs git-town vs Graphite

Concept mapping, model differences, and how to coexist with git-town in one repo.

Verified against **gh-stack v0.1.0** and **Git Town 24.0.0** on this machine. **Graphite was
never installed** (`gt` here is a shell alias to `git-town`), so every Graphite cell below is
documentation-only, from graphite.com/docs, and was not confirmed by running anything.

## Concept mapping

"--" means the tool has no equivalent.

| Concept | `gh stack` v0.1.0 | git-town 24 | Graphite (docs only) |
|---|---|---|---|
| Trunk / main | `--base <branch>` on `init`/`link`, defaults to repo default branch; `gh stack trunk` checks it out | `[branches] main` in `.git-town.toml` | configured at `gt init` |
| Stack is a first-class object | **Yes, server-side.** REST `/repos/{owner}/{repo}/stacks`, repo-scoped stack number shown in the UI | **No.** Emergent from parent pointers | Yes, in Graphite's own DB and SaaS |
| Parentage source of truth | `gh-stack` JSON in the git dir **plus** the GitHub stack object | git config `git-town-branch.<name>.parent`, local only | Graphite metadata plus Graphite servers |
| Create a stack | `gh stack init auth api ui` | `git town hack <name>` | `gt create <name>` |
| Create branch on top | `gh stack add api-routes` (only from the top branch, else exit 5) | `git town append <name>` | `gt create <name>` |
| Insert below / add a parent | `gh stack modify` TUI, insert (`i`). **No CLI flag, unusable non-interactively** | `git town prepend <name>` | `gt create` after `gt down`, or `gt move` |
| Restack after trunk moves | `gh stack rebase` (`--downstack`, `--upstack`, `--no-trunk`) | `git town sync`, `git town sync --stack` | `gt restack` |
| Sync with remote | `gh stack sync [--prune]` | `git town sync [-a] [-s] [-p]` | `gt sync` |
| Submit / propose PRs | `gh stack submit --auto [--open]` | `git town propose --title=... --body=... [-s]` | `gt submit [--stack]` |
| Push only, no PR changes | `gh stack push` | -- (closest is `git town sync --push`) | -- (`gt submit` always touches PRs) |
| Land the bottom PR | `gh stack merge --yes [--squash\|--rebase\|--merge]`, or the merge box | `git town ship` (local merge into parent) | `gt merge` |
| Navigate | `up`/`down`/`top`/`bottom` | `up`/`down` (**inverted**, see SKILL.md) | `gt up`/`down`/`top`/`bottom` |
| Interactive picker | `gh stack switch` | `git town switch` | `gt checkout` |
| Reorder branches | `gh stack modify`, `Shift+Up/Down` (TUI only) | `git town swap` (with parent only) | `gt move` |
| Fold into a neighbour | `gh stack modify`, `d`/`u` (TUI only) | `git town combine` | `gt fold` |
| Split a branch | -- | -- | `gt split` (by commit, hunk, or file) |
| Amend into the right commit | -- | -- | `gt absorb` |
| Reparent an arbitrary branch | -- (only `unstack` then `init`) | `git town set-parent [branch]` | `gt move --onto <branch>` |
| Rename in the stack | `gh stack modify`, `r` (TUI only) | `git town rename` | `gt rename` |
| Drop a branch from the stack | `gh stack modify`, `x` (TUI only); or `gh stack unstack [--local]` | `git town detach`, `git town delete` | `gt untrack`, `gt delete` |
| Squash a branch's commits | -- | `git town compress` | `gt squash` |
| View the stack | `gh stack view --json` | `git town branch` | `gt log` |
| Check out by PR number | `gh stack checkout 42` (fetches from GitHub if not tracked locally) | -- | `gt get <branch\|PR>` |
| Adopt externally-managed branches | `gh stack link a b c` | -- | `gt track` |
| Undo the last command | -- (only `rebase --abort`, `modify --abort`) | **`git town undo`**, `git town runlog` | -- |
| Pause a branch from syncing | -- | `git town park`, `observe`, `contribute`, `prototype` | -- |
| Run a command on every branch | -- | `git town walk` | -- |

### Gaps worth internalising

- **`gh stack` has no undo and no runlog.** git-town's `undo`/`runlog` has no counterpart.
  `gh stack`'s safety net is narrower: `rebase --abort` and `modify --abort` restore
  pre-operation state, and `sync` restores all branches when it hits a conflict. Everything
  else is `git reflog`.
- **Restructuring is TUI-only.** `modify` has no non-interactive mode, which makes it
  unusable from an agent session. The scripted substitute is `unstack`, then rename or
  reorder with plain git, then `init` with the new order.
- **No `split` and no `absorb`.** These are Graphite's remaining CLI advantage per its docs.
  They matter mainly when retrofitting a stack onto a finished branch, which `gh stack`
  cannot do at all.
- **No reparenting.** `git town set-parent` has no equivalent. Changing a branch's parent
  means tearing the stack down and recreating it.

## Where the mental models diverge

### Who owns the truth

| Tool | Source of truth | Characteristic failure when truth and reality disagree |
|---|---|---|
| git-town | Local git config parent pointers. Nothing server-side. | The pointer goes stale silently when a parent is rebased, shipped, or renamed. Presents as phantom commits: conflicts in files you never touched, other people's commits appearing in your branch. Fix is `git town set-parent`. |
| Graphite | Graphite's metadata plus its SaaS. GitHub is a rendering target. | Graphite's DB drifts from GitHub; reconciled with `gt track`/`gt sync`. The vendor sits in the critical path. (Documentation-only.) |
| `gh stack` | **Two owners by design.** The `gh-stack` JSON locally, and a real GitHub stack object server-side. | Novel: the local and remote stacks can diverge as first-class objects, and `sync` has an explicit resolution protocol for it. |

### The divergence protocol

Unique to `gh stack`, per `gh stack sync --help`:

- **Remote ahead** (PRs appended to the stack on github.com): branches are pulled down and
  appended to the local stack automatically, no prompt. Safe unattended.
- **Genuine divergence** (a branch added locally while different PRs were added remotely):
  an interactive terminal offers three choices -- take the remote as source of truth, delete
  the stack on GitHub and recreate it later, or cancel.
- **Non-interactive divergence: sync aborts, pushes nothing, and exits 0** with
  `Sync aborted`. A silent no-op that looks like success. Never conclude a sync worked from
  its exit code; re-read `gh stack view --json` and assert the state you expected.

### Phantom commits

The git-town failure mode carries over in kind but is structurally mitigated:

- `rerere` covers repeated conflicts across layers, though `gh stack init` only enables it
  when a human is present (see SKILL.md).
- Squash-merge is handled explicitly with
  `git rebase --onto <squash-sha> <old-tip-sha> <branch>`, both in the CLI and server-side.
  That is exactly the case that generates phantom conflicts, per GitHub's FAQ.
- A conflicting rebase restores every branch to its pre-rebase state rather than leaving a
  half-rebased stack.

Mitigated, not impossible. The old prevention advice still holds: keep stacks shallow, land
the bottom quickly, and diff `git log --oneline main..HEAD` before and after risky syncs.

## The one thing neither competitor can replicate

**Every PR in a stack is evaluated as if it targets the stack base, not its literal base
branch.** From GitHub's stacked-PR FAQ, this applies to:

- required reviews
- required status checks
- CODEOWNERS
- code scanning workflows

So a `CODEOWNERS` change in the bottom PR does not affect the PRs above it in the same stack,
and PR #3 is not protected as though `main` were irrelevant just because its base is PR #2's
branch.

git-town and Graphite both produce ordinary pull requests whose protection resolves against
their literal base branch. Getting stack-base semantics requires the forge to model the stack,
which is precisely what the server-side stack object does. No client-side tool can emulate it.

## Coexisting with git-town in one repo

Supported, in two distinct shapes. Pick based on whether you want local tracking.

### `gh stack link`: GitHub-side stack only, no local tracking

The sanctioned path when another tool owns branch topology. Quoting `gh stack link --help`:

> This command does not rely on gh-stack local tracking state. It is designed for users who
> manage branches with external tools (e.g. jj, Sapling, ghstack, git-town, etc...) and want
> to use GitHub stacked PRs without adopting local tracking.

```bash
# git-town owns local topology
git town hack data-models
git town append api-routes
git town append frontend

# gh stack owns only the GitHub-side stack object
gh stack link data-models api-routes frontend
```

Arguments run bottom to top and may be branch names, PR numbers, or PR URLs. `link` pushes the
branches, creates PRs with correct base chaining (drafts unless `--open`), corrects any PR
whose base does not match the chain, and creates or updates the stack. It is **additive only**;
existing PRs are never removed from a stack. Append later by passing the stack number first:

```bash
gh stack link 42 change4 change5
```

### `gh stack init <branches>`: full local adoption

When you want `rebase`, `sync`, and navigation, adopt the branches into local tracking. The
adoption is positional; existing branches are adopted and missing ones created:

```bash
gh stack init change1 change2 change3   # bottom to top
gh stack submit --auto
```

There is a hidden `--adopt` flag. It is a deprecated no-op that prints a warning and continues
(confirmed in `cmd/init.go`, which marks it hidden). Do not use it; older help text and blog
posts still show it.

### What breaks when both tools own the same branches

| Conflict | What happens |
|---|---|
| Both managing local topology | The parent pointers and the `gh-stack` JSON are independent and neither knows about the other. `git town set-parent` can reparent a branch out from under a stack whose JSON still records the old order. Nothing errors; the stack is just wrong. |
| `git town ship` on a stacked branch | `ship` merges locally into the parent. The GitHub stack expects to land through the merge API or merge box. Shipping out of band leaves the stack holding merged PRs it cannot reconcile. |
| `gh pr merge` on a stacked PR | Does not work. Stacks merge through the async `/pulls/{n}/merge-async` endpoint; the legacy synchronous REST and GraphQL merge APIs do not support stacks. Use `gh stack merge`. |
| `gh stack checkout <pr>` against branches another local stack already tracks | Triggers an unbypassable conflict prompt, which hangs an agent. Run `gh stack unstack --local` first (this keeps the GitHub stack intact), then retry the checkout. |
| A branch belonging to two stacks | Commands exit 6. Check out a non-shared branch first. |
| Reparenting | No `gh stack` equivalent to `git town set-parent`. Requires `unstack` then `init`. |
| Repo without stacks enabled | Exit 9. Non-interactive runs just exit; treat as "this repo cannot stack" and fall back to plain PRs rather than retrying. |

**Rule: one owner of local topology per repo.** Either git-town owns branches and `gh stack`
is used only via `link` for the GitHub-side object, or `gh stack` owns them end to end. Do not
point both at the same branches.

## CI cost management

Because every PR is evaluated as if it targets the stack base, a workflow triggered on
`pull_request` against `main` **runs for every PR in the stack**. A five-layer stack is five
times the CI.

`github.event.pull_request.stack` is available in workflow expressions, and is present only
when the PR belongs to a stack:

| Expression | Meaning |
|---|---|
| `.stack.number` | repo-scoped stack number |
| `.stack.size` | total PRs in the stack |
| `.stack.position` | 1-based position, `1` is the bottom |
| `.stack.base.ref` | branch the whole stack targets |
| `.stack.base.sha` | HEAD SHA of the stack base |

Two gates earn their keep:

```yaml
# Lowest unmerged PR: its direct base equals the stack base
if: github.event.pull_request.stack != null &&
    github.event.pull_request.stack.base.ref == github.event.pull_request.base.ref

# Top PR: carries the full cumulative change
if: github.event.pull_request.stack != null &&
    github.event.pull_request.stack.position == github.event.pull_request.stack.size
```

Usual split: cheap checks (lint, unit) on every layer, expensive ones (e2e, integration,
deploy previews) only on the top PR or only on the lowest unmerged PR. As PRs land, the lowest
unmerged PR changes, so that gate tracks the moving bottom automatically.

**`stack` is absent from `pull_request.opened`.** A PR is always created before it joins a
stack, so any event firing before the join carries no `stack` object. To detect the join,
listen for the `pull_request` event with the **`stacked`** action, which carries the object.

## Landing order and merge strategy

Stacks land **bottom-up and contiguously**. Merging PR #3 also lands #1 and #2. Merging a
middle PR in isolation is impossible; per GitHub's docs, the PRs below it always merge with it.
After a partial merge the lowest unmerged PR is retargeted to the stack base automatically and
a cascading rebase runs across the remainder.

| Method | Effect on the base branch |
|---|---|
| Squash | One squashed commit **per PR**. Merging n PRs creates n commits. Original commits vanish, which would cause artificial rebase conflicts; handled automatically via `git rebase --onto`. |
| Rebase | Commits from each PR replayed onto the base. Linear history, no merge commit, per-commit granularity preserved. |
| Merge commit | **One** merge commit for the entire merged group, with each PR's full history preserved inside it. Coarsest of the three. |

Constraints, all from GitHub's stacked-PR docs and FAQ:

- **A fully linear history between every branch is a strict merge requirement.** When it is
  lost, the merge box shows a "Rebase stack" button that performs a server-side cascading
  rebase and force-push. The CLI equivalent is `gh stack rebase` then `gh stack push`.
- **All PRs below the target must independently pass** required reviews, checks, and rules
  before anything can merge.
- **Direct merge is atomic.** If any part of the group fails, nothing merges.
- **Auto-merge is not supported** for stacked PRs, for direct merges or the queue. Marked
  "coming soon".
- **Bypassing merge requirements is not supported.** Also marked "coming soon". Every PR must
  genuinely satisfy its rules.
- **Merge queue is supported.** All PRs enter together in order and are evaluated
  individually, bottom-up. A PR that fails is ejected along with all of its descendants; PRs
  below it are unaffected. The queue chooses the merge method, so `--squash`, `--rebase`,
  `--merge`, and `--merge-method` are ignored with a warning. A stack exceeding 150% of the
  configured maximum queue size lands across consecutive merge groups, preserving order.
- **A fully merged stack cannot be extended.** `gh stack submit` with new branches on top of
  one automatically starts a new stack rooted at the trunk and leaves the merged stack alone.
- **Closing a mid-stack PR blocks every PR above it** and preserves the stack relationship.
  Recovering means `unstack` and recreate. Prefer dropping the branch via `gh stack modify`
  before closing the PR.
- **`unstack` only removes open, draft, and closed PRs.** Merged and queued PRs stay in the
  stack permanently, so a stack that has landed anything can never be fully dissolved.

## Other documented limits

- Maximum **100 PRs** per stack.
- All branches must be in the **same repository**. Cross-fork stacks are not supported.
- Not available in GitHub Desktop.
- A stack's trunk can be any branch, not just the default branch (`--base` on `init` or
  `link`). Branch protection and CI are evaluated against whatever that trunk is.
