#!/usr/bin/env bash
#
# demo-lib.sh — presenter plumbing shared by the slide-NN-*.sh scripts.
#
# This is stagecraft, not demo content: echo a command, wait for a key so the
# presenter can talk over it, then run it. The commands themselves — and
# self_serve_receipt, which the audience is meant to read — live in the slide
# scripts, spelled out in full.
#
# Sourced, never executed:
#   source "$(dirname "${BASH_SOURCE[0]:-$0}")/demo-lib.sh"
#
# Cross-slide handoffs (ENTRY_ID, STMT, …) go through .output/shared/demo.state,
# so each slide script runs standalone in a fresh shell, in deck order.
#
# DEMO_AUTO=1 skips every pause — that is how the scripts are tested unattended.

DEMO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_STATE="$DEMO_ROOT/.output/shared/demo.state"

# demo_init <slide-number> — load env + prior slides' handoffs, make this
# slide's scratch dir. Exports S (the scratch dir) and everything demo.env and
# demo.state carry.
demo_init() {
	local n="$1"
	cd "$DEMO_ROOT" || exit 1
	if [ ! -f .output/shared/demo.env ]; then
		printf '\033[1;31mno .output/shared/demo.env — run ./preflight.sh first\033[0m\n' >&2
		exit 1
	fi
	# shellcheck disable=SC1091
	source .output/shared/demo.env
	# shellcheck disable=SC1090
	[ -f "$DEMO_STATE" ] && source "$DEMO_STATE"
	S=".output/slide-$n"
	mkdir -p "$S"
	export S
	printf '\n\033[1;36m━━━ slide %s ━━━\033[0m\n' "$n"
}

# pause — wait for any key. Reads the tty directly so it still works when the
# script's stdin is a pipe.
pause() {
	[ -n "${DEMO_AUTO:-}" ] && return 0
	read -rsn1 -p $'\033[2m  [any key]\033[0m' _ </dev/tty
	printf '\r\033[K'
}

# run '<command>' — show it, wait, run it. Single-quote the argument so $VARS
# display as written and expand at run time.
run() {
	local cmd="$1" rc
	printf '\n\033[1;32m$\033[0m \033[1m%s\033[0m\n' "$cmd"
	pause
	eval "$cmd"
	rc=$?
	[ "$rc" -ne 0 ] && printf '\033[1;31m  ✗ exit %d\033[0m\n' "$rc"
	return "$rc"
}

# note '<text>' — narration on screen; nothing runs, no pause.
note() { printf '\033[2m# %s\033[0m\n' "$*"; }

# retry <cmd...> — retry until it succeeds (checkpoint coverage lands within
# ~2.5s; allow ~90s). Quiet while retrying; the verify that follows shows PASS.
retry() {
	local n=0
	until "$@" >/dev/null 2>&1; do
		n=$((n + 1))
		[ "$n" -ge 45 ] && {
			echo "  (timed out waiting for coverage)"
			return 1
		}
		sleep 2
	done
}

# save_state VAR... — persist handoffs for the later slide scripts.
save_state() {
	local n v
	mkdir -p "$(dirname "$DEMO_STATE")"
	touch "$DEMO_STATE"
	for n in "$@"; do
		v="${!n-}"
		grep -v "^export $n=" "$DEMO_STATE" >"$DEMO_STATE.tmp" 2>/dev/null || true
		mv "$DEMO_STATE.tmp" "$DEMO_STATE"
		printf 'export %s=%q\n' "$n" "$v" >>"$DEMO_STATE"
	done
}
