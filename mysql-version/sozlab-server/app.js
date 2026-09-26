'use strict';
// ══════════════════════════════════════════════════════════════════════════
// SözLab — Node.js + MySQL server (cPanel "Setup Node.js App" üçün)
// Başlanğıc faylı (Application startup file): app.js
//
// Heç bir framework yoxdur (yalnız mysql2, istəyə görə nodemailer) — hostinqdə
// "Run NPM Install" tez bitsin, daha az asılılıq = daha az təhlükə.
//
//   GET  /                         → sayt (public/index.html və s.)
//   POST /api/query                → cədvəl sorğuları (sb.from(...))
//   POST /api/rpc/<ad>             → server funksiyaları (sb.rpc(...))
//   POST /api/auth/<əməliyyat>     → qeydiyyat / giriş / kod / çıxış
//   GET  /api/auth/user            → cari istifadəçi
//   POST /api/storage/<bucket>/<fayl yolu>   → şəkil yüklə (xam baytlar)
//   POST /api/storage-remove/<bucket>        → şəkilləri sil {prefixes:[...]}
//   GET  /storage/<bucket>/<fayl yolu>       → yüklənmiş şəkli göstər
//   GET  /api/health               → baza bağlantısını yoxla
// ══════════════════════════════════════════════════════════════════════════
const http = require('http');
const fs = require('fs');
const path = require('path');
const { config, checkConfig } = require('./lib/config');
const { q } = require('./lib/db');
const auth = require('./lib/auth');
const { handleQuery } = require('./lib/rest');
const { handleRpc } = require('./lib/rpc');
const storage = require('./lib/storage');

const JSON_LIMIT = 4 * 1024 * 1024;

const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json; charset=utf-8', '.webmanifest': 'application/manifest+json',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.gif': 'image/gif', '.webp': 'image/webp',
  '.svg': 'image/svg+xml', '.ico': 'image/x-icon', '.txt': 'text/plain; charset=utf-8', '.xml': 'application/xml',
  '.woff2': 'font/woff2', '.woff': 'font/woff', '.mp3': 'audio/mpeg', '.wav': 'audio/wav', '.pdf': 'application/pdf',
};
const SEC_HEADERS = {
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'strict-origin-when-cross-origin',
  'X-Frame-Options': 'SAMEORIGIN',
};

function send(res, status, obj, extra) {
  const body = JSON.stringify(obj === undefined ? null : obj);
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', ...SEC_HEADERS, ...extra });
  res.end(body);
}
function sendError(res, e) {
  if (e && e.api) return send(res, e.status || 400, { error: { message: e.message, code: e.code, details: e.details, hint: null, status: e.status } });
  console.error('[sozlab] gözlənilməz xəta:', e);
  const dbDown = e && ['ECONNREFUSED', 'ER_ACCESS_DENIED_ERROR', 'ER_BAD_DB_ERROR', 'PROTOCOL_CONNECTION_LOST', 'ETIMEDOUT'].includes(e.code);
  send(res, dbDown ? 503 : 500, { error: { message: dbDown ? 'Verilənlər bazasına qoşulmaq alınmadı' : 'Server xətası', code: dbDown ? 'db_unavailable' : 'internal' } });
}

