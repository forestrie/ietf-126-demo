#!/bin/bash
#
# preflight.sh — everything the demo needs BEFORE the first on-stage step.
#
# Runs the rehearsal preflight (R1–R5 of the demo outline) against the selected
# lane — pass --lane=a or --lane=b (default b). The lane only picks a handful of
# endpoints + the ops-admin token source; the R1–R5 steps and every slide-NN
# script are lane-agnostic (they read the generated demo.env):
#   R1  deploy a fresh univocity instance (generates Robert's ES256 bootstrap key)
#   R2  operator-onboard the root genesis (mint onboard token + POST genesis)
#   R3  fetch + cache the public genesis for offline verification
#   R4  pre-delegate root sealing (so the first checkpoint lands in seconds)
#   R5  mint the self-referential root grant
#   R6  create David's auth log under the root, and wait until it is anchored
#   R7  create Alice's data log under David's, and wait until it is anchored
#
# A log's authority is used only once anchored: canopy refuses writes under a
# new log until its owner has published, on chain, a checkpoint covering the
# log's create grant. Each level waits for its owner's next checkpoint, a
# minute or two, so preflight builds the slide-6 hierarchy ahead of time.
#
# All generated state lands under .output/shared/ (gitignored). On success it
# writes .output/shared/demo.env with everything the slides need. Then:
#
#     source .output/shared/demo.env
#     # …and paste demo-script.sh, slide by slide.
#
# R1 and R2 cost gas and an x402 payment, so demo.env is written as soon as R5
# completes and again after each log. If R6 or R7 fails (an anchoring wait can
# time out), rerun with --logs-only: it reuses the forest demo.env records and
# creates the two logs again, without redeploying or paying.
#
# Repeatable: each run deploys a FRESH forest (new bootstrap key + logId), so it
# never depends on prior state. Persona keys (David/Alice/Bob) are stable —
# generated once if absent. Requires: doppler auth (canopy/dev for lane a,
# system-testing/stg for lane b), node, jq, openssl, curl, uuidgen. The forestrie CLI
# binary is FETCHED from the public GitHub release (no build, nothing checked
# in) — pin with FORESTRIE_VERSION (v0.15.0 or later: it waits for anchoring).
set -euo pipefail
cd "$(dirname "$0")"

step() { printf '\n\033[1;36m▸ %s\033[0m\n' "$*"; }

# --- lane selection: --lane=a|b (default b) ---
LANE=b
LOGS_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --lane=a | --lane=A) LANE=a ;;
    --lane=b | --lane=B) LANE=b ;;
    --logs-only) LOGS_ONLY=1 ;;
    --lane=*) echo "unknown --lane (use a|b): $arg" >&2; exit 1 ;;
    *) echo "unknown arg: $arg" >&2; exit 1 ;;
  esac
done

# Fail before anything costs gas or a payment.
for tool in doppler jq openssl curl uuidgen; do
  command -v "$tool" >/dev/null 2>&1 || { echo "preflight needs $tool on PATH" >&2; exit 1; }
done

# --- forestrie CLI: fetched from a GitHub release (gitignored, never committed) ---
FORESTRIE_VERSION="${FORESTRIE_VERSION:-v0.15.0}"

# SHA-256 of the default release's binaries, checked as well as the release's
# own sidecar, so a replaced release asset is caught. An overridden
# FORESTRIE_VERSION is checked against its sidecar only.
pinned_sha256() { # $1=asset
  [ "$FORESTRIE_VERSION" = v0.15.0 ] || return 0
  case "$1" in
    forestrie-darwin-arm64) echo b66c822fe99671fab13efd62ce0fa75e38b5bf730b0edec8d01020579b00edfb ;;
    forestrie-linux-x64)    echo c93bfb0de2332571d7126341b57ad2ec1768209733b513819e92e90cc2096069 ;;
  esac
}

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
  local pinned
  pinned=$(pinned_sha256 "$asset")
  if [ -n "$pinned" ] && [ "$pinned" != "$got" ]; then
    rm -f ./forestrie.download
    echo "forestrie ${FORESTRIE_VERSION} ${asset} is not the pinned build (want ${pinned}, got ${got})" >&2
    return 1
  fi
  chmod +x ./forestrie.download
  mv ./forestrie.download ./forestrie
  echo "  fetched ./forestrie (${FORESTRIE_VERSION}, ${asset})"
}

# --- all shared, cross-slide state lives here (gitignored) ---
SHARED=".output/shared"
mkdir -p "$SHARED"
# The slides load demo.state over demo.env, so handoffs an earlier forest's
# slides saved (log ids, entry ids) would point this forest's slides at the
# old logs. A fresh forest makes all of them stale.
rm -f "$SHARED/demo.state"

