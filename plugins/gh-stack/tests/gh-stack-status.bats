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

@test "resolves head SHAs, which gh stack omits until a rebase records them" {
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

@test "names the candidate stacks on a trunk shared by two stacks" {
	git -C "$REPO" switch -qc other main
	printf 'x\n' >"$REPO/x.txt"
	git -C "$REPO" add -A
	git -C "$REPO" commit -qm other
	(cd "$REPO" && gh stack init other >/dev/null 2>&1)
	git -C "$REPO" switch -q main

	run status_json
	[ "$status" -eq 1 ]
	printf '%s' "$output" | grep -q "trunk of 2 stacks"
	printf '%s' "$output" | grep -q "other"
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

@test "sees the stack from a linked worktree through gh stack itself" {
	worktree="${BATS_TEST_TMPDIR}/wt"
	git -C "$REPO" worktree add -q "$worktree" feat-one

	run python3 "$STATUS_SCRIPT" -C "$worktree" --no-prs
	[ "$status" -eq 0 ]
	[ "$(json_get "$output" "source")" = "gh-stack-view" ]
	[ "$(json_get "$output" "current_branch")" = "feat-one" ]
	[ "$(json_get "$output" "worktree.is_linked")" = "true" ]
}

@test "the state file it reports is the one shared by every worktree" {
	worktree="${BATS_TEST_TMPDIR}/wt"
	git -C "$REPO" worktree add -q "$worktree" feat-one

	run python3 "$STATUS_SCRIPT" -C "$worktree" --no-prs
	state_file="$(json_get "$output" "worktree.state_file")"
	[ -f "$state_file" ]
	# macOS /tmp is a symlink to /private/tmp, so compare physical paths.
	[ "$(cd "$(dirname "$state_file")" && pwd -P)" = "$(cd "$REPO/.git" && pwd -P)" ]
	[ ! -e "$(git -C "$worktree" rev-parse --absolute-git-dir)/gh-stack" ]
}

# Stop a stack rebase on a conflict in a worktree that holds feat-two.
conflict_in_worktree() {
	worktree="${BATS_TEST_TMPDIR}/wt"
	git -C "$REPO" switch -q main
	git -C "$REPO" worktree add -q "$worktree" feat-two
	git -C "$REPO" switch -q feat-one
	printf 'one\n' >"$REPO/c.txt"
	git -C "$REPO" add -A
	git -C "$REPO" commit -qm "conflict on one"
	printf 'two\n' >>"$worktree/c.txt"
	git -C "$worktree" commit -qam "conflict on two"
	(cd "$REPO" && gh stack rebase --no-trunk >/dev/null 2>&1) || true
}

@test "flags a rebase stopped in another worktree, which view --json hides" {
	conflict_in_worktree

	# Baseline: gh stack reports a normal stack from the other checkout.
	run bash -c "cd '$REPO' && gh stack view --json 2>/dev/null"
	[ "$status" -eq 0 ]

	run status_json
	has_finding "$output" "REBASE_IN_PROGRESS"
	printf '%s' "$output" | grep -q "$worktree"

	run status_json --strict --for rebase
	[ "$status" -eq 2 ]
	has_blocker "$output" "REBASE_IN_PROGRESS"
}

@test "explains a detached HEAD caused by a stopped stack rebase" {
	conflict_in_worktree

	run bash -c "python3 '$STATUS_SCRIPT' -C '$worktree' --no-prs 2>/dev/null"
	[ "$status" -eq 1 ]
	[ "$(json_get "$output" "ok")" = "false" ]
	printf '%s' "$output" | grep -q "rebase stopped on a conflict on 'feat-two'"
	printf '%s' "$output" | grep -q "$worktree"
}

@test "the rebase blocker clears after gh stack rebase --abort" {
	conflict_in_worktree
	(cd "$REPO" && gh stack rebase --abort >/dev/null 2>&1)

	run status_json --strict --for rebase
	[ "$status" -eq 0 ]
}

# Write a rebase-state record by hand, standing in for one gh-stack wrote.
fake_rebase_state() {
	printf '%b' "$1" >"$REPO/.git/gh-stack-rebase-state"
}

@test "a stopped rebase leaves commit open and blocks navigation" {
	fake_rebase_state '{"conflictBranch":"feat-two"}'

	run status_json --strict --for commit
	[ "$status" -eq 0 ]

	run status_json --strict --for navigate
	[ "$status" -eq 2 ]
	has_blocker "$output" "REBASE_IN_PROGRESS"
}

@test "a malformed rebase record still blocks, with JSON on stdout" {
	for record in 'null' '[]' '"x"' '{bad' '\xff\xfe' '{"conflictBranch":{"a":1}}' \
		'{"conflictBranch":"feat-two","worktrees":{"owners":{"feat-two":"p"}}}'; do
		fake_rebase_state "$record"
		run status_json --strict --for rebase
		echo "record: $record, status: $status"
		[ "$status" -eq 2 ]
		has_blocker "$output" "REBASE_IN_PROGRESS"
	done
}

@test "turns off the upgrade notifier for every gh call it makes" {
	real_gh="$(command -v gh)"
	shim="${BATS_TEST_TMPDIR}/bin"
	mkdir -p "$shim"
	cat >"$shim/gh" <<EOF
#!/bin/sh
printf '%s\n' "\${GH_STACK_NO_UPDATE_NOTIFIER-unset}" >>"${BATS_TEST_TMPDIR}/notifier"
exec "$real_gh" "\$@"
EOF
	chmod +x "$shim/gh"

	PATH="$shim:$PATH" env -u GH_STACK_NO_UPDATE_NOTIFIER \
		python3 "$STATUS_SCRIPT" -C "$REPO" --no-prs >/dev/null
	[ -s "${BATS_TEST_TMPDIR}/notifier" ]
	run grep -v '^1$' "${BATS_TEST_TMPDIR}/notifier"
	[ "$status" -eq 1 ]
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
