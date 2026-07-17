<!-- _class: compact -->

## The verification trust ladder

Four ways to answer *"why do I trust this receipt?"* — each rung needs
**less trust** and proves **more**:

| # | Anchor | You must trust | What it gives you |
|---|--------|----------------|-------------------|
| 1 | **Known log key** (out of band) | the channel the key came over, per log | standard SCITT relying-party posture; key↔log binding is *asserted*; no lifecycle, no split-view |
| 2 | **Grant-chain walk** (offline, genesis-rooted) | only `genesis.cbor` — itself checkable on-chain | binding *proven* from public tiles; grant lifecycle visible; still no split-view |
| 3 | **Known accumulator** (cached chain read) | the party that read it from chain — *auditable* at its block ref | the contract-enforced state itself: signature, grant chain **and split-view**, fully offline |
| 4 | **Live chain read** (`--rpc-url`) | your RPC provider (also just a trusted chain reader) | same as 3, plus freshness |

- Old receipts **extend forward** into any newer accumulator using public log
  nodes — old-accumulator compatibility (Reyzin–Yakoubov, *Efficient
  Asynchronous Accumulators for Distributed PKI*)
- **The receipt never expires, and the anchor never needs to be current — only trusted**
- Known accumulator + tiles = the strongest **fully offline** verification

<!--
Rung 1 is what every SCITT RP does today with a TS key from discovery — forestrie meets you there.
Rung 2 is the forestrie enhancement: the key↔log binding is derived, not distributed — every link
is a receipted, self-servable grant leaf back to the deploy-bound bootstrap key.
Rung 3 is the subtle one: a cached accumulator is the chain-side analogue of a cached checkpoint.
Staleness only limits coverage, never validity — the contract's consistency gating means every
anchored state is a committed prefix of every later one. And the snapshot is publicly FALSIFIABLE:
re-run the read at its recorded block. Never source it from the operator's store unauthenticated.
Rung 4: point out --rpc-url was never trust-free — the RPC provider is a trusted chain reader too;
rung 3 just makes that trust explicit and portable.
Extension mechanics (the first bullet): a buried peak is an interior node of the newer state; append
the ancestor path from public tiles and match the covering peak. Soundness = hash collision
resistance + the on-chain consistency proofs binding old state to new.
Implementation status (don't belabor on stage): rung 4 shipped (chain-anchored verify); rungs 1 and
3 are specced (--known-log-key, --known-accumulator — status-2607-09 D1/D5); rung 2 is FOR-297
approach A, in design.
-->
