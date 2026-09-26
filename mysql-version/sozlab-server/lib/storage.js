'use strict';
// ══════════════════════════════════════════════════════════════════════════
// Fayl yükləmə (Supabase Storage-in əvəzi). Fayllar hostinqdə uploads/
// qovluğunda saxlanılır, siyahısı isə storage_objects cədvəlindədir.
//
// Qaydalar (Supabase siyasətlərindən köçürülüb, bir az sərtləşdirilib):
//   lesson-images  — yalnız müəllim, yalnız öz "<username>/" qovluğuna yükləyir
//                    və yalnız oradan silir.
//   school-uploads — şagird yalnız öz "<user id>/" qovluğuna; məktəb heyəti
//                    (admin/direktor/müəllim) istənilən yerə (məs. "content/").
//                    Silmək: faylın sahibi və ya məktəb heyəti.
//   Hamısı üçün: yalnız şəkil (PNG/JPEG/GIF/WEBP — faylın öz baytlarına baxılır,
//   uzantıya yox), ölçü limiti: dərs şəkli 8 MB, məktəb yükləməsi 5 MB (Supabase-dəki kimi). SVG/HTML qəbul edilmir (XSS riski).
// ══════════════════════════════════════════════════════════════════════════
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { config } = require('./config');
const { q, apiError } = require('./db');

const BUCKETS = {
  'lesson-images': {
    maxBytes: 8 * 1024 * 1024,
    canInsert: (ctx, name) => ctx.role === 'teacher' && firstFolder(name) === ctx.username,
    canDelete: (ctx, name) => firstFolder(name) === ctx.username,
  },
  'school-uploads': {
    maxBytes: 5 * 1024 * 1024,
    canInsert: (ctx, name) => isSchoolStaff(ctx) || firstFolder(name) === ctx.uid,
    canDelete: (ctx, name, obj) => isSchoolStaff(ctx) || (obj && obj.owner === ctx.uid),
  },
};
const isSchoolStaff = c => ['admin', 'director', 'teacher'].includes(c.role);
const firstFolder = name => (name.includes('/') ? name.split('/')[0] : null);

function cleanName(name) {
  const n = String(name || '').replace(/^\/+/, '');
  if (!n || n.length > 180) throw apiError(400, 'InvalidKey', 'Yanlış fayl adı');
  const parts = n.split('/');
  if (parts.length > 4 || parts.some(p => !/^[\w.\-]+$/.test(p) || p === '.' || p === '..'))
    throw apiError(400, 'InvalidKey', 'Yanlış fayl adı');
  return n;
}
function bucketOf(id) {
  if (!Object.prototype.hasOwnProperty.call(BUCKETS, id)) throw apiError(404, 'Bucket not found', 'Bucket not found');
  return BUCKETS[id];
}
const diskPath = (bucket, name) => path.join(config.uploadDir, bucket, ...name.split('/'));

function sniffImage(b) {
  if (b.length >= 8 && b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) return 'image/png';
  if (b.length >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return 'image/jpeg';
  if (b.length >= 6 && b.slice(0, 6).toString('latin1').match(/^GIF8[79]a$/)) return 'image/gif';
  if (b.length >= 12 && b.slice(0, 4).toString('latin1') === 'RIFF' && b.slice(8, 12).toString('latin1') === 'WEBP') return 'image/webp';
  return null;
}

async function upload(ctx, bucketId, rawName, buf) {
  if (!ctx.uid) throw apiError(401, 'Unauthorized', 'Giriş tələb olunur');
  const b = bucketOf(bucketId), name = cleanName(rawName);
  if (!b.canInsert(ctx, name)) throw apiError(403, 'Unauthorized', 'new row violates row-level security policy');
  if (!buf || !buf.length) throw apiError(400, 'InvalidRequest', 'Fayl boşdur');
  if (buf.length > Math.min(b.maxBytes, config.maxUploadBytes)) throw apiError(413, 'Payload too large', `Fayl çox böyükdür (maks. ${Math.round(Math.min(b.maxBytes, config.maxUploadBytes) / 1048576)} MB)`);
  const mime = sniffImage(buf);
  if (!mime) throw apiError(415, 'invalid_mime_type', 'Yalnız şəkil faylları (PNG, JPG, GIF, WEBP) qəbul olunur');
  const file = diskPath(bucketId, name);
  try {
    await q('INSERT INTO storage_objects (id, bucket_id, name, owner, mime, size) VALUES (?, ?, ?, ?, ?, ?)',
      [crypto.randomUUID(), bucketId, name, ctx.uid, mime, buf.length]);
  } catch (e) {
    if (e.errno === 1062) throw apiError(409, 'Duplicate', 'The resource already exists');
    throw e;
  }
  try {
    await fs.promises.mkdir(path.dirname(file), { recursive: true });
    await fs.promises.writeFile(file, buf, { flag: 'wx' });
  } catch (e) {
    await q('DELETE FROM storage_objects WHERE bucket_id = ? AND name = ?', [bucketId, name]);
    throw apiError(500, 'StorageError', 'Faylı yadda saxlamaq alınmadı: ' + e.code);
  }
  return { path: name, id: name, fullPath: bucketId + '/' + name, Key: bucketId + '/' + name };
}

async function remove(ctx, bucketId, names) {
  if (!ctx.uid) throw apiError(401, 'Unauthorized', 'Giriş tələb olunur');
  const b = bucketOf(bucketId), out = [];
  for (const raw of (Array.isArray(names) ? names : []).slice(0, 100)) {
    let name; try { name = cleanName(raw); } catch (_) { continue; }
    const obj = (await q('SELECT * FROM storage_objects WHERE bucket_id = ? AND name = ?', [bucketId, name]))[0];
    if (!obj || !b.canDelete(ctx, name, obj)) continue;       // Supabase kimi: icazəsiz fayl səssizcə ötürülür
    await q('DELETE FROM storage_objects WHERE id = ?', [obj.id]);
    await fs.promises.unlink(diskPath(bucketId, name)).catch(() => {});
    out.push({ name, bucket_id: bucketId });
  }
  return out;
}

// GET /storage/v1/object/public/<bucket>/<name> — hamıya açıq (Supabase-də də public idi)
async function serve(res, bucketId, rawName) {
  let name;
  try { bucketOf(bucketId); name = cleanName(decodeURIComponent(rawName)); } catch (_) { res.writeHead(404); return res.end(); }
  const obj = (await q('SELECT mime, size FROM storage_objects WHERE bucket_id = ? AND name = ?', [bucketId, name]))[0];
  if (!obj) { res.writeHead(404, { 'Content-Type': 'text/plain' }); return res.end('Not found'); }
  const file = diskPath(bucketId, name);
  fs.stat(file, (err, st) => {
    if (err) { res.writeHead(404); return res.end(); }
    res.writeHead(200, {
      'Content-Type': obj.mime, 'Content-Length': st.size,
      'Cache-Control': 'public, max-age=31536000, immutable',
      'X-Content-Type-Options': 'nosniff',
      'Content-Security-Policy': "default-src 'none'; sandbox",
    });
    fs.createReadStream(file).pipe(res);
  });
}

module.exports = { upload, remove, serve, sniffImage, cleanName };
