## Forestrie

Forestrie is a Transparency Service offering a SCRAPI interface for registering
SCITT signed statements  and obtaing COSE-Receipts based on the
draft-bryce-cose-receipts-mmr-profile ID

## The Forestrie TS is a "pipe" not a "store".

Checkpoint publishing is permissionless and requires only an mmr-profile signed
consistency proof from the logs owner.

Split-view protection and checkpoint publishing authority for logs is provided
by an independently provisioned smart contract. Chain of choice, no particular
EVM is favoured.

The contract deployer has no special privilages, the "root" log is declared at deployment time.
The root log owner only has authority to publish checkpoint for its own log and is not special
in any other way.

Log owners are free to exit to other TS operators at any time and retain the
ability to continue publishing checkpoints independently.

## Async registration

The affordances of the mmr-profile decouple receipt production from statement
registration.

Receipts can be self-asembled, offline, for any entry given only a published checkpoint.

Typically this only requires access to the "head" tile and the latest published
checkpoint.

1000's of complete registrations per second, including receipts, can be
amortized by a single checkpoint fetch. Typical latency 1-3 seconds for a
checkpoint that enables self local assembly of 1000's of receipts.



# IETF 126 — Forestrie demo

Forestrie is a Transparency Service offering a SCRAPI interface for registering
SCITT signed statements and obtaing [MMR-profile draft COSE
Receipts](https://github.com/robinbryce/draft-bryce-cose-receipts-mmr-profile/blob/main/draft-bryce-cose-receipts-mmr-profile.md)


## Setup (run before the talk)

`preflight.sh` stands up a fresh forest (deploy → onboard genesis → fetch
genesis → delegate root sealing → mint the root grant) and writes a secret-free
`demo.env`. Run it once, then `source demo.env` so every command below has
`FORESTRIE_BASE_URL`, `ROBERT_LOG_ID`, `ROBERT_PEM`, `ROOT_GRANT_B64`,
`PINNED_REGISTRAR_KEY`, the persona PEMs, etc. in the environment:

```bash
./preflight.sh          # ~1 min: deploys + provisions a fresh forest on Base Sepolia
source demo.env
```

Secrets (the ops-admin token and the gas-paying deployer key) are pulled from
Doppler at runtime by `preflight.sh`; they are never written to `demo.env` or to
disk.

## Publishing a signed statement

```bash
source demo.env

echo '{"claim":"hello scitt wg"}' > statement.json

./forestrie sign-statement --key "$ROBERT_PEM" --payload statement.json \
      --content-type application/json --out statement.cose

REG=$(./forestrie register --base-url "$FORESTRIE_BASE_URL" \
      --log-id "$ROBERT_LOG_ID" --statement statement.cose \
      --grant-b64 "$ROOT_GRANT_B64" --out receipt.cbor 2>&1); echo "$REG"

ENTRY_ID=$(echo "$REG" | grep -oE 'entries/[0-9a-f]{32}/receipt' | head -1 | grep -oE '[0-9a-f]{32}')

./forestrie verify --genesis genesis.cbor --receipt receipt.cbor \
      --payload statement.cose --entry-id "$ENTRY_ID"

```

* Create the statement and sign it using the log owners key producing
`statement.cose`

* Register the statement on the Forestrie TS
  --log-id is the log to register on
  --grant-b64 is the authorization for the statement signer to publish to the log ( more on this later)
  --base-url is where the forestrie operator SCRAPI register-sgined-statement
is hosted

* Verify the receipt
  --genesis genesis.cbor is the registration document for the log, obtained
when the log is registered with the forestrie operator (not necessary for
receipt verification, just convenient)
  --receipt COSE-Receipt draft-bryce-mmr-profile reciept
  --payload the exact bytes that were registered (the leaf commits
`SHA-256(payload)`); this is the generic, SCITT-compatible verify
  --entry-id the SCRAPI entry-id for the log entry

A property of the mmr-profile means that receipts can be self-created from a
published checkpoint, and verified off line.

Access to the single tile data containing the leaf (or leaves) of interest is the only requirement. Forestrie publishes tiles imediately and publicly

```bash
# Self-create the SAME receipt offline from the public head tile + checkpoint —
# no operator round-trip. LOG_STORE_URL is the public read-only R2 origin.
export LOG_STORE_URL="https://pub-d7bc2e23615b4cd1a80a0944c3cd3507.r2.dev"
export MASSIF_H=14 MASSIF_IDX=0000000000000000

curl -sS "$LOG_STORE_URL/v2/merklelog/massifs/$MASSIF_H/$ROBERT_LOG_ID/$MASSIF_IDX.log"  -o massif.log
curl -sS "$LOG_STORE_URL/v2/merklelog/checkpoints/$MASSIF_H/$ROBERT_LOG_ID/$MASSIF_IDX.sth" -o checkpoint.sth

./forestrie create-receipt --massif massif.log --checkpoint checkpoint.sth \
      --entry-id "$ENTRY_ID" --out receipt.selfserve.cbor

# Byte-identical to the API-issued receipt; verifies with the same command.
./forestrie verify --genesis genesis.cbor --receipt receipt.selfserve.cbor \
      --payload statement.cose --entry-id "$ENTRY_ID"
```


## The Forestrie TS is a "pipe" not a "store".

Granting publishing authority to the forestrie opoerator

The forestrie operator publishes checkpoints on behalf of log owners.

The forestrie operator signs a voucher for its sealer ahead of time, enabling
log owners to pre-submit a checkpoint publishing grant.


The log owner verifies the voucher against its copy of the --pinned-registry-key for the forestrie operator

```bash
# The log owner (here Robert, holding his root key) fetches the operator's
# standing sealer voucher from the coordinator, checks it against the pinned
# registrar key, then signs a wide-horizon delegation authorizing that sealer to
# publish checkpoints on the log's behalf. Public coordinator endpoint only —
# no operator token. (preflight.sh already ran this for the root log as R4.)
./forestrie delegate \
      --coordinator-url "$DELEGATION_COORDINATOR_URL" \
      --log-id "$ROBERT_LOG_ID" \
      --sign-with "$ROBERT_PEM" \
      --pinned-registrar-key "$PINNED_REGISTRAR_KEY"
```
The grant is both time and log size limited.

When it expires, the operators sealer will stop publishing checkpoints unless a
further grant is registered.

## Creating a log

If you have an authority log, you can grant creation of one or more data logs to a new data log owner.

The new data log owner must approve checkpoint publishing for their data log. Approval is via a delegation certificate to the forestrie operators derived signing key.

The grant endorsing the new data log owners checkpoint publishing expires. On a basis of time and log size. There is no revocation.

The authority log owner can withhold future publishing rights to badly behaved data log owners.

But it cannot publish checkpoints for the data log or register statements on it without the data log owners approval.

```bash
# Two fresh log ids: David's auth log, and the data log under it.
export DAVID_AUTH_LOG_ID=$(uuidgen | tr 'A-Z' 'a-z')
export DAVID_DATA_LOG_ID=$(uuidgen | tr 'A-Z' 'a-z')

# 1. Robert creates David's AUTH log (signed by the root key; grantData = David,
#    so David becomes its owner). --prepare registers David's root at the
#    coordinator; the second call sequences the create grant.
./forestrie create-log --prepare --base-url "$FORESTRIE_BASE_URL" \
      --owner-log "$ROBERT_LOG_ID" --new-log "$DAVID_AUTH_LOG_ID" --auth-log \
      --signer-pem "$DAVID_PEM" --sign-with "$ROBERT_PEM" \
      --parent-grant-b64 "$ROOT_GRANT_B64" --out-b64 auth-grant.b64

# David approves checkpoint publishing on his new auth log (delegation cert).
./forestrie delegate --coordinator-url "$DELEGATION_COORDINATOR_URL" \
      --log-id "$DAVID_AUTH_LOG_ID" --sign-with "$DAVID_PEM" \
      --pinned-registrar-key "$PINNED_REGISTRAR_KEY"

./forestrie create-log --base-url "$FORESTRIE_BASE_URL" \
      --owner-log "$ROBERT_LOG_ID" --new-log "$DAVID_AUTH_LOG_ID" --auth-log \
      --signer-pem "$DAVID_PEM" --sign-with "$ROBERT_PEM" \
      --parent-grant-b64 "$ROOT_GRANT_B64" --out-b64 auth-grant.b64
export AUTH_GRANT_B64=$(cat auth-grant.b64)

# 2. David creates his DATA log under his auth log (signed by David, its owner).
./forestrie create-log --prepare --base-url "$FORESTRIE_BASE_URL" \
      --owner-log "$DAVID_AUTH_LOG_ID" --new-log "$DAVID_DATA_LOG_ID" \
      --bootstrap-log "$ROBERT_LOG_ID" --data-log \
      --signer-pem "$DAVID_PEM" --sign-with "$DAVID_PEM" \
      --parent-grant-b64 "$AUTH_GRANT_B64" --out-b64 david-data-grant.b64

./forestrie delegate --coordinator-url "$DELEGATION_COORDINATOR_URL" \
      --log-id "$DAVID_DATA_LOG_ID" --sign-with "$DAVID_PEM" \
      --pinned-registrar-key "$PINNED_REGISTRAR_KEY"

./forestrie create-log --base-url "$FORESTRIE_BASE_URL" \
      --owner-log "$DAVID_AUTH_LOG_ID" --new-log "$DAVID_DATA_LOG_ID" \
      --bootstrap-log "$ROBERT_LOG_ID" --data-log \
      --signer-pem "$DAVID_PEM" --sign-with "$DAVID_PEM" \
      --parent-grant-b64 "$AUTH_GRANT_B64" --out-b64 david-data-grant.b64
export DATA_GRANT_B64=$(cat david-data-grant.b64)

# 3. David authorizes Alice as a WRITER on his data log (extend-only — no create,
#    no re-root), signed by David. Recorded in the auth log, not a side channel.
./forestrie register-grant --base-url "$FORESTRIE_BASE_URL" \
      --owner-log "$DAVID_AUTH_LOG_ID" --data-log "$DAVID_DATA_LOG_ID" \
      --bootstrap-log "$ROBERT_LOG_ID" --signer-pem "$ALICE_PEM" \
      --parent-grant-b64 "$DATA_GRANT_B64" --sign-with "$DAVID_PEM" \
      --out-b64 grant-alice.b64
export ALICE_GRANT_B64=$(cat grant-alice.b64)

# 4. Alice registers a statement to the data log with her writer grant, and
#    verifies its receipt offline — same shape as the first section.
echo '{"alice":"data"}' > alice-stmt.json
./forestrie sign-statement --key "$ALICE_PEM" --payload alice-stmt.json \
      --content-type application/json --out alice-stmt.cose

ALICE_REG=$(./forestrie register --base-url "$FORESTRIE_BASE_URL" \
      --log-id "$DAVID_DATA_LOG_ID" --statement alice-stmt.cose \
      --grant-b64 "$ALICE_GRANT_B64" --out alice-receipt.cbor 2>&1); echo "$ALICE_REG"
ALICE_ENTRY_ID=$(echo "$ALICE_REG" | grep -oE 'entries/[0-9a-f]{32}/receipt' | head -1 | grep -oE '[0-9a-f]{32}')

./forestrie verify --genesis genesis.cbor --receipt alice-receipt.cbor \
      --payload alice-stmt.cose --entry-id "$ALICE_ENTRY_ID"
```

The grant Alice used is itself a signed statement recorded in the auth log — you
can complete and verify it offline from the same tile data, no operator call.
This is the "SCITT built using SCITT" point: authorization is a receipted
statement, verified exactly like the data entries.

```bash
./forestrie complete-grant --grant grant-alice.b64 \
      --checkpoint checkpoint.sth --massif massif.log \
      --out-b64 grant-alice.completed.b64

./forestrie verify-grant --genesis genesis.cbor --receipt alice-receipt.cbor \
      --committed-grant "$(cat grant-alice.completed.b64)"
```

## Split view protection and the *first* authority log

Split-view protection and checkpoint publishing authority for logs is provided
by an independently provisioned smart contract. Chain of choice, no particular
EVM is favoured.

Log owners are free to exit to other TS operators at any time.



The Univocity smart contract is a checkpoint publisher and consistency proof checker

Anyone can deploy one.

You need an onboard token to register it with Forestrie

A single Univocity contract instance hosts a tree of authority logs and datalogs

When the contract is deployed, the root authority log checkpoint publisher is bound to it

The forestrie operator has no special privalage.

The Univocity instance owner  is free to move to another forestrie operator at
anytime.

The deployment chain is the trust root for the univocal history of all logs on that single Univocity instance

```bash
# --- Deploy a Univocity instance (this is preflight.sh R1). Generates the
#     bootstrap ES256 key and binds its public key to the contract at deploy. ---
export CANOPY_OPS_ADMIN_TOKEN=$(doppler secrets get CANOPY_OPS_ADMIN_TOKEN --project canopy --config dev --plain)
export DEPLOYER_KEY=$(doppler secrets get DEPLOY_KEY --project canopy --config dev --plain)
export OWNER_ADDRESS="0xdA30dB778C4aAE42BfAE2e81d4b12dEb0725F98C"   # must match DEPLOYER_KEY

./forestrie deploy --bootstrap-alg es256 \
      --bootstrap-es256-generate --bootstrap-es256-pem-out "$ROBERT_PEM" \
      --owner-address "$OWNER_ADDRESS" --deployer-key "$DEPLOYER_KEY" \
      --rpc-url "$RPC_URL" --out deployment.json
export UNIVOCITY_ADDRESS=$(jq -r .imutableUnivocity deployment.json)
export ROBERT_LOG_ID=$(jq -r .genesisLogId deployment.json)

# --- Register (onboard) the instance with Forestrie. Needs a minted onboard
#     token; onboard-genesis.mjs mints one from the ops-admin token, builds the
#     genesis CBOR, and POSTs it (preflight.sh R2). ---
node onboard-genesis.mjs
curl -sS -o genesis.cbor "$FORESTRIE_BASE_URL/api/forest/$ROBERT_LOG_ID/genesis"

# --- Prove the binding on-chain: the contract's bootstrap config is exactly the
#     ES256 key that signed the root grant. This is the trust root — split-view
#     protection lives in the contract + chain consensus, not the operator. ---
~/.foundry/bin/cast call "$UNIVOCITY_ADDRESS" "bootstrapConfig()(int64,bytes)" --rpc-url "$RPC_URL"

# --- Chain-anchored verify: recompute the receipt's peak and match it against
#     the on-chain accumulator — no signature check, only the contract + chain. ---
./forestrie verify --genesis genesis.cbor --receipt receipt.cbor \
      --payload statement.cose --entry-id "$ENTRY_ID" \
      --univocity "$UNIVOCITY_ADDRESS" --log-id "$ROBERT_LOG_ID" --rpc-url "$RPC_URL"
```

## Throughput and Latency

Because receipts are rooted at accumulator peaks rather than singular tree heads, a single checkpoint covers all nodes previously committed to the log.

The most recently sequenced statements are always in the head tile.

This means if you grab a copy of the head tile (4mb max), you can self create a
receipt from that tile and the latest checkpoint for any entry sequenced in
that tile

We have loadtested forestrie in excess of 4000 request a second.
The limit was cloudlfare rate limiting on the free tier account we used.

One checkpoint was enough to cover all 4000 checkpoints. The latency of 2-3 seconds on checkpoint publishing is amortized.

This shows this for 100 statements

```bash
# Submit N statements concurrently, wait ONCE for the single checkpoint that
# covers the whole batch, then derive all N receipts OFFLINE from that one
# massif + checkpoint (zero operator calls per receipt). Reads ROBERT_LOG_ID,
# ROBERT_PEM and the root grant from demo.env / root-grant.b64.
N=100 bun batch-receipts.ts
```

Expected shape:

```
submitted+sequenced 100 statements in ~2s
ONE checkpoint now covers all 100 after ~2.5s
derived 100/100 receipts OFFLINE (zero operator calls) in <1s
```

## Roundup

Forestrie is a pipe not a store.
Your split view protection is owned by you.
You can switch operator any time you like.
Receipts can be self assembled off line with minimal effort by *any* party.
The data required to guarantee receipt availability is easily replicable.

The split view protoection is not dependent on the log operator.
The Univocity heirarchical grant model gives you control over log creation and
statement registration without relying on operators.

The mmr-profile of COSE-Receipts is the enabler.

```bash
# The single closer — the exact command from the very first section, proving the
# receipt stays valid forever with nothing from the operator. Run it again;
# nothing changed but the audience's understanding.
./forestrie verify --genesis genesis.cbor --receipt receipt.cbor \
      --payload statement.cose --entry-id "$ENTRY_ID"
```
