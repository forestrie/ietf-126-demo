<!-- _class: compact -->

## Publishing a signed statement

Here we
- Sign a SCITT statement
- Register it; `
- And then we verify its receipt

```bash
forestrie sign-statement --key "$ROBERT_PEM" --payload statement.json \
  --content-type application/json --out statement.cose

forestrie register --base-url "$FORESTRIE_BASE_URL" --log-id "$ROBERT_LOG_ID" \
  --statement statement.cose --grant-b64 "$ROOT_GRANT_B64" --out receipt.cbor

forestrie verify --genesis "$GENESIS" --receipt receipt.cbor \
  --payload statement.cose --entry-id "$ENTRY_ID"
```

- `--genesis` is the log's registration document — convenient, not required for verification
- `--entry-id` (the SCRAPI entry id) makes discovery efficient; not essential

<!--
Payoff first: a verifiable receipt in hand before any chain talk. The grant header is
just a bearer credential for now — where it comes from is the log-creation slide.
verify's --payload is the exact registered bytes: the leaf commits SHA-256(payload).
This is generic, SCITT-compatible verification. entry-id is captured from the register output.
-->
