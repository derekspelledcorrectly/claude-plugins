# STACK-AUTH

## Overview
Implement OAuth 2.0 passkey authentication system as a primary auth method, replacing legacy password-based login while maintaining backward compatibility with existing sessions.

## Goals & Success Criteria
- Users can register and authenticate using WebAuthn/passkeys
- Existing password-based users can migrate seamlessly
- All auth flows maintain <100ms latency at p99
- Zero auth-related security vulnerabilities in QA testing
- Success: OAuth flow passes integration tests, passkey registration/login works end-to-end, migration path exists for legacy users

## Architecture & Design Decisions
- Use WebAuthn API on frontend, FIDO2 server library on backend
- Store passkey credentials in existing user table with new `passkey_credential_id` column
- Session management: existing JWT tokens remain unchanged, add `auth_method` claim to distinguish passkey vs password logins
- SECURITY: Ensure passkey public key verification uses constant-time comparison to prevent timing attacks
- DEVOPS: Add feature flag `enable_passkeys` to allow gradual rollout
- DESIGN: API endpoints: POST /auth/register/passkey, POST /auth/authenticate/passkey, POST /auth/migrate (legacy to passkey)

## Testing Strategy
- Unit tests: passkey credential verification, JWT claim handling
- Integration tests: full WebAuthn registration/auth flow, migration from password
- Security tests: timing attack resistance, invalid credential rejection, session validation
- Load tests: auth endpoint latency under 100ms p99
- See SDET notes in each PR for detailed test cases

## File Existence Validation
**Files verified**: 2025-10-31 14:30

### Existing Files (to be modified)
- ✅ `server/lib/db/models/user.py` (will add passkey_credentials table)
- ✅ `server/lib/auth/jwt.py` (will add auth_method claim)

### New Files (to be created)
- ❌ `server/lib/auth/passkey.py` (NOT FOUND - will create)
- ❌ `server/lib/handlers/auth_passkey.py` (NOT FOUND - will create)

## PR Breakdown

**Status Tracking**: Implementation agents will mark each PR as complete with ✅ COMPLETE, timestamp, and PR URL after submitting for review.

**Example - Before implementation:**
```markdown
### PR 1: Passkey credential storage
```

**Example - After submission:**
```markdown
### PR 1: Passkey credential storage ✅ COMPLETE

**Status**: ✅ Submitted for review on 2025-11-02
**PR URL**: https://github.com/acme/app/pull/456
**Completed by**: Implementation Agent
```

---

### PR 1: Passkey credential storage
**Files**:
  - `server/lib/db/models/user.py` (add passkey_credentials table schema)
  - `server/lib/auth/passkey.py` (NEW - credential verification logic)
  - `tests/unit/auth/test_passkey_verification.py` (NEW)

