#!/bin/bash
#
# preflight.sh — everything the demo needs BEFORE the first on-stage step.
#
# Runs the rehearsal preflight (R1–R5 of the demo outline) against lane-A:
#   R1  deploy a fresh univocity instance (generates Robert's ES256 bootstrap key)
#   R2  operator-onboard the root genesis (mint onboard token + POST genesis)
#   R3  fetch + cache the public genesis for offline verification
#   R4  pre-delegate root sealing (so the first checkpoint lands in seconds)
#   R5  mint the self-referential root grant
#
# All generated state lands under .output/shared/ (gitignored). On success it
# writes .output/shared/demo.env with everything the slides need. Then:
#
#     source .output/shared/demo.env
#     # …and paste demo-script.sh, slide by slide.
#
# Repeatable: each run deploys a FRESH forest (new bootstrap key + logId), so it
# never depends on prior state. Persona keys (David/Alice/Bob) are stable —
# generated once if absent. Requires: doppler auth (canopy/dev), node, jq,
# openssl, curl. The forestrie CLI binary is FETCHED from the public GitHub
# release (no build, nothing checked in) — pin with FORESTRIE_VERSION.
set -euo pipefail
cd "$(dirname "$0")"

step() { printf '\n\033[1;36m▸ %s\033[0m\n' "$*"; }

# --- forestrie CLI: fetched from a GitHub release (gitignored, never committed) ---
FORESTRIE_VERSION="${FORESTRIE_VERSION:-v0.5.0}"

# Download the pinned release binary for this platform into ./forestrie, verify
# its sha256 sidecar, and mark it executable. Idempotent: reuses an already-
# present matching version.
fetch_forestrie() {
  if [ -x ./forestrie ] && ./forestrie --version 2>/dev/null | grep -q "${FORESTRIE_VERSION#v}"; then
    echo "  reuse ./forestrie (${FORESTRIE_VERSION})"
    return 0
  fi
  local os arch asset
  os=$(uname -s); arch=$(uname -m)
  case "$os/$arch" in
    Darwin/arm64)             asset="forestrie-darwin-arm64" ;;
    Linux/x86_64|Linux/amd64) asset="forestrie-linux-x64" ;;
    *)
      echo "no forestrie release asset for $os/$arch — build ./forestrie manually" >&2
      return 1 ;;
  esac
  local base="https://github.com/forestrie/forestrie-cli/releases/download/${FORESTRIE_VERSION}"
  curl -fsSL "$base/$asset" -o ./forestrie.download
  local want got
  want=$(curl -fsSL "$base/$asset.sha256" | awk '{print $1}')
  if command -v sha256sum >/dev/null 2>&1; then
    got=$(sha256sum ./forestrie.download | awk '{print $1}')
  else
    got=$(shasum -a 256 ./forestrie.download | awk '{print $1}')
  fi
  if [ -z "$want" ] || [ "$want" != "$got" ]; then
    rm -f ./forestrie.download
    echo "forestrie ${FORESTRIE_VERSION} ${asset} sha256 mismatch (want ${want:-<none>}, got ${got})" >&2
    return 1
  fi
  chmod +x ./forestrie.download
  mv ./forestrie.download ./forestrie
  echo "  fetched ./forestrie (${FORESTRIE_VERSION}, ${asset})"
}

# --- all shared, cross-slide state lives here (gitignored) ---
SHARED=".output/shared"
mkdir -p "$SHARED"

# --- secrets (preflight only; NOT written to demo.env) ---
export CANOPY_OPS_ADMIN_TOKEN=$(doppler secrets get CANOPY_OPS_ADMIN_TOKEN --project canopy --config dev --plain)
export DEPLOYER_KEY=$(doppler secrets get DEPLOY_KEY --project canopy --config dev --plain)

# --- lane-A config (public) ---
export FORESTRIE_BASE_URL="https://api-forest-2.forestrie.dev"
export RPC_URL="https://sepolia.base.org"
export CHAIN_ID=84532
export DELEGATION_COORDINATOR_URL="https://coordinator-a.forest-2.forestrie.dev"
export KNOWN_SEALER_KEY="z1YarLKXrsRe5egrwrFfbeYadd9lOqplKxbRuMGymHUOSY7YAfdOhhPWb3H72TrPMiMLw0CBMpDPXUGMEvbkOQ=="
export OWNER_ADDRESS="0xdA30dB778C4aAE42BfAE2e81d4b12dEb0725F98C"   # must match DEPLOYER_KEY
export LOG_STORE_URL="https://pub-d7bc2e23615b4cd1a80a0944c3cd3507.r2.dev"
export ROBERT_PEM="$SHARED/robert.es256.pem"
export DAVID_PEM="$SHARED/david.es256.pem"
export ALICE_PEM="$SHARED/alice.es256.pem"
export BOB_PEM="$SHARED/bob.es256.pem"
export GENESIS="$SHARED/genesis.cbor"
DEPLOYMENT="$SHARED/deployment.json"

# --- persona keys: stable across runs; generate only if missing ---
step "Persona keys (David / Alice / Bob)"
for pem in "$DAVID_PEM" "$ALICE_PEM" "$BOB_PEM"; do
  if [ -f "$pem" ]; then
    echo "  reuse $pem"
  else
    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -outform PEM -out "$pem" >/dev/null 2>&1
    echo "  generated $pem"
  fi
done

# --- forestrie CLI binary (fetched, not built/committed) ---
step "forestrie CLI — fetch ${FORESTRIE_VERSION} release binary"
fetch_forestrie

