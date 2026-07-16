# Forestrie Demo — Copy-paste Commands

Full command reference for the IETF SCITT WG demo. All commands are production-ready; paste them into your shell (working directory: `~/Dev/personal/forestrie/demo/`).

## Setup

**Assumption:** `genkeys.sh` has been run and the four PEM files exist in this directory.

### Fetch secrets from Doppler

Fetch the onboard token and funded deployer key from the canopy project:

```bash
export DOPPLER_PROJECT="canopy"
export DOPPLER_CONFIG="dev"
export CANOPY_PAYMENTS_ONBOARD_TOKEN=$(doppler secrets get CANOPY_OPS_ADMIN_TOKEN --project "$DOPPLER_PROJECT" --config "$DOPPLER_CONFIG" --plain)
export DEPLOYER_KEY=$(doppler secrets get DEPLOY_KEY --project "$DOPPLER_PROJECT" --config "$DOPPLER_CONFIG" --plain)

# Verify they're set
echo "✓ Onboard token: ${CANOPY_PAYMENTS_ONBOARD_TOKEN:0:20}…"
echo "✓ Deployer key: ${DEPLOYER_KEY:0:10}…"
```

If you need a different Doppler config (e.g., `stg` or `prd`), override it:

```bash
export DOPPLER_CONFIG="stg"  # or "prd"
```

Alternatively, create `.env.secret` manually if Doppler is unavailable:

```bash
cat > .env.secret <<'EOF'
export CANOPY_PAYMENTS_ONBOARD_TOKEN=$(doppler secrets get CANOPY_OPS_ADMIN_TOKEN --project "$DOPPLER_PROJECT" --config "$DOPPLER_CONFIG" --plain)
export DEPLOYER_KEY=$(doppler secrets get DEPLOY_KEY --project "$DOPPLER_PROJECT" --config "$DOPPLER_CONFIG" --plain)
EOF
source .env.secret
```

### Export environment

```bash
export FORESTRIE_BASE_URL="https://api-forest-2.forestrie.dev"
export RPC_URL="https://sepolia.base.org"
export CHAIN_ID=84532
export DELEGATION_COORDINATOR_URL="https://coordinator-a.forest-2.forestrie.dev"
export PINNED_REGISTRAR_KEY="z1YarLKXrsRe5egrwrFfbeYadd9lOqplKxbRuMGymHUOSY7YAfdOhhPWb3H72TrPMiMLw0CBMpDPXUGMEvbkOQ=="
export ROBERT_PEM=./robert.es256.pem
export DAVID_PEM=./david.es256.pem
export ALICE_PEM=./alice.es256.pem
export BOB_PEM=./bob.es256.pem
```

---

## Preflight

**Prerequisites:** The operator must complete R2 before you can proceed with R4–R5. Contact the operator and provide them with the `ROBERT_LOG_ID` from R1 output, then wait for confirmation that the genesis has been onboarded.

### R1 — Deploy ImutableUnivocity

Deploy a univocity contract on Base Sepolia and generate the bootstrap ES256 key. The CLI writes the contract address and genesis log ID to `deployment.json`.

```bash
export OWNER_ADDRESS="0xdA30dB778C4aAE42BfAE2e81d4b12dEb0725F98C"

././forestrie deploy \
  --bootstrap-alg es256 \
  --bootstrap-es256-generate --bootstrap-es256-pem-out "$ROBERT_PEM" \
  --owner-address "$OWNER_ADDRESS" \
  --deployer-key "$DEPLOYER_KEY" \
  --rpc-url "$RPC_URL" \
  --out deployment.json
```

Extract the contract address and genesis log ID:

```bash
export UNIVOCITY_ADDRESS=$(jq -r .imutableUnivocity deployment.json)
export ROBERT_LOG_ID=$(jq -r .genesisLogId deployment.json)
export DEPLOY_BLOCK=$(jq -r .blockNumber deployment.json)
echo "Deployed: $UNIVOCITY_ADDRESS"
echo "Genesis log: $ROBERT_LOG_ID"
```

### R2 — Onboard the root genesis

Create the genesis CBOR body from the deployment outputs, then post it to the API. The onboard token comes from `.env.secret`.

**Step 1: Create genesis-body.cbor**

