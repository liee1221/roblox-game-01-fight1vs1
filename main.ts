// Fight 1vs1 — entrypoint for make.fun's "Make the best Roblox game" bounty.
// This is a plain Node 22 program (standard library only). It gathers the
// entry's files — game.rbxl, PLAY.json, src/, screenshots/ — into the output
// directory, then asks the vendored make.fun library to write dossier.json,
// the summary the judge reads first.
//
// The place (game.rbxl) is built from src/ by Rojo, so every .luau file in
// src/ is exactly a script inside the place. PLAY.json points at the live
// published place. Screenshots are ordered by name; the first one is the
// cover, so the FIGHT! gameplay shot is named 01-cover.jpg.
//
// When run outside the grader, MAKEFUN_OUTPUT_DIR replaces /output:
//   MAKEFUN_OUTPUT_DIR=out node main.ts

import { copyFileSync, cpSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildDossier } from './vendor/makefun-roblox.ts';

const here = fileURLToPath(new URL('.', import.meta.url));
const out = process.env.MAKEFUN_OUTPUT_DIR ?? '/output';

// Create the output directory up front; the starter only creates the
// screenshots folder, which happens after the first copies.
mkdirSync(out, { recursive: true });

// Fail fast with a clear message if a required input is missing, instead of
// dying mid-copy with a bare ENOENT from copyFileSync. src/ is checked too,
// because a Rojo build that produced no scripts would otherwise ship an
// empty game.
for (const f of ['game.rbxl', 'PLAY.json', 'src']) {
  if (!existsSync(join(here, f))) throw new Error(`missing required input: ${f}`);
}

copyFileSync(join(here, 'game.rbxl'), join(out, 'game.rbxl'));
copyFileSync(join(here, 'PLAY.json'), join(out, 'PLAY.json'));
cpSync(join(here, 'src'), join(out, 'src'), { recursive: true });
mkdirSync(join(out, 'screenshots'), { recursive: true });
if (existsSync(join(here, 'screenshots'))) cpSync(join(here, 'screenshots'), join(out, 'screenshots'), { recursive: true });

// Caps from the scorer (reference/gate.json). Only text_max_bytes shapes the
// dossier bytes; the rest refuse an entry the scorer would refuse anyway:
// more than 4 screenshots or one over 256 KiB, a place over 500000
// instances, scripts over 8 MiB of source, or script paths over 1048576
// characters in total.
writeFileSync(
  join(out, 'dossier.json'),
  buildDossier(out, { text_max_bytes: 65536, screenshots: { max: 4, max_bytes: 262144 }, max_instances: 500000, scripts_max_source_bytes: 8388608, scripts_max_path_chars: 1048576 }),
);
