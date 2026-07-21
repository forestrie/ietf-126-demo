<!-- _class: compact -->

## Roundup

MMR-profile receipts and consistency proofs enable a Forestrie-style TS which:

- Offers great throughput and **amortized low-latency** receipts
- Lets **any party self-assemble** receipts, any time, from published checkpoints
- Provides **split-view protection in software** — no special hardware
- **Avoids operator lock-in**

Forestrie uses **SCITT to authorize SCITT** statement registration. The same grant
system gives hierarchical, log-owner-enforced publishing and registration with no
dependency on a single operator.

**Forestrie is a pipe, not a store.**


The [preflight](https://github.com/forestrie/ietf-126-demo/blob/main/preflight.sh) script illustrates on boarding with a forestrie TS. Ask me for an onboard token if you want to kick the tires

```bash
./preflight.sh
```

<!--
Land the line: the operator was only ever a pipe — split-view protection and the trust that
matters live on-chain. Cache the checkpoint forever, self-serve receipts, swap operators at will.
The mmr-profile of COSE Receipts is the enabler.
-->
