// Emulates the Supabase API gateway: /auth/v1 -> GoTrue, /rest/v1 -> PostgREST,
// /functions/v1/<name> -> Deno edge function runners.
import http from 'node:http';
const fnPorts = JSON.parse(process.env.FN_PORTS);
const route = (url) => {
  if (url.startsWith('/auth/v1')) return [9999, url.slice('/auth/v1'.length) || '/'];
  if (url.startsWith('/rest/v1')) return [3000, url.slice('/rest/v1'.length) || '/'];
  const m = url.match(/^\/functions\/v1\/([^/?]+)(.*)$/);
  if (m && fnPorts[m[1]]) return [fnPorts[m[1]], m[2] || '/'];
  return null;
};
const cors = {
  'access-control-allow-origin': '*',
  'access-control-allow-headers': 'authorization, x-client-info, apikey, content-type, prefer, accept-profile, content-profile, range, x-supabase-api-version',
  'access-control-allow-methods': 'GET, POST, PATCH, PUT, DELETE, OPTIONS',
  'access-control-expose-headers': 'content-range, x-total-count',
};
http.createServer((req, res) => {
  // Like the hosted gateway, answer CORS for auth/rest (functions answer their own).
  if (req.method === 'OPTIONS' && !req.url.startsWith('/functions/')) { res.writeHead(204, cors); return res.end(); }
  const target = route(req.url);
  if (!target) { res.writeHead(404); return res.end('no route'); }
  const headers = { ...req.headers, host: '127.0.0.1' };
  // Like Kong: an apikey with no bearer token acts as the bearer.
  if (!headers.authorization && headers.apikey) headers.authorization = `Bearer ${headers.apikey}`;
  const p = http.request({ host: '127.0.0.1', port: target[0], path: target[1], method: req.method, headers }, (r) => {
    const headers = req.url.startsWith('/functions/') ? r.headers : { ...r.headers, ...cors };
    res.writeHead(r.statusCode, headers); r.pipe(res);
  });
  p.on('error', (e) => { res.writeHead(502); res.end(String(e)); });
  req.pipe(p);
}).listen(8100, '127.0.0.1', () => console.log('gateway on 8100'));
