# pr-stack Plugin

Plan and implement features as stacks of small, focused PRs using TDD with git-town branch management.

## Commands

| Command | Purpose |
|---------|---------|
| `/pr-stack:plan [feature]` | Plan a feature as a PR stack, creating a STACK-[FEATURE].md file |
| `/pr-stack:implement [stack]` | Implement PRs from an existing STACK file using TDD |
| `/pr-stack:setup-parallel [stack]` | Set up parallel execution workspaces with git worktrees |

## Agents

| Agent | Role | Tools |
|-------|------|-------|
| planner-orchestrator | Read-only planning, architect consultation, STACK file creation | Read-only + web + agents |
| implementation-agent | TDD implementation, commits, PR creation via git-town | Full access |
| parallel-setup-agent | Worktree creation, STACK file splitting, symlink setup | Bash + file ops |

## Typical Workflow

```
/pr-stack:plan OAuth passkey authentication
# Planner creates STACK-AUTH.md, consults architects, stops
/clear
/pr-stack:implement auth stack
# Implementation agent executes TDD cycle per PR
```

## Dependencies

- **git-town**: Required for branch management (`hack`, `append`, `propose`)
- **git-town skill**: Should be installed for implementation agent reference

## Key Principles

- Each PR <200 lines (tests + implementation)
- Vertical slicing: tests + code together, always passing
- TDD: RED (failing tests) -> GREEN (pass) -> commit -> PR
- STACK files never committed to git
- `git town propose` for PRs (never `gh pr create`)
- Planning and implementation in separate context windows
