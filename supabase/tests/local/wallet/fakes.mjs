// Test doubles for the two outside services the wallet functions talk to:
//   :8443  Apple Push Notification service (HTTP/2, client certificate required)
//   :8444  Google OAuth token endpoint + Google Wallet API (generic classes/objects)
// plus GET /__state and POST /__reset on :8444 for the test to inspect and clear.
// Usage: node fakes.mjs <dir with ca.pem, srv.pem, srv.key>
import fs from 'node:fs';
import http from 'node:http';
import http2 from 'node:http2';

const dir = process.argv[2];
let state;
const reset = () => { state = { pushes: [], classes: {}, objects: {}, calls: [] }; };
reset();

http2.createSecureServer({
  key: fs.readFileSync(`${dir}/srv.key`), cert: fs.readFileSync(`${dir}/srv.pem`),
  ca: fs.readFileSync(`${dir}/ca.pem`), requestCert: true, rejectUnauthorized: true,
}, (req, res) => {
  const token = req.url.replace('/3/device/', '');
  let body = '';
  req.on('data', (chunk) => { body += chunk; });
  req.on('end', () => {
    state.pushes.push({
      token, body, topic: req.headers['apns-topic'], httpVersion: req.httpVersion,
      certificate: req.socket.getPeerCertificate()?.subject?.CN ?? null,
    });
    // A token that Apple no longer knows.
    if (token.startsWith('dead')) { res.writeHead(410, { 'content-type': 'application/json' }); return res.end('{"reason":"Unregistered"}'); }
    res.writeHead(200); res.end();
  });
}).listen(8443, '0.0.0.0');

http.createServer((req, res) => {
  let raw = '';
  req.on('data', (chunk) => { raw += chunk; });
  req.on('end', () => {
    const send = (status, body) => { res.writeHead(status, { 'content-type': 'application/json' }); res.end(JSON.stringify(body)); };
    if (req.url === '/__state') return send(200, state);
    if (req.url === '/__reset') { reset(); return send(200, {}); }
    if (req.url === '/token') return send(200, { access_token: 'fake-access-token', expires_in: 3600 });

    const match = req.url.match(/^\/walletobjects\/v1\/(genericClass|genericObject)(?:\/(.+))?$/);
    if (!match) return send(404, { error: { message: 'no route' } });
    if (req.headers.authorization !== 'Bearer fake-access-token') return send(401, { error: { message: 'unauthenticated' } });
    const store = match[1] === 'genericClass' ? state.classes : state.objects;
    const id = match[2] ? decodeURIComponent(match[2]) : null;
    const body = raw ? JSON.parse(raw) : null;
    state.calls.push({ method: req.method, kind: match[1], id: id ?? body?.id, body });

    if (req.method === 'POST' && !id) {
      if (store[body.id]) return send(409, { error: { message: 'already exists' } });
      store[body.id] = body; return send(200, body);
    }
    if (!store[id]) return send(404, { error: { message: 'not found' } });
    if (req.method === 'PUT') { store[id] = body; return send(200, body); }
    if (req.method === 'PATCH') { store[id] = { ...store[id], ...body }; return send(200, store[id]); }
    if (req.method === 'GET') return send(200, store[id]);
    return send(405, { error: { message: 'method' } });
  });
}).listen(8444, '0.0.0.0', () => console.log('wallet fakes up'));
