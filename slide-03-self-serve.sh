#!/usr/bin/env bash
#
# Slide 3 — Self-service receipts: derive the SAME receipt offline.
#
# No operator round-trip: grab the one public tile holding the leaf, plus the
# latest checkpoint, and build the receipt locally.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]:-$0}")/demo-lib.sh"
demo_init 03

# Self-serve a receipt for <entry-id> in <log-id> from that log's public tile,
# into <dir>/receipt.cbor. Massif height on lane-A is 14, first tile index 0.
self_serve_receipt() { # $1=log-id  $2=entry-id  $3=out-dir
	local log="$1" eid="$2" d="$3"
	mkdir -p "$d"
	curl -fsS "$LOG_STORE_URL/v2/merklelog/massifs/14/$log/0000000000000000.log" -o "$d/massif.log" || return 1
	curl -fsS "$LOG_STORE_URL/v2/merklelog/checkpoints/14/$log/0000000000000000.sth" -o "$d/checkpoint.sth" || return 1
	./forestrie create-receipt --massif "$d/massif.log" --checkpoint "$d/checkpoint.sth" \
		--entry-id "$eid" --out "$d/receipt.cbor"
}

note 'public read-only tile + checkpoint, then build the receipt locally'
run 'retry self_serve_receipt "$ROBERT_LOG_ID" "$ENTRY_ID" "$S"'

note 'byte-identical to the API receipt; verifies with the same command'
run './forestrie verify --genesis "$GENESIS" --receipt "$S/receipt.cbor" \
	--payload "$STMT" --entry-id "$ENTRY_ID"'
