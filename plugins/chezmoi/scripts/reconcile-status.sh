#!/bin/bash
# reconcile-status.sh - Detect ALL chezmoi drift, including silent template drift
#
# Usage:
#   bash ${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-status.sh [--verbose]
#
# This script detects two types of drift:
#   1. VISIBLE drift: files where `chezmoi status` reports differences
#   2. SILENT drift: template-managed files where the target was edited
#      outside chezmoi but happens to match the rendered template output,
#      so `chezmoi status` stays quiet
#
# Exit codes:
#   0 - No drift detected (everything clean)
#   1 - Drift detected (see output for details)
#   2 - Error (missing tools, etc.)

set -euo pipefail

VERBOSE=false
if [[ "${1:-}" == "--verbose" ]]; then
	VERBOSE=true
fi

DRIFT_FOUND=false
VISIBLE_DRIFT=()
SILENT_DRIFT=()

# Color codes (if terminal supports it)
if [[ -t 1 ]]; then
	RED='\033[0;31m'
	YELLOW='\033[0;33m'
	GREEN='\033[0;32m'
	CYAN='\033[0;36m'
	BOLD='\033[1m'
	RESET='\033[0m'
else
	RED='' YELLOW='' GREEN='' CYAN='' BOLD='' RESET=''
fi

printf "${BOLD}Chezmoi Reconciliation Status${RESET}\n"
printf '%s\n' "=============================="
printf "\n"

# --- Sandbox environment check ---
if [[ "${TMPDIR:-}" == */tmp/claude* || "${TMPDIR:-}" == */private/tmp/claude* ]]; then
	printf "${RED}WARNING: Sandbox-overridden TMPDIR detected (${TMPDIR})${RESET}\n"
	printf "${RED}Templates using {{ env \"TMPDIR\" }} will render with the sandbox path,${RESET}\n"
	printf "${RED}causing false positive drift. Run this script outside the sandbox${RESET}\n"
	printf "${RED}(dangerouslyDisableSandbox: true) for accurate results.${RESET}\n"
	printf "\n"
fi

# --- Pre-scan: Count template-managed files ---
TMPL_COUNT=0

while IFS= read -r target; do
	[[ -z "$target" ]] && continue
	src=$(chezmoi source-path "$target" 2>/dev/null || true)
	if [[ "$src" == *.tmpl ]]; then
		((TMPL_COUNT++)) || true
	fi
done < <(chezmoi managed --include=files --path-style=absolute 2>/dev/null)

if $VERBOSE; then
	printf "${BOLD}[0/2] Template index: ${TMPL_COUNT} template-managed file(s)${RESET}\n"
	printf "\n"
fi

# --- Part 1: Visible drift (chezmoi status) ---
printf "${BOLD}[1/2] Checking chezmoi status (visible drift)...${RESET}\n"
STATUS_OUTPUT=$(chezmoi status 2>/dev/null || true)

VISIBLE_RUN=()
VISIBLE_TMPL=()
INFRA_ADD_COUNT=0

if [[ -n "$STATUS_OUTPUT" ]]; then
	DRIFT_FOUND=true
	while IFS= read -r line; do
		col1="${line:0:1}"
		col2="${line:1:1}"
		path="${line:3}"

		is_tmpl=false
		tmpl_src=""
		src_check=$(chezmoi source-path "$path" 2>/dev/null || true)
		if [[ "$src_check" == *.tmpl ]]; then
			is_tmpl=true
			tmpl_src="$src_check"
			VISIBLE_TMPL+=("$path")
		fi

		direction=""
		if [[ "$col1" == "R" || "$col2" == "R" ]]; then
			direction="[WILL EXECUTE] script will run (may have side effects)"
			VISIBLE_RUN+=("$path")
		elif [[ "$col1" != " " && "$col2" != " " ]]; then
			direction="both directions"
		elif [[ "$col2" == "M" ]]; then
			direction="source template differs from target (chezmoi apply would change target)"
		elif [[ "$col2" == "A" ]]; then
			direction="new file in source (chezmoi apply would create target)"
			if [[ "$path" != *dot_* && "$path" != *private_* && "$path" != *executable_* ]]; then
				((INFRA_ADD_COUNT++)) || true
			fi
		elif [[ "$col2" == "D" ]]; then
			direction="removed from source (chezmoi apply would delete target)"
		elif [[ "$col1" == "M" ]]; then
			direction="target edited outside chezmoi"
		else
			direction="status: ${col1}${col2}"
		fi

		VISIBLE_DRIFT+=("$path")

		tmpl_tag=""
		if $is_tmpl; then
			tmpl_tag=" ${CYAN}[TEMPLATE]${RESET}"
		fi

		if [[ "$col1" == "R" || "$col2" == "R" ]]; then
			printf "  ${RED}RUN${RESET}      ${col1}${col2}  ${path}${tmpl_tag}\n"
		else
			printf "  ${YELLOW}VISIBLE${RESET}  ${col1}${col2}  ${path}${tmpl_tag}\n"
		fi
		if $VERBOSE; then
			printf "           %s\n" "$direction"
			if $is_tmpl; then
				printf "           ${CYAN}source: ${tmpl_src}${RESET}\n"
				printf "           ${CYAN}re-add will STRIP template directives -- edit template manually instead${RESET}\n"
			fi
		fi
	done <<<"$STATUS_OUTPUT"
else
	printf "  ${GREEN}Clean${RESET} - no visible differences\n"
fi

