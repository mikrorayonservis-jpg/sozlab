'use strict';
// MySQL qatı: bağlantı hovuzu, tranzaksiya və sxemə görə dəyər çevirmə.
// Bütün sorğular parametrlidir (?), identifikatorlar isə YALNIZ schema.json
// ağ siyahısından gəlir — SQL injection üçün boşluq qalmır.
const mysql = require('mysql2/promise');
const crypto = require('crypto');
const { config } = require('./config');
const SCHEMA = require('../schema.json');

let pool = null;
function getPool() {
  if (pool) return pool;
  pool = mysql.createPool({
    ...config.db,
    charset: 'utf8mb4',
    timezone: 'Z',
    dateStrings: true,          // tarixləri özümüz UTC ISO-ya çeviririk
    supportBigNumbers: true,
    bigNumberStrings: false,
    decimalNumbers: true,
    waitForConnections: true,
    multipleStatements: false,
  });
  // Hər bağlantı UTC-də işləsin (CURRENT_TIMESTAMP → UTC)
  pool.pool.on('connection', c => { c.query("SET time_zone = '+00:00'"); });
  return pool;
}

const q = (sql, params = [], conn = null) => (conn || getPool()).query(sql, params).then(([rows]) => rows);

async function tx(fn) {
  const conn = await getPool().getConnection();
  try {
    await conn.beginTransaction();
    const out = await fn(conn);
    await conn.commit();
    return out;
  } catch (e) {
    try { await conn.rollback(); } catch (_) {}
    throw e;
  } finally { conn.release(); }
}

// ── tip çevirmə ─────────────────────────────────────────────────────────
const colMap = {};
for (const [t, def] of Object.entries(SCHEMA)) {
  colMap[t] = {};
  for (const c of def.columns) colMap[t][c.name] = c;
}

function isoFromMysql(s) {            // '2026-09-24 15:21:03.123' → ISO UTC
  if (s == null) return null;
  const [d, t = '00:00:00'] = String(s).split(' ');
  const [hms, ms = '000'] = t.split('.');
  return `${d}T${hms}.${(ms + '000').slice(0, 3)}+00:00`;
}
function mysqlFromIso(v) {            // hər hansı tarix → 'YYYY-MM-DD HH:MM:SS.mmm' UTC
  if (v == null || v === '') return null;
  const d = v instanceof Date ? v : new Date(v);
  if (isNaN(d.getTime())) throw apiError(400, '22007', 'Tarix formatı yanlışdır: ' + v);
  return d.toISOString().replace('T', ' ').replace('Z', '');
}

function decodeValue(col, v) {
  if (v == null) return v;
  switch (col.kind) {
    case 'bool': return v === 1 || v === true || v === '1';
    case 'json': case 'array':
      if (typeof v === 'string') { try { return JSON.parse(v); } catch (_) { return v; } }
      return v;
    case 'datetime': return isoFromMysql(v);
    case 'date': return String(v).slice(0, 10);
    case 'int': case 'bigint': case 'smallint': case 'decimal': return typeof v === 'string' ? Number(v) : v;
    default: return v;
  }
}
function decodeRow(table, row, cols) {
  const cm = colMap[table] || {};
  const out = {};
  for (const k of cols || Object.keys(row)) {
    const c = cm[k];
    out[k] = c ? decodeValue(c, row[k]) : row[k];
  }
  return out;
}

function encodeValue(col, v) {
  if (v === undefined) return undefined;
  if (v === null) return null;
  switch (col.kind) {
    case 'bool': return v ? 1 : 0;
    case 'json': return JSON.stringify(v);
    case 'array':
      if (!Array.isArray(v)) throw apiError(400, '22P02', `"${col.name}" massiv olmalıdır`);
      return JSON.stringify(v);
    case 'datetime': return mysqlFromIso(v);
    case 'date': {
      if (v instanceof Date) return v.toISOString().slice(0, 10);
      const s = String(v); if (!/^\d{4}-\d\d-\d\d/.test(s)) throw apiError(400, '22007', 'Tarix yanlışdır: ' + s);
      return s.slice(0, 10);
    }
    case 'int': case 'bigint': case 'smallint': {
      const n = Number(v); if (!Number.isFinite(n) || !Number.isInteger(n)) throw apiError(400, '22P02', `"${col.name}" tam ədəd olmalıdır`);
      return n;
    }
    case 'decimal': { const n = Number(v); if (!Number.isFinite(n)) throw apiError(400, '22P02', `"${col.name}" ədəd olmalıdır`); return n; }
    case 'uuid': {
      const s = String(v); if (!/^[0-9a-f-]{36}$/i.test(s)) throw apiError(400, '22P02', `"${col.name}" uuid deyil`);
      return s.toLowerCase();
    }
    default: return typeof v === 'string' ? v : (typeof v === 'object' ? JSON.stringify(v) : String(v));
  }
}

function defaultFor(col) {
  const d = col.default;
  if (!d) return undefined;
  if (d.now) return mysqlFromIso(new Date());
  if (d.today) return new Date().toISOString().slice(0, 10);
  if (d.uuid) return crypto.randomUUID();
  return encodeValue(col, d.value);
}

// PostgREST / Postgres xəta formatı (frontend error.message / error.code oxuyur)
function apiError(status, code, message, details) {
  const e = new Error(message);
  e.status = status; e.code = code; e.details = details || null; e.api = true;
  return e;
}

module.exports = { getPool, q, tx, SCHEMA, colMap, decodeRow, decodeValue, encodeValue, defaultFor, apiError, isoFromMysql, mysqlFromIso };
