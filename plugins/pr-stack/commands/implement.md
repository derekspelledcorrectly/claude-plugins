---
description: Implement PRs from an existing STACK file using TDD
argument-hint: STACK file path or feature name (e.g., "auth stack" or "STACK-AUTH.md")
allowed-tools: Glob, Grep, LS, Read, Edit, Write, Bash, BashOutput, KillBash, TodoWrite, WebFetch, WebSearch, Skill
---

# Implement a PR Stack

Execute a STACK-[FEATURE].md file ONE PR AT A TIME using strict Test-Driven Development.

## Startup

1. If $ARGUMENTS specifies a file path, verify it exists. Otherwise, search for STACK-*.md files in the repo root (`ls STACK-*.md`) and let the user choose.
2. Read the STACK file and determine which PR to work on (first incomplete PR, or the one the user specified).
3. Check for .stack-workflow.md in repo root.
4. Check current git branch and status with `git branch --show-current` and `git status`.
5. Begin Phase 1 for the target PR.

## Git Town Sandbox Rule

All `git town` commands (`hack`, `append`, `propose`, `sync`, `undo`, etc.) MUST be run with `dangerouslyDisableSandbox: true` on the Bash tool. They require filesystem and network access beyond the default sandbox permissions. The user will be prompted to approve each one.

## The #1 Rule

**EVERY PR must go through ALL phases in order. No skipping. No combining. No moving to the next PR until the current one is fully committed, proposed, and marked complete.**

Writing code is only HALF the work. The commit/test/propose cycle is the other half. Both halves are mandatory.

## PR Lifecycle (Strict Sequential Pipeline)

Each PR goes through exactly 6 phases. You MUST complete each phase before starting the next. You MUST complete ALL 6 phases before starting the next PR.

### Phase 1: SETUP

1. Read the STACK file and identify the current PR
2. Extract: goal, files, dependencies, branch command, base branch, testing focus
3. Create the branch:
   a. **Check the base branch.** The STACK file specifies a Base Branch for each PR. For `git town append`, you MUST be on the base branch first because append creates a child of the current branch. For `git town hack`, you can be on any branch.
   b. If you are not on the correct base branch, run `git checkout <base-branch>` before the branch command.
   c. Run the branch command from the STACK file (e.g., `git town hack auth-1` or `git town append auth-2`).
   d. **Verify the branch was created.** Run `git branch --show-current` to confirm you are on the new branch. Do NOT rely on the branch command's stdout/stderr to determine success -- git-town outputs informational messages that are not errors. The branch command succeeded if and only if `git branch --show-current` returns the expected branch name.
   e. If the branch already exists (you are resuming), just check it out.
4. Read .stack-workflow.md if it exists (for quality check commands). If the file does not exist, skip all quality check steps in Phases 4 and 5 -- just run tests directly instead.

### Phase 2: RED (Write Failing Tests)

1. Write tests for the behavior described in the PR's testing section
2. Run the tests. They MUST fail (the code doesn't exist yet)
3. If tests pass, something is wrong -- investigate before proceeding

**DO NOT commit. DO NOT move to Phase 3 until tests exist and fail.**

### Phase 3: GREEN (Implement)

1. Write the minimum code to make the tests pass
2. Run the tests. They MUST pass
3. If tests fail, fix the implementation until they pass

**DO NOT commit yet. DO NOT move to the review gate until tests pass.**

### Review Gate (between Phase 3 and Phase 4)

**MANDATORY**: After tests pass, you MUST pause and present your changes to the user for review. Do NOT proceed to Phase 4 until the user explicitly approves.

**Present the following:**
1. A summary of what you implemented and why
2. List of files created or modified (with line counts)
3. Test results (number of tests, all passing)
4. Quality check results if .stack-workflow.md exists (formatting, linting, typecheck)
5. Ask: "Ready to commit, or do you want changes?"

**Handle feedback:**
- If the user approves (e.g., "y", "go", "lgtm", "ship it"), proceed to Phase 4
- If the user requests changes, make them, re-run tests and quality checks, and present again
- NEVER commit, push, or propose without explicit user approval

**HARD GATE: DO NOT proceed to Phase 4 until the user has explicitly approved.**

### Phase 4: COMMIT

This phase has 3 mandatory steps. Do all 3, in order.

**Step 1: Quality Check**
If .stack-workflow.md exists, run its Pre-Commit Check commands. If it does not exist, just run the project's tests. If checks fail, fix the issues and re-run until they pass.

**Step 2: Stage and Commit**
- ALWAYS stage and commit in a SINGLE Bash command using `&&`:
  `git add file1 file2 ... && git commit -m "message"`
- NEVER run `git add` and `git commit` as separate Bash calls (this causes a race condition on index.lock)
- Never stage STACK-*.md files
- Never reference STACK files in commit messages

**Step 3: Verify**
Run `git log --oneline -1` to confirm the commit was created.

**HARD GATE: DO NOT proceed to Phase 5 until the commit exists. If the commit failed (e.g., pre-commit hook), fix the issue and commit again. Do NOT skip ahead.**

### Phase 5: PROPOSE

This phase creates the PR. It is MANDATORY. Never skip it.

**Step 1: Pre-PR Check (optional)**
If .stack-workflow.md exists and has a Pre-PR Check section, run those commands. Otherwise skip this step.

**Step 2: Create the PR**
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
- This PR: [description]
- Next: [next PR]

Generated with Claude Code
EOF
)"
```

Both `--title` and `--body` are required. Never use `gh pr create`.

**Step 3: Verify**
Confirm the command succeeded. Note the PR URL from the output.

**HARD GATE: DO NOT proceed to Phase 6 until `git town propose` has succeeded and you have a PR URL. If it failed, diagnose and retry.**

### Phase 6: COMPLETE

**Step 1: Update STACK file**
Mark the PR complete in the STACK file:
```markdown
### PR X: [Title] COMPLETE

**Status**: Submitted for review on YYYY-MM-DD
**PR URL**: [URL from Phase 5]
**Completed by**: Implementation Agent
```

**Step 2: Report to user**
Tell the user: the PR number, title, URL, and what's next in the stack.

**Step 3: Check for more PRs**
- If more PRs remain: start Phase 1 for the next PR
- If no more PRs: summarize the full stack and stop

---

## Branch Strategy

- `git town hack [name-N]`: PR is independent (no code or file deps on previous PRs). Can run from any branch.
- `git town append [name-N]`: PR depends on previous (code deps OR same files modified). MUST be on the parent branch first.
- Branch names MUST end with numbers: auth-1, auth-2, auth-3
- Parallel stacks use dotted numbers: auth-1.1, auth-1.2

## NEVER Undo Without Verification

- Do NOT run `git town undo` unless you have concrete evidence the command failed (e.g., `git branch --show-current` returns the wrong branch, or an actual error exit code).
- git-town outputs informational/progress messages to stderr. This is normal, not an error.
- If you are unsure whether a command succeeded, verify with `git branch --show-current` and `git config --get git-town-branch.<branch>.parent` before taking any corrective action.

## STACK Files

- Never commit STACK-*.md files
- Never reference them in commit messages or PR bodies
- Use `ls` or `ls -la` to find them (NOT `ls -f`)

## Resuming Mid-Stack

If user says "continue the auth stack, PR 3":
1. Find the STACK file
2. Check which PRs are marked COMPLETE
3. Verify current git branch
4. Begin Phase 1 for the specified PR

## Reality Check

If the STACK file lists files that don't exist:
- STOP. Report the mismatch
- Ask the user how to proceed
- Do not guess or improvise
