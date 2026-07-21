<!-- _class: compact -->

## Log creation and authorizing grants — SCITT using SCITT

- The `--grant-b64` from the start is just a **SCITT signed statement** with a
  Univocity-contract-defined payload; its authority *is* a **proof of inclusion
  in the parent log**
- The same grant primitive authorizes **new-log creation** and **statement registration**
- Statement signers are individually grant authorized to register statements on
a particular log
- Grants can not be revoked. The only expire, expiry time or usage based.
- This is quite a long set of commands, illustrating provisioning of a
heirarchy of logs rooted at Roberts, and extending down to David and Alice

```bash
# Robert creates David's AUTH log (grantData = David). David then grants Alice a
# DATA log to write to (grantData = Alice, signed by David). Each log's sealing is
# delegated by that log's key holder (auth → David, data → Alice):
forestrie create-log … --owner-log "$ROBERT_LOG_ID"     --new-log "$DAVID_AUTH_LOG_ID"  --auth-log --signer-pem "$DAVID_PEM" --sign-with "$ROBERT_PEM"
forestrie create-log … --owner-log "$DAVID_AUTH_LOG_ID" --new-log "$ALICE_DATA_LOG_ID" --data-log --signer-pem "$ALICE_PEM" --sign-with "$DAVID_PEM"

# Alice writes to her data log — child logs register via the FOREST (root) path;
# the grant directs the statement to the data log. Her statement carries her own
# CWT claims (iss = her key id; here she names the subject: --sub urn:demo:alice:hello-1):
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