**Branch Command**: `git town hack auth-passkey-storage-1`
**Base Branch**: `main`
**Complexity**: Small
**Lines**: ~80 (40 implementation + 40 tests)
**Code Dependencies**: None (doesn't need other PR implementations)
**File Dependencies**: None (touches different files than other PRs)

**Testing**: `pytest tests/unit/auth/test_passkey_verification.py`

**Goal**: Add passkey credential storage to user database, implement credential verification logic

**Implementation Guidance**:
  - Add `passkey_credentials` table with user_id FK, credential_id, public_key, sign_count
  - Implement `verify_credential_signature()` function using FIDO2 library
  - Write unit tests for signature verification with valid/invalid inputs
  - SECURITY: Use constant-time comparison for public key verification

### PR 2: WebAuthn registration endpoint
**Files**:
  - `server/lib/handlers/auth_passkey.py` (NEW - registration endpoint)
  - `server/lib/auth/passkey.py` (add challenge generation/validation)
  - `tests/integration/auth/test_passkey_registration.py` (NEW)

**Branch Command**: `git town append auth-passkey-register-2`
**Base Branch**: `auth-passkey-storage-1`
**Complexity**: Medium
**Lines**: ~150 (100 implementation + 50 tests)
**Code Dependencies**: Requires PR 1 (needs credential storage and verification)
**File Dependencies**: YES - modifies `server/lib/auth/passkey.py` (same as PR 1)
**Recommended Branch Strategy**: `git town append` (file conflict + code dependency)

**Testing**: `pytest tests/integration/auth/test_passkey_registration.py`

**Goal**: Implement POST /auth/register/passkey endpoint that creates challenge and accepts credential

**Implementation Guidance**:
  - Create challenge on POST, return to frontend
  - Accept credential from frontend in second request
  - Verify attestation, store credential
  - Return success response
  - DEVOPS: Add feature flag check before allowing registration

### PR 3: WebAuthn authentication endpoint
**Files**:
  - `server/lib/handlers/auth_passkey.py` (add authentication endpoint)
  - `server/lib/auth/jwt.py` (add auth_method claim support)
  - `tests/integration/auth/test_passkey_authentication.py` (NEW)

**Branch Command**: `git town append auth-passkey-auth-3`
**Base Branch**: `auth-passkey-register-2`
**Complexity**: Medium
**Lines**: ~120 (80 implementation + 40 tests)
**Code Dependencies**: None (doesn't need PR 2's registration code)
**File Dependencies**: YES - modifies `server/lib/handlers/auth_passkey.py` (same as PR 2)
**Recommended Branch Strategy**: `git town append` (file conflict, even though no code dependency)

**Testing**: `pytest tests/integration/auth/test_passkey_authentication.py`

**Goal**: Implement POST /auth/authenticate/passkey endpoint with assertion verification

**Implementation Guidance**:
  - Create assertion challenge on initial request
  - Accept assertion response, verify with stored credential
  - Generate JWT with `auth_method: "passkey"` claim
  - Return token and user info
  - SECURITY: Rate-limit failed attempts to prevent brute force

### PR 4: Legacy password migration endpoint
**Files**:
  - `server/lib/handlers/auth_passkey.py` (add migration endpoint)
  - `tests/integration/auth/test_passkey_migration.py` (NEW)

**Branch Command**: `git town append auth-passkey-migrate-4`
**Base Branch**: `auth-passkey-auth-3`
**Complexity**: Medium
**Lines**: ~90 (60 implementation + 30 tests)
**Code Dependencies**: Requires PR 2 (needs registration flow for adding passkey)
**File Dependencies**: YES - modifies `server/lib/handlers/auth_passkey.py` (same as PR 2 and 3)
**Recommended Branch Strategy**: `git town append` (file conflict + code dependency)

**Testing**: `pytest tests/integration/auth/test_passkey_migration.py`

**Goal**: POST /auth/migrate endpoint allows password-authenticated users to add passkey without re-auth

**Implementation Guidance**:
  - Verify existing JWT has valid session
  - Create passkey registration challenge
  - Link new passkey to existing user
  - Optional: mark password as deprecated
  - DESIGN: Consider one-time migration vs. allowing multiple passkeys

### Example: Repetitive Migration PR (from your test hardening work)

This example shows how to document a PR with repetitive transformations:

#### PR 5: Migrate repository tests to transaction pattern
**Files**:
  - `server/lib/db/repositories/hand-fingerprint-repository.integration.test.ts` (15 test cases)
  - `server/lib/db/repositories/game-repository.integration.test.ts` (8 test cases)

**Branch Command**: `git town hack repository-transaction-migration`
**Base Branch**: `main`
**Complexity**: Low (repetitive transformation)
**Lines**: ~120 (60 per file)
**Dependencies**: Requires transaction helper from previous PR

**Testing**: `deno task test:integration`

**Goal**: Wrap all repository integration tests in withTestTransaction for proper isolation

**Implementation Pattern**: Repetitive transformation across 23 test cases total
- Use batched edits (3-4 Edit calls per message) for efficiency
- Pattern: wrap each test's `async () => {}` with `await withTestTransaction(async () => {})`
- Remove manual cleanup code (DELETE statements, repository.clear() calls)
- **Bonus improvements**: Update assertions from `>= N` to `=== N` where transaction isolation allows exact counts

**Todo Structure**:
```
✅ Migrate hand-fingerprint-repository.integration.test.ts (15 test cases)
⏳ Migrate game-repository.integration.test.ts (8 test cases)
⏳ Run integration tests
⏳ Commit changes
```

NOT 23 separate todos for each test case.

### Example: File Conflicts Without Code Dependencies (CI Optimization)

This is the scenario that caused the CI workflow issue. All 3 PRs are logically independent but modify the same files:

#### PR 6: Quick CI wins (caching, parallelization)
**Files**:
  - `.github/workflows/ci.yml` (add caching steps)
  - `.github/workflows/test.yml` (enable parallel test execution)

**Branch Command**: `git town hack ci-quick-wins`
**Base Branch**: `main`
**Complexity**: Small
**Lines**: ~40 (configuration changes only)
**Code Dependencies**: None (doesn't need other PR implementations)
**File Dependencies**: None (first PR in stack)
**Recommended Branch Strategy**: `git town hack` (first PR, no dependencies)

**Testing**: Run CI workflow manually to verify caching works

**Goal**: Add dependency caching and parallel test execution for faster CI

#### PR 7: Enhanced caching strategies
**Files**:
  - `.github/workflows/ci.yml` (add more sophisticated caching)
  - `.github/workflows/test.yml` (cache test fixtures)

**Branch Command**: `git town append ci-caching`
**Base Branch**: `ci-quick-wins`
**Complexity**: Small
**Lines**: ~50 (configuration changes)
**Code Dependencies**: None (doesn't use PR 6's code)
**File Dependencies**: YES - modifies `.github/workflows/ci.yml` and `.github/workflows/test.yml` (same as PR 6)
**Recommended Branch Strategy**: `git town append` (file conflict, even with no code dependency)

**Testing**: Run CI workflow, verify enhanced caching reduces build time

**Goal**: Layer additional caching strategies on top of basic caching

**CRITICAL NOTE**: Even though this PR doesn't need PR 6's code to function, we MUST use `append` because both PRs modify the same workflow files. Using `hack` would create merge conflicts when trying to merge both PRs.

#### PR 8: Database optimization for CI
**Files**:
  - `.github/workflows/ci.yml` (add database setup optimization)
  - `.github/workflows/test.yml` (optimize test database creation)

**Branch Command**: `git town append ci-db-optimization`
**Base Branch**: `ci-caching`
**Complexity**: Small
**Lines**: ~45 (configuration changes)
**Code Dependencies**: None (doesn't use PR 6 or 7's code)
**File Dependencies**: YES - modifies `.github/workflows/ci.yml` and `.github/workflows/test.yml` (same as PR 6 and 7)
**Recommended Branch Strategy**: `git town append` (file conflict with previous PRs)

**Testing**: Run CI workflow with database tests, verify faster database setup

**Goal**: Optimize database setup during CI runs

**CRITICAL NOTE**: All three PRs are logically independent (no code dependencies), but they ALL modify the same workflow files. This is the classic case where the planner might say "independent, branches from main" but file conflicts require stacking with `append`. The implementation agent should detect this and override to use `append`.

## Implementation Notes
- WebAuthn spec is complex; use well-tested FIDO2 library (e.g., py_webauthn for Python, webauthn-rs for Rust)
- Challenge must be cryptographically secure random and invalidated after use
- Frontend will be handled separately (out of scope for this stack)
- Backward compatibility is critical: never remove password auth in this stack, only add passkey path
- Test with real authenticators if possible (security team has USB keys available)
- **For migration-style PRs**: Look for opportunities to improve code during transformation (better assertions, cleaner patterns, updated comments)

## Workspace Setup (for parallel execution)

**Execution Model**: Sequential (single agent)
**Worktree Prefix**: N/A - single stack, no parallelization needed

This stack executes sequentially with no parallel agents. For an example of parallel execution with multiple agents working on sub-stacks, see the workspace setup orchestrator documentation.

### When to Add Parallel Execution Metadata

Include this section when your STACK file describes a large feature that can be split across multiple agents working in parallel worktrees. For example:

- Large refactors touching different subsystems (data layer, API layer, client)
- Test infrastructure buildout across multiple domains
- Multiple independent feature implementations under one umbrella

If adding parallel execution, include:

**Execution Model**: [3-Agent Parallel / 5-Agent Parallel / Custom]
**Worktree Prefix**: `projectname` (or use short project abbreviation)

**Naming Convention**: Use agent-based names for clarity and brevity:
- Pattern: `<project-prefix>-<agent-name>`
- Examples: `myapp-alpha`, `proj-beta`, `api-gamma`
- Benefits: Shorter names, clear agent assignment, easier to reference

### Agent Assignments (Example Format)

**Agent Alpha - Data Layer Specialist**:
- **Worktree**: `../projectname-alpha`
- **Stacks**: Stack 1 (Transaction Migration), Stack 2 (Repository Tests)
- **Timeline**: Weeks 1-6
- **Dependencies**: None (can start immediately)
- **Blocks**: Agent Delta cannot start Stack 4 until Stack 2 completes
- **Starting PR**: PR 1.1 - Migrate hand-repository tests to transaction pattern
- **Key Files**: `server/lib/db/repositories/*.integration.test.ts`
- **Gold Standards**: `server/lib/db/repositories/hand-repository.integration.test.ts`

**Agent Beta - API Layer Specialist**:
- **Worktree**: `../projectname-beta`
- **Stacks**: Stack 11 (Test Pattern Helpers), Stack 3 (Handler Tests)
- **Timeline**: Weeks 1-5
- **Dependencies**: Stack 1 must complete before starting Stack 3
- **Blocks**: Agent Epsilon cannot start Stack 6 until Stack 3 completes
- **Starting PR**: PR 11.1 - Add test helper for common database setup scenarios
- **Key Files**: `server/lib/handlers/*.integration.test.ts`, `server/tests/helpers/*.ts`
- **Gold Standards**: `server/lib/handlers/api-contracts.integration.test.ts`

**Agent Gamma - Client & Services Specialist**:
- **Worktree**: `../projectname-gamma`
- **Stacks**: Stack 7 (Client Tests), Stack 4 (Service Tests)
- **Timeline**: Weeks 1-5
- **Dependencies**: Stack 2 must complete before starting Stack 4
- **Blocks**: None
- **Starting PR**: PR 7.1 - Add test infrastructure for client islands
- **Key Files**: `client/islands/*.test.ts`, `server/lib/services/*.test.ts`
- **Gold Standards**: `server/lib/services/session/game-session-manager.test.ts`

### Coordination Strategy

**Daily Standup** (5 minutes):
- "I'm on Stack X, PR Y, blocked/not blocked"
- Flag any unexpected dependencies or file conflicts

**Handoff Points**:
- When Stack 1 completes, notify Agents Beta and Delta
- When Stack 2 completes, notify Agent Gamma
- When Stack 3 completes, notify Agent Epsilon

**Merge Strategy**:
- Each agent merges PRs to main as they complete
- Other agents pull from main daily
- Use git-town for stack management within each worktree

### Worktree Setup Commands

```bash
# Agent Alpha
git worktree add ../projectname-alpha main
cd ../projectname-alpha
git town hack transaction-migration-1

# Agent Beta
git worktree add ../projectname-beta main
cd ../projectname-beta
git town hack test-pattern-helpers-1

# Agent Gamma
git worktree add ../projectname-gamma main
cd ../projectname-gamma
git town hack client-tests-1
```

### Symlink Setup

Per-agent STACK files (with quickstart info at the top) and workflow should be symlinked to all worktrees:

```bash
# From main repo - symlink ALL agent STACK files to ALL worktrees
# Each agent has their own STACK file with quickstart section at the top

# Agent Alpha worktree gets all agent STACK files:
ln -s /absolute/path/to/main-repo/STACK-[NAME]-ALPHA.md /absolute/path/to/projectname-alpha/STACK-[NAME]-ALPHA.md
ln -s /absolute/path/to/main-repo/STACK-[NAME]-BETA.md /absolute/path/to/projectname-alpha/STACK-[NAME]-BETA.md
ln -s /absolute/path/to/main-repo/STACK-[NAME]-GAMMA.md /absolute/path/to/projectname-alpha/STACK-[NAME]-GAMMA.md
ln -s /absolute/path/to/main-repo/.stack-workflow.md /absolute/path/to/projectname-alpha/.stack-workflow.md

# Repeat pattern for Beta and Gamma worktrees
```

Verify with:
```bash
ls -l ../projectname-*/STACK-*.md
# Should show ALL agent STACK files symlinked to each worktree
# Agent Alpha writes to STACK-[NAME]-ALPHA.md, can read others for coordination
```

---

## Implementation Workflow Notes

### Starting a New PR

When the user says "ready for the next PR, N", the implementation agent should:

1. Read STACK.md and identify PR N
2. Validate file existence before starting
3. Report to user:
   ```
   PR 1.2: Migrate hand-fingerprint-repository tests
   - File: server/lib/db/repositories/hand-fingerprint-repository.integration.test.ts ✅ EXISTS
   - Branch: git town append transaction-migration-2
   - Complexity: Low (~50 lines)
   Ready to proceed?
   ```
4. If files missing: Ask user how to proceed (skip, adjust plan, create files first)

### Reality Check Protocol

If STACK.md lists files that don't exist:
- **DON'T** proceed with assumptions
- **DO** report the mismatch immediately
- **DO** ask the user for clarification
- **DO** offer to adjust the STACK plan

Example:
```
Girl, I found an issue. STACK.md says PR 1.2 should migrate these files:
- ❌ user-repository.test.ts (NOT FOUND)
- ❌ game-repository.test.ts (NOT FOUND)

But I actually found:
- ✅ hand-fingerprint-repository.integration.test.ts
- ✅ game-repository.integration.test.ts

Should I:
1. Update STACK.md to match reality
2. Skip this PR
3. Something else?
```

### Velocity Tips

- **Batch similar edits**: For repetitive transformations, use 3-4 Edit calls in parallel
- **High-level todos**: Track per-file, not per-change for migrations
- **Improve as you go**: Migrations are opportunities for quality improvements
- **Report patterns**: Tell user what transformation you're applying for consistency
