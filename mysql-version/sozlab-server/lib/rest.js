'use strict';
// ══════════════════════════════════════════════════════════════════════════
// Cədvəl API-si — supabase-js-in `sb.from(t).select().eq()...` zəncirinin
// server tərəfi. PostgREST-in saytın asılı olduğu davranışları dəqiq təkrarlanır:
//   • .single() 0 və ya 1-dən çox sətirdə xəta (PGRST116) verir
//   • RLS-in buraxmadığı UPDATE/DELETE xəta VERMİR, sadəcə 0 sətir dəyişir
//   • yeni sətir qaydanı pozursa 42501 "violates row-level security policy"
//   • NULL-lar Postgres kimi sıralanır (ASC → sonda, DESC → əvvəldə)
// ══════════════════════════════════════════════════════════════════════════
const { q, tx, SCHEMA, colMap, decodeRow, decodeValue, encodeValue, defaultFor, apiError, mysqlFromIso } = require('./db');
const { VIEWS, BEFORE_UPDATE, BEFORE_INSERT, usingSql, checkRow } = require('./policies');

const OPS = { eq: '=', neq: '<>', gt: '>', gte: '>=', lt: '<', lte: '<=' };

function tableInfo(table) {
  if (VIEWS[table]) {
    const v = VIEWS[table];
    const cols = Object.fromEntries(Object.entries(v.columns).map(([n, k]) => [n, { name: n, kind: k }]));
    return { view: v, cols, pk: [] };
  }
  const def = SCHEMA[table];
  if (!def) throw apiError(404, '42P01', `relation "public.${table}" does not exist`);
  return { def, cols: colMap[table], pk: def.pk };
}

function colOrErr(info, table, col) {
  const c = info.cols[col];
  if (!c) throw apiError(400, '42703', `column ${table}.${col} does not exist`);
  return c;
}

function encodeFilterValue(c, v) {
  if (v === null) return null;
  if (c.kind === 'bool') return (v === true || v === 'true' || v === 1 || v === '1') ? 1 : 0;
  if (c.kind === 'datetime') return mysqlFromIso(v);
  if (['int', 'bigint', 'smallint', 'decimal'].includes(c.kind)) {
    const n = Number(v); if (!Number.isFinite(n)) throw apiError(400, '22P02', `invalid input syntax for ${c.kind}: "${v}"`); return n;
  }
  if (c.kind === 'json' || c.kind === 'array') return JSON.stringify(v);
  return String(v);
}

// Tək filtr → SQL. col: t.`x`, op, dəyər.
function filterSql(info, table, [col, op, val]) {
  const c = colOrErr(info, table, col);
  const ref = `t.\`${col}\``;
  if (OPS[op]) {
    if (val === null) return { sql: op === 'neq' ? `${ref} IS NOT NULL` : '1=0', params: [] };
    return { sql: `${ref} ${OPS[op]} ?`, params: [encodeFilterValue(c, val)] };
  }
  if (op === 'in') {
    const arr = Array.isArray(val) ? val : [];
    if (!arr.length) return { sql: '1=0', params: [] };
    return { sql: `${ref} IN (${arr.map(() => '?').join(',')})`, params: arr.map(v => encodeFilterValue(c, v)) };
  }
  if (op === 'is') {
    if (val === null || val === 'null') return { sql: `${ref} IS NULL`, params: [] };
    if (val === true || val === 'true') return { sql: `${ref} = 1`, params: [] };
    if (val === false || val === 'false') return { sql: `${ref} = 0`, params: [] };
    throw apiError(400, '22P02', 'is() yalnız null/true/false qəbul edir');
  }
  if (op === 'like') return { sql: `${ref} LIKE ?`, params: [String(val).replace(/\*/g, '%')] };
  if (op === 'ilike') return { sql: `LOWER(${ref}) LIKE LOWER(?)`, params: [String(val).replace(/\*/g, '%')] };
  throw apiError(400, 'PGRST100', `dəstəklənməyən operator: ${op}`);
}

// PostgREST or() sətri: "a.eq.x,b.eq.y"
function parseOr(str) {
  const parts = []; let depth = 0, cur = '';
  for (const ch of String(str)) {
    if (ch === '(') depth++; else if (ch === ')') depth--;
    if (ch === ',' && depth === 0) { parts.push(cur); cur = ''; } else cur += ch;
  }
  if (cur) parts.push(cur);
  return parts.map(p => {
    const m = p.match(/^([a-z_][a-z0-9_]*)\.(eq|neq|gt|gte|lt|lte|is|like|ilike)\.(.*)$/i);
    if (!m) throw apiError(400, 'PGRST100', 'or() filtri başa düşülmədi: ' + p);
    let v = m[3]; if (v.startsWith('"') && v.endsWith('"')) v = v.slice(1, -1);
    return [m[1], m[2], v];
  });
}

