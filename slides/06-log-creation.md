<!-- _class: compact -->

## Log creation — SCITT using SCITT

- The `--grant-b64` from the start is just a **SCITT signed statement** with a
  Univocity-contract-defined payload; its authority *is* a **proof of inclusion
  in the parent log** — no side channel
- The same grant primitive authorizes **new-log creation** and **statement writing**
- A data-log **create+extend** grant names its writer in `grantData` — that grant
  **is** the write authorization

```bash
# Robert creates David's AUTH log (grantData = David). David then grants Alice a
# DATA log to write to (grantData = Alice, signed by David). Each log's sealing is
# delegated by that log's key holder (auth → David, data → Alice):
forestrie create-log … --owner-log "$ROBERT_LOG_ID"     --new-log "$DAVID_AUTH_LOG_ID"  --auth-log --signer-pem "$DAVID_PEM" --sign-with "$ROBERT_PEM"
forestrie create-log … --owner-log "$DAVID_AUTH_LOG_ID" --new-log "$ALICE_DATA_LOG_ID" --data-log --signer-pem "$ALICE_PEM" --sign-with "$DAVID_PEM"

# Alice writes to her data log — child logs register via the FOREST (root) path;
# the grant directs the statement to the data log:
forestrie register --log-id "$ROBERT_LOG_ID" --grant-b64 "$ALICE_GRANT_B64" --statement alice.cose
```

- Authorization is a **receipted statement**, sequenced in the auth log like any entry
- Verification of Alice's statement → **next slide**

<!--
The point to land: SCITT requires the TS to authorize what it registers; Forestrie meets that
with SCITT — a grant is a signed statement, recorded and receipted in an auth log. Create vs write
are different authorities: create-log makes a log; the data-log grant's grantData names its writer.
Child registration goes to /register/{root}/entries (the forest), not the child id.
Don't verify here — the chain-anchored closer and the trust argument are the NEXT slide, so the
split-view payoff gets its own beat.
-->
