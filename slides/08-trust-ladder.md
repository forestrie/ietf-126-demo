<!-- _class: compact -->

## The verification trust ladder

Three anchors for *"why do I trust this receipt?"* — **not one "less trust /
more proof" line.** Each answers a different subset of three independent
questions: **split-view** (a single, un-forked history — your inclusion proof
matches the on-chain accumulator), **sealing** (who signed the checkpoint),
**authority** (the log is granted back to the bootstrap key). A weaker fourth
axis, **currency** (*is this the latest accumulator*), bears only on coverage —
never on the validity of what a snapshot already covers.

| # | Anchor | You must trust | What it answers |
|---|--------|----------------|-----------------|
| 1 | **Known log key** (out of band) | the channel the key came over, per log | **sealing** — the standard SCITT RP posture; key↔log binding *asserted*; no split-view; authority not proven |
| 2 | **Known accumulator** (cached chain read) | the party that read it — *auditable* at its block ref | **split-view** — your leaf roots into the one canonical history; sealing + authority come free (contract-enforced at publish). Valid up to its tree size regardless of age. Fully offline |
| 3 | **Live chain read** (`--rpc-url`) | your RPC provider (also just a chain reader) | same as 2, plus **currency** ("as of now" — newer coverage) |

- Old receipts **extend forward** into any newer accumulator using public log
  nodes — old-accumulator compatibility (Reyzin–Yakoubov, *Efficient
  Asynchronous Accumulators for Distributed PKI*)
- **The receipt never expires, and the anchor never needs to be current — only trusted**
- Known accumulator + tiles = the strongest **fully offline** verification
- If you care about only one entry, you are guaranteed to only need one tile

<!--
The frame: these are NOT a single trust axis — each rung answers a DIFFERENT question
(split-view / sealing / authority), and you pick the rung whose question you care about.
Rung 1 is what every SCITT RP does today with a TS key from discovery — forestrie meets you
there. It answers SEALING (an authorized signer sealed this) and asserts the key↔log binding out
of band; it says nothing about split-view, and authority is asserted, not proven.
Rung 2 is the subtle one: a cached accumulator is the chain-side analogue of a cached checkpoint.
It answers SPLIT-VIEW (the leaf roots into the one canonical history); sealing and authority were
already discharged by the contract at publish, so you get them for free without re-checking the
signature. Currency (is this the latest accumulator) is a SEPARATE, weaker axis: staleness only
limits coverage, never validity — the contract's consistency gating means every anchored state is a
committed prefix of every later one, so any accumulator is valid up to its own tree size. And the snapshot is publicly
FALSIFIABLE: re-run the read at its recorded block. Never source it from the operator's store
unauthenticated.
Rung 3: point out --rpc-url was never trust-free — the RPC provider is a trusted chain reader too;
rung 2 just makes that trust explicit and portable.
Extension mechanics (the extend-forward bullet): a buried peak is an interior node of the newer
state; append the ancestor path from public tiles and match the covering peak. Soundness = hash
collision resistance + the on-chain consistency proofs binding old state to new.
Implementation status (don't belabor on stage): rung 3 shipped (chain-anchored verify); rung 1
shipped (--known-log-key, no genesis needed; wrong key reports known_key_mismatch); rung 2 shipped
(fetch-accumulator writes the block-pinned snapshot; verify --known-accumulator matches offline,
extends older receipts via --massif, fails newer ones closed).
Deliberately OFF the ladder: the offline genesis-rooted grant-chain walk (child-log authority
proven from public tiles, the "derived binding" enhancement). It is not yet implementable, so it
stays out of the demo until it can be run live like everything else here — tracked as FOR-419. If
asked on stage: child-log authority today is discharged on-chain by the contract at publish (rungs
2-3); the fully-offline proof is future work.
-->
