// Fails when the JavaScript needed before the first screen grows past its budget.
// Run after `vite build` (npm run check:bundle does both).
//
// What is counted: the entry script, everything it imports statically, and the
// lazily loaded chunks that screen needs (with their own static imports). The
// chunk graph is read from the built files themselves, so a new shared chunk or a
// page that starts importing a heavy module is counted without touching this file.
import { readFileSync, readdirSync } from 'node:fs';
import { gzipSync } from 'node:zlib';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const dist = resolve(dirname(fileURLToPath(import.meta.url)), '..', process.env.BUNDLE_DIR || 'dist');
const assets = join(dist, 'assets');

/**
 * Budgets in bytes, about 10% above what was measured on 2026-10-09:
 *   sign-in page                       491,146 raw / 141,596 gzip  (8 files)
 *   company admin, first page          536,395 raw / 158,899 gzip  (17 files)
 * 438 kB of each is the three vendor chunks (supabase, react, query).
 */
const BUDGETS = {
  'sign-in page': { lazy: ['LoginPage'], raw: 540_000, gzip: 155_700 },
  'company admin, first page (overview)': { lazy: ['Workspace', 'OverviewPage'], raw: 590_000, gzip: 174_800 },
};

const files = readdirSync(assets).filter((name) => name.endsWith('.js'));
const source = new Map(files.map((name) => [name, readFileSync(join(assets, name))]));

/** `LoginPage` → `LoginPage-3fa9c1.js` (the hash changes with every build). */
function chunkNamed(name) {
  const found = files.filter((file) => new RegExp(`^${name}-[\\w-]{8}\\.js$`).test(file));
  if (found.length !== 1) throw new Error(`expected one chunk named ${name}, found ${found.length}`);
  return found[0];
}

/** Static imports only: `import"./x.js"` and `from"./x.js"`, never `import("./x.js")`. */
function staticImports(file) {
  const text = source.get(file).toString('utf8');
  const found = new Set();
  for (const match of text.matchAll(/(?:\bfrom|\bimport)\s*["']\.\/([^"']+\.js)["']/g)) found.add(match[1]);
  return [...found].filter((name) => source.has(name));
}

function closure(roots) {
  const seen = new Set();
  const visit = (file) => {
    if (seen.has(file)) return;
    seen.add(file);
    staticImports(file).forEach(visit);
  };
  roots.forEach(visit);
  return [...seen];
}

const html = readFileSync(join(dist, 'index.html'), 'utf8');
const entry = /<script[^>]+type="module"[^>]+src="\/assets\/([^"]+\.js)"/.exec(html)?.[1];
if (!entry) throw new Error('entry script not found in dist/index.html');

let failed = false;
const report = (label, value, budget) => {
  const over = budget > 0 && value > budget;
  if (over) failed = true;
  return `${label} ${value.toLocaleString('en-US')} B${budget > 0 ? ` (budget ${budget.toLocaleString('en-US')})` : ''}${over ? '  <-- OVER' : ''}`;
};

for (const [screen, budget] of Object.entries(BUDGETS)) {
  const needed = closure([entry, ...budget.lazy.map(chunkNamed)]);
  const raw = needed.reduce((sum, file) => sum + source.get(file).length, 0);
  const gzip = needed.reduce((sum, file) => sum + gzipSync(source.get(file)).length, 0);
  console.log(`${screen}: ${needed.length} files, ${report('raw', raw, budget.raw)}, ${report('gzip', gzip, budget.gzip)}`);
}

if (failed) {
  console.error('\nBundle budget exceeded. Find what grew (a new static import of a heavy module is the usual cause) before raising a budget.');
  process.exit(1);
}