# Warn about script entries
if [[ ${#VISIBLE_RUN[@]} -gt 0 ]]; then
	printf "\n"
	printf "  ${RED}${BOLD}Note:${RESET} ${#VISIBLE_RUN[@]} entry(s) marked RUN will ${RED}execute scripts${RESET}, not just modify files.\n"
	printf "  Scripts may take a long time, require interactive input, or have side effects.\n"
fi

# Warn about template-managed drift
if [[ ${#VISIBLE_TMPL[@]} -gt 0 ]]; then
	printf "\n"
	printf "  ${CYAN}${BOLD}Note:${RESET} ${#VISIBLE_TMPL[@]} drifted file(s) are ${CYAN}template-managed${RESET}.\n"
	printf "  ${CYAN}Do NOT use 'chezmoi re-add' on these -- it will strip template directives.${RESET}\n"
	printf "  ${CYAN}Instead, edit the .tmpl source file to incorporate the live changes.${RESET}\n"
fi

# Warn about possible infrastructure false positives
if [[ $INFRA_ADD_COUNT -gt 5 ]]; then
	printf "\n"
	printf "  ${YELLOW}${BOLD}Hint:${RESET} ${INFRA_ADD_COUNT} 'add' entries don't follow chezmoi naming conventions.\n"
	printf "  These may be repo infrastructure files that need to be added to ${BOLD}.chezmoiignore${RESET}.\n"
fi

printf "\n"

# --- Part 2: Silent template drift ---
printf "${BOLD}[2/2] Checking template entry states (silent drift)...${RESET}\n"

STATE_JSON=$(chezmoi state dump 2>/dev/null)

TMPL_TARGETS=()
while IFS= read -r target; do
	src=$(chezmoi source-path "$target" 2>/dev/null || true)
	if [[ "$src" == *.tmpl ]]; then
		TMPL_TARGETS+=("$target")
	fi
done < <(chezmoi managed --include=files --path-style=absolute 2>/dev/null)

if [[ ${#TMPL_TARGETS[@]} -eq 0 ]]; then
	printf "  No template-managed files found\n"
else
	for target in "${TMPL_TARGETS[@]}"; do
		skip=false
		for visible in "${VISIBLE_DRIFT[@]+"${VISIBLE_DRIFT[@]}"}"; do
			if [[ "$target" == *"$visible"* || "$visible" == *"$target"* ]]; then
				skip=true
				break
			fi
		done
		if $skip; then
			if $VERBOSE; then
				printf "  ${CYAN}SKIP${RESET}    %s (already in visible drift)\n" "$target"
			fi
			continue
		fi

		entry_hash=$(echo "$STATE_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
entry = data.get('entryState', {}).get('$target', {})
print(entry.get('contentsSHA256', ''))
" 2>/dev/null || true)

		if [[ -z "$entry_hash" ]]; then
			if $VERBOSE; then
				printf "  ${CYAN}SKIP${RESET}    %s (no entry state -- never applied?)\n" "$target"
			fi
			continue
		fi

		if [[ ! -f "$target" ]]; then
			if $VERBOSE; then
				printf "  ${CYAN}SKIP${RESET}    %s (target file does not exist)\n" "$target"
			fi
			continue
		fi

		actual_hash=$(shasum -a 256 "$target" 2>/dev/null | awk '{print $1}')

		if [[ "$entry_hash" != "$actual_hash" ]]; then
			DRIFT_FOUND=true
			SILENT_DRIFT+=("$target")
			src=$(chezmoi source-path "$target" 2>/dev/null || echo "unknown")
			printf "  ${RED}SILENT${RESET}   %s\n" "$target"
			if $VERBOSE; then
				printf "           source:      %s\n" "$src"
				printf "           entry state:  %s...\n" "${entry_hash:0:16}"
				printf "           actual file:  %s...\n" "${actual_hash:0:16}"
				printf "           Target was edited outside chezmoi but matches rendered template.\n"
				printf "           Run: chezmoi re-add %s  (to accept target changes)\n" "$target"
				printf "           Or:  chezmoi apply --force %s  (to overwrite target)\n" "$target"
			fi
		else
			if $VERBOSE; then
				printf "  ${GREEN}CLEAN${RESET}   %s\n" "$target"
			fi
		fi
	done

	if [[ ${#SILENT_DRIFT[@]} -eq 0 ]]; then
		printf "  ${GREEN}Clean${RESET} - no silent template drift detected\n"
	fi
fi

printf "\n"

# --- Summary ---
printf "${BOLD}Summary${RESET}\n"
printf '%s\n' "-------"
printf "Visible drift:  %d file(s)\n" "${#VISIBLE_DRIFT[@]}"
printf "  Scripts (R):  %d\n" "${#VISIBLE_RUN[@]}"
printf "  Templates:    %d\n" "${#VISIBLE_TMPL[@]}"
printf "Silent drift:   %d file(s)\n" "${#SILENT_DRIFT[@]}"
printf "Template index: %d total template-managed file(s)\n" "$TMPL_COUNT"
printf "\n"

if $DRIFT_FOUND; then
	printf "${YELLOW}Drift detected.${RESET} Reconciliation needed.\n"
	printf "\n"
	printf "To resolve plain (non-template) drift:\n"
	printf "  chezmoi diff                    # review differences\n"
	printf "  chezmoi re-add <file>           # accept target changes into source\n"
	printf "  chezmoi apply --force <file>    # overwrite target with source\n"
	printf "\n"
	if [[ ${#VISIBLE_TMPL[@]} -gt 0 || ${#SILENT_DRIFT[@]} -gt 0 ]]; then
		printf "To resolve ${CYAN}template${RESET} drift:\n"
		printf "  Edit the .tmpl source file directly to incorporate live changes.\n"
		printf "  Do NOT use 'chezmoi re-add' -- it strips template directives.\n"
		printf "  chezmoi apply --force <file>    # overwrite target with source (discards live changes)\n"
		printf "\n"
	fi
	exit 1
else
	printf "${GREEN}All clean!${RESET} No drift detected.\n"
	exit 0
fi
