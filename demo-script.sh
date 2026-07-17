#!/usr/bin/env bash
#
# demo-script.sh — the runnable terminal companion to the Marp deck (slides/).
#
# Usage: run preflight.sh ONCE, then paste this file into the long-lived demo
# terminal one "SLIDE" block at a time (the terminal is the OBS "Terminal"
# scene; the deck is the "Slides" scene). Env + shared state come from
# .output/shared/demo.env; per-slide scratch lands under .output/slide-N/.
#
#   ./preflight.sh
#   source .output/shared/demo.env
#   # then paste each SLIDE block below, in order
#
# Slide numbers here follow the deck (slides/NN-*.md). All commands are the
# tested forms; the deck shows their essence.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]:-$0}")"

# Source the env if the shell doesn't already have it (idempotent for re-paste).
[ -n "${ROBERT_LOG_ID:-}" ] || source .output/shared/demo.env

# --- helpers ---------------------------------------------------------------
# Retry a command until it succeeds (checkpoint coverage lands within ~2.5s;
# give it up to ~90s). Quiet during retries; the following verify shows PASS.
retry() { local n=0; until "$@" >/dev/null 2>&1; do n=$((n+1)); [ "$n" -ge 45 ] && { echo "  (timed out waiting for coverage)"; return 1; }; sleep 2; done; }

# Self-serve a receipt for <entry-id> in <log-id> from that log's public tile,
# into <dir>/receipt.cbor. Massif height on lane-A is 14, first tile index 0.
fetch_and_receipt() { # $1=log-id  $2=entry-id  $3=out-dir
  local log="$1" eid="$2" d="$3"; mkdir -p "$d"
  curl -fsS "$LOG_STORE_URL/v2/merklelog/massifs/14/$log/0000000000000000.log"     -o "$d/massif.log"     || return 1
  curl -fsS "$LOG_STORE_URL/v2/merklelog/checkpoints/14/$log/0000000000000000.sth" -o "$d/checkpoint.sth" || return 1
  ./forestrie create-receipt --massif "$d/massif.log" --checkpoint "$d/checkpoint.sth" \
    --entry-id "$eid" --out "$d/receipt.cbor"
}

# ═══════════════════════════════════════════════════════════════════════════
# SLIDE 2 — Publishing a signed statement
# ═══════════════════════════════════════════════════════════════════════════
S=.output/slide-1; mkdir -p "$S"

echo '{"claim":"hello scitt wg"}' > "$S/statement.json"

./forestrie sign-statement --key "$ROBERT_PEM" --payload "$S/statement.json" \
  --content-type application/json --out "$S/statement.cose"

REG=$(./forestrie register --base-url "$FORESTRIE_BASE_URL" --log-id "$ROBERT_LOG_ID" \
  --statement "$S/statement.cose" --grant-b64 "$ROOT_GRANT_B64" --out "$S/receipt.cbor" 2>&1); echo "$REG"
export ENTRY_ID=$(echo "$REG" | grep -oE 'entries/[0-9a-f]{32}/receipt' | head -1 | grep -oE '[0-9a-f]{32}')

# handoffs the later slides reuse (the closer re-verifies exactly these):
export STMT="$S/statement.cose" RECEIPT="$S/receipt.cbor"

./forestrie verify --genesis "$GENESIS" --receipt "$RECEIPT" \
  --payload "$STMT" --entry-id "$ENTRY_ID"

# ═══════════════════════════════════════════════════════════════════════════
# SLIDE 3 — Self-service receipts (derive the SAME receipt offline)
# ═══════════════════════════════════════════════════════════════════════════
S=.output/slide-2; mkdir -p "$S"

# Grab the public tile + checkpoint and self-create the receipt (no operator call).
retry fetch_and_receipt "$ROBERT_LOG_ID" "$ENTRY_ID" "$S"

# Byte-identical to the API receipt; verifies with the same command.
./forestrie verify --genesis "$GENESIS" --receipt "$S/receipt.cbor" \
  --payload "$STMT" --entry-id "$ENTRY_ID"

