'use strict';
// ══════════════════════════════════════════════════════════════════════════
// Giriş sistemi — Supabase Auth-un əvəzi.
//   • şifrə: scrypt (Node-un daxili modulu) + hər istifadəçiyə ayrı salt
//   • sessiya: təsadüfi 32 bayt token; bazada YALNIZ SHA-256 hash-i saxlanılır
//   • e-poçt təsdiqi (istəyə bağlı): 6 rəqəmli kod, hash-lənmiş, 15 dəq, 5 cəhd
//   • IP üzrə cəhd limiti (şifrə təxmin etməyə qarşı)
// Cavab formatı supabase-js ilə eynidir ki, sayt dəyişmədən işləsin.
// ══════════════════════════════════════════════════════════════════════════
const crypto = require('crypto');
const { config } = require('./config');
const { q, tx, apiError, isoFromMysql, mysqlFromIso, encodeValue, colMap, decodeRow } = require('./db');
const mailer = require('./mailer');

// ── şifrə ───────────────────────────────────────────────────────────────
const SCRYPT = { N: 16384, r: 8, p: 1, keylen: 64 };
function hashPassword(pw) {
  const salt = crypto.randomBytes(16);
  const h = crypto.scryptSync(pw, salt, SCRYPT.keylen, { N: SCRYPT.N, r: SCRYPT.r, p: SCRYPT.p });
  return `scrypt$${SCRYPT.N}$${SCRYPT.r}$${SCRYPT.p}$${salt.toString('base64')}$${h.toString('base64')}`;
}
function verifyPassword(pw, stored) {
  const [alg, N, r, p, salt, hash] = String(stored).split('$');
  if (alg !== 'scrypt') return false;
  const want = Buffer.from(hash, 'base64');
  const got = crypto.scryptSync(pw, Buffer.from(salt, 'base64'), want.length, { N: +N, r: +r, p: +p });
  return crypto.timingSafeEqual(want, got);
}
const sha256 = s => crypto.createHash('sha256').update(s).digest('hex');

// ── sadə cəhd limiti (yaddaşda; bir prosesli cPanel tətbiqi üçün kifayətdir) ──
const hits = new Map();
// Diqqət: məktəbdə bütün sinif EYNİ internet ünvanından (IP) girir, ona görə
// IP limitləri genişdir; şifrə təxmininə qarşı əsas qoruma — hesab üzrə
// UĞURSUZ cəhdlərin sayıdır (uğurlu girişlər sayılmır).
function rlGet(key, windowMs) {
  const now = Date.now();
  let h = hits.get(key);
  if (!h || now > h.reset) { h = { n: 0, reset: now + windowMs }; hits.set(key, h); }
  return h;
}
function rateCheck(key, max, windowMs) {
  if (rlGet(key, windowMs).n >= max) throw apiError(429, 'over_request_rate_limit', 'For security purposes, you can only request this after some seconds. (rate limit)');
}
function rateHit(key, windowMs) { rlGet(key, windowMs).n++; }
function rateLimit(key, max, windowMs) { rateCheck(key, max, windowMs); rateHit(key, windowMs); }
setInterval(() => { const now = Date.now(); for (const [k, v] of hits) if (now > v.reset) hits.delete(k); }, 60000).unref();

// ── istifadəçi / sessiya formatı (supabase-js ilə eyni) ──────────────────
function userObj(u) {
  const meta = typeof u.raw_user_meta_data === 'string' ? JSON.parse(u.raw_user_meta_data || '{}') : (u.raw_user_meta_data || {});
  return {
    id: u.id, aud: 'authenticated', role: 'authenticated', email: u.email,
    email_confirmed_at: isoFromMysql(u.email_confirmed_at), confirmed_at: isoFromMysql(u.email_confirmed_at),
    created_at: isoFromMysql(u.created_at), user_metadata: meta, app_metadata: { provider: 'email', providers: ['email'] },
    identities: [{ id: u.id, user_id: u.id, provider: 'email', identity_data: { email: u.email, sub: u.id } }],
  };
}
async function createSession(user, conn) {
  const token = crypto.randomBytes(32).toString('base64url');
  const expires = new Date(Date.now() + config.sessionDays * 864e5);
  await q('INSERT INTO auth_sessions (token_hash, user_id, expires_at) VALUES (?, ?, ?)', [sha256(token), user.id, mysqlFromIso(expires)], conn);
  return { access_token: token, token_type: 'bearer', expires_in: config.sessionDays * 86400,
           expires_at: Math.floor(expires.getTime() / 1000), refresh_token: token, user: userObj(user) };
}

// Sorğudakı token → kontekst (RLS qaydaları bunu işlədir)
async function contextFromToken(token) {
  const anon = { uid: null, username: null, role: 'anon', classGrade: '', teacherClass: '' };
  if (!token) return anon;
  const rows = await q(`SELECT u.*, p.username, p.role AS prole, p.class_grade, p.teacher_class
      FROM auth_sessions s JOIN auth_users u ON u.id = s.user_id LEFT JOIN profiles p ON p.id = u.id
      WHERE s.token_hash = ? AND s.expires_at > UTC_TIMESTAMP(3)`, [sha256(token)]);
  if (!rows.length) return anon;
  const r = rows[0];
  return { uid: r.id, username: r.username || null, role: r.prole || 'user', classGrade: r.class_grade || '',
           teacherClass: r.teacher_class || '', user: r, token };
}

