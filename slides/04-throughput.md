<!-- _class: compact -->

## Throughput and latency

- With the MMR-profile, log checkpoints are accumulators, rather than signed singleton tree heads.
- This means receipt production is decoupled from statement registration
- **One checkpoint covers every node** previously committed to the log
- Peaks can be pre-signed, so the receipts self-created later
- This means we can amortize receipt latency across many 100's or 1000's of statements

```bash
# 100 statements → one covering checkpoint → all 100 receipts derived offline
N=100 bun batch-receipts.ts
```

```
submitted+sequenced 100 statements in ~2s
ONE checkpoint now covers all 100 after ~2.5s
derived 100/100 receipts OFFLINE (zero operator calls) in <1s
```

- Load-tested to **~4k req/s** — Cloud provider rate limits (for hobby accounts) were the ceiling
- For batch use cases, **amortized latency is tiny**

<!--
The 2–3s checkpoint latency is paid ONCE for the whole batch, then every receipt is derived
offline from one massif + one checkpoint. Confirm the 4k/s and ~2.5s figures are current before
quoting. TODO before the talk: push this repo to a forestrie-org upstream; link batch-receipts.ts.
-->
