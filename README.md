# Forestrie — IETF 126 demo

A live `forestrie` walkthrough for the IETF SCITT WG, as **two artifacts driven
off one narrative**:

- **`slides/`** — the Marp deck (the primary content; what the audience sees).
- **`demo-script.sh`** — the runnable terminal companion (what you paste/run).

The deck shows the talking points; the terminal shows the commands live. During
the talk you cut between a **Slides** scene and a **Terminal** scene (see
*Recording*).

## Quick start

```bash
# 1. one-time prep: deploy a fresh forest + write .output/shared/demo.env
./preflight.sh
source .output/shared/demo.env

# 2. drive the deck (presenter view with notes on your 2nd screen)
pnpm install
pnpm run present         # or: build / preview / open / pdf

# 3. paste demo-script.sh into the long-lived terminal, one SLIDE block at a time
```

The terminal session runs `preflight.sh` **once** and sources the env **once**;
every slide reuses that state.

## Layout

| Path | What |
|------|------|
| `slides/NN-*.md` | Marp deck source (one file per slide) — **primary content** |
| `demo-script.sh` | the tested terminal sequence, slide by slide |
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

Commit `slides/`, `themes/`, `scripts/`, `demo-script.sh`, and the `.sh`/`.ts`/
`.mjs` helpers — not `dist/`, `node_modules/`, or `.output/`.

## Recording (deck on screen + terminal as overlay)

Compose in OBS: a **Slides** browser source (`pnpm run preview` →
`localhost:8080`) and a **Terminal** window-capture scene, with a shared
branding overlay; drive slides from `pnpm run present` on a 2nd screen (never
captured). Cut to **Terminal** for each live demo, back to **Slides** to narrate.
(Same pattern as `product/decks/ietf-126-mmr-profile-demo/recording/`.)

## Tested status (2026-07-16, lane-A Base Sepolia)

| Slide | Demo | Status |
|-------|------|--------|
| 2 Publishing | sign → register → **verify offline** | ✅ pass |
| 3 Self-serve | derive the same receipt from the public tile | ✅ pass |
| 4 Throughput | 100 statements → one checkpoint → 100 offline receipts | ✅ pass (100/100) |
| 5 Split-view | throwaway deploy + on-chain `bootstrapConfig` | ✅ pass |
| 6 Log creation | build auth→data hierarchy, Alice writes, self-serve + **chain-anchored verify** her receipt | ✅ pass (chain-anchored closer) |
| 7 Roundup | the root-log closer | ✅ pass |

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
directions). This is the Slide 6 closer.

**Still open (FOR-297 approach A):** purely-offline child verify needs the
multi-hop grant-chain resolver in `@forestrie/receipt-verify` (walk genesis →
auth grant [root-signed] → data grant [David-signed, grantData=Alice] → Alice's
delegation cert; every link is a self-servable receipted leaf) plus CLI plumbing
for the intermediate grants.

Corollaries learned while validating Slide 6, baked into `demo-script.sh`:
- A data-log **create+extend** grant names its writer in `grantData` — that grant
  is the write authorization; no separate `register-grant` is needed for a single
  writer.
- Each log's sealing delegation must be signed by **that log's key holder**
  (auth → David, data → Alice), else the coordinator rejects it.
- Child-log statements register via the **forest (root) path**
  (`register --log-id "$ROBERT_LOG_ID"`); the grant directs the entry to the
  child log. Using the child id 404s ("Forest genesis not found").