// ── compute_level (Postgres funksiyasının eynisi) ────────────────────────
function computeLevel(xp) {
  let l = 1, rem = Math.max(0, xp | 0);
  while (rem >= l * 100) { rem -= l * 100; l++; }
  return l;
}

// ── handle_new_user (birləşdirilmiş qeydiyyat trigger-inin eynisi) ────────
async function createProfile(conn, id, meta) {
  const m = meta || {};
  let username = String(m.username ?? ('user_' + id.slice(0, 8))).toLowerCase();
  const first = String(m.first_name ?? '').trim(), last = String(m.last_name ?? '').trim();
  const display = (String(m.display_name ?? '').trim()) || (`${first} ${last}`.trim()) || username;
  let cls = String(m.class_grade ?? '').trim().toUpperCase();
  const phone = String(m.phone ?? '').trim();
  let ref = String(m.referred_by ?? '').trim().toLowerCase();
  if (!/^[a-z0-9_]{3,20}$/.test(username) || (await q('SELECT 1 FROM profiles WHERE username = ?', [username], conn)).length)
    username = 'user_' + id.slice(0, 8);
  if (!/^(1[01]|[1-9])[A-D]$/.test(cls)) cls = '';
  let bonus = 0;
  if (ref && ref !== username && (await q('SELECT 1 FROM profiles WHERE username = ?', [ref], conn)).length) {
    bonus = 20;
    const [{ xp }] = await q('SELECT xp FROM profiles WHERE username = ? FOR UPDATE', [ref], conn);
    await q('UPDATE profiles SET xp = ?, level = ? WHERE username = ?', [xp + 20, computeLevel(xp + 20), ref], conn);
  } else ref = '';
  await insertWithDefaults(conn, 'profiles', {
    id, username, display_name: display, first_name: first, last_name: last, class_grade: cls, phone,
    xp: bonus, level: computeLevel(bonus), streak: 0, role: 'user', last_visit: null, referred_by: ref,
  });
}

// Sxemdəki default-larla sətir əlavə et (default-lar əl ilə təkrarlanmasın)
async function insertWithDefaults(conn, table, values) {
  const { SCHEMA, defaultFor } = require('./db');
  const cols = [], vals = [];
  for (const c of SCHEMA[table].columns) {
    if (c.identity) continue;
    if (values[c.name] !== undefined) { cols.push(c.name); vals.push(encodeValue(c, values[c.name])); }
    else if (c.default) { cols.push(c.name); vals.push(defaultFor(c)); }
  }
  const [res] = await conn.query(`INSERT INTO \`${table}\` (${cols.map(c => '`' + c + '`').join(',')}) VALUES (${cols.map(() => '?').join(',')})`, vals);
  return res;
}

const OTP_TTL_MS = 15 * 60 * 1000, OTP_MAX_TRIES = 5, OTP_RESEND_MS = 60 * 1000;
async function issueOtp(conn, user) {
  const code = String(crypto.randomInt(0, 1000000)).padStart(6, '0');
  await q('UPDATE auth_users SET otp_hash = ?, otp_expires_at = ?, otp_attempts = 0, otp_sent_at = UTC_TIMESTAMP(3) WHERE id = ?',
    [sha256(user.id + ':' + code), mysqlFromIso(new Date(Date.now() + OTP_TTL_MS)), user.id], conn);
  await mailer.sendOtp(user.email, code);      // uğursuz olsa — tranzaksiya geri qaytarılır
}

const validEmail = e => /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(e) && e.length <= 190;

// ── endpoint-lər ─────────────────────────────────────────────────────────
async function signUp(body, ip) {
  rateLimit('signup:' + ip, 60, 10 * 60 * 1000);   // bütöv sinif eyni IP-dən qeydiyyatdan keçə bilsin
  const email = String(body.email || '').trim().toLowerCase();
  const password = String(body.password || '');
  if (!validEmail(email)) throw apiError(400, 'validation_failed', 'Unable to validate email address: invalid format');
  if (password.length < 6) throw apiError(400, 'weak_password', 'Password should be at least 6 characters.');
  const meta = body.data || body.options?.data || {};
  const existing = await q('SELECT * FROM auth_users WHERE email = ?', [email]);
  if (existing.length) {
    // Supabase kimi: təsdiq açıqdırsa hesab siyahısını gizlətmək üçün "boş identities" qaytarılır
    if (config.emailConfirm) return { user: { ...userObj(existing[0]), identities: [] }, session: null };
    throw apiError(422, 'user_already_exists', 'User already registered');
  }
  const id = crypto.randomUUID();
  return tx(async conn => {
    await q(`INSERT INTO auth_users (id, email, password_hash, raw_user_meta_data, email_confirmed_at)
             VALUES (?, ?, ?, ?, ${config.emailConfirm ? 'NULL' : 'UTC_TIMESTAMP(3)'})`,
      [id, email, hashPassword(password), JSON.stringify(meta)], conn);
    await createProfile(conn, id, meta);
    const [u] = await q('SELECT * FROM auth_users WHERE id = ?', [id], conn);
    if (config.emailConfirm) {
      try { await issueOtp(conn, u); }
      catch (e) { throw apiError(500, 'unexpected_failure', 'Error sending confirmation email'); }
      return { user: userObj(u), session: null };
    }
    const session = await createSession(u, conn);
    return { user: userObj(u), session };
  });
}

