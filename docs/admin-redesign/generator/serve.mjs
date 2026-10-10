/**
 * Static server for admin-canvas2 plus the height report the measure pages call.
 *   node serve.mjs [port]      (default 8793; run it in the background, stop it when done)
 */
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(here, '..');
const port = Number(process.argv[2] ?? 8793);
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.json': 'application/json', '.png': 'image/png', '.css': 'text/css' };
fs.mkdirSync(path.join(here, '.heights'), { recursive: true });
http.createServer((req, res) => {
  const url = new URL(req.url, 'http://x');
  if (url.pathname === '/__h') {
    const n = (url.searchParams.get('n') ?? '').replace(/[^A-Za-z0-9_-]/g, '');
    const h = Number(url.searchParams.get('h'));
    if (n && h > 0) fs.writeFileSync(path.join(here, '.heights', n), String(h));
    res.writeHead(204); res.end(); return;
  }
  const file = path.normalize(path.join(root, decodeURIComponent(url.pathname)));
  if (!file.startsWith(root) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); res.end('not found'); return; }
  res.writeHead(200, { 'content-type': TYPES[path.extname(file)] ?? 'application/octet-stream', 'cache-control': 'no-store' });
  fs.createReadStream(file).pipe(res);
}).listen(port, () => console.log(`serving ${root} on http://localhost:${port}`));
