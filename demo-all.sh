#!/bin/bash
set -euo pipefail
cd ~/Dev/personal/forestrie/demo

export CANOPY_OPS_ADMIN_TOKEN=$(doppler secrets get CANOPY_OPS_ADMIN_TOKEN --project canopy --config dev --plain)
export DEPLOYER_KEY=$(doppler secrets get DEPLOY_KEY --project canopy --config dev --plain)
export FORESTRIE_BASE_URL="https://api-forest-2.forestrie.dev"
export RPC_URL="https://sepolia.base.org"
export CHAIN_ID=84532
export DELEGATION_COORDINATOR_URL="https://coordinator-a.forest-2.forestrie.dev"
export PINNED_REGISTRAR_KEY="z1YarLKXrsRe5egrwrFfbeYadd9lOqplKxbRuMGymHUOSY7YAfdOhhPWb3H72TrPMiMLw0CBMpDPXUGMEvbkOQ=="
export ROBERT_PEM="./robert.es256.pem"
export DAVID_PEM="./david.es256.pem"
export ALICE_PEM="./alice.es256.pem"
export BOB_PEM="./bob.es256.pem"
export OWNER_ADDRESS="0xdA30dB778C4aAE42BfAE2e81d4b12dEb0725F98C"
export WEBHOOK_URL="${WEBHOOK_URL:-https://example.com/sign}"

./forestrie deploy --bootstrap-alg es256 --bootstrap-es256-generate --bootstrap-es256-pem-out "$ROBERT_PEM" --owner-address "$OWNER_ADDRESS" --deployer-key "$DEPLOYER_KEY" --rpc-url "$RPC_URL" --out deployment.json

export UNIVOCITY_ADDRESS=$(jq -r .imutableUnivocity deployment.json)
export ROBERT_LOG_ID=$(jq -r .genesisLogId deployment.json)
export DEPLOY_BLOCK=$(jq -r .blockNumber deployment.json)

# R2 — operator onboarding of the root genesis. Mints a payments-onboard token
# from CANOPY_OPS_ADMIN_TOKEN, builds the genesis CBOR (current private labels),
# and POSTs it; webhookUrl forwards to the coordinator signing-route. The raw
# ops-admin token is NOT accepted here — the genesis endpoint claims a minted
# onboard token. See onboard-genesis.mjs.
node onboard-genesis.mjs

# R3 — fetch + cache the public genesis for offline verification (AFTER onboarding).
curl -sS -o genesis.cbor "$FORESTRIE_BASE_URL/api/forest/$ROBERT_LOG_ID/genesis"

./forestrie delegate --coordinator-url "$DELEGATION_COORDINATOR_URL" --log-id "$ROBERT_LOG_ID" --sign-with "$ROBERT_PEM" --pinned-registrar-key "$PINNED_REGISTRAR_KEY"

./forestrie create-log --base-url "$FORESTRIE_BASE_URL" --owner-log "$ROBERT_LOG_ID" --new-log "$ROBERT_LOG_ID" --sign-with "$ROBERT_PEM" --self-referential --out-b64 root-grant.b64

export ROOT_GRANT_B64=$(cat root-grant.b64)
export GRANT_B64="$ROOT_GRANT_B64"

echo '{"claim":"hello scitt wg","ts":"2026-07-11"}' > statement.json

# The root grant is self-referential (bound to the bootstrap signer, Robert), so
# the root-log statement must be bootstrap-signed. Alice/Bob write to the data
# log in Step 2, against grants bound to them.
./forestrie sign-statement --key "$ROBERT_PEM" --payload statement.json --content-type application/json --out statement.cose

REG_OUT=$(./forestrie register --base-url "$FORESTRIE_BASE_URL" --log-id "$ROBERT_LOG_ID" --statement statement.cose --grant-b64 "$ROOT_GRANT_B64" --out receipt.cbor 2>&1); echo "$REG_OUT"
ENTRY_ID=$(echo "$REG_OUT" | grep -oE 'entries/[0-9a-f]{32}/receipt' | head -1 | grep -oE '[0-9a-f]{32}')

# Verify the STATEMENT receipt: the generic, SCITT-compatible verify — the
# payload is the EXACT registered statement (leaf commits SHA-256(payload)).
./forestrie verify --genesis genesis.cbor --receipt receipt.cbor --payload statement.cose --entry-id "$ENTRY_ID"

