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

# Alice's data log anchors only AFTER David's auth log does — univocity checks
# the grant against the owner's on-chain state, so the chain root -> auth ->
# data settles one link at a time (~2 min after slide 6 on lane-A). Silently
# wait for it rather than fail the closer on stage. This is coverage lag, not
# a failure: the verify below is the real assertion.
anchored() { # $1=log-id — true once the log has any on-chain accumulator
	local st
	st=$(~/.foundry/bin/cast call "$UNIVOCITY_ADDRESS" \
		"logState(bytes32)((bytes32[],uint64))" \
		"$(printf '0x%064s' "$(echo "$1" | tr -d '-')" | tr ' ' '0')" \
		--rpc-url "$RPC_URL" 2>/dev/null) || return 1
	[ -n "$st" ] && [ "${st##*, }" != "0)" ]
}
retry anchored "$ALICE_DATA_LOG_ID" ||
	echo "  (alice's data log is not anchored yet — the verify below will say so)"

# Read the CheckpointPublished events for a log straight from the JSON-RPC
# endpoint with plain curl — public on-chain state, no operator, no SDK. Prints
# the exact curl (real values, not $VARS) so anyone in the room can copy and run
# it, plus a link to the contract on the Base Sepolia explorer.
publishing_events() { # $1=log-id
	local topic key payload cmd
	# topic0 = the CheckpointPublished event signature; topic1 = the log id
	# (indexed), so the filter returns just this log's publishing events.
	topic=$(~/.foundry/bin/cast keccak \
		"CheckpointPublished(bytes32,bytes32,bytes,address,bytes8,uint8,uint64,bytes32[],uint64,bytes32[])")
	key=$(printf '0x%064s' "$(echo "$1" | tr -d '-')" | tr ' ' '0')
	payload=$(printf '{"jsonrpc":"2.0","id":1,"method":"eth_getLogs","params":[{"address":"%s","fromBlock":"0x%x","toBlock":"latest","topics":["%s","%s"]}]}' \
		"$UNIVOCITY_ADDRESS" "${DEPLOY_BLOCK:-0}" "$topic" "$key")
	cmd="curl -sS -X POST $RPC_URL -H 'Content-Type: application/json' --data '$payload'"
	printf '\n\033[1mcopy this to read the publishing events straight from the chain:\033[0m\n%s\n\n' "$cmd"
	eval "$cmd" | jq "{contract: \"$UNIVOCITY_ADDRESS\", published_checkpoints: (.result | length)}"
	printf '\n\033[1mor open the contract in the explorer:\033[0m\n  https://sepolia.basescan.org/address/%s#events\n' "$UNIVOCITY_ADDRESS"
}

note "verify Alice's receipt against her data log's OWN on-chain accumulator — matching the peak proves inclusion AND split-view in a single check"
run './forestrie verify --genesis "$GENESIS" --receipt "$ALICE_RECEIPT" \
	--payload "$ALICE_STMT" --entry-id "$ALICE_ENTRY_ID" \
	--univocity "$UNIVOCITY_ADDRESS" --log-id "$ALICE_DATA_LOG_ID" --rpc-url "$RPC_URL"'

note "and it is all public — here is a curl anyone can run to read Alice's publishing events off the chain, plus a link to the contract in the explorer"
run 'publishing_events "$ALICE_DATA_LOG_ID"'

# Trust-ladder rung 1: the same receipt, fully offline, under Alice's key
# obtained out of band — no genesis, no chain. (The key is the data-log
# OWNER's: the delegation cert still resolves under it.)
note "rung 1: the same receipt, fully offline, under Alice's key obtained out of band — the standard SCITT verifier posture"
run 'ALICE_KNOWN_KEY=$(openssl ec -in "$ALICE_PEM" -pubout -outform DER 2>/dev/null | tail -c 64 | base64)
./forestrie verify --known-log-key "$ALICE_KNOWN_KEY" --receipt "$ALICE_RECEIPT" \
	--payload "$ALICE_STMT" --entry-id "$ALICE_ENTRY_ID"'

# Trust-ladder rung 3: cache the on-chain accumulator once (auditable at its
# block), then the chain-anchored check runs with NO rpc at all.
note "rung 3: cache the on-chain accumulator once, pinned to its block"
run './forestrie fetch-accumulator --univocity "$UNIVOCITY_ADDRESS" \
	--log-id "$ALICE_DATA_LOG_ID" --rpc-url "$RPC_URL" --out "$S/alice-accumulator.cbor"'

note "now the very same chain-anchored check runs fully offline — no RPC at all"
run './forestrie verify --genesis "$GENESIS" --receipt "$ALICE_RECEIPT" \
	--payload "$ALICE_STMT" --entry-id "$ALICE_ENTRY_ID" \
	--known-accumulator "$S/alice-accumulator.cbor"'

# (Slide 8 — trust ladder — is conceptual; no terminal segment.)
