---
description: Plan a new feature as a stack of small, focused PRs using TDD
argument-hint: Feature description (e.g., "OAuth passkey authentication")
allowed-tools: Agent, Read, Glob, Grep
---

# Plan a PR Stack

Plan a feature by breaking it into small, vertically-sliced PRs (<200 lines each) with a TDD-first approach.

## Instructions

1. Launch the **planner-orchestrator** agent with the following context:

   **Feature to plan**: $ARGUMENTS

   The planner agent will:
   - Ask clarifying questions about the feature
   - Ensure .stack-workflow.md exists (creates from template if needed)
   - Sketch architecture and design decisions
   - Consult architect agents (design-review-architect, security-audit-reviewer, devops-architect) as needed
   - Break the feature into small PRs with dependency analysis
   - Write STACK-[FEATURE].md to the repo root
   - Stop and tell the user to /clear before implementation

2. After the agent completes, relay its summary to the user.

**CRITICAL**: The planner must NOT proceed to implementation. Planning and implementation are separate phases for context management.
