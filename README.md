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
| 6 Log creation | build auth→data hierarchy, Alice writes, self-serve her receipt | ⚠️ builds + writes; child verify blocked (below) |
| 7 Roundup | the root-log closer | ✅ pass |

### Known limitation — hierarchical offline verify

Offline `forestrie verify` / `verify-grant` of a **child-log** receipt currently
fails `signature: delegation_invalid`. Root-log receipts verify cleanly. For
Slide 6 the demo therefore **builds the hierarchy, has Alice write, and self-
serves her receipt** (all tested) — it does not offline-verify the child receipt.

**Root cause (a library gap, not a hierarchy failing):** the offline verifier
has a *single* trust anchor — the genesis bootstrap key (`decodeTrustRootFrom
Genesis`) — and `resolveDelegatedVerifyKey` accepts a checkpoint's label-1000
delegation certificate only if it is signed **directly** by that key (one hop).
A child log's cert is signed by the child key holder (Alice), so it is rejected.
The **server** (`canopy-api/src/env/receipt-authority-resolver.ts`) verifies
child receipts fine because it resolves the *per-log* authorized signing key via
`client.logSigningKey(ownerLogId)` — a coordinator/custodian trust-root lookup
the offline library has no equivalent of. The authority chain itself is complete
and offline-checkable (genesis → auth grant [root-signed] → data grant [David-
signed, grantData=Alice] → Alice's per-log delegation cert), so the fix is a
**multi-hop resolver** in `@forestrie/receipt-verify` (walk + verify the grant
chain to genesis) plus CLI plumbing to supply/auto-fetch the intermediate grants
(they are publicly self-servable). Tracked under FOR-297.

Corollaries learned while validating Slide 6, baked into `demo-script.sh`:
- A data-log **create+extend** grant names its writer in `grantData` — that grant
  is the write authorization; no separate `register-grant` is needed for a single
  writer.
- Each log's sealing delegation must be signed by **that log's key holder**
  (auth → David, data → Alice), else the coordinator rejects it.
- Child-log statements register via the **forest (root) path**
  (`register --log-id "$ROBERT_LOG_ID"`); the grant directs the entry to the
  child log. Using the child id 404s ("Forest genesis not found").