# --- R1: deploy a fresh univocity instance (fresh bootstrap key) ---
step "R1 — deploy univocity + generate bootstrap key (on-chain, Base Sepolia)"
./forestrie deploy --bootstrap-alg es256 \
  --bootstrap-es256-generate --bootstrap-es256-pem-out "$ROBERT_PEM" \
  --owner-address "$OWNER_ADDRESS" --deployer-key "$DEPLOYER_KEY" \
  --rpc-url "$RPC_URL" --out "$DEPLOYMENT"
export UNIVOCITY_ADDRESS=$(jq -r .imutableUnivocity "$DEPLOYMENT")
export ROBERT_LOG_ID=$(jq -r .genesisLogId "$DEPLOYMENT")
# deployment.json carries the txHash but not the block; resolve the deploy block
# from the receipt (portable — curl + jq only) so the on-chain event query
# (fromBlock) works.
DEPLOY_TX=$(jq -r .txHash "$DEPLOYMENT")
DEPLOY_BLOCK_HEX=$(curl -fsS -X POST "$RPC_URL" -H 'Content-Type: application/json' \
  --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getTransactionReceipt\",\"params\":[\"$DEPLOY_TX\"]}" \
  | jq -r '.result.blockNumber // ""')
if [ -n "$DEPLOY_BLOCK_HEX" ] && [ "$DEPLOY_BLOCK_HEX" != "null" ]; then
  export DEPLOY_BLOCK=$(( DEPLOY_BLOCK_HEX ))
else
  export DEPLOY_BLOCK=""
fi
echo "  univocity=$UNIVOCITY_ADDRESS  logId=$ROBERT_LOG_ID  block=${DEPLOY_BLOCK:-<unresolved>}"

# --- R2: operator onboarding of the root genesis (FOR-406: pure CLI) ---
# admin onboard-token mints under the operator credential; onboard-genesis
# posts the direct-sign genesis under the pre-minted token and caches the
# public genesis (the old R3) via --out. x402 payments are the future
# public token source feeding the same --onboard-token input.
step "R2 — onboard the root genesis (admin onboard-token + onboard-genesis)"
ONBOARD_TOKEN=$(./forestrie admin onboard-token \
  --base-url "$FORESTRIE_BASE_URL" --label ietf-126-demo)

# --- R3: onboard + fetch/cache genesis.cbor (offline trust root forever after) ---
step "R3 — onboard-genesis (POST + cache genesis.cbor)"
./forestrie onboard-genesis --base-url "$FORESTRIE_BASE_URL" \
  --deployment "$DEPLOYMENT" --bootstrap-pem "$ROBERT_PEM" \
  --chain-id "$CHAIN_ID" --coordinator-url "$DELEGATION_COORDINATOR_URL" \
  --onboard-token "$ONBOARD_TOKEN" --out "$GENESIS"
echo "  wrote $GENESIS ($(wc -c < "$GENESIS" | tr -d ' ') bytes)"

# --- R4: pre-delegate root sealing (before the first write) ---
step "R4 — pre-delegate root sealing to the vouched standing sealer key"
./forestrie delegate --coordinator-url "$DELEGATION_COORDINATOR_URL" \
  --log-id "$ROBERT_LOG_ID" --sign-with "$ROBERT_PEM" \
  --known-sealer-key "$KNOWN_SEALER_KEY"

# --- R5: mint the self-referential root grant ---
step "R5 — mint the self-referential root grant"
./forestrie create-log --base-url "$FORESTRIE_BASE_URL" \
  --owner-log "$ROBERT_LOG_ID" --new-log "$ROBERT_LOG_ID" \
  --sign-with "$ROBERT_PEM" --self-referential --out-b64 "$SHARED/root-grant.b64"
export ROOT_GRANT_B64=$(cat "$SHARED/root-grant.b64")

# --- write demo.env (secret-free; safe to leave on disk) ---
step "Writing $SHARED/demo.env"
cat > "$SHARED/demo.env" <<EOF
# Generated by preflight.sh — source this before the on-stage steps.
export FORESTRIE_BASE_URL="$FORESTRIE_BASE_URL"
export RPC_URL="$RPC_URL"
export CHAIN_ID=$CHAIN_ID
export DELEGATION_COORDINATOR_URL="$DELEGATION_COORDINATOR_URL"
export KNOWN_SEALER_KEY="$KNOWN_SEALER_KEY"
export LOG_STORE_URL="$LOG_STORE_URL"
export OWNER_ADDRESS="$OWNER_ADDRESS"
export ROBERT_PEM="$ROBERT_PEM"
export DAVID_PEM="$DAVID_PEM"
export ALICE_PEM="$ALICE_PEM"
export BOB_PEM="$BOB_PEM"
export GENESIS="$GENESIS"
export UNIVOCITY_ADDRESS="$UNIVOCITY_ADDRESS"
export ROBERT_LOG_ID="$ROBERT_LOG_ID"
export DEPLOY_BLOCK="$DEPLOY_BLOCK"
export ROOT_GRANT_B64="$ROOT_GRANT_B64"
export GRANT_B64="$ROOT_GRANT_B64"
EOF
echo "  wrote $SHARED/demo.env"

cat <<EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Preflight complete. The forest is deployed, onboarded, delegated, and granted.

Start the demo:

  source $SHARED/demo.env

Then paste demo-script.sh, slide by slide.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