export DAVID_AUTH_LOG_ID=$(uuidgen | tr 'A-Z' 'a-z')
export DAVID_DATA_LOG_ID=$(uuidgen | tr 'A-Z' 'a-z')

./forestrie create-log --prepare --base-url "$FORESTRIE_BASE_URL" --owner-log "$ROBERT_LOG_ID" --new-log "$DAVID_AUTH_LOG_ID" --auth-log --signer-pem "$DAVID_PEM" --sign-with "$ROBERT_PEM" --parent-grant-b64 "$ROOT_GRANT_B64" --out-b64 auth-grant.b64

./forestrie delegate --coordinator-url "$DELEGATION_COORDINATOR_URL" --log-id "$DAVID_AUTH_LOG_ID" --sign-with "$DAVID_PEM" --pinned-registrar-key "$PINNED_REGISTRAR_KEY"

./forestrie create-log --base-url "$FORESTRIE_BASE_URL" --owner-log "$ROBERT_LOG_ID" --new-log "$DAVID_AUTH_LOG_ID" --auth-log --signer-pem "$DAVID_PEM" --sign-with "$ROBERT_PEM" --parent-grant-b64 "$ROOT_GRANT_B64" --out-b64 auth-grant.b64

export AUTH_GRANT_B64=$(cat auth-grant.b64)

./forestrie create-log --prepare --base-url "$FORESTRIE_BASE_URL" --owner-log "$DAVID_AUTH_LOG_ID" --new-log "$DAVID_DATA_LOG_ID" --bootstrap-log "$ROBERT_LOG_ID" --data-log --signer-pem "$DAVID_PEM" --sign-with "$DAVID_PEM" --parent-grant-b64 "$AUTH_GRANT_B64" --out-b64 david-data-grant.b64

./forestrie delegate --coordinator-url "$DELEGATION_COORDINATOR_URL" --log-id "$DAVID_DATA_LOG_ID" --sign-with "$DAVID_PEM" --pinned-registrar-key "$PINNED_REGISTRAR_KEY"

./forestrie create-log --base-url "$FORESTRIE_BASE_URL" --owner-log "$DAVID_AUTH_LOG_ID" --new-log "$DAVID_DATA_LOG_ID" --bootstrap-log "$ROBERT_LOG_ID" --data-log --signer-pem "$DAVID_PEM" --sign-with "$DAVID_PEM" --parent-grant-b64 "$AUTH_GRANT_B64" --out-b64 david-data-grant.b64

export DATA_GRANT_B64=$(cat david-data-grant.b64)

./forestrie register-grant --base-url "$FORESTRIE_BASE_URL" --owner-log "$DAVID_AUTH_LOG_ID" --data-log "$DAVID_DATA_LOG_ID" --bootstrap-log "$ROBERT_LOG_ID" --signer-pem "$ALICE_PEM" --parent-grant-b64 "$DATA_GRANT_B64" --sign-with "$DAVID_PEM" --out-b64 grant-alice.b64

export ALICE_GRANT_B64=$(cat grant-alice.b64)

echo '{"alice":"data"}' > alice-stmt.json

./forestrie sign-statement --key "$ALICE_PEM" --payload alice-stmt.json --content-type application/json --out alice-stmt.cose

ALICE_REG_OUT=$(./forestrie register --base-url "$FORESTRIE_BASE_URL" --log-id "$DAVID_DATA_LOG_ID" --statement alice-stmt.cose --grant-b64 "$ALICE_GRANT_B64" --out alice-receipt.cbor 2>&1); echo "$ALICE_REG_OUT"
ALICE_ENTRY_ID=$(echo "$ALICE_REG_OUT" | grep -oE 'entries/[0-9a-f]{32}/receipt' | head -1 | grep -oE '[0-9a-f]{32}')

./forestrie verify --genesis genesis.cbor --receipt alice-receipt.cbor --payload alice-stmt.cose --entry-id "$ALICE_ENTRY_ID"

~/.foundry/bin/cast call "$UNIVOCITY_ADDRESS" "bootstrapConfig()(int64,bytes)" --rpc-url "$RPC_URL"

# Same receipt, now also checked against the on-chain accumulator.
./forestrie verify --genesis genesis.cbor --receipt receipt.cbor --payload statement.cose --entry-id "$ENTRY_ID" --univocity "$UNIVOCITY_ADDRESS" --log-id "$ROBERT_LOG_ID" --rpc-url "$RPC_URL"

echo "Demo complete"
