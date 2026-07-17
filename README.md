# Forestrie — IETF 126 demo

A live `forestrie` walkthrough for the IETF SCITT WG, as **two artifacts driven
off one narrative**:

- **`slides/`** — the Marp deck (the primary content; what the audience sees).
- **`slide-NN-*.sh`** — one runnable script per slide (what you run live).

The deck shows the talking points; the terminal shows the commands live. During
the talk you cut between a **Slides** scene and a **Terminal** scene (see
*Recording*).

## Quick start

```bash
# 1. one-time prep: deploy a fresh forest + write .output/shared/demo.env
./preflight.sh

# 2. drive the deck (presenter view with notes on your 2nd screen)
pnpm install
pnpm run present         # or: build / preview / open / pdf

# 3. run one script per slide, in deck order
./slide-02-publishing.sh
./slide-03-self-serve.sh
...
```

Each script **echoes a command, waits for any key, then runs it** — so you can
talk over each command before it executes. No `source` needed: every script
loads `.output/shared/demo.env` itself and exits with a clear error if
`preflight.sh` hasn't run.

Cross-slide handoffs (`ENTRY_ID`, `STMT`, `RECEIPT`, Alice's ids …) pass through
`.output/shared/demo.state`, which each script sources on entry and updates on
exit. So the scripts run in **separate shells**, in deck order, and a slide can
be re-run without re-running the whole deck. Per-slide scratch lands in
`.output/slide-NN/`.

`DEMO_AUTO=1 ./slide-02-publishing.sh` skips every pause — that's how the
scripts are tested unattended.

## Layout

| Path | What |
|------|------|
| `slides/NN-*.md` | Marp deck source (one file per slide) — **primary content** |
| `slide-NN-*.sh` | the tested terminal sequence — one script per slide |
| `demo-lib.sh` | presenter plumbing: echo → wait for key → run; state handoff |
| `preflight.sh` | R1–R5 prep → `.output/shared/demo.env` |
| `onboard-genesis.mjs` | operator genesis onboarding helper (R2) |
| `batch-receipts.ts` | Slide 4: N statements → one checkpoint → N offline receipts |
| `themes/`, `scripts/build-deck.mjs`, `package.json` | Marp build scaffolding |
| `.output/` | runtime state (gitignored): `shared/` + per-slide `slide-N/` |
| `dist/` | built deck (gitignored): `deck.md`, `index.html`, `deck.pdf` |
| `archive/` | retired source outlines (superseded by `slides/`) |
| `ietf-126-demo-cuttings.md` | off-cuts kept for possible reuse |

## Marp commands

```bash
pnpm run build      # dist/index.html
pnpm run open       # build + open in browser
pnpm run preview    # live server http://localhost:8080/
pnpm run present    # presenter view (notes + next slide) — put on your 2nd screen
pnpm run pdf        # dist/deck.pdf
```

Commit `slides/`, `themes/`, `scripts/`, the `slide-NN-*.sh` scripts, and the
`.sh`/`.ts`/`.mjs` helpers — not `dist/`, `node_modules/`, or `.output/`.

## Recording (deck on screen + terminal as overlay)

Compose in OBS: a **Slides** browser source (`pnpm run preview` →
`localhost:8080`) and a **Terminal** window-capture scene, with a shared
branding overlay; drive slides from `pnpm run present` on a 2nd screen (never
captured). Cut to **Terminal** for each live demo, back to **Slides** to narrate.
(Same pattern as `product/decks/ietf-126-mmr-profile-demo/recording/`.)

## Tested status (2026-07-17, lane-A Base Sepolia, fresh preflight)

| Slide | Script | Demo | Status |
|-------|--------|------|--------|
| 2 Publishing | `slide-02-publishing.sh` | sign → register → **verify offline** | ✅ pass |
| 3 Self-serve | `slide-03-self-serve.sh` | derive the same receipt from the public tile | ✅ pass |
| 4 Throughput | `slide-04-throughput.sh` | 100 statements → one checkpoint → 100 offline receipts | ✅ pass (100/100, 4.3s submit / 2.6s seal / 3.4s receipts) |
| 5 Split-view | `slide-05-split-view.sh` | throwaway deploy + on-chain `bootstrapConfig` | ✅ pass (on-chain bootstrap key == slide 2's signing `kid`) |
| 6 Log creation | `slide-06-log-creation.sh` | build auth→data hierarchy, Alice writes, self-serve her receipt | ✅ pass |
| 7 Split-view verify | `slide-07-split-view-verify.sh` | **chain-anchored verify** + trust-ladder rungs 1 & 3 | ✅ pass (needs univocity **≥ v0.1.8** — see below) |
| 9 Roundup | `slide-09-roundup.sh` | the root-log closer | ✅ pass |

Rehearsed 2026-07-17 in **presentation order** (02→03→04→05→06→07→09) against a
fresh preflight on univocity **v0.1.8**: all pass, including the root=201
(103-leaf, odd) case that deterministically failed on v0.1.7.

Delegation is healthy throughout: preflight R4 pre-delegates the root before the
first write, and slide 6 pre-delegates each child (`create-log --prepare` →
`delegate` → `create-log`). The sealer logs show no errors and every child log
seals. **Sealing is not the problem; the on-chain publish is.**

### Slide 7 needs univocity ≥ v0.1.8 — the lone-peak grant leaf (FIXED)

On **v0.1.7 and earlier**, running the deck in presentation order made slide 7
fail deterministically (reproduced twice). Never a demo bug and never a
delegation bug — a univocity contract bug, now fixed in
[v0.1.8](https://github.com/forestrie/univocity/releases/tag/v0.1.8)
([FOR-393](https://linear.app/forestrie/issue/FOR-393),
[PR #32](https://github.com/forestrie/univocity/pull/32)).

`_Univocity.sol` accepted an **empty** grant inclusion path only when
`ownerLog.size == 1`. But an empty path is legitimate whenever **the grant leaf
is itself a peak** of the owner's accumulator — exactly when it is the owner's
last leaf and the owner's leaf count is **odd**. David's auth grant is always
the root's last leaf, so it was a parity coin flip:

| root leaves after David's grant | David's grant leaf | path | v0.1.7 |
|---|---|---|---|
| 103 (odd — R5 + slide 2 + slide 4's 100 + grant) | lone peak (103 = 64+32+4+2+**1**) | empty | ❌ revert → branch dead |
| 104 (even) | inside the 8-peak | length 3 | ✅ publishes |

The failure cascaded: David's auth publish reverted `InvalidPaymentReceipt` →
publisher logged `unpublishable checkpoint terminally acked` and **never
retried** → Alice's data log retried `owner_not_anchored` forever → slide 7 had
an empty accumulator to match and correctly fell back to `delegation_invalid`.
Making the publisher retry would **not** have helped: the revert is
deterministic until the owner grows, and this demo's root never grows after
slide 6.

Confirmed fixed on v0.1.8 (2026-07-17): same deck, same order, root again at
201 (103 leaves, odd) — David's auth log published first time, Alice's followed,
and all three slide-7 rungs passed.

`preflight.sh` needs no change: `forestrie deploy` defaults to
`--release-tag latest`, so a fresh preflight now deploys v0.1.8. Confirm with
`jq -r .releaseId .output/shared/deployment.json`. Note the contracts are
immutable — **forests deployed before v0.1.8 keep the bug**; re-run preflight.

### Timing: slide 7 waits for the child chain to anchor

Alice's data log can only anchor **after** David's auth log does — univocity
checks each grant against the owner's *on-chain* state, so `root → auth → data`
settles one link at a time (~2 min after slide 6 on lane-A). Run slide 7
immediately after slide 6 and the accumulator is still empty. `slide-07-*.sh`
therefore polls `logState` until Alice's log is anchored before verifying; it
is silent, and slide 8 (conceptual) covers the wait on stage.

### Child-log verification — chain-anchored (shipped) vs offline (in flight)

A **child-log** receipt is sealed under a per-log delegation signed by the child
key holder (Alice for her data log), which does not chain to the root genesis —
so purely-offline `verify`/`verify-grant` fails `signature: delegation_invalid`
(the offline library resolves the label-1000 cert against the genesis key only,
one hop; the server resolves per-log keys via `logSigningKey(ownerLogId)`).

**Shipped (FOR-297 approach C, 2026-07-16):** in chain-anchored mode
(`verify … --univocity --log-id <child> --rpc-url`) the CLI recomputes the peak
locally from the leaf commitment (`SHA-256(idtimestamp ‖ SHA-256(payload))`) and
the receipt's proof path — **no signature involved** — and byte-matches it
against the child log's own on-chain `logState` accumulator. Univocity anchors
every log independently, so the anchor match proves binding + inclusion under
the contract's consistency-gated state; the signature row reports
`skipped … externalised to the on-chain accumulator`. A forged payload or
tampered path recomputes a different peak and cannot anchor (tested live, both
directions). This is the Slide 7 closer. The mechanism is shipped and correct;
when it reports `delegation_invalid` the cause is an **unanchored child log**,
not a verify bug — either the forest predates univocity v0.1.8, or the chain
has not settled yet (see the two notes above).

**Still open (FOR-297 approach A):** purely-offline child verify needs the
multi-hop grant-chain resolver in `@forestrie/receipt-verify` (walk genesis →
auth grant [root-signed] → data grant [David-signed, grantData=Alice] → Alice's
delegation cert; every link is a self-servable receipted leaf) plus CLI plumbing
for the intermediate grants.

Corollaries learned while validating Slide 6, baked into the slide scripts:
- A data-log **create+extend** grant names its writer in `grantData` — that grant
  is the write authorization; no separate `register-grant` is needed for a single
  writer.
- Each log's sealing delegation must be signed by **that log's key holder**
  (auth → David, data → Alice), else the coordinator rejects it.
- Child-log statements register via the **forest (root) path**
  (`register --log-id "$ROBERT_LOG_ID"`); the grant directs the entry to the
  child log. Using the child id 404s ("Forest genesis not found").
