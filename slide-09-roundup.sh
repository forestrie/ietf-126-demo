#!/usr/bin/env bash
#
# Slide 9 — Roundup: the closer. The same verify as slide 2, still true.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]:-$0}")/demo-lib.sh"
demo_init 09

note "the closer: the very first receipt, from slide 2, still verifies — same command, still true"
run './forestrie verify --genesis "$GENESIS" --receipt "$RECEIPT" \
	--payload "$STMT" --entry-id "$ENTRY_ID"'
