<!-- _class: compact -->

## Verifying Alice's statement — the accumulator is the authority

```bash
# CHAIN-ANCHORED verify — the peak recomputed from Alice's statement + the
# receipt's proof path must be in the data log's OWN on-chain accumulator;
# the delegated seal was already enforced by univocity at publish:
forestrie verify … --univocity "$UNIVOCITY_ADDRESS" --log-id "$ALICE_DATA_LOG_ID" --rpc-url "$RPC_URL"
```

- Every log — root or child — has its **own on-chain accumulator**: split-view protection is per log
- If you trust the contract's consistency-proof checking for split-view protection, and your
  receipt's inclusion proof produces a peak in the on-chain accumulator, it follows that:
  - **a)** the checkpoint signature that advanced that accumulator was **verified by the
    contract at publish** — you can trust that check
  - **b)** the publisher (the log owner, or a sealer the owner delegated) presented a grant
    from the parent log — the contract **re-verified its inclusion against the parent's
    on-chain accumulator, within the grant's size bounds, at that same publish**
  - **c)** transitively, every ancestor state that grant rests on was gated the **same way** —
    link by link, up to the bootstrap key bound into the contract at deploy
- So why verify the signature again if you have the accumulator from the chain?
  **Match the peak and you are done.**
- This **combines inclusion verification with a split-view check** — signature verification
  against a "known log key", provided at verification time, doesn't do that on its own

<!--
Mechanics of the closer: recompute leaf = SHA-256(idtimestamp ‖ SHA-256(statement)), walk the
receipt's proof path to a peak, byte-match it against logState(dataLog) on univocity. No local
signature check — and per this slide's argument that is the STRONGER claim, not a concession.
(CLI wording update pending: the signature row currently prints "skipped … externalised to the
on-chain accumulator"; it will become "ok — verified against accumulator from chain".)
Contract facts backing a/b/c (checked in _Univocity.sol publishCheckpoint): the grant is presented
and inclusion-verified against the owner log's CURRENT on-chain state on EVERY publish, not just
the first checkpoint; bounds are size-based (maxHeight / minGrowth — rule 4), so say "within its
authorized bounds" rather than wall-clock "expired"; with delegation, the owner signs the
delegation and the delegate signs the receipt (rule 5); the root's first checkpoint requires the
self-referential grant signed by the deploy-bound bootstrap key (rule 1) — that is where the
transitivity in (c) grounds out.
Purely-offline child verify (no chain access) needs the FOR-297 multi-hop grant-chain resolver, or
a caller-supplied --known-log-key (standard SCITT RP posture) — both in flight; see status-2607-09.
-->