```bash
source .env.secret

node - <<'NODE'
import fs from 'fs';
import crypto from 'crypto';

const deployment = JSON.parse(fs.readFileSync('deployment.json', 'utf-8'));
const bootstrapPem = fs.readFileSync('./robert.es256.pem', 'utf-8');

const keyObj = crypto.createPrivateKey({ key: bootstrapPem, format: 'pem' });
const pubKey = crypto.createPublicKey(keyObj);
const pubKeyDer = pubKey.export({ format: 'der', type: 'spki' });
const xyCoordinate = pubKeyDer.slice(26, 90);

const contractAddr = deployment.imutableUnivocity.toLowerCase().replace('0x', '');
const contractAddrBytes = Buffer.from(contractAddr, 'hex');
const chainIdStr = deployment.chainId.toString();

const cbor = [0xa5];
cbor.push(0x3a, 0x00, 0x01, 0x09, 0x08, 0x02);
cbor.push(0x3a, 0x00, 0x01, 0x09, 0x71, 0x26);
cbor.push(0x3a, 0x00, 0x01, 0x09, 0x72, 0x58, 0x40, ...xyCoordinate);
cbor.push(0x3a, 0x00, 0x01, 0x09, 0x6f, 0x58, 0x14, ...contractAddrBytes);
const chainIdBytes = Buffer.from(chainIdStr);
cbor.push(0x3a, 0x00, 0x01, 0x09, 0x70, 0x78, chainIdBytes.length, ...chainIdBytes);

fs.writeFileSync('genesis-body.cbor', Buffer.from(cbor));
console.log('✓ genesis-body.cbor created');
NODE
```

**Step 2: Post to operator API**

Set the webhook URL for the coordinator to call back on checkpoint signing:

```bash
# REQUIRED: Replace with your actual operator signing route
export WEBHOOK_URL="https://your-operator-signing-route.example.com/sign"

curl -sS -X POST \
  -H "Authorization: Bearer $CANOPY_PAYMENTS_ONBOARD_TOKEN" \
  -H "Content-Type: application/cbor" \
  --data-binary @genesis-body.cbor \
  "$FORESTRIE_BASE_URL/api/forest/$ROBERT_LOG_ID/genesis?webhookUrl=$WEBHOOK_URL"

echo "✓ Genesis onboarded"
```

**Troubleshooting:** If you get `401 Unauthorized - Invalid or revoked onboard token`:
1. Verify `CANOPY_PAYMENTS_ONBOARD_TOKEN` is set: `echo $CANOPY_PAYMENTS_ONBOARD_TOKEN`
2. Fetch a fresh token: `doppler secrets get CANOPY_OPS_ADMIN_TOKEN --project canopy --config dev --plain`
3. Verify the token is not expired in Doppler

Once R2 succeeds, the coordinator is notified and you can proceed to R4.

### R3 — Fetch and cache the genesis

Fetch the public genesis CBOR (no auth needed) and verify it's available:

```bash
curl -sS "$FORESTRIE_BASE_URL/api/forest/$ROBERT_LOG_ID/genesis" -o genesis.cbor
curl -sS "$FORESTRIE_BASE_URL/.well-known/scitt-configuration" | jq .
```

### R4 — Pre-delegate the root log

Robert pre-signs a delegation to the custodian's standing sealer key (vetted via the pinned registrar key).

```bash
./forestrie delegate \
  --coordinator-url "$DELEGATION_COORDINATOR_URL" \
  --log-id "$ROBERT_LOG_ID" \
  --sign-with "$ROBERT_PEM" \
  --pinned-registrar-key "$PINNED_REGISTRAR_KEY"
```

### R5 — Register the root grant (self-referential)

Robert registers the root log's own creation grant; the signer is the bootstrap key.

```bash
./forestrie create-log \
  --base-url "$FORESTRIE_BASE_URL" \
  --owner-log "$ROBERT_LOG_ID" \
  --new-log "$ROBERT_LOG_ID" \
  --sign-with "$ROBERT_PEM" \
  --self-referential \
  --out-b64 root-grant.b64

export ROOT_GRANT_B64=$(cat root-grant.b64)
echo "Root grant: $ROOT_GRANT_B64"
```

---

## Step 1 — Register a signed statement

Alice signs a statement and registers it with the root grant. The receipt returns in ~4–8s and verifies offline.

### 1a. Sign a statement

```bash
echo '{"claim":"hello scitt wg","ts":"2026-07-11"}' > statement.json

./forestrie sign-statement \
  --key "$ALICE_PEM" \
  --payload statement.json \
  --content-type application/json \
  --out statement.cose
```