function whereFor(info, table, body) {
  const parts = [];
  for (const f of body.filters || []) parts.push(filterSql(info, table, f));
  if (body.or) {
    const ors = parseOr(body.or).map(f => filterSql(info, table, f));
    parts.push({ sql: '(' + ors.map(x => x.sql).join(' OR ') + ')', params: ors.flatMap(x => x.params) });
  }
  return parts;
}

function joinWhere(parts) {
  if (!parts.length) return { sql: '1=1', params: [] };
  return { sql: parts.map(p => '(' + p.sql + ')').join(' AND '), params: parts.flatMap(p => p.params) };
}

function orderSql(info, table, order) {
  if (!order || !order.length) return '';
  return ' ORDER BY ' + order.map(([col, asc, nullsFirst]) => {
    const c = colOrErr(info, table, col);
    const ref = `t.\`${col}\``;
    const nf = nullsFirst == null ? !asc : !!nullsFirst;      // Postgres default: ASC→NULLS LAST, DESC→NULLS FIRST
    const expr = c.kind === 'text' ? `${ref} COLLATE utf8mb4_unicode_ci` : ref;
    return `(${ref} IS NULL) ${nf ? 'DESC' : 'ASC'}, ${expr} ${asc ? 'ASC' : 'DESC'}`;
  }).join(', ');
}

function selectCols(info, table, columns) {
  const all = Object.keys(info.cols);
  if (!columns || columns.trim() === '*' || columns.trim() === '') return all;
  const list = columns.split(',').map(s => s.trim()).filter(Boolean);
  for (const c of list) {
    if (c === '*') return all;
    colOrErr(info, table, c);
  }
  return [...new Set(list)];
}

function decode(info, table, row, cols) {
  if (info.view) {
    const out = {};
    for (const k of cols) out[k] = decodeValue(info.cols[k], row[k]);
    return out;
  }
  return decodeRow(table, row, cols);
}

function shape(body, rows, count) {
  if (body.head) return { data: null, count };
  if (body.single || body.maybe) {
    if (rows.length === 1) return { data: rows[0], count };
    if (rows.length === 0 && body.maybe) return { data: null, count };
    throw apiError(406, 'PGRST116', 'JSON object requested, multiple (or no) rows returned',
      `The result contains ${rows.length} rows`);
  }
  return { data: rows, count };
}

// ── SELECT ──────────────────────────────────────────────────────────────
async function doSelect(ctx, table, body, conn) {
  const info = tableInfo(table);
  const cols = selectCols(info, table, body.columns);
  let from, pol;
  if (info.view) {
    const role = ctx.uid ? 'authenticated' : 'anon';
    if (!info.view.roles.includes(role)) throw apiError(401, '42501', `permission denied for view ${table}`);
    from = `(${info.view.from}) AS t`; pol = { sql: '1=1', params: [] };
  } else {
    from = `\`${table}\` AS t`; pol = usingSql(table, 'select', ctx);
  }
  const w = joinWhere([...whereFor(info, table, body), pol]);
  let count = null;
  if (body.count) count = Number((await q(`SELECT COUNT(*) AS n FROM ${from} WHERE ${w.sql}`, w.params, conn))[0].n);
  if (body.head) return shape(body, [], count);
  let sql = `SELECT ${cols.map(c => 't.`' + c + '`').join(', ')} FROM ${from} WHERE ${w.sql}`;
  sql += orderSql(info, table, body.order);
  if (!body.order?.length && info.view?.defaultOrder) sql += ' ORDER BY ' + info.view.defaultOrder;
  const limit = body.single || body.maybe ? Math.min(2, body.limit ?? 2) : body.limit;   // .limit(1).single() — PostgREST kimi
  const off = Math.max(0, parseInt(body.offset, 10) || 0);
  if (limit != null) sql += ` LIMIT ${Math.max(0, parseInt(limit, 10) || 0)}`;
  else if (off) sql += ' LIMIT 18446744073709551615';            // MySQL-də OFFSET yalnız LIMIT ilə
  if (off) sql += ` OFFSET ${off}`;
  const rows = (await q(sql, w.params, conn)).map(r => decode(info, table, r, cols));
  return shape(body, rows, count);
}

