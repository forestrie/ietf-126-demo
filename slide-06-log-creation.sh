#!/usr/bin/env bash
#
# Slide 6 — Log creation: SCITT using SCITT.
#
# Authorization is a SCITT grant statement. The data-log create+extend grant
# names its writer in grantData — that grant IS the write authorization (no
# separate step). Each log's sealing is delegated by that log's key holder.
#
# A new log's authority counts only once it is anchored: its owner must have
# published, on chain, a checkpoint covering the log's create grant. That
# takes a minute or two per level, so preflight (R6, R7) created David's and
# Alice's logs with the commands narrated below. On stage the slide proves
# both are anchored, from public chain data alone, and Alice writes.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]:-$0}")/demo-lib.sh"
demo_init 06
if [ -z "${AUTH_GRANT_B64:-}" ] || [ -z "${ALICE_GRANT_B64:-}" ]; then
	printf '\033[1;31m%s\033[0m\n' "demo.env names no slide-6 logs: preflight did not finish R6 and R7. Run ./preflight.sh --logs-only (same --lane) first." >&2
	exit 1
fi

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

note "preflight built the hierarchy: David's auth log under Robert's root, Alice's data log under David's"
run 'echo "  david auth log: $DAVID_AUTH_LOG_ID"
echo "  alice data log: $ALICE_DATA_LOG_ID"'

# 1. Robert created David's AUTH log (grantData = David → David holds it).
note "1. Robert created David's AUTH log (grantData = David → David holds it), in three steps:"
note "prepare: pre-register David's log root, claimed once for this log id — parent-authorized by Robert's root grant, no operator token"
note '  forestrie create-log --prepare --owner-log "$ROBERT_LOG_ID" --new-log "$DAVID_AUTH_LOG_ID" --auth-log --signer-pem "$DAVID_PEM" --sign-with "$ROBERT_PEM" …'
note "delegate: David approves the operator's sealer for his log, before its first checkpoint"
note '  forestrie delegate --log-id "$DAVID_AUTH_LOG_ID" --sign-with "$DAVID_PEM" --known-sealer-key "$KNOWN_SEALER_KEY" …'
note "create: the same call without --prepare sequences the create grant into Robert's log, and waits until it is anchored"
note '  forestrie create-log … --wait-anchored --genesis "$GENESIS"'

# 2. David granted Alice a DATA log to write to: grantData = Alice, signed by
#    David (the auth-log holder). This grant IS Alice's write authorization.
#    Alice, as the data-log key holder, delegated its sealing.
note "2. David granted Alice a DATA log the same way, one level down: grantData = Alice, signed by David, sequenced into David's auth log"
note '  forestrie create-log … --owner-log "$DAVID_AUTH_LOG_ID" --new-log "$ALICE_DATA_LOG_ID" --signer-pem "$ALICE_PEM" --sign-with "$DAVID_PEM" --wait-anchored'

# The proof the waits rely on: each create grant's leaf, hashed up its
# receipt's path, reaches a peak its owner published on chain (or the chain
# has recorded the log under that owner and key). No operator answer counts.
note "a new log's authority is used only once anchored: a checkpoint its owner published on chain covers its create grant, or the chain already records the log under that owner and key — proven here from public chain data alone"
run './forestrie log wait-anchored --create-grant "$AUTH_GRANT" --genesis "$GENESIS" --timeout 60'
run './forestrie log wait-anchored --create-grant "$ALICE_GRANT" --genesis "$GENESIS" --timeout 60'

# 3. Alice writes to her data log. Child logs register via the FOREST (root)
#    path — /register/{root}/entries — and the grant directs the statement to the
#    data log. Alice's first write opens the log; a checkpoint follows in ~seconds.
note "3. Alice writes to her data log"
note "her payload"
run "echo '{\"alice\":\"hello from the data log\"}' > \"\$S/alice.json\""

note "Alice signs it with her OWN key — same as slide 2, but she names her subject explicitly (--sub); iss still defaults to her key id, and --iss/--iat are there when she wants them"
run './forestrie sign-statement --key "$ALICE_PEM" --payload "$S/alice.json" \
	--content-type application/json --sub "urn:demo:alice:hello-1" --out "$S/alice.cose"'

note "register via the FOREST (root) log id — child logs register on the root's /register path; Alice's grant routes the entry to her data log. Her first write opens the log; a checkpoint follows in ~seconds"
run 'AR=$(./forestrie register --base-url "$FORESTRIE_BASE_URL" --log-id "$ROBERT_LOG_ID" \
	--statement "$S/alice.cose" --grant-b64 "$ALICE_GRANT_B64" --out "$S/alice-receipt.cbor" 2>&1)
echo "$AR"
export ALICE_ENTRY_ID=$(echo "$AR" | grep -oE "entries/[0-9a-f]{32}/receipt" | head -1 | grep -oE "[0-9a-f]{32}")'

# 4. Alice's receipt is self-servable offline from her data-log tile (as in Slide 3).
note "4. Alice's receipt is self-servable offline from her data-log tile (as in slide 3)"
run 'retry self_serve_receipt "$ALICE_DATA_LOG_ID" "$ALICE_ENTRY_ID" "$S/adata"
echo "Alice: registered under David'"'"'s SCITT grant, self-servable: $S/adata/receipt.cbor"'

# handoffs slide 7 reuses (it verifies exactly these bytes); the log ids come
# from demo.env
export ALICE_STMT="$S/alice.cose" ALICE_RECEIPT="$S/adata/receipt.cbor"
save_state ALICE_ENTRY_ID ALICE_STMT ALICE_RECEIPT