# ═══════════════════════════════════════════════════════════════════════════
# SLIDE 4 — Throughput and latency (100 statements, one checkpoint)
# ═══════════════════════════════════════════════════════════════════════════
# batch-receipts.ts reads ROBERT_LOG_ID / ROBERT_PEM / ROOT_GRANT_B64 from the env.
N=100 bun batch-receipts.ts

# ═══════════════════════════════════════════════════════════════════════════
# SLIDE 5 — Split-view protection (throwaway deploy + on-chain binding)
# ═══════════════════════════════════════════════════════════════════════════
S=.output/slide-4; mkdir -p "$S"

# Deploying is easy — a THROWAWAY instance so we don't disturb the live forest
# (its own --out + pem; we do NOT re-export ROBERT_LOG_ID / UNIVOCITY_ADDRESS).
# The gas-paying key is fetched at runtime, never stored in demo.env.
DEPLOYER_KEY=$(doppler secrets get DEPLOY_KEY --project canopy --config dev --plain)
./forestrie deploy --bootstrap-alg es256 --bootstrap-es256-generate \
  --bootstrap-es256-pem-out "$S/throwaway.es256.pem" \
  --owner-address "$OWNER_ADDRESS" --deployer-key "$DEPLOYER_KEY" \
  --rpc-url "$RPC_URL" --out "$S/throwaway.json"

# The real payoff: on-chain, the live contract's bootstrap key IS the key that
# signed our root grant — split-view lives in the contract, not the operator.
~/.foundry/bin/cast call "$UNIVOCITY_ADDRESS" "bootstrapConfig()(int64,bytes)" --rpc-url "$RPC_URL"

# ═══════════════════════════════════════════════════════════════════════════
# SLIDE 6 — Log creation: SCITT using SCITT
# ═══════════════════════════════════════════════════════════════════════════
# Authorization is a SCITT grant statement. The data-log create+extend grant
# names its writer in grantData — that grant IS the write authorization (no
# separate step). Each log's sealing is delegated by that log's key holder.
S=.output/slide-5; mkdir -p "$S"
export DAVID_AUTH_LOG_ID=$(uuidgen | tr 'A-Z' 'a-z')
export ALICE_DATA_LOG_ID=$(uuidgen | tr 'A-Z' 'a-z')

# 1. Robert creates David's AUTH log (grantData = David → David holds it).
./forestrie create-log --prepare --base-url "$FORESTRIE_BASE_URL" \
  --owner-log "$ROBERT_LOG_ID" --new-log "$DAVID_AUTH_LOG_ID" --auth-log \
  --signer-pem "$DAVID_PEM" --sign-with "$ROBERT_PEM" \
  --parent-grant-b64 "$ROOT_GRANT_B64" --out-b64 "$S/auth-grant.b64"
./forestrie delegate --coordinator-url "$DELEGATION_COORDINATOR_URL" \
  --log-id "$DAVID_AUTH_LOG_ID" --sign-with "$DAVID_PEM" --pinned-registrar-key "$PINNED_REGISTRAR_KEY"
./forestrie create-log --base-url "$FORESTRIE_BASE_URL" \
  --owner-log "$ROBERT_LOG_ID" --new-log "$DAVID_AUTH_LOG_ID" --auth-log \
  --signer-pem "$DAVID_PEM" --sign-with "$ROBERT_PEM" \
  --parent-grant-b64 "$ROOT_GRANT_B64" --out-b64 "$S/auth-grant.b64"
export AUTH_GRANT_B64=$(cat "$S/auth-grant.b64")

