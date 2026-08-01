#!/usr/bin/env bats
# Tests for scripts/gh_stack_status.py.
#
# Each test maps to a specific thing `gh stack view --json` cannot answer, which
# is the only justification for the script existing.

load 'test_helper'

setup() {
	require_gh_stack
	make_stack
}

# ---------- parentage and ordering ----------

@test "resolves parent branch names, which gh only exposes as commit SHAs" {
	run status
	[ "$status" -eq 0 ]
	[ "$(json_get "$output" "branches.0.parent")" = "main" ]
	[ "$(json_get "$output" "branches.1.parent")" = "feat-one" ]
}

@test "orders branches trunk to top, matching --json and not --short" {
	run status
	[ "$(json_get "$output" "branches.0.name")" = "feat-one" ]
	[ "$(json_get "$output" "branches.1.name")" = "feat-two" ]
	[ "$(json_get "$output" "branches.0.position")" = "1" ]
}

@test "resolves head SHAs even though gh stack v0.1.0 never emits them" {
	run status
	head_sha="$(json_get "$output" "branches.0.head")"
	expected="$(git -C "$REPO" rev-parse feat-one)"
	[ "$head_sha" = "$expected" ]
}

@test "computes ahead/behind against the parent branch" {
	run status
	[ "$(json_get "$output" "branches.1.ahead_of_parent")" = "1" ]
	[ "$(json_get "$output" "branches.1.behind_parent")" = "0" ]
}

# ---------- identity ----------

@test "distinguishes being on trunk from being off-stack" {
	git -C "$REPO" switch -q main
	run status
	[ "$status" -eq 0 ]
	[ "$(json_get "$output" "on_trunk")" = "true" ]
	[ "$(json_get "$output" "position")" = "0" ]
	has_finding "$output" "ON_TRUNK"
}

@test "reports detached HEAD as a structured error, not a crash" {
	git -C "$REPO" checkout -q --detach HEAD
	run status_json
	[ "$status" -eq 1 ]
	[ "$(json_get "$output" "ok")" = "false" ]
	printf '%s' "$output" | grep -q "detached"
}

@test "flags not being at the top of the stack, which gh stack add requires" {
	git -C "$REPO" switch -q feat-one
	run status
	has_finding "$output" "NOT_AT_TOP"
}

# ---------- safety gates ----------

@test "a dirty tree blocks rebase but not commit" {
	printf 'dirty\n' >>"$REPO/c.txt"

	run status --strict --for rebase
	[ "$status" -eq 2 ]

	run status --strict --for commit
	[ "$status" -eq 0 ]
}

@test "non-strict mode reports blockers without failing" {
	printf 'dirty\n' >>"$REPO/c.txt"
	run status --for rebase
	[ "$status" -eq 0 ]
	has_finding "$output" "DIRTY_WORKTREE"
}

@test "a clean tree passes the rebase gate" {
	run status --strict --for rebase
	[ "$status" -eq 0 ]
}

@test "detects a branch that needs rebasing onto its parent" {
	git -C "$REPO" switch -q feat-one
	printf 'more\n' >>"$REPO/b.txt"
	git -C "$REPO" commit -qam "extend feat one"
	git -C "$REPO" switch -q feat-two

	run status
	[ "$(json_get "$output" "branches.1.needs_rebase")" = "true" ]
}

# ---------- the worktree case ----------

@test "sees the stack from a linked worktree where gh stack cannot" {
	worktree="${BATS_TEST_TMPDIR}/wt"
	git -C "$REPO" worktree add -q "$worktree" feat-one

	# Baseline: gh itself claims the branch is not in a stack.
	run bash -c "cd '$worktree' && gh stack view --json"
	[ "$status" -eq 2 ]

	# The script falls back to the state file in the common git dir.
	run python3 "$STATUS_SCRIPT" -C "$worktree" --no-prs
	[ "$status" -eq 0 ]
	[ "$(json_get "$output" "source")" = "git-state-file" ]
	[ "$(json_get "$output" "current_branch")" = "feat-one" ]
	[ "$(json_get "$output" "worktree.is_linked")" = "true" ]
	has_finding "$output" "WORKTREE_STATE_INVISIBLE"
}

@test "the worktree fix it emits actually restores gh stack visibility" {
	worktree="${BATS_TEST_TMPDIR}/wt"
	git -C "$REPO" worktree add -q "$worktree" feat-one

	common="$(git -C "$worktree" rev-parse --git-common-dir)"
	private="$(git -C "$worktree" rev-parse --absolute-git-dir)"
	ln -s "${common}/gh-stack" "${private}/gh-stack"

	run bash -c "cd '$worktree' && gh stack view --json"
	[ "$status" -eq 0 ]
	printf '%s' "$output" | grep -q '"currentBranch": "feat-one"'
}

# ---------- output contract ----------

@test "stdout is always valid JSON, on success and on failure" {
	run status_json
	printf '%s' "$output" | python3 -m json.tool >/dev/null

	git -C "$REPO" checkout -q --detach HEAD
	run status_json
	[ "$status" -eq 1 ]
	printf '%s' "$output" | python3 -m json.tool >/dev/null
}

@test "diagnostics go to stderr, never contaminating the JSON on stdout" {
	git -C "$REPO" checkout -q --detach HEAD
	out="$(python3 "$STATUS_SCRIPT" -C "$REPO" --no-prs 2>/dev/null || true)"
	err="$(python3 "$STATUS_SCRIPT" -C "$REPO" --no-prs 2>&1 >/dev/null || true)"
	printf '%s' "$out" | python3 -m json.tool >/dev/null
	printf '%s' "$err" | grep -q "^error: "
}

@test "text mode renders top-down with the current branch marked" {
	run status --text
	[ "$status" -eq 0 ]
	printf '%s' "$output" | grep -q '\* 2\. feat-two'
	printf '%s' "$output" | grep -q '0\. main (trunk)'
}

@test "never mutates the repository" {
	before="$(git -C "$REPO" rev-parse HEAD)$(git -C "$REPO" status --porcelain)"
	run status --strict --for submit
	after="$(git -C "$REPO" rev-parse HEAD)$(git -C "$REPO" status --porcelain)"
	[ "$before" = "$after" ]
}