// ── yazma üçün doğrulama (NOT NULL + CHECK — Postgres məhdudiyyətləri) ──
function validateRow(table, row) {
  const def = SCHEMA[table];
  for (const c of def.columns) {
    if (!c.nullable && !c.identity && (row[c.name] === null || row[c.name] === undefined))
      throw apiError(400, '23502', `null value in column "${c.name}" of relation "${table}" violates not-null constraint`);
  }
  for (const ch of def.checks) {
    const v = row[ch.col];
    if (v === null || v === undefined) continue;          // Postgres: NULL CHECK-dən keçir
    let ok = true;
    if (ch.type === 'enum') ok = ch.values.includes(v);
    else if (ch.type === 'len') ok = [...String(v)].length >= ch.min && [...String(v)].length <= ch.max;
    else if (ch.type === 'regex') ok = (ch.allowEmpty && v === '') || new RegExp(ch.pattern).test(String(v));
    else if (ch.type === 'cmp') ok = ({ '>=': v >= ch.value, '<=': v <= ch.value, '=': v === ch.value, '>': v > ch.value, '<': v < ch.value })[ch.op];
    if (!ok) throw apiError(400, '23514', `new row for relation "${table}" violates check constraint`, `${ch.col}: ${JSON.stringify(v)}`);
  }
}

function assertWritableColumns(table, obj) {
  for (const k of Object.keys(obj)) {
    if (!colMap[table][k]) throw apiError(400, 'PGRST204', `Could not find the '${k}' column of '${table}' in the schema cache`);
  }
}

function mapMysqlError(e) {
  if (e.api) return e;
  const map = { 1062: [409, '23505', 'duplicate key value violates unique constraint'],
                1452: [409, '23503', 'insert or update on table violates foreign key constraint'],
                1451: [409, '23503', 'update or delete on table violates foreign key constraint'],
                1048: [400, '23502', 'null value violates not-null constraint'],
                3819: [400, '23514', 'new row violates check constraint'],
                4025: [400, '23514', 'new row violates check constraint'],
                1406: [400, '22001', 'value too long for type'] };
  const m = map[e.errno];
  return m ? apiError(m[0], m[1], m[2], e.sqlMessage) : e;
}

// Oxuma: yazılan sətirləri SELECT qaydası ilə geri qaytar (Postgres "return=representation")
async function readBack(ctx, table, pkRows, conn) {
  if (!pkRows.length) return [];
  const pk = SCHEMA[table].pk;
  const conds = pkRows.map(r => '(' + pk.map(k => `t.\`${k}\` = ?`).join(' AND ') + ')');
  const params = pkRows.flatMap(r => pk.map(k => encodeValue(colMap[table][k], r[k])));
  const pol = usingSql(table, 'select', ctx);
  const rows = await q(`SELECT * FROM \`${table}\` AS t WHERE (${conds.join(' OR ')}) AND ${pol.sql}`, [...params, ...pol.params], conn);
  if (rows.length < pkRows.length)
    throw apiError(403, '42501', `new row violates row-level security policy for table "${table}"`);
  return rows.map(r => decodeRow(table, r));
}

// ── INSERT ──────────────────────────────────────────────────────────────
async function doInsert(ctx, table, body) {
  if (VIEWS[table]) throw apiError(405, '42809', `cannot insert into view "${table}"`);
  const def = SCHEMA[table]; if (!def) throw apiError(404, '42P01', `relation "public.${table}" does not exist`);
  const input = Array.isArray(body.values) ? body.values : [body.values];
  if (!input.length) return { data: [], count: null };
  return tx(async conn => {
    const inserted = [];
    for (const raw of input) {
      if (!raw || typeof raw !== 'object') throw apiError(400, 'PGRST102', 'Yanlış məlumat');
      assertWritableColumns(table, raw);
      const row = {};
      for (const c of def.columns) {
        if (raw[c.name] !== undefined) row[c.name] = raw[c.name];
        else if (!c.identity && c.default) row[c.name] = decodeValue(c, defaultFor(c));
        else row[c.name] = c.identity ? undefined : null;
      }
      if (BEFORE_INSERT[table]) BEFORE_INSERT[table](ctx, row);
      validateRow(table, row);
      if (!checkRow(table, 'insert', ctx, row))
        throw apiError(403, '42501', `new row violates row-level security policy for table "${table}"`);
      const cols = def.columns.filter(c => row[c.name] !== undefined);
      const vals = cols.map(c => encodeValue(c, row[c.name]));
      let res;
      try {
        [res] = await conn.query(`INSERT INTO \`${table}\` (${cols.map(c => '`' + c.name + '`').join(', ')}) VALUES (${cols.map(() => '?').join(', ')})`, vals);
      } catch (e) { throw mapMysqlError(e); }
      const idCol = def.columns.find(c => c.identity);
      if (idCol && row[idCol.name] === undefined) row[idCol.name] = res.insertId;
      inserted.push(row);
    }
    if (!body.returning) return { data: null, count: null };
    const rows = await readBack(ctx, table, inserted, conn);
    return shape(body, rows, null);
  });
}