# 2. David grants Alice a DATA log to write to: grantData = Alice, signed by
#    David (the auth-log holder). This grant IS Alice's write authorization.
#    Alice, as the data-log key holder, delegates its sealing.
./forestrie create-log --prepare --base-url "$FORESTRIE_BASE_URL" \
  --owner-log "$DAVID_AUTH_LOG_ID" --new-log "$ALICE_DATA_LOG_ID" --bootstrap-log "$ROBERT_LOG_ID" --data-log \
  --signer-pem "$ALICE_PEM" --sign-with "$DAVID_PEM" \
  --parent-grant-b64 "$AUTH_GRANT_B64" --out-b64 "$S/alice-data-grant.b64"
./forestrie delegate --coordinator-url "$DELEGATION_COORDINATOR_URL" \
  --log-id "$ALICE_DATA_LOG_ID" --sign-with "$ALICE_PEM" --pinned-registrar-key "$PINNED_REGISTRAR_KEY"
./forestrie create-log --base-url "$FORESTRIE_BASE_URL" \
  --owner-log "$DAVID_AUTH_LOG_ID" --new-log "$ALICE_DATA_LOG_ID" --bootstrap-log "$ROBERT_LOG_ID" --data-log \
  --signer-pem "$ALICE_PEM" --sign-with "$DAVID_PEM" \
  --parent-grant-b64 "$AUTH_GRANT_B64" --out-b64 "$S/alice-data-grant.b64"
export ALICE_GRANT_B64=$(cat "$S/alice-data-grant.b64")

# 3. Alice writes to her data log. Child logs register via the FOREST (root)
#    path — /register/{root}/entries — and the grant directs the statement to the
#    data log. Alice's first write opens the log; a checkpoint follows in ~seconds.
echo '{"alice":"hello from the data log"}' > "$S/alice.json"
./forestrie sign-statement --key "$ALICE_PEM" --payload "$S/alice.json" \
  --content-type application/json --out "$S/alice.cose"
AR=$(./forestrie register --base-url "$FORESTRIE_BASE_URL" --log-id "$ROBERT_LOG_ID" \
  --statement "$S/alice.cose" --grant-b64 "$ALICE_GRANT_B64" --out "$S/alice-receipt.cbor" 2>&1); echo "$AR"
export ALICE_ENTRY_ID=$(echo "$AR" | grep -oE 'entries/[0-9a-f]{32}/receipt' | head -1 | grep -oE '[0-9a-f]{32}')

# 4. Alice's receipt is self-servable offline from her data-log tile (as in Slide 3).
retry fetch_and_receipt "$ALICE_DATA_LOG_ID" "$ALICE_ENTRY_ID" "$S/adata"
echo "Alice's statement is registered under David's SCITT grant and self-servable: $S/adata/receipt.cbor"

# ═══════════════════════════════════════════════════════════════════════════
# SLIDE 7 — Split-view verification: the accumulator is the authority
# ═══════════════════════════════════════════════════════════════════════════
# CHAIN-ANCHORED verify of Alice's statement. The peak is recomputed locally
# from her statement + the receipt's proof path and matched against the data
# log's OWN on-chain accumulator. The contract verified the checkpoint
# signature, the publisher's grant (inclusion in the parent, re-checked every
# publish), and consistency — transitively to the bootstrap — at publish, so
# matching the peak subsumes the signature check AND adds split-view.
# (Purely-offline child verify needs the FOR-297 multi-hop resolver or a
# caller-supplied known log key — see status-2607-09.)
./forestrie verify --genesis "$GENESIS" --receipt "$S/adata/receipt.cbor" \
  --payload "$S/alice.cose" --entry-id "$ALICE_ENTRY_ID" \
  --univocity "$UNIVOCITY_ADDRESS" --log-id "$ALICE_DATA_LOG_ID" --rpc-url "$RPC_URL"

# (SLIDE 8 — trust ladder — is conceptual; no terminal segment.)

# ═══════════════════════════════════════════════════════════════════════════
# SLIDE 9 — Roundup: the closer (same verify as Slide 2, still true)
# ═══════════════════════════════════════════════════════════════════════════
./forestrie verify --genesis "$GENESIS" --receipt "$RECEIPT" \
  --payload "$STMT" --entry-id "$ENTRY_ID"