# --- lane-specific config: ONLY the canopy + coordinator endpoints differ
# between lanes. Since v0.6.0 onboarding is fully self-service (attested +
# x402-paid) — no operator credential appears anywhere in this script. ---
step "Lane $LANE — endpoints"
case "$LANE" in
  a)
    # api-a, NOT the unprefixed api-forest-2 alias. forest-1 binds api-{DNS_SUB}
    # as a custom domain on the LANE B worker (dns_catalog.tf
    # edge_api_alias_fqdn), so the alias belongs to lane B.
    #
    # History, because the first version of this comment got it wrong: until
    # 2026-07-23 a stale zone route shadowed that custom domain and sent the
    # alias to lane A, so the old value here happened to reach lane A and the
    # demo was accidentally consistent. The route has since been removed
    # (FOR-453), so the alias now really does resolve to lane B -- and a stale
    # checkout using it fails at R4 with "no standing delegate-key entry for
    # log", after R1-R3 have already deployed and onboarded on the wrong lane.
    # Naming the lane explicitly is what actually protects this.
    export FORESTRIE_BASE_URL="https://api-a.forest-2.forestrie.dev"
    export DELEGATION_COORDINATOR_URL="https://coordinator-a.forest-2.forestrie.dev"
    # forest-1 provisions log storage PER SLOT (forest-1 log-storage.tf): slot a
    # keeps the legacy `forest-dev-5-logs` bucket; its Cloudflare managed domain:
    export LOG_STORE_URL="${LOG_STORE_URL:-https://pub-d7bc2e23615b4cd1a80a0944c3cd3507.r2.dev}"
    ;;
  b)
    export FORESTRIE_BASE_URL="https://api-b.forest-2.forestrie.dev"
    export DELEGATION_COORDINATOR_URL="https://coordinator-b.forest-2.forestrie.dev"
    # slot b log storage is a SEPARATE bucket `forest-dev-5-logs-b` (suffix `-b`);
    # its Cloudflare managed r2.dev domain (distinct hash from slot a):
    export LOG_STORE_URL="${LOG_STORE_URL:-https://pub-7ed90970555841999fcd76749f4f9ec8.r2.dev}"
    ;;
esac
echo "  base=$FORESTRIE_BASE_URL  coordinator=$DELEGATION_COORDINATOR_URL"

# --- lane-agnostic config ---
# DEPLOY_KEY is a Base Sepolia gas-only payer (same chain both lanes), so the
# deploy key + its OWNER_ADDRESS are shared; KNOWN_SEALER_KEY (registrar) and
# RPC/chain are shared too.
export DEPLOYER_KEY=$(doppler secrets get DEPLOY_KEY --project canopy --config dev --plain)
export RPC_URL="https://sepolia.base.org"
export CHAIN_ID=84532
export KNOWN_SEALER_KEY="z1YarLKXrsRe5egrwrFfbeYadd9lOqplKxbRuMGymHUOSY7YAfdOhhPWb3H72TrPMiMLw0CBMpDPXUGMEvbkOQ=="
export OWNER_ADDRESS="0xdA30dB778C4aAE42BfAE2e81d4b12dEb0725F98C"   # matches DEPLOYER_KEY
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

# --- R1–R5: a fresh forest, or (--logs-only) the one demo.env records ---
create_forest() {
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

  # --- R2: attested self-service onboarding (ADR-0059 D8 + x402) ---
  # The bootstrap key Robert generated in R1 signs a registrant attestation —
  # proof that the onboard request comes from the deployed contract's only
  # legitimate registrant — and the deployer wallet pays the operator's x402
  # challenge (nominal USDC on Base Sepolia; REAL settlement). No operator
  # credential is involved: the payment and the attestation are the whole
  # authorization.
  step "R2 — attested onboard request (x402-paid, bootstrap-key attestation)"
  ONBOARD_TOKEN=$(./forestrie onboard-request \
    --base-url "$FORESTRIE_BASE_URL" --deployment "$DEPLOYMENT" \
    --bootstrap-pem "$ROBERT_PEM" --label ietf-126-demo \
    --contact-email robert@ietf-126.demo \
    --payer-key "$DEPLOYER_KEY")

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
  # A root is anchored once its contract holds the genesis key, so the wait
  # returns at once; it still proves the contract is rooted at no other log.
  step "R5 — mint the self-referential root grant (and check the root is anchored)"
  ./forestrie create-log --base-url "$FORESTRIE_BASE_URL" \
    --owner-log "$ROBERT_LOG_ID" --new-log "$ROBERT_LOG_ID" \
    --sign-with "$ROBERT_PEM" --self-referential --out-b64 "$SHARED/root-grant.b64" \
    --wait-anchored --genesis "$GENESIS" --rpc-url "$RPC_URL"
  export ROOT_GRANT_B64=$(cat "$SHARED/root-grant.b64")
}

# --logs-only: reuse the forest an earlier run recorded, on the same lane.
reuse_forest() {
  if [ ! -f "$SHARED/demo.env" ]; then
    echo "--logs-only needs $SHARED/demo.env from an earlier preflight" >&2
    return 1
  fi
  local lane_url="$FORESTRIE_BASE_URL"
  # shellcheck source=/dev/null
  source "$SHARED/demo.env"
  if [ "$FORESTRIE_BASE_URL" != "$lane_url" ]; then
    echo "$SHARED/demo.env is for $FORESTRIE_BASE_URL, not lane $LANE ($lane_url)" >&2
    return 1
  fi
  echo "  univocity=$UNIVOCITY_ADDRESS  logId=$ROBERT_LOG_ID"
}