// ── UPDATE ──────────────────────────────────────────────────────────────
async function doUpdate(ctx, table, body) {
  if (VIEWS[table]) throw apiError(405, '42809', `cannot update view "${table}"`);
  const def = SCHEMA[table]; if (!def) throw apiError(404, '42P01', `relation "public.${table}" does not exist`);
  const patch = body.values || {};
  assertWritableColumns(table, patch);
  const info = tableInfo(table);
  return tx(async conn => {
    const w = joinWhere([...whereFor(info, table, body), usingSql(table, 'update', ctx)]);
    const olds = (await q(`SELECT * FROM \`${table}\` AS t WHERE ${w.sql} FOR UPDATE`, w.params, conn)).map(r => decodeRow(table, r));
    const now = new Date().toISOString().replace('Z', '+00:00');
    const changed = [];
    for (const old of olds) {
      const neu = { ...old, ...patch };
      if (BEFORE_UPDATE[table]) BEFORE_UPDATE[table](ctx, old, neu, now);
      validateRow(table, neu);
      if (!checkRow(table, 'update', ctx, neu))
        throw apiError(403, '42501', `new row violates row-level security policy for table "${table}"`);
      const cols = def.columns.filter(c => JSON.stringify(neu[c.name]) !== JSON.stringify(old[c.name]));
      if (cols.length) {
        const pkw = def.pk.map(k => `\`${k}\` = ?`).join(' AND ');
        try {
          await conn.query(`UPDATE \`${table}\` SET ${cols.map(c => '`' + c.name + '` = ?').join(', ')} WHERE ${pkw}`,
            [...cols.map(c => encodeValue(c, neu[c.name])), ...def.pk.map(k => encodeValue(colMap[table][k], old[k]))]);
        } catch (e) { throw mapMysqlError(e); }
      }
      changed.push(neu);
    }
    if (!body.returning) return { data: null, count: null };
    const rows = await readBack(ctx, table, changed, conn).catch(e => { if (e.code === '42501') return []; throw e; });
    return shape(body, rows, null);
  });
}

// ── DELETE ──────────────────────────────────────────────────────────────
async function doDelete(ctx, table, body) {
  if (VIEWS[table]) throw apiError(405, '42809', `cannot delete from view "${table}"`);
  const def = SCHEMA[table]; if (!def) throw apiError(404, '42P01', `relation "public.${table}" does not exist`);
  const info = tableInfo(table);
  return tx(async conn => {
    const w = joinWhere([...whereFor(info, table, body), usingSql(table, 'delete', ctx)]);
    const rows = (await q(`SELECT * FROM \`${table}\` AS t WHERE ${w.sql} FOR UPDATE`, w.params, conn)).map(r => decodeRow(table, r));
    if (rows.length) {
      const pkw = rows.map(() => '(' + def.pk.map(k => `\`${k}\` = ?`).join(' AND ') + ')').join(' OR ');
      try {
        await conn.query(`DELETE FROM \`${table}\` WHERE ${pkw}`, rows.flatMap(r => def.pk.map(k => encodeValue(colMap[table][k], r[k]))));
      } catch (e) { throw mapMysqlError(e); }
    }
    if (!body.returning) return { data: null, count: null };
    return shape(body, rows, null);
  });
}

async function handleQuery(ctx, body) {
  const table = String(body.table || '');
  if (!/^[a-z_][a-z0-9_]*$/.test(table)) throw apiError(400, '42P01', 'Yanlış cədvəl adı');
  switch (body.op) {
    case 'select': return doSelect(ctx, table, body);
    case 'insert': return doInsert(ctx, table, body);
    case 'update': return doUpdate(ctx, table, body);
    case 'delete': return doDelete(ctx, table, body);
    default: throw apiError(400, 'PGRST100', 'Naməlum əməliyyat');
  }
}

module.exports = { handleQuery, mapMysqlError, validateRow };
