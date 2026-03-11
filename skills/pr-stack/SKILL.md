---
name: pr-stack
description: PR stacking methodology for breaking features into small, focused PRs using TDD and git-town. Provides vertical slicing philosophy, STACK file format, and branch strategy guidance. Use when (1) discussing PR stacking concepts, (2) someone mentions vertical slicing or TDD workflow, (3) questions about STACK file format, (4) branch strategy decisions (hack vs append). Triggers include "pr stack", "feature stack", "vertical slicing", "STACK file", "stack format", "hack vs append".
---

# PR Stacking Methodology

Core reference for the PR stacking workflow. For active planning or implementation, use the `/pr-stack:plan` or `/pr-stack:implement` commands instead.

## Philosophy

- **Vertical slicing**: Each PR contains BOTH implementation AND tests. Tests must pass. Never split "code PR" + "test PR".
- **Small PRs**: Target <200 lines each (tests + implementation combined). Smaller is better, but 200 is a target, not a hard limit. Keep code together when splitting would be forced or illogical.
- **TDD discipline**: RED (write failing tests) -> GREEN (make pass, commit) -> never commit failing tests.
- **PR creation is immediate**: After committing, IMMEDIATELY run `git town propose`. Never skip this.
- **STACK files stay local**: Never commit STACK-*.md files. Never reference them in commits or PRs.

## Branch Strategy

Use git-town for all branch management:

- **`git town hack [name-N]`**: PR is independent - doesn't need code from previous PRs AND touches different files
- **`git town append [name-N]`**: PR depends on previous - needs code OR modifies same files as previous PRs
- **Default to `append`** when in doubt
- **File conflicts trump code independence**: Even if PR 2 doesn't need PR 1's code, use `append` if they modify the same files
- **Branch names end with numbers**: auth-1, auth-2, auth-3 (single stack) or auth-1.1, auth-1.2 (parallel)

## STACK File Format

See `${CLAUDE_PLUGIN_ROOT}/templates/STACK-EXAMPLE.md` for a complete example.

Required sections:
- **Overview**: 1-2 sentence summary
- **Goals & Success Criteria**: What we're building and how we know it's done
- **Architecture & Design Decisions**: High-level design with SECURITY/DEVOPS/DESIGN inline notes
- **File Existence Validation**: Verified file paths with timestamp
- **PR Breakdown**: Each PR with complexity, dependencies, files, branch command, testing, guidance
- **Implementation Notes**: Gotchas and edge cases

Each PR entry must specify:
- **Code Dependencies**: Does this PR need code from previous PRs?
- **File Dependencies**: Does this PR modify same files as previous PRs?
- **Branch Command**: Explicit `git town hack` or `git town append`

## Workflow Configuration

Each repository needs `.stack-workflow.md` defining quality check commands:

- **Early Iteration Check**: Fast validation during TDD (<10s)
- **Pre-Commit Check**: Comprehensive validation before commits
- **Pre-PR Check**: Optional expensive checks before `git town propose`

Template: `${CLAUDE_PLUGIN_ROOT}/templates/stack-workflow-template.md`

Exclude from git: `echo -e "STACK-*.md\n.stack-workflow.md\n.stack-workspace-checklist.md" >> .git/info/exclude`

## PR Creation Format

Always use `git town propose` (never `gh pr create`):

```bash
git town propose --title "type(scope): description" --body "$(cat <<'EOF'
## Summary
Brief description

### Changes
- Bullet points

### Test Coverage
- Tests added/modified

### Stack Context
**Stack Progress**: X/Y PRs

Generated with Claude Code
EOF
)"
```

## Two-Phase Workflow

1. **Planning** (`/pr-stack:plan`): Analyze feature, consult architects, create STACK file. STOP. /clear.
2. **Implementation** (`/pr-stack:implement`): Read STACK file, execute TDD cycle per PR. Commit + PR after each.
3. **Parallel Setup** (`/pr-stack:setup-parallel`): Optional. Create worktrees and per-agent STACK files for multi-agent execution.

Phases are separate for context management. Planning fills context with architecture discussions. Implementation needs clean context for code and tests.

## Architect Consultation

During planning, consult as needed:
- **design-review-architect**: Architecture and design patterns
- **security-audit-reviewer**: Security implications
- **devops-architect**: Deployment strategy and infrastructure
- **sdet-agent**: Testing strategy for complex features
