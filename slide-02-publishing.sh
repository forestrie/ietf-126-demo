#!/usr/bin/env bash
#
# Slide 2 — Publishing a signed statement.
#
# A plain COSE Sign1 statement, registered with a grant, and a receipt that
# verifies offline. Exports ENTRY_ID / STMT / RECEIPT for the later slides —
# slide 9's closer re-verifies exactly these.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]:-$0}")/demo-lib.sh"
demo_init 02

run "echo '{\"claim\":\"hello scitt wg\"}' > \"\$S/statement.json\""

run './forestrie sign-statement --key "$ROBERT_PEM" --payload "$S/statement.json" \
	--content-type application/json --out "$S/statement.cose"'

run 'REG=$(./forestrie register --base-url "$FORESTRIE_BASE_URL" --log-id "$ROBERT_LOG_ID" \
	--statement "$S/statement.cose" --grant-b64 "$ROOT_GRANT_B64" --out "$S/receipt.cbor" 2>&1)
echo "$REG"
export ENTRY_ID=$(echo "$REG" | grep -oE "entries/[0-9a-f]{32}/receipt" | head -1 | grep -oE "[0-9a-f]{32}")'

export STMT="$S/statement.cose" RECEIPT="$S/receipt.cbor"

run './forestrie verify --genesis "$GENESIS" --receipt "$RECEIPT" \
	--payload "$STMT" --entry-id "$ENTRY_ID"'

# handoffs the later slides reuse
save_state ENTRY_ID STMT RECEIPT