function readBody(req, limit) {
  return new Promise((resolve, reject) => {
    const len = Number(req.headers['content-length'] || 0);
    if (len > limit) { const e = new Error('too large'); e.api = true; e.status = 413; e.code = 'payload_too_large'; e.message = 'Göndərilən məlumat çox böyükdür'; return reject(e); }
    const chunks = []; let size = 0;
    req.on('data', c => {
      size += c.length;
      if (size > limit) { const e = new Error('Göndərilən məlumat çox böyükdür'); e.api = true; e.status = 413; e.code = 'payload_too_large'; req.destroy(); reject(e); }
      else chunks.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}
async function readJson(req) {
  const buf = await readBody(req, JSON_LIMIT);
  if (!buf.length) return {};
  try { return JSON.parse(buf.toString('utf8')); }
  catch (_) { const e = new Error('Yanlış JSON'); e.api = true; e.status = 400; e.code = 'bad_json'; throw e; }
}
const clientIp = req => String(req.headers['x-forwarded-for'] || '').split(',')[0].trim() || req.socket.remoteAddress || '?';
const bearer = req => { const m = /^Bearer\s+(.+)$/i.exec(req.headers.authorization || ''); return m ? m[1].trim() : null; };

// ── statik fayllar (sayt) ────────────────────────────────────────────────
function serveStatic(req, res, pathname) {
  let rel;
  try { rel = decodeURIComponent(pathname); } catch (_) { res.writeHead(400); return res.end(); }
  if (rel.endsWith('/')) rel += 'index.html';
  const file = path.normalize(path.join(config.publicDir, rel));
  if (!file.startsWith(config.publicDir + path.sep) && file !== config.publicDir) { res.writeHead(403); return res.end(); }
  if (path.basename(file).startsWith('.')) { res.writeHead(404); return res.end(); }   // .env, .git və s. heç vaxt verilmir
  fs.stat(file, (err, st) => {
    if (err || !st.isFile()) {
      // naməlum yol → saytın özü (SPA), amma fayl kimi görünən yollar üçün 404
      if (!path.extname(rel)) return serveStatic(req, res, '/index.html');
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' }); return res.end('Tapılmadı');
    }
    const ext = path.extname(file).toLowerCase();
    const noCache = ext === '.html' || path.basename(file) === 'sw.js';
    res.writeHead(200, {
      'Content-Type': MIME[ext] || 'application/octet-stream', 'Content-Length': st.size,
      'Cache-Control': noCache ? 'no-cache' : 'public, max-age=86400', ...SEC_HEADERS,
    });
    if (req.method === 'HEAD') return res.end();
    fs.createReadStream(file).pipe(res);
  });
}

// ── marşrutlar ───────────────────────────────────────────────────────────
async function route(req, res) {
  const url = new URL(req.url, 'http://x');
  const p = url.pathname, m = req.method;

  if (p.startsWith('/storage/') && (m === 'GET' || m === 'HEAD')) {
    const [, , bucket, ...rest] = p.split('/');
    return storage.serve(res, bucket, rest.join('/'));
  }
  if (!p.startsWith('/api/')) {
    if (m !== 'GET' && m !== 'HEAD') { res.writeHead(405); return res.end(); }
    return serveStatic(req, res, p);
  }

  // Bütün API sorğuları yalnız eyni saytdan gəlir (CORS açılmır)
  if (m === 'OPTIONS') { res.writeHead(204); return res.end(); }

  if (p === '/api/health' && m === 'GET') {
    try { await q('SELECT 1 AS ok FROM profiles LIMIT 1'); return send(res, 200, { ok: true, db: 'connected' }); }
    catch (e) { return send(res, 503, { ok: false, db: 'error', message: e.code === 'ER_NO_SUCH_TABLE' ? 'Cədvəllər yoxdur — 01_schema.sql import edilməyib' : 'Bazaya qoşulmaq alınmadı (' + (e.code || e.message) + ')' }); }
  }

  const token = bearer(req);
  const ctx = await auth.contextFromToken(token);
  const ip = clientIp(req);
  // Vaxtı keçmiş / silinmiş sessiya: Supabase kimi 401 (sayt sessiyanı təmizləyib giriş ekranını göstərir)
  if (token && !ctx.uid && !/^\/api\/auth\/(signin|signup|verify|resend|signout)$/.test(p))
    return send(res, 401, { error: { message: 'JWT expired', code: 'PGRST301' } });

  if (p.startsWith('/api/auth/')) {
    const op = p.slice('/api/auth/'.length);
    if (op === 'user' && m === 'GET') return send(res, 200, await auth.getUser(ctx));
    if (m !== 'POST') return send(res, 405, { error: { message: 'Method not allowed' } });
    const body = await readJson(req);
    switch (op) {
      case 'signup': return send(res, 200, await auth.signUp(body, ip));
      case 'signin': return send(res, 200, await auth.signIn(body, ip));
      case 'verify': return send(res, 200, await auth.verifyOtp(body, ip));
      case 'resend': return send(res, 200, await auth.resend(body, ip));
      case 'signout': return send(res, 200, await auth.signOut(ctx));
    }
    return send(res, 404, { error: { message: 'Not found' } });
  }

  if (p === '/api/query' && m === 'POST') {
    const out = await handleQuery(ctx, await readJson(req));
    return send(res, out.status || 200, { data: out.data, count: out.count ?? null });
  }

  if (p.startsWith('/api/rpc/') && m === 'POST') {
    const name = p.slice('/api/rpc/'.length);
    if (!/^[a-z0-9_]+$/.test(name)) return send(res, 404, { error: { message: 'Not found' } });
    return send(res, 200, { data: await handleRpc(ctx, name, await readJson(req)) });
  }

  if (p.startsWith('/api/storage/') && m === 'POST') {
    const [bucket, ...rest] = p.slice('/api/storage/'.length).split('/');
    let name; try { name = decodeURIComponent(rest.join('/')); } catch (_) { name = ''; }
    const buf = await readBody(req, config.maxUploadBytes + 1024);
    return send(res, 200, { data: await storage.upload(ctx, bucket, name, buf) });
  }
  if (p.startsWith('/api/storage-remove/') && m === 'POST') {
    const bucket = p.slice('/api/storage-remove/'.length);
    const body = await readJson(req);
    return send(res, 200, { data: await storage.remove(ctx, bucket, body.prefixes) });
  }

  return send(res, 404, { error: { message: 'Not found', code: 'not_found' } });
}

const server = http.createServer((req, res) => {
  route(req, res).catch(e => {
    if (process.env.LOG_API_ERRORS) console.log('[api-xəta]', req.method, req.url.slice(0, 120), e.status || 500, e.code || '', String(e.message).slice(0, 160));
    if (!res.headersSent) sendError(res, e); else res.end();
  });
});
server.requestTimeout = 60000;
server.headersTimeout = 20000;

if (require.main === module || process.env.PASSENGER_APP_ENV || typeof PhusionPassenger !== 'undefined') {
  const warn = checkConfig();
  if (warn) console.error('[sozlab] DİQQƏT: ' + warn);
  const port = process.env.PORT || config.port;
  server.listen(port, () => console.log(`[sozlab] server işləyir: port ${port}  (sayt: ${config.publicDir})`));
}

module.exports = { server };
