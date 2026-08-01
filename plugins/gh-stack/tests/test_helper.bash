# test_helper.bash - shared setup for gh-stack tests.
#
# These tests drive the REAL `gh stack` extension against real throwaway git
# repos. gh stack's local operations (init, add, view --json, rebase,
# navigation) are entirely offline and work in a repo with no remote at all, so
# nothing here needs the network, credentials, or a mock of the tool under test.
# That also makes the suite a canary: it fails when the extension changes shape.

# Plugin root = parent of this tests/ directory.
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PLUGIN_ROOT

STATUS_SCRIPT="${PLUGIN_ROOT}/scripts/gh_stack_status.py"
export STATUS_SCRIPT

# Skip the whole file when gh stack is unavailable, rather than failing.
require_gh_stack() {
	if ! command -v gh >/dev/null 2>&1; then
		skip "gh is not installed"
	fi
	if ! gh stack --version >/dev/null 2>&1; then
		skip "the github/gh-stack extension is not installed"
	fi
}

# Build a real stack in an isolated repo: main <- feat-one <- feat-two.
#
# Uses $BATS_TEST_TMPDIR rather than rolling our own mktemp: BSD mktemp
# ignores $TMPDIR without an explicit template, and bats already gives us a
# per-test directory it cleans up.
make_stack() {
	REPO="${BATS_TEST_TMPDIR}/repo"
	export REPO
	mkdir -p "$REPO"
	git -C "$REPO" init -q -b main
	git -C "$REPO" config user.email test@example.com
	git -C "$REPO" config user.name Tester

	printf 'base\n' >"$REPO/a.txt"
	git -C "$REPO" add -A
	git -C "$REPO" commit -qm base

	git -C "$REPO" switch -qc feat-one
	printf 'one\n' >"$REPO/b.txt"
	git -C "$REPO" add -A
	git -C "$REPO" commit -qm "feat one"

	git -C "$REPO" switch -qc feat-two
	printf 'two\n' >"$REPO/c.txt"
	git -C "$REPO" add -A
	git -C "$REPO" commit -qm "feat two"

	(cd "$REPO" && gh stack init feat-one feat-two >/dev/null 2>&1)
}

# Run the status script against $REPO. Always offline: --no-prs skips the only
# step that touches the network.
status() {
	python3 "$STATUS_SCRIPT" -C "$REPO" --no-prs "$@"
}

# Same, but with stderr discarded inside the function so bats' `run` cannot
# merge the streams. The script's contract is JSON on stdout and prose on
# stderr; `run` combines them by default, which would corrupt the JSON on any
# path that emits both. Use this whenever the assertion parses $output.
status_json() {
	python3 "$STATUS_SCRIPT" -C "$REPO" --no-prs "$@" 2>/dev/null
}

# Pull a value out of the JSON report with a jq-ish python one-liner, so the
# suite has no jq dependency. Usage: json_get "$output" "trunk"
json_get() {
	printf '%s' "$1" | python3 -c '
import json,sys
doc = json.load(sys.stdin)
for key in sys.argv[1].split("."):
    doc = doc[int(key)] if key.isdigit() else doc[key]
print(doc if not isinstance(doc, bool) else str(doc).lower())
' "$2"
}

# Return 0 if the report contains a finding with the given code.
has_finding() {
	printf '%s' "$1" | python3 -c '
import json,sys
doc = json.load(sys.stdin)
codes = {f["code"] for f in doc.get("blockers", []) + doc.get("warnings", [])}
sys.exit(0 if sys.argv[1] in codes else 1)
' "$2"
}
