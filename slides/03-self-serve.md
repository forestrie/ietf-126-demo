<!-- _class: compact -->

## Self-service receipts

- MMR-profile receipts can be **self-created from a published checkpoint**
- Grab the one **tile** holding your leaf + the latest checkpoint — that's all you need
- The self-served receipt is **byte-identical** to the API-issued one

```bash
# public read-only tile + checkpoint
curl -sS "$LOG_STORE_URL/v2/merklelog/massifs/14/$ROBERT_LOG_ID/…0.log"  -o massif.log
curl -sS "$LOG_STORE_URL/v2/merklelog/checkpoints/14/$ROBERT_LOG_ID/…0.sth" -o checkpoint.sth

forestrie create-receipt --massif massif.log --checkpoint checkpoint.sth \
  --entry-id "$ENTRY_ID" --out receipt.selfserve.cbor

forestrie verify --genesis "$GENESIS" --receipt receipt.selfserve.cbor \
  --payload statement.cose --entry-id "$ENTRY_ID"
```

- No operator round-trip — Forestrie publishes tiles immediately and publicly

<!--
This is "pipe not store" made concrete, and it rests on peak-signing: each signed peak is
a self-contained attestation, so a client with the tile rebuilds the leaf→peak path and
attaches it to the pre-signed peak — producing the exact bytes the operator would have.
The closer is the SAME verify command as the previous slide.
-->