### 1b. Register it

```bash
./forestrie register \
  --base-url "$FORESTRIE_BASE_URL" \
  --log-id "$ROBERT_LOG_ID" \
  --statement statement.cose \
  --grant-b64 "$ROOT_GRANT_B64" \
  --out receipt.cbor

export GRANT_B64="$ROOT_GRANT_B64"
```

### 1c. Verify the receipt offline

```bash
./forestrie verify \
  --genesis genesis.cbor \
  --receipt receipt.cbor \
  --committed-grant "$GRANT_B64"
```

---

## Step 1b — Amortization: 100 statements, one checkpoint, offline receipts

Submit 100 statements, wait once for the covering checkpoint, then derive all 100 receipts locally (zero operator calls per receipt).

```bash
export LOG_STORE_URL="https://pub-d7bc2e23615b4cd1a80a0944c3cd3507.r2.dev"

N=100 FLUSH=3 \
  FORESTRIE_BASE_URL="$FORESTRIE_BASE_URL" \
  ROOT_LOG_ID="$ROBERT_LOG_ID" \
  ROBERT_PEM="$ROBERT_PEM" \
  GRANT_FILE=root-grant.b64 \
  LOG_STORE_URL="$LOG_STORE_URL" \
  bun docs/demo/batch-receipts.ts
```

---

## Step 2 — Build the authorization hierarchy

David creates an auth log and a data log, then authorizes Alice and Bob as writers. Each step is a COSE statement in a parent log.

### 2a. David's auth log — prepare, delegate, create

Generate two UUIDs for David's logs:

```bash
export DAVID_AUTH_LOG_ID=$(uuidgen | tr 'A-Z' 'a-z')
export DAVID_DATA_LOG_ID=$(uuidgen | tr 'A-Z' 'a-z')
echo "Auth log: $DAVID_AUTH_LOG_ID"
echo "Data log: $DAVID_DATA_LOG_ID"
```

