#!/usr/bin/env bash
#
# Slide 7 — Split-view verification: the accumulator is the authority.
#
# CHAIN-ANCHORED verify of Alice's statement (registered on slide 6). The peak
# is recomputed locally from her statement + the receipt's proof path and
# matched against the data log's OWN on-chain accumulator. The contract
# verified the checkpoint signature, the publisher's grant (inclusion in the
# parent, re-checked every publish), and consistency — transitively to the
# bootstrap — at publish, so matching the peak subsumes the signature check AND
# adds split-view.
#
# The other two rungs of the trust ladder (status-2607-09, shipped) close the
# slide: purely-offline verify under a caller-known log key (--known-log-key,
# the SCITT RP posture — asserts the key↔log binding, no split-view), and the
# strongest fully offline anchor — a cached, block-pinned chain read
# (fetch-accumulator → --known-accumulator). The grant-chain walk (approach A)
# remains open.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]:-$0}")/demo-lib.sh"
demo_init 07

run './forestrie verify --genesis "$GENESIS" --receipt "$ALICE_RECEIPT" \
	--payload "$ALICE_STMT" --entry-id "$ALICE_ENTRY_ID" \
	--univocity "$UNIVOCITY_ADDRESS" --log-id "$ALICE_DATA_LOG_ID" --rpc-url "$RPC_URL"'

# Trust-ladder rung 1: the same receipt, fully offline, under Alice's key
# obtained out of band — no genesis, no chain. (The key is the data-log
# OWNER's: the delegation cert still resolves under it.)
note 'rung 1 — offline under a caller-known log key (no genesis, no chain)'
run 'ALICE_KNOWN_KEY=$(openssl ec -in "$ALICE_PEM" -pubout -outform DER 2>/dev/null | tail -c 64 | base64)
./forestrie verify --known-log-key "$ALICE_KNOWN_KEY" --receipt "$ALICE_RECEIPT" \
	--payload "$ALICE_STMT" --entry-id "$ALICE_ENTRY_ID"'

# Trust-ladder rung 3: cache the on-chain accumulator once (auditable at its
# block), then the chain-anchored check runs with NO rpc at all.
note 'rung 3 — cache the accumulator, then verify chain-anchored fully offline'
run './forestrie fetch-accumulator --univocity "$UNIVOCITY_ADDRESS" \
	--log-id "$ALICE_DATA_LOG_ID" --rpc-url "$RPC_URL" --out "$S/alice-accumulator.cbor"'

run './forestrie verify --genesis "$GENESIS" --receipt "$ALICE_RECEIPT" \
	--payload "$ALICE_STMT" --entry-id "$ALICE_ENTRY_ID" \
	--known-accumulator "$S/alice-accumulator.cbor"'

# (Slide 8 — trust ladder — is conceptual; no terminal segment.)
