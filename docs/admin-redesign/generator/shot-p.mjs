/**
 * Measure and render boards with headless Edge.
 *   node shot.mjs measure <batch> [Name…]   → writes heights.<batch>.json (all boards of the batch, or the named ones)
 *   node shot.mjs render  <batch> [Name…]   → writes ../project/renders/<Name>.png
 * Needs `node serve.mjs` running (PORT env, default 8793).
 * Edge hands the work to a background process and returns at once, so both modes wait for the result file.
 */
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const EDGE = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const PORT = process.env.PORT ?? '8793';
const [mode, batch, ...only] = process.argv.slice(2);
const names = only.length ? only : fs.readFileSync(path.join(here, `names.${batch}.txt`), 'utf8').split(/\r?\n/).filter(Boolean);
const edge = (args) => spawnSync(EDGE, ['--headless=new', '--disable-gpu', '--hide-scrollbars', '--virtual-time-budget=6000', '--user-data-dir=' + path.join(here, '.edge-platform', 'p' + Date.now()), ...args], { stdio: 'ignore' });
const size = (file) => { const m = fs.readFileSync(file, 'utf8').match(/"width":(\d+),"height":(\d+)/); return [Number(m[1]), Number(m[2])]; };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function waitFor(file, ms = 60000) {
  const t0 = Date.now(); let last = -1;
  while (Date.now() - t0 < ms) {
    await sleep(400);
    if (!fs.existsSync(file)) continue;
    const s = fs.statSync(file).size;
    if (s > 0 && s === last) return true;
    last = s;
  }
  return false;
}

if (mode === 'measure') {
  const file = path.join(here, `heights.${batch}.json`);
  let out = {}; try { out = JSON.parse(fs.readFileSync(file, 'utf8')); } catch { /* first run */ }
  for (const n of names) {
    const f = path.join(here, 'measure', `${n}.dc.html`);
    if (!fs.existsSync(f)) continue;
    const [w] = size(f);
    const hf = path.join(here, '.heights', n);
    fs.rmSync(hf, { force: true });
    edge([`--window-size=${Math.max(w, 800)},900`, '--dump-dom', `http://localhost:${PORT}/build2/measure/${n}.dc.html`]);
    const ok = await waitFor(hf);
    const h = ok ? Number(fs.readFileSync(hf, 'utf8')) : 0;
    if (h > 0) out[n] = h;
    console.log(n, h || 'NOT MEASURED');
  }
  fs.writeFileSync(file, JSON.stringify(out, null, 1));
} else if (mode === 'render') {
  const dir = path.join(here, '..', 'project', 'renders');
  fs.mkdirSync(dir, { recursive: true });
  for (const n of names) {
    const [w, h] = size(path.join(here, '..', 'project', `${n}.dc.html`));
    const ww = Math.max(w, 800);
    const png = path.join(dir, `${n}.png`);
    fs.rmSync(png, { force: true });
    edge([`--window-size=${ww},${h}`, `--screenshot=${png}`, `http://localhost:${PORT}/project/${n}.dc.html`]);
    const ok = await waitFor(png);
    if (ok && ww !== w) spawnSync('python', ['-c', 'from PIL import Image\nimport sys\np=sys.argv[1]; w=int(sys.argv[2]); im=Image.open(p); W,H=im.size\nim.crop((W-w,0,W,H)).save(p)', png, String(w)], { stdio: 'inherit' });
    console.log(n, ok ? `${w}x${h}` : 'NOT RENDERED');
  }
} else {
  console.log('usage: node shot.mjs measure|render <batch> [Name…]');
}
