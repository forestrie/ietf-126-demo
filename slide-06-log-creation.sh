#!/usr/bin/env bash
#
# Slide 6 — Log creation: SCITT using SCITT.
#
# Authorization is a SCITT grant statement. The data-log create+extend grant
# names its writer in grantData — that grant IS the write authorization (no
# separate step). Each log's sealing is delegated by that log's key holder.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]:-$0}")/demo-lib.sh"
demo_init 06

# Self-serve a receipt for <entry-id> in <log-id> from that log's public tile,
# into <dir>/receipt.cbor. Massif height on lane-A is 14, first tile index 0.
# (Same helper as slide 3 — a child log self-serves exactly the same way.)
self_serve_receipt() { # $1=log-id  $2=entry-id  $3=out-dir
	local log="$1" eid="$2" d="$3"
	mkdir -p "$d"
	curl -fsS "$LOG_STORE_URL/v2/merklelog/massifs/14/$log/0000000000000000.log" -o "$d/massif.log" || return 1
	curl -fsS "$LOG_STORE_URL/v2/merklelog/checkpoints/14/$log/0000000000000000.sth" -o "$d/checkpoint.sth" || return 1
	./forestrie create-receipt --massif "$d/massif.log" --checkpoint "$d/checkpoint.sth" \
		--entry-id "$eid" --out "$d/receipt.cbor"
}

note "two fresh log ids: David's auth log, and Alice's data log that will live under it"
run 'export DAVID_AUTH_LOG_ID=$(uuidgen | tr "A-Z" "a-z")
export ALICE_DATA_LOG_ID=$(uuidgen | tr "A-Z" "a-z")
echo "  david auth log: $DAVID_AUTH_LOG_ID"
echo "  alice data log: $ALICE_DATA_LOG_ID"'

# 1. Robert creates David's AUTH log (grantData = David → David holds it).
note "1. Robert creates David's AUTH log (grantData = David → David holds it)"
note "prepare: pre-register David's log root at the coordinator (no sequencing yet), so we can delegate BEFORE the log exists — parent-authorized by Robert's root grant, no operator token"
run './forestrie create-log --prepare --base-url "$FORESTRIE_BASE_URL" \
	--owner-log "$ROBERT_LOG_ID" --new-log "$DAVID_AUTH_LOG_ID" --auth-log \
	--signer-pem "$DAVID_PEM" --sign-with "$ROBERT_PEM" \
	--parent-grant-b64 "$ROOT_GRANT_B64" --out-b64 "$S/auth-grant.b64"'

note "delegate: David approves the operator's sealer for his log (a delegation cert) — must land before the log's first checkpoint, which is why prepare comes first"
run './forestrie delegate --coordinator-url "$DELEGATION_COORDINATOR_URL" \
	--log-id "$DAVID_AUTH_LOG_ID" --sign-with "$DAVID_PEM" --known-sealer-key "$KNOWN_SEALER_KEY"'

note "create: the SAME call, now WITHOUT --prepare, sequences the create grant into Robert's log — this actually opens David's log; sealing is already delegated so its first checkpoint seals in seconds"
run './forestrie create-log --base-url "$FORESTRIE_BASE_URL" \
	--owner-log "$ROBERT_LOG_ID" --new-log "$DAVID_AUTH_LOG_ID" --auth-log \
	--signer-pem "$DAVID_PEM" --sign-with "$ROBERT_PEM" \
	--parent-grant-b64 "$ROOT_GRANT_B64" --out-b64 "$S/auth-grant.b64"
export AUTH_GRANT_B64=$(cat "$S/auth-grant.b64")'

# 2. David grants Alice a DATA log to write to: grantData = Alice, signed by
#    David (the auth-log holder). This grant IS Alice's write authorization.
#    Alice, as the data-log key holder, delegates its sealing.
note '2. David grants Alice a DATA log: grantData = Alice, signed by David'
note "prepare: same two-step, one level down — pre-register Alice's data-log root at the coordinator (owner is now David's auth log, not Robert's root)"
run './forestrie create-log --prepare --base-url "$FORESTRIE_BASE_URL" \
	--owner-log "$DAVID_AUTH_LOG_ID" --new-log "$ALICE_DATA_LOG_ID" --bootstrap-log "$ROBERT_LOG_ID" --data-log \
	--signer-pem "$ALICE_PEM" --sign-with "$DAVID_PEM" \
	--parent-grant-b64 "$AUTH_GRANT_B64" --out-b64 "$S/alice-data-grant.b64"'

note "delegate: Alice (the data-log key holder) approves the sealer for HER log — each log's sealing is delegated by its own owner, never by the parent"
run './forestrie delegate --coordinator-url "$DELEGATION_COORDINATOR_URL" \
	--log-id "$ALICE_DATA_LOG_ID" --sign-with "$ALICE_PEM" --known-sealer-key "$KNOWN_SEALER_KEY"'

note "create: sequence Alice's create grant into David's auth log — grantData = Alice, so this grant IS Alice's write authorization (no separate register-grant step)"
run './forestrie create-log --base-url "$FORESTRIE_BASE_URL" \
	--owner-log "$DAVID_AUTH_LOG_ID" --new-log "$ALICE_DATA_LOG_ID" --bootstrap-log "$ROBERT_LOG_ID" --data-log \
	--signer-pem "$ALICE_PEM" --sign-with "$DAVID_PEM" \
	--parent-grant-b64 "$AUTH_GRANT_B64" --out-b64 "$S/alice-data-grant.b64"
export ALICE_GRANT_B64=$(cat "$S/alice-data-grant.b64")'

# 3. Alice writes to her data log. Child logs register via the FOREST (root)
#    path — /register/{root}/entries — and the grant directs the statement to the
#    data log. Alice's first write opens the log; a checkpoint follows in ~seconds.
note "3. Alice writes to her data log"
note "her payload"
run "echo '{\"alice\":\"hello from the data log\"}' > \"\$S/alice.json\""

note "Alice signs it with her OWN key — a plain COSE Sign1 statement, same as slide 2"
run './forestrie sign-statement --key "$ALICE_PEM" --payload "$S/alice.json" \
	--content-type application/json --out "$S/alice.cose"'

note "register via the FOREST (root) log id — child logs register on the root's /register path; Alice's grant routes the entry to her data log. Her first write opens the log; a checkpoint follows in ~seconds"
run 'AR=$(./forestrie register --base-url "$FORESTRIE_BASE_URL" --log-id "$ROBERT_LOG_ID" \
	--statement "$S/alice.cose" --grant-b64 "$ALICE_GRANT_B64" --out "$S/alice-receipt.cbor" 2>&1)
echo "$AR"
export ALICE_ENTRY_ID=$(echo "$AR" | grep -oE "entries/[0-9a-f]{32}/receipt" | head -1 | grep -oE "[0-9a-f]{32}")'

# 4. Alice's receipt is self-servable offline from her data-log tile (as in Slide 3).
note "4. Alice's receipt is self-servable offline from her data-log tile (as in slide 3)"
run 'retry self_serve_receipt "$ALICE_DATA_LOG_ID" "$ALICE_ENTRY_ID" "$S/adata"
echo "Alice: registered under David'"'"'s SCITT grant, self-servable: $S/adata/receipt.cbor"'

# handoffs slide 7 reuses (it verifies exactly these bytes)
export ALICE_STMT="$S/alice.cose" ALICE_RECEIPT="$S/adata/receipt.cbor"
save_state DAVID_AUTH_LOG_ID ALICE_DATA_LOG_ID ALICE_ENTRY_ID ALICE_STMT ALICE_RECEIPT
