#!/usr/bin/env node
/**
 * Concatenate slides/*.md -> dist/deck.md with Marp slide breaks (---), injecting
 * the deck frontmatter and copying the theme into dist/. Slides are the single
 * source of truth for the presented content; the runnable terminal commands live
 * in ../demo-script.sh.
 */
import { readdir, readFile, writeFile, mkdir, cp } from "node:fs/promises";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const slidesDir = join(root, "slides");
const outDir = join(root, "dist");
const outFile = join(outDir, "deck.md");

const frontmatter = `---
marp: true
theme: forestrie
paginate: true
header: "Forestrie · MMR-profile COSE Receipts"
footer: "IETF 126 · SCITT"
---

`;

const files = (await readdir(slidesDir))
  .filter((f) => f.endsWith(".md"))
  .sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));

const bodies = await Promise.all(
  files.map(async (f) => (await readFile(join(slidesDir, f), "utf8")).trim()),
);

await mkdir(outDir, { recursive: true });
const deckBody = frontmatter + bodies.join("\n\n---\n\n") + "\n";
await writeFile(outFile, deckBody, "utf8");

await cp(join(root, "themes"), join(outDir, "themes"), { recursive: true });

console.log(`Built ${outFile} from ${files.length} slides: ${files.join(", ")}`);
