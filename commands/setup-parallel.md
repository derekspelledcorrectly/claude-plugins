---
description: Set up parallel execution workspaces with git worktrees for a STACK file
argument-hint: STACK file path or feature name (e.g., "test-hardening" or "STACK-TEST-HARDENING.md")
allowed-tools: Agent, Read, Glob, Grep
---

# Set Up Parallel Execution

Prepare the environment for multiple agents to work on independent portions of a stack simultaneously using git worktrees and per-agent STACK files.

## Instructions

1. If $ARGUMENTS specifies a file path, verify it exists. Otherwise, search for STACK-*.md files in the repo root.

2. Launch the **parallel-setup-agent** agent with the following context:

   **STACK file or feature**: $ARGUMENTS

   The parallel setup agent will:
   - Analyze the STACK file for parallelization metadata (agent assignments, worktree paths)
   - Determine scenario: multiple independent STACK files or single STACK with internal agent assignments
   - Create git worktrees for each agent
   - Split the master STACK file into per-agent STACK files with quickstart sections
   - Symlink ALL agent STACK files to ALL worktrees (write own, read others)
   - Symlink .stack-workflow.md to all worktrees
   - Create a workspace checklist
   - Provide agent assignment guide with ready-to-copy start commands

3. After the agent completes, relay its summary and the start commands to the user.