Prepare (register David's public root at the coordinator):

```bash
./forestrie create-log --prepare \
  --base-url "$FORESTRIE_BASE_URL" \
  --owner-log "$ROBERT_LOG_ID" \
  --new-log "$DAVID_AUTH_LOG_ID" \
  --auth-log \
  --signer-pem "$DAVID_PEM" \
  --sign-with "$ROBERT_PEM" \
  --parent-grant-b64 "$ROOT_GRANT_B64" \
  --out-b64 auth-grant.b64
```

Delegate (David pre-signs sealing on his auth log):

```bash
./forestrie delegate \
  --coordinator-url "$DELEGATION_COORDINATOR_URL" \
  --log-id "$DAVID_AUTH_LOG_ID" \
  --sign-with "$DAVID_PEM" \
  --pinned-registrar-key "$PINNED_REGISTRAR_KEY"
```

Create (sequence the auth log):

```bash
./forestrie create-log \
  --base-url "$FORESTRIE_BASE_URL" \
  --owner-log "$ROBERT_LOG_ID" \
  --new-log "$DAVID_AUTH_LOG_ID" \
  --auth-log \
  --signer-pem "$DAVID_PEM" \
  --sign-with "$ROBERT_PEM" \
  --parent-grant-b64 "$ROOT_GRANT_B64" \
  --out-b64 auth-grant.b64

export AUTH_GRANT_B64=$(cat auth-grant.b64)
```

### 2b. David's data log — prepare, delegate, create

Prepare:

```bash
./forestrie create-log --prepare \
  --base-url "$FORESTRIE_BASE_URL" \
  --owner-log "$DAVID_AUTH_LOG_ID" \
  --new-log "$DAVID_DATA_LOG_ID" \
  --bootstrap-log "$ROBERT_LOG_ID" \
  --data-log \
  --signer-pem "$DAVID_PEM" \
  --sign-with "$DAVID_PEM" \
  --parent-grant-b64 "$AUTH_GRANT_B64" \
  --out-b64 david-data-grant.b64
```

Delegate:

```bash
./forestrie delegate \
  --coordinator-url "$DELEGATION_COORDINATOR_URL" \
  --log-id "$DAVID_DATA_LOG_ID" \
  --sign-with "$DAVID_PEM" \
  --pinned-registrar-key "$PINNED_REGISTRAR_KEY"
```

Create:

```bash
./forestrie create-log \
  --base-url "$FORESTRIE_BASE_URL" \
  --owner-log "$DAVID_AUTH_LOG_ID" \
  --new-log "$DAVID_DATA_LOG_ID" \
  --bootstrap-log "$ROBERT_LOG_ID" \
  --data-log \
  --signer-pem "$DAVID_PEM" \
  --sign-with "$DAVID_PEM" \
  --parent-grant-b64 "$AUTH_GRANT_B64" \
  --out-b64 david-data-grant.b64

export DATA_GRANT_B64=$(cat david-data-grant.b64)
```

### 2c. Authorize Alice and Bob as writers

Grant Alice write-only access to David's data log:

```bash
./forestrie register-grant \
  --base-url "$FORESTRIE_BASE_URL" \
  --owner-log "$DAVID_AUTH_LOG_ID" \
  --data-log "$DAVID_DATA_LOG_ID" \
  --bootstrap-log "$ROBERT_LOG_ID" \
  --signer-pem "$ALICE_PEM" \
  --parent-grant-b64 "$DATA_GRANT_B64" \
  --sign-with "$DAVID_PEM" \
  --out-b64 grant-alice.b64

export ALICE_GRANT_B64=$(cat grant-alice.b64)
```

Grant Bob write-only access:

```bash
./forestrie register-grant \
  --base-url "$FORESTRIE_BASE_URL" \
  --owner-log "$DAVID_AUTH_LOG_ID" \
  --data-log "$DAVID_DATA_LOG_ID" \
  --bootstrap-log "$ROBERT_LOG_ID" \
  --signer-pem "$BOB_PEM" \
  --parent-grant-b64 "$DATA_GRANT_B64" \
  --sign-with "$DAVID_PEM" \
  --out-b64 grant-bob.b64

export BOB_GRANT_B64=$(cat grant-bob.b64)
```

### 2d. Alice and Bob register statements to the data log

Alice signs and registers:

```bash
echo '{"alice":"statement"}' > alice-stmt.json

./forestrie sign-statement \
  --key "$ALICE_PEM" \
  --payload alice-stmt.json \
  --content-type application/json \
  --out alice-stmt.cose

./forestrie register \
  --base-url "$FORESTRIE_BASE_URL" \
  --log-id "$DAVID_DATA_LOG_ID" \
  --statement alice-stmt.cose \
  --grant-b64 "$ALICE_GRANT_B64" \
  --out alice-receipt.cbor
```

Bob signs and registers:

```bash
echo '{"bob":"statement"}' > bob-stmt.json

./forestrie sign-statement \
  --key "$BOB_PEM" \
  --payload bob-stmt.json \
  --content-type application/json \
  --out bob-stmt.cose

./forestrie register \
  --base-url "$FORESTRIE_BASE_URL" \
  --log-id "$DAVID_DATA_LOG_ID" \
  --statement bob-stmt.cose \
  --grant-b64 "$BOB_GRANT_B64" \
  --out bob-receipt.cbor
```

Verify both:

```bash
./forestrie verify \
  --genesis genesis.cbor \
  --receipt alice-receipt.cbor \
  --committed-grant "$ALICE_GRANT_B64"

./forestrie verify \
  --genesis genesis.cbor \
  --receipt bob-receipt.cbor \
  --committed-grant "$BOB_GRANT_B64"
```

---

## Step 3 — Verify the bootstrap key on-chain

Verify that the bootstrap key bound to the ImutableUnivocity contract matches the signer of the root grant.

```bash
~/.foundry/bin/cast call "$UNIVOCITY_ADDRESS" "bootstrapConfig()(int64,bytes)" --rpc-url "$RPC_URL"
```

Re-run the offline verifier to show the same grant still verifies:

```bash
./forestrie verify \
  --genesis genesis.cbor \
  --receipt receipt.cbor \
  --committed-grant "$GRANT_B64"
```

---

## Step 4 — Self-serve receipts

### 4a. Fetch the massif and checkpoint (public read-only)

```bash
export LOG_STORE_URL="https://pub-d7bc2e23615b4cd1a80a0944c3cd3507.r2.dev"
export MASSIF_H=14
export MASSIF_IDX=0000000000000000

curl -sS "$LOG_STORE_URL/v2/merklelog/massifs/$MASSIF_H/$DAVID_DATA_LOG_ID/$MASSIF_IDX.log" \
  -o massif.log

curl -sS "$LOG_STORE_URL/v2/merklelog/checkpoints/$MASSIF_H/$DAVID_DATA_LOG_ID/$MASSIF_IDX.sth" \
  -o checkpoint.sth
```

### 4b. Self-create a receipt (no operator call)

Derive a receipt for the entry at MMR index 0:

```bash
./forestrie create-receipt \
  --massif massif.log \
  --checkpoint checkpoint.sth \
  --mmr-index 0 \
  --out receipt-selfserve.cbor
```

### 4c. Self-complete a grant header

Recover a grant's mmrIndex and idtimestamp from the massif, rebuild its inclusion proof offline:

```bash
./forestrie complete-grant \
  --grant grant-alice.b64 \
  --checkpoint checkpoint.sth \
  --massif massif.log \
  --out-b64 grant-alice-completed.b64

export ALICE_GRANT_COMPLETED=$(cat grant-alice-completed.b64)
```

### 4d. Decode the self-served receipt

Inspect the COSE structure and MMR proof:

```bash
./forestrie decode-receipt receipt-selfserve.cbor
```

### 4e. Verify the self-served receipt offline

```bash
./forestrie verify \
  --genesis genesis.cbor \
  --receipt receipt-selfserve.cbor \
  --committed-grant "$ALICE_GRANT_COMPLETED"
```

---

## Step 5 — Operator exit: verify against the public record

### 5a. Verify a receipt against the on-chain accumulator

Recompute the peak and check it matches the anchored accumulator (no signature verification needed):

```bash
./forestrie verify \
  --genesis genesis.cbor \
  --receipt receipt.cbor \
  --committed-grant "$GRANT_B64" \
  --univocity "$UNIVOCITY_ADDRESS" \
  --log-id "$ROBERT_LOG_ID" \
  --rpc-url "$RPC_URL"
```

### 5b. (Optional) Watch checkpoints advance on-chain

Query the Base Sepolia blockchain for all `CheckpointPublished` events on the Univocity contract (split-view protection made concrete):

```bash
export CHECKPOINT_TOPIC="0x156942b408823cb05a16027962ea485fa7171d99779ee04094280b2569482426"

curl -sS -X POST "$RPC_URL" -H 'Content-Type: application/json' --data '{
  "jsonrpc":"2.0","id":1,"method":"eth_getLogs","params":[{
    "address":"'"$UNIVOCITY_ADDRESS"'","fromBlock":"'"$DEPLOY_BLOCK"'","toBlock":"latest",
    "topics":["'"$CHECKPOINT_TOPIC"'"]}]}' \
| jq '.result[] | {block: (.blockNumber | tonumber), logId: .topics[1], mmrSize: (.data[66:130] | tonumber)}'
```

### 5c. Final verification offline

Run the offline verifier one last time — same command as Step 1, proving the receipt stays valid forever:

```bash
./forestrie verify \
  --genesis genesis.cbor \
  --receipt receipt.cbor \
  --committed-grant "$GRANT_B64"
```

---

## Optional Aside — Multisig Safe root (KS256)

If you have a KS256 deployment pre-provisioned, verify the root key is a Safe contract and compatible with ERC-1271:

```bash
~/.foundry/bin/cast call "$KS256_UNIVOCITY_ADDRESS" "logConfig(bytes32)(...)" <log-id> --rpc-url "$RPC_URL"
```

---

## Command reference quick lookup

| Action | Command |
|--------|---------|
| **Deploy** | `./forestrie deploy --bootstrap-alg es256 ...` |
| **Sign statement** | `./forestrie sign-statement --key PEM --payload file ...` |
| **Register** | `./forestrie register --base-url URL --log-id UUID --statement cose ...` |
| **Delegate** | `./forestrie delegate --coordinator-url URL --log-id UUID --sign-with PEM ...` |
| **Create log** | `./forestrie create-log --owner-log UUID --new-log UUID --sign-with PEM ...` |
| **Authorize writer** | `./forestrie register-grant --owner-log UUID --data-log UUID --signer-pem PEM ...` |
| **Self-serve receipt** | `./forestrie create-receipt --massif .log --checkpoint .sth --mmr-index N ...` |
| **Complete grant** | `./forestrie complete-grant --grant b64 --checkpoint .sth --massif .log ...` |
| **Verify (offline)** | `./forestrie verify --genesis .cbor --receipt .cbor --committed-grant b64` |
| **Verify (on-chain)** | `./forestrie verify ... --univocity ADDR --log-id UUID --rpc-url URL` |
| **Decode receipt** | `./forestrie decode-receipt receipt.cbor` |