# demo.env: everything the slides need (secret-free; safe to leave on disk).
# The R6/R7 values are empty until those steps complete.
write_demo_env() {
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
export DAVID_AUTH_LOG_ID="${DAVID_AUTH_LOG_ID:-}"
export AUTH_GRANT="${AUTH_GRANT:-}"
export AUTH_GRANT_B64="${AUTH_GRANT_B64:-}"
export ALICE_DATA_LOG_ID="${ALICE_DATA_LOG_ID:-}"
export ALICE_GRANT="${ALICE_GRANT:-}"
export ALICE_GRANT_B64="${ALICE_GRANT_B64:-}"
EOF
}

# A failure once the forest exists says how to finish without paying again.
FOREST_READY=0
on_exit() {
  local status=$?
  if [ "$status" -ne 0 ] && [ "$FOREST_READY" = 1 ]; then
    printf '\n\033[1;31m%s\033[0m\n' "preflight failed after the forest was ready; $SHARED/demo.env records it. Rerun ./preflight.sh --lane=$LANE --logs-only to create the slide-6 logs again without redeploying or paying." >&2
  fi
}
trap on_exit EXIT

if [ "$LOGS_ONLY" = 1 ]; then
  step "--logs-only: reuse the forest in $SHARED/demo.env (R1–R5 skipped)"
  reuse_forest
else
  create_forest
fi
write_demo_env
FOREST_READY=1

# --- R6: David's auth log, under Robert's root ---
# prepare → delegate → create, as slide 6 narrates: David delegates his log's
# sealing before its first checkpoint, and create waits until the root has
# published a checkpoint covering the create grant.
step "R6 — David's auth log (prepare → delegate → create, wait until anchored)"
DAVID_AUTH_LOG_ID=$(uuidgen | tr 'A-Z' 'a-z'); export DAVID_AUTH_LOG_ID
export AUTH_GRANT="$SHARED/auth-grant.b64"
david_create_log() { # $@ = extra flags
  ./forestrie create-log --base-url "$FORESTRIE_BASE_URL" \
    --owner-log "$ROBERT_LOG_ID" --new-log "$DAVID_AUTH_LOG_ID" --auth-log \
    --signer-pem "$DAVID_PEM" --sign-with "$ROBERT_PEM" \
    --parent-grant-b64 "$ROOT_GRANT_B64" --out-b64 "$AUTH_GRANT" "$@"
}
david_create_log --prepare
./forestrie delegate --coordinator-url "$DELEGATION_COORDINATOR_URL" \
  --log-id "$DAVID_AUTH_LOG_ID" --sign-with "$DAVID_PEM" \
  --known-sealer-key "$KNOWN_SEALER_KEY"
david_create_log --wait-anchored --genesis "$GENESIS" --rpc-url "$RPC_URL"
AUTH_GRANT_B64=$(cat "$AUTH_GRANT"); export AUTH_GRANT_B64
write_demo_env

# --- R7: Alice's data log, under David's auth log ---
# Its create grant is registered under David's log, which canopy accepts only
# now that David's log is anchored. Alice writes to it on slide 6.
step "R7 — Alice's data log (prepare → delegate → create, wait until anchored)"
ALICE_DATA_LOG_ID=$(uuidgen | tr 'A-Z' 'a-z'); export ALICE_DATA_LOG_ID
export ALICE_GRANT="$SHARED/alice-data-grant.b64"
alice_create_log() { # $@ = extra flags
  ./forestrie create-log --base-url "$FORESTRIE_BASE_URL" \
    --owner-log "$DAVID_AUTH_LOG_ID" --new-log "$ALICE_DATA_LOG_ID" \
    --bootstrap-log "$ROBERT_LOG_ID" --data-log \
    --signer-pem "$ALICE_PEM" --sign-with "$DAVID_PEM" \
    --parent-grant-b64 "$AUTH_GRANT_B64" --out-b64 "$ALICE_GRANT" "$@"
}
alice_create_log --prepare
./forestrie delegate --coordinator-url "$DELEGATION_COORDINATOR_URL" \
  --log-id "$ALICE_DATA_LOG_ID" --sign-with "$ALICE_PEM" \
  --known-sealer-key "$KNOWN_SEALER_KEY"
alice_create_log --wait-anchored --genesis "$GENESIS" --rpc-url "$RPC_URL"
ALICE_GRANT_B64=$(cat "$ALICE_GRANT"); export ALICE_GRANT_B64

# --- demo.env, now complete ---
step "Writing $SHARED/demo.env"
write_demo_env
echo "  wrote $SHARED/demo.env"

cat <<EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Preflight complete. The forest is deployed, onboarded, delegated, and granted,
and David's auth log and Alice's data log under it are anchored.

Start the demo:

  source $SHARED/demo.env

Then paste demo-script.sh, slide by slide.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