async function signIn(body, ip) {
  const W = 10 * 60 * 1000;
  const email = String(body.email || '').trim().toLowerCase();
  rateCheck('login-fail-ip:' + ip, 100, W);          // bir IP-dən 100 uğursuz cəhd / 10 dəq
  rateCheck('login-fail:' + email, 10, W);           // bir hesaba 10 uğursuz cəhd / 10 dəq
  const rows = await q('SELECT * FROM auth_users WHERE email = ?', [email]);
  // istifadəçi yoxdursa da hash hesablanır — cavab müddətinə görə hesab varlığı bilinməsin
  const ok = rows.length ? verifyPassword(String(body.password || ''), rows[0].password_hash)
                         : (verifyPassword('x', hashPassword('y')), false);
  if (!ok) { rateHit('login-fail-ip:' + ip, W); rateHit('login-fail:' + email, W); throw apiError(400, 'invalid_credentials', 'Invalid login credentials'); }
  const u = rows[0];
  if (config.emailConfirm && !u.email_confirmed_at) throw apiError(400, 'email_not_confirmed', 'Email not confirmed');
  const session = await createSession(u);
  return { user: userObj(u), session };
}

async function verifyOtp(body, ip) {
  rateLimit('otp:' + ip, 120, 10 * 60 * 1000);
  const email = String(body.email || '').trim().toLowerCase();
  const token = String(body.token || '').trim();
  return tx(async conn => {
    const rows = await q('SELECT * FROM auth_users WHERE email = ? FOR UPDATE', [email], conn);
    const u = rows[0];
    if (!u || !u.otp_hash) throw apiError(403, 'otp_expired', 'Token has expired or is invalid');
    if (u.otp_attempts >= OTP_MAX_TRIES || new Date(isoFromMysql(u.otp_expires_at)) < new Date())
      throw apiError(403, 'otp_expired', 'Token has expired or is invalid');
    if (sha256(u.id + ':' + token) !== u.otp_hash) {
      await q('UPDATE auth_users SET otp_attempts = otp_attempts + 1 WHERE id = ?', [u.id], conn);
      throw apiError(403, 'otp_expired', 'Token has expired or is invalid');
    }
    await q('UPDATE auth_users SET email_confirmed_at = COALESCE(email_confirmed_at, UTC_TIMESTAMP(3)), otp_hash = NULL, otp_expires_at = NULL WHERE id = ?', [u.id], conn);
    const [fresh] = await q('SELECT * FROM auth_users WHERE id = ?', [u.id], conn);
    const session = await createSession(fresh, conn);
    return { user: userObj(fresh), session };
  });
}

async function resend(body, ip) {
  rateLimit('resend:' + ip, 60, 10 * 60 * 1000);
  const email = String(body.email || '').trim().toLowerCase();
  if (!config.emailConfirm) return {};
  return tx(async conn => {
    const [u] = await q('SELECT * FROM auth_users WHERE email = ? FOR UPDATE', [email], conn);
    if (!u || u.email_confirmed_at) return {};           // hesabın varlığı bildirilmir
    if (u.otp_sent_at && Date.now() - new Date(isoFromMysql(u.otp_sent_at)).getTime() < OTP_RESEND_MS)
      throw apiError(429, 'over_email_send_rate_limit', 'For security purposes, you can only request this after 60 seconds.');
    try { await issueOtp(conn, u); } catch (e) { throw apiError(500, 'unexpected_failure', 'Error sending confirmation email'); }
    return {};
  });
}

async function getUser(ctx) {
  if (!ctx.uid) throw apiError(401, 'no_authorization', 'Auth session missing!');
  return { user: userObj(ctx.user) };
}

async function signOut(ctx) {
  if (ctx.token) await q('DELETE FROM auth_sessions WHERE token_hash = ?', [sha256(ctx.token)]);
  return {};
}

// köhnəlmiş sessiyaları vaxtaşırı təmizlə
setInterval(() => { q('DELETE FROM auth_sessions WHERE expires_at < UTC_TIMESTAMP(3)').catch(() => {}); }, 6 * 3600 * 1000).unref();

module.exports = { signUp, signIn, verifyOtp, resend, getUser, signOut, contextFromToken, computeLevel, hashPassword, createProfile, insertWithDefaults };
