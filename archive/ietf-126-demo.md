## Slide 1: Forestrie

Forestrie is a Transparency Service offering a SCRAPI interface for registering
SCITT signed statements.

Forestrie issues [MMR-profile draft COSE
Receipts](https://github.com/robinbryce/draft-bryce-cose-receipts-mmr-profile/blob/main/draft-bryce-cose-receipts-mmr-profile.md)

## Publishing a signed statement

Let's register a statement.

> BEGIN: DEMO IN TERMINAL

### Create and sign:


```bash
source demo.env

echo '{"claim":"hello scitt wg"}' > statement.json

./forestrie sign-statement --key "$ROBERT_PEM" --payload statement.json \
      --content-type application/json --out statement.cose

```

### Register

* Create the statement and sign it using the log owners key producing `statement.cose`

```bash
REG=$(./forestrie register --base-url "$FORESTRIE_BASE_URL" \
      --log-id "$ROBERT_LOG_ID" --statement statement.cose \
      --grant-b64 "$ROOT_GRANT_B64" --out receipt.cbor 2>&1); echo "$REG"

ENTRY_ID=$(echo "$REG" | grep -oE 'entries/[0-9a-f]{32}/receipt' | head -1 | grep -oE '[0-9a-f]{32}')
```

* `--grant-b64` is the authorization for publishing to the log (more on this later)

### Verify

```bash
./forestrie verify --genesis genesis.cbor --receipt receipt.cbor \
      --payload statement.cose --entry-id "$ENTRY_ID"

```

`--genesis genesis.cbor` is the response from forestrie when a new log is registered.
It is not necessary for receipt verification, just convenient.

`--entry-id` the SCRAPI entry-id for the log entry. It's not critical to know
this — content discovery works — but it is more efficient and convenient.

> END: DEMO IN TERMINAL

## Slide 2:  Self service receipts

A property of the mmr-profile means that receipts can be self-created from a published checkpoint.

Let's just show this.

> BEGIN: DEMO IN TERMINAL

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

> END: DEMO IN TERMINAL

## Slide 3:  Throughput and Latency

Receipts for the mmr-profile are rooted at accumulator peaks rather than singular tree heads.
A single checkpoint covers all nodes previously committed to the log.

And receipts can be pre-signed and then later self-service.

Let's do 100 statements, get one checkpoint, then make all the receipts locally:

<!-- TODO: create ietf-126-demo upstream in forestrie org, push this repo to it,
     add a gitweb link to batch-receipts.ts -->

> BEGIN: DEMO IN TERMINAL

```bash
# Submit 100 concurrently, wait once for the covering checkpoint, then derive
# all 100 receipts offline. Reads ROBERT_LOG_ID / ROBERT_PEM / root-grant.b64.
N=100 bun batch-receipts.ts
```

```
submitted+sequenced 100 statements in ~2s
ONE checkpoint now covers all 100 after ~2.5s
derived 100/100 receipts OFFLINE (zero operator calls) in <1s
```

> END: DEMO IN TERMINAL

This can go really fast! We've done 4k/sec with Cloudflare rate limits being the
ceiling rather than system throughput.

For batch use cases, *amortized* latency is tiny.

## Slide 4:  The Forestrie TS Split-view protection

To get split-view protection with the Forestrie TS we accept a little
blockchain in our lives.

Anyone can deploy our Univocity smart contract and register it with the TS.

Checkpoints are published permissionlessly to the contract.
They are COSE mmr-profile consistency proofs, must be signed by the log owner,
and must be consistent to the previously published checkpoint.

Publishing the first checkpoint requires a grant (discussed later), and the
grant establishes the log owner.

Univocity supports a hierarchy of log owners, each with independent split-view.

> BEGIN: DEMO IN TERMINAL

Deploying is not hard:

```bash
./forestrie deploy --bootstrap-alg es256 \
  --bootstrap-es256-generate --bootstrap-es256-pem-out "$ROBERT_PEM" \
  --owner-address "$OWNER_ADDRESS" --deployer-key "$DEPLOYER_KEY" \
  --rpc-url "$RPC_URL" --out deployment.json
export UNIVOCITY_ADDRESS=$(jq -r .imutableUnivocity deployment.json)
export ROBERT_LOG_ID=$(jq -r .genesisLogId deployment.json)

```

Registering a "genesis" root log is a bit more involved, but it's still a short
script away:

```bash
node onboard-genesis.mjs
```

> END: DEMO IN TERMINAL

The forestrie operator has no special privileges — the owner of the univocity
contract, set by the deployer, can re-locate to another TS any time.


## Slide 5: Forestrie log creation

AKA: SCITT using SCITT: registration authorization using SCITT statements

The `--grant-b64` we saw at the start is simply a SCITT signed statement with a
Univocity-contract-defined payload authorizing the subject of the grant to
register statements on the log. Authorization is a proof of inclusion in the
parent log.

Forestrie Grants as SCITT payloads are the basis for authorizing statement registration and for authorizing the creation of new logs.

> BEGIN: DEMO IN TERMINAL

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


> END: DEMO IN TERMINAL

##  Slide 6: Roundup

MMR-profile receipts and consistency proofs enable a Forestrie style TS which:
- Offers great throughput and (amortized) low latency receipts.
- Self-assembly of receipts at any time from published checkpoints.
- Split-view protection in software with no special hardware requirements.
- Avoids operator lockin

Forestrie itself, uses SCITT to build the authorization of SCITT statement
registration.

The same grant system provides for hierarchical, log-owner-enforced statement publishing and
statement registration without dependency on a single operator.

Forestrie is a pipe not a store.


> BEGIN: DEMO
```bash
./forestrie verify --genesis genesis.cbor --receipt receipt.cbor \
      --payload statement.cose --entry-id "$ENTRY_ID"
```

> END: DEMO

---

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



