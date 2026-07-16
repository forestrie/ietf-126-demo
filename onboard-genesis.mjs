// Operator onboarding of a forest root genesis (R2 of the demo).
// 1. mint a payments-onboard token from the ops-admin token
// 2. build the genesis CBOR (current private labels, deterministic order)
// 3. POST it with the minted token (+ webhookUrl -> coordinator signing-route)
// Env: FORESTRIE_BASE_URL, CANOPY_OPS_ADMIN_TOKEN, BOOTSTRAP_LOG_ID,
//      UNIVOCITY_ADDRESS, CHAIN_ID, DELEGATION_COORDINATOR_URL, BOOTSTRAP_PEM
// Set BODY_ONLY=1 to only (re)write genesis-body.cbor and exit (offline check).
import { readFileSync, writeFileSync } from "node:fs";
import { createPublicKey } from "node:crypto";

const API = process.env.FORESTRIE_BASE_URL;
const OPS = (process.env.CANOPY_OPS_ADMIN_TOKEN || "").trim();
const LOG_ID = process.env.BOOTSTRAP_LOG_ID;
const UNIV = process.env.UNIVOCITY_ADDRESS.replace(/^0x/, "").toLowerCase();
const CHAIN = String(process.env.CHAIN_ID);
const COORD = process.env.DELEGATION_COORDINATOR_URL;
const PEM = readFileSync(process.env.BOOTSTRAP_PEM, "utf8");

// x||y (64 bytes) from the bootstrap ES256 public key.
const jwk = createPublicKey({ key: PEM, format: "pem" }).export({ format: "jwk" });
const xy = new Uint8Array(64);
xy.set(Buffer.from(jwk.x, "base64url"), 0);
xy.set(Buffer.from(jwk.y, "base64url"), 32);

// Minimal deterministic CBOR for this fixed shape.
const negKey = (n) => { const v = -n - 1; return [0x3a, (v >>> 24) & 0xff, (v >>> 16) & 0xff, (v >>> 8) & 0xff, v & 0xff]; };
const txt = (s) => { const b = Buffer.from(s, "utf8"); if (b.length < 24) return [0x60 | b.length, ...b]; return [0x78, b.length, ...b]; };
const bstr = (u8) => { if (u8.length < 24) return [0x40 | u8.length, ...u8]; return [0x58, u8.length, ...u8]; };

const univBytes = Uint8Array.from(Buffer.from(UNIV, "hex"));
// Deterministic key order (encoded-byte ascending): -68009,-68011,-68013,-68014,-68015
const body = Buffer.from([
  0xa5,
  ...negKey(-68009), 0x02,            // FOREST_GENESIS_LABEL_GENESIS_VERSION = 2
  ...negKey(-68011), ...bstr(univBytes), // UNIVOCITY_ADDR (20 bytes)
  ...negKey(-68013), ...txt(CHAIN),   // CHAIN_ID (text)
  ...negKey(-68014), 0x26,            // GENESIS_ALG = -7 (ES256)
  ...negKey(-68015), ...bstr(xy),     // BOOTSTRAP_KEY (x||y, 64 bytes)
]);
writeFileSync("genesis-body.cbor", body);
console.error(`genesis body: ${body.length} bytes for log ${LOG_ID}`);

if (process.env.BODY_ONLY) process.exit(0);

// Mint a payments-onboard token: POST {1:"demo"} with the ops-admin bearer.
const mintResp = await fetch(`${API}/api/payments/onboard-tokens`, {
  method: "POST",
  headers: { Authorization: `Bearer ${OPS}`, "Content-Type": "application/cbor" },
  body: Uint8Array.from([0xa1, 0x01, 0x64, 0x64, 0x65, 0x6d, 0x6f]),
});
if (!mintResp.ok) {
  console.error("mint onboard-token failed:", mintResp.status, await mintResp.text());
  process.exit(1);
}
const mb = Buffer.from(await mintResp.arrayBuffer());
// Extract the "token" text value from the CBOR map { cref, label, token }.
const mi = mb.indexOf(Buffer.from([0x65, 0x74, 0x6f, 0x6b, 0x65, 0x6e])); // "token"
if (mi < 0) { console.error("token key not in mint response"); process.exit(1); }
let p = mi + 6, tlen, tstart;
if (mb[p] === 0x78) { tlen = mb[p + 1]; tstart = p + 2; }
else if ((mb[p] & 0xe0) === 0x60) { tlen = mb[p] & 0x1f; tstart = p + 1; }
else { console.error("unexpected token encoding byte", mb[p].toString(16)); process.exit(1); }
const token = mb.slice(tstart, tstart + tlen).toString("utf8");

// POST the genesis with the minted token; webhookUrl forwards to the coordinator.
const webhook = `${COORD}/api/logs/${LOG_ID}/signing-route`;
const gr = await fetch(`${API}/api/forest/${LOG_ID}/genesis?webhookUrl=${encodeURIComponent(webhook)}`, {
  method: "POST",
  headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/cbor" },
  body,
});
console.error("genesis onboard POST:", gr.status);
if (!gr.ok) { console.error(await gr.text()); process.exit(1); }
console.error("onboarded root genesis for", LOG_ID);
