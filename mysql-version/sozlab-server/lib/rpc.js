'use strict';
// ══════════════════════════════════════════════════════════════════════════
// Server funksiyaları (Supabase RPC) — PL/pgSQL mənbəsindən (pg/functions.sql)
// sətir-sətir köçürülüb. Hər funksiya tranzaksiyadadır; orijinaldakı
// "FOR UPDATE" kilidləri saxlanılıb ki, eyni anda gələn cavablarda xal itməsin.
//
// İki funksiya QƏSDƏN sərtləşdirilib (Supabase versiyasındakı boşluqlar):
//   • ss_award_points — şagird özünə limitsiz 205 Points yaza bilirdi.
//     İndi: heyət istənilən xalı verə bilər; şagird yalnız özünə, yalnız
//     "startap qurdum" (qurduğu hər startap üçün bir dəfə, ≤200) və
//     "olimpiada nəticəsi" (hər yarışa bir dəfə, nəticəsi yazılıbsa, ≤150).
//   • log_xp_gain — başqasının XP jurnalını dəyişmək olurdu; indi yalnız özününkü.
// ══════════════════════════════════════════════════════════════════════════
const { q, tx, apiError, decodeRow, isoFromMysql } = require('./db');
const { computeLevel, insertWithDefaults } = require('./auth');

const raise = msg => apiError(400, 'P0001', msg);
const todayUtc = () => new Date().toISOString().slice(0, 10);
const nowSql = 'UTC_TIMESTAMP(3)';
const one = async (sql, p, conn) => (await q(sql, p, conn))[0] || null;
const isSsStaff = r => ['admin', 'director', 'teacher', 'mentor'].includes(r);

async function me(ctx, conn, lock = false) {
  if (!ctx.uid) return null;
  return one(`SELECT id, username, display_name, role, class_grade, teacher_class, xp FROM profiles WHERE id = ?${lock ? ' FOR UPDATE' : ''}`, [ctx.uid], conn);
}
async function addXp(conn, username, n) {
  const r = await one('SELECT xp FROM profiles WHERE username = ? FOR UPDATE', [username], conn);
  if (!r) return null;
  const xp = r.xp + n;
  await q('UPDATE profiles SET xp = ?, level = ? WHERE username = ?', [xp, computeLevel(xp), username], conn);
  return xp;
}
async function logXp(conn, username, date, amount) {
  if (amount == null || amount <= 0) return;
  await q(`INSERT INTO xp_log (username, log_date, xp_gained) VALUES (?, ?, ?)
           ON DUPLICATE KEY UPDATE xp_gained = xp_gained + VALUES(xp_gained)`, [username, date, amount], conn);
}
const jsonArr = v => { const a = typeof v === 'string' ? JSON.parse(v) : v; return Array.isArray(a) ? a : null; };
async function uniqueCode(conn, table) {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  for (;;) {
    let code = ''; for (let i = 0; i < 6; i++) code += chars[require('crypto').randomInt(chars.length)];
    if (!(await one(`SELECT 1 AS x FROM \`${table}\` WHERE code = ?`, [code], conn))) return code;
  }
}
const row = (table, r) => (r ? decodeRow(table, r) : null);
const normClass = s => String(s || '').replace(/[^a-zA-Z0-9]/g, '').toUpperCase();

// ── funksiyalar ─────────────────────────────────────────────────────────
const RPC = {
  // ── ümumi ──
  async get_public_stats() {
    const u = await one('SELECT COUNT(*) AS n FROM profiles'), s = await one('SELECT COUNT(*) AS n FROM stories');
    return { users: Number(u.n), stories: Number(s.n) };
  },
  async is_username_taken(ctx, a) {
    return !!(await one('SELECT 1 AS x FROM profiles WHERE username = ?', [String(a.p_username || '').toLowerCase()]));
  },
  async log_xp_gain(ctx, a) {
    if (!ctx.uid || a.p_username !== ctx.username) throw raise('İcazə yoxdur');
    await logXp(null, a.p_username, String(a.p_date || todayUtc()).slice(0, 10), a.p_amount);
    return null;
  },
  async equip_cosmetic(ctx, a) {
    return tx(async c => {
      const p = await me(ctx, c); if (!p) throw raise('Profil tapılmadı');
      const cat = await one('SELECT * FROM cosmetics_catalog WHERE id = ?', [a.p_cosmetic_id], c);
      if (!cat) throw raise('Naməlum kosmetik element');
      if (p.xp < cat.min_xp) throw raise(`Bu elementi hələ açmamısınız (lazımi XP: ${cat.min_xp})`);
      await q(`UPDATE profiles SET ${cat.type === 'frame' ? 'equipped_frame' : 'equipped_theme'} = ? WHERE id = ?`, [a.p_cosmetic_id, ctx.uid], c);
      return null;
    });
  },
  async get_display_activity() {
    const duels = await q("SELECT p1_username, p2_username, p1_score, p2_score, winner_username FROM duels WHERE status = 'finished' ORDER BY created_at DESC LIMIT 8");
    const sess = await q("SELECT id, class_grade FROM live_quiz_sessions WHERE status = 'finished' ORDER BY created_at DESC LIMIT 5");
    const quizzes = [];
    for (const s of sess) {
      const top = await q('SELECT display_name, score FROM live_quiz_participants WHERE session_id = ? ORDER BY score DESC LIMIT 3', [s.id]);
      quizzes.push({ class: s.class_grade, top: top.map(t => ({ name: t.display_name, score: t.score })) });
    }
    return { duels: duels.map(d => ({ p1: d.p1_username, p2: d.p2_username, p1_score: d.p1_score, p2_score: d.p2_score, winner: d.winner_username })), quizzes };
  },

  // ── söz kəşf et ──
  async submit_word_definition(ctx, a) {
    return tx(async c => {
      const p = await me(ctx, c); if (!p) throw raise('Profil tapılmadı');
      if (p.role !== 'user') throw raise('Yalnız şagirdlər söz göndərə bilər');
      const word = String(a.p_word || '').trim(), def = String(a.p_definition || '').trim(), ex = String(a.p_example || '').trim();
      if (word === '' || [...word].length < 2) throw raise('Söz düzgün deyil');
      if (def === '' || [...def].length < 5) throw raise('Məna ən azı 5 hərf olmalıdır');
      if (def.toLowerCase() === word.toLowerCase()) throw raise('Məna sözün özü ola bilməz');
      if (await one('SELECT 1 AS x FROM word_submissions WHERE username = ? AND LOWER(word) = LOWER(?)', [p.username, word], c))
        throw raise('Bu sözü artıq göndərmisiniz');
      const { n } = await one('SELECT COUNT(*) AS n FROM word_submissions WHERE username = ? AND DATE(submitted_at) = UTC_DATE()', [p.username], c);
      if (n >= 100) throw raise('Bugünlük limitə çatdınız (100/100) — sabah davam edin');
      const flagged = isLowQuality(def);
      await insertWithDefaults(c, 'word_submissions', { username: p.username, display_name: p.display_name ?? p.username,
        word, definition: def, example: ex, status: flagged ? 'flagged' : 'pending', xp_awarded: !flagged });
      let xp;
      if (flagged) xp = p.xp;
      else { xp = await addXp(c, p.username, 1); await logXp(c, p.username, todayUtc(), 1); }
      return { today_count: Number(n) + 1, xp, flagged };
    });
  },
  async admin_review_word_submission(ctx, a) {
    return tx(async c => {
      const p = await me(ctx, c);
      if (!p || p.role !== 'admin') throw raise('Yalnız adminlər baxa bilər');
      const w = await one('SELECT * FROM word_submissions WHERE id = ? FOR UPDATE', [a.p_submission_id], c);
      if (!w) throw raise('Göndəriş tapılmadı');
      if (!['pending', 'flagged'].includes(w.status)) throw raise('Bu göndəriş artıq baxılıb');
      await q(`UPDATE word_submissions SET status = ?, reviewed_at = ${nowSql}, reviewed_by = ? WHERE id = ?`,
        [a.p_approve ? 'approved' : 'rejected', p.username, w.id], c);
      if (a.p_approve && !w.xp_awarded) {
        await addXp(c, w.username, 1);
        await q('UPDATE word_submissions SET xp_awarded = 1 WHERE id = ?', [w.id], c);
        await logXp(c, w.username, todayUtc(), 1);
      }
      if (a.p_approve) {
        await insertWithDefaults(c, 'community_words', { en: w.word, az: w.definition, ex: (w.example || '') !== '' ? w.example : w.word + '.',
          ex_az: w.example, tags: a.p_tags ?? null, difficulty: a.p_difficulty ?? null, added_by: w.username, source_submission_id: w.id });
      }
      return null;
    });
  },
  async admin_add_word_direct(ctx, a) {
    return tx(async c => {
      const p = await me(ctx, c);
      if (!p || p.role !== 'admin') throw raise('Yalnız adminlər söz əlavə edə bilər');
      const en = String(a.p_en || '').trim(), az = String(a.p_az || '').trim();
      if (en === '' || az === '') throw raise('Söz və məna mütləqdir');
      if (await one('SELECT 1 AS x FROM community_words WHERE LOWER(en) = LOWER(?)', [en], c)) throw raise('Bu söz artıq lüğətdədir');
      const ex = String(a.p_ex || '').trim();
      await insertWithDefaults(c, 'community_words', { en, az, ex: ex !== '' ? ex : en + '.', ex_az: String(a.p_ex_az || '').trim(),
        tags: a.p_tags ?? ['B2'], difficulty: a.p_difficulty ?? 2, added_by: p.username, source_submission_id: null });
      return null;
    });
  },
  async admin_export_community_words(ctx) {
    const p = await me(ctx); if (!p || p.role !== 'admin') throw raise('Yalnız adminlər ixrac edə bilər');
    const rows = await q('SELECT en, az, ex, ex_az, tags, difficulty FROM community_words ORDER BY added_at');
    return rows.map(r => ({ en: r.en, az: r.az, ex: r.ex, exAz: r.ex_az, tags: jsonArr(r.tags) ?? r.tags, difficulty: r.difficulty }));
  },
  async admin_export_backup(ctx) {
    const p = await me(ctx); if (!p || p.role !== 'admin') throw raise('Yalnız adminlər ehtiyat nüsxə ala bilər');
    const out = { exported_at: new Date().toISOString() };
    for (const t of ['profiles', 'stories', 'announcements', 'class_tasks', 'class_task_completions', 'duels', 'xp_log',
                     'live_quiz_sessions', 'live_quiz_participants', 'support_messages'])
      out[t] = (await q(`SELECT * FROM \`${t}\``)).map(r => decodeRow(t, r));
    return out;
  },

  // ── dəstək söhbəti ──
  async send_support_message(ctx, a) {
    return tx(async c => {
      const p = await me(ctx, c); if (!p) throw raise('Profil tapılmadı');
      const body = String(a.p_body ?? '').trim();
      if ([...body].length === 0 || [...body].length > 1000) throw raise('Mesaj boş və ya çox uzundur');
      if (p.role === 'admin' || p.role === 'director') {
        if (!(await one('SELECT 1 AS x FROM profiles WHERE username = ?', [a.p_username], c))) throw raise('İstifadəçi tapılmadı');
        await insertWithDefaults(c, 'support_messages', { username: a.p_username, sender_role: p.role, sender_name: p.username, body });
      } else if (p.role === 'teacher') {
        if (!(await one('SELECT 1 AS x FROM profiles WHERE username = ? AND class_grade = ?', [a.p_username, p.teacher_class], c)))
          throw raise('Bu şagird sizin sinfinizdə deyil');
        await insertWithDefaults(c, 'support_messages', { username: a.p_username, sender_role: 'teacher', sender_name: p.username, body });
      } else {
        await insertWithDefaults(c, 'support_messages', { username: p.username, sender_role: 'user', sender_name: p.username, body });
      }
      return null;
    });
  },
  async mark_support_read(ctx, a) {
    const p = await me(ctx); if (!p) return null;
    if (p.role === 'admin' || p.role === 'director' ||
        (p.role === 'teacher' && await one('SELECT 1 AS x FROM profiles WHERE username = ? AND class_grade = ?', [a.p_username, p.teacher_class])))
      await q("UPDATE support_messages SET `read` = 1 WHERE username = ? AND sender_role = 'user' AND `read` = 0", [a.p_username]);
    else if (p.username === a.p_username)
      await q("UPDATE support_messages SET `read` = 1 WHERE username = ? AND sender_role IN ('admin','director','teacher') AND `read` = 0", [a.p_username]);
    return null;
  },

  // ── duel ──
  async create_duel(ctx, a) {
    return tx(async c => {
      const p = await me(ctx, c); if (!p) throw raise('Profil tapılmadı');
      const opp = String(a.p_opponent_username || '').toLowerCase(), mode = a.p_mode || 'normal';
      if (opp === p.username) throw raise('Özünüzə duel göndərə bilməzsiniz');
      if (!(await one('SELECT 1 AS x FROM profiles WHERE username = ?', [opp], c))) throw raise('İstifadəçi tapılmadı');
      const qs = jsonArr(a.p_questions);
      if (!qs || qs.length < 1 || qs.length > 20) throw raise('Yanlış sual formatı');
      if (!['normal', 'sureli'].includes(mode)) throw raise('Yanlış rejim');
      const r = await insertWithDefaults(c, 'duels', { p1_username: p.username, p2_username: opp, questions: qs, status: 'pending', mode });
      return r.insertId;
    });
  },
  async respond_duel(ctx, a) {
    const p = await me(ctx); if (!p) return null;
    await q("UPDATE duels SET status = ? WHERE id = ? AND p2_username = ? AND status = 'pending'", [a.p_accept ? 'active' : 'declined', a.p_duel_id, p.username]);
    return null;
  },
  async cancel_duel(ctx, a) {
    const p = await me(ctx); if (!p) throw raise('Profil tapılmadı');
    await q("UPDATE duels SET status = 'cancelled' WHERE id = ? AND (p1_username = ? OR p2_username = ?) AND status IN ('pending','active')", [a.p_duel_id, p.username, p.username]);
    return null;
  },
  async submit_duel_answer(ctx, a) {
    return tx(async c => {
      const p = await me(ctx, c); if (!p) return null;
      let d = await one('SELECT * FROM duels WHERE id = ? FOR UPDATE', [a.p_duel_id], c);
      if (!d || d.status !== 'active') return null;
      let isP1; if (d.p1_username === p.username) isP1 = true; else if (d.p2_username === p.username) isP1 = false; else return null;
      const total = jsonArr(d.questions)?.length || 0;
      const k = isP1 ? 'p1' : 'p2';
      if (d[k + '_finished_at'] != null) return null;
      await q(`UPDATE duels SET ${k}_score = ${k}_score + ?, ${k}_progress = ${k}_progress + 1 WHERE id = ?`, [a.p_correct ? 1 : 0, d.id], c);
      d = await one('SELECT * FROM duels WHERE id = ? FOR UPDATE', [d.id], c);
      if (d[k + '_progress'] >= total && d[k + '_finished_at'] == null)
        await q(`UPDATE duels SET ${k}_finished_at = ${nowSql} WHERE id = ?`, [d.id], c);
      d = await one('SELECT * FROM duels WHERE id = ? FOR UPDATE', [d.id], c);
      if (d.p1_finished_at != null && d.p2_finished_at != null && d.status === 'active') {
        const winner = d.p1_score > d.p2_score ? d.p1_username : d.p2_score > d.p1_score ? d.p2_username : null;
        const [x1, x2] = winner == null ? [20, 20] : winner === d.p1_username ? [30, 10] : [10, 30];
        await addXp(c, d.p1_username, x1); await addXp(c, d.p2_username, x2);
        await logXp(c, d.p1_username, todayUtc(), x1); await logXp(c, d.p2_username, todayUtc(), x2);
        await q("UPDATE duels SET status = 'finished', winner_username = ?, xp_awarded = 1 WHERE id = ?", [winner, d.id], c);
      }
      return null;
    });
  },
  async finalize_duel(ctx, a) {
    return tx(async c => {
      const p = await me(ctx, c); if (!p) return null;
      let d = await one('SELECT * FROM duels WHERE id = ? FOR UPDATE', [a.p_duel_id], c);
      if (!d || d.status !== 'active') return null;
      if (d.p1_username !== p.username && d.p2_username !== p.username) return null;
      if (d.p1_finished_at == null) await q(`UPDATE duels SET p1_finished_at = ${nowSql} WHERE id = ?`, [d.id], c);
      if (d.p2_finished_at == null) await q(`UPDATE duels SET p2_finished_at = ${nowSql} WHERE id = ?`, [d.id], c);
      d = await one('SELECT * FROM duels WHERE id = ? FOR UPDATE', [d.id], c);
      const winner = d.p1_score > d.p2_score ? d.p1_username : d.p2_score > d.p1_score ? d.p2_username : null;
      const [x1, x2] = winner == null ? [20, 20] : winner === d.p1_username ? [30, 10] : [10, 30];
      await addXp(c, d.p1_username, x1); await addXp(c, d.p2_username, x2);
      await q(`UPDATE duels SET status = 'finished', winner_username = ?, finished_at = ${nowSql} WHERE id = ?`, [winner, d.id], c);
      return null;
    });
  },

  // ── canlı sinif yarışması ──
  async create_live_quiz(ctx, a) {
    return tx(async c => {
      const p = await me(ctx, c); if (!p) throw raise('Profil tapılmadı');
      if (p.role !== 'teacher' || !p.teacher_class) throw raise('Yalnız sinfi olan müəllimlər canlı yarışma başlada bilər');
      const qs = jsonArr(a.p_questions); if (!qs || qs.length < 1 || qs.length > 30) throw raise('Yanlış sual formatı');
      const code = await uniqueCode(c, 'live_quiz_sessions');
      const r = await insertWithDefaults(c, 'live_quiz_sessions', { code, teacher_username: p.username, class_grade: p.teacher_class, questions: qs, status: 'waiting', current_index: -1 });
      return row('live_quiz_sessions', await one('SELECT * FROM live_quiz_sessions WHERE id = ?', [r.insertId], c));
    });
  },
  async join_live_quiz(ctx, a) {
    return tx(async c => {
      const p = await me(ctx, c); if (!p) throw raise('Profil tapılmadı');
      if (p.role !== 'user') throw raise('Yalnız şagirdlər yarışmaya qoşula bilər');
      const s = await one('SELECT * FROM live_quiz_sessions WHERE UPPER(code) = UPPER(TRIM(?))', [a.p_code || ''], c);
      if (!s) throw raise('Kod tapılmadı — yenidən yoxlayın');
      if ((s.class_grade || '') !== '' && normClass(s.class_grade) !== normClass(p.class_grade))
        throw raise(`Bu yarışma ${s.class_grade} sinfi üçündür, sizin sinfiniz isə ${p.class_grade || 'təyin edilməyib'}`);
      if (s.status === 'finished') throw raise('Bu yarışma artıq bitib');
      await q('INSERT IGNORE INTO live_quiz_participants (session_id, username, display_name) VALUES (?, ?, ?)', [s.id, p.username, p.display_name ?? p.username], c);
      return row('live_quiz_sessions', s);
    });
  },
  async start_live_quiz_question(ctx, a) {
    return tx(async c => {
      const p = await me(ctx, c);
      const s = await one('SELECT * FROM live_quiz_sessions WHERE id = ? FOR UPDATE', [a.p_session_id], c);
      if (!s) throw raise('Sessiya tapılmadı');
      if (!p || s.teacher_username !== p.username) throw raise('Yalnız yarışmanı başladan müəllim idarə edə bilər');
      const next = s.current_index + 1, total = jsonArr(s.questions)?.length || 0;
      if (next >= total) await q("UPDATE live_quiz_sessions SET status = 'finished' WHERE id = ?", [s.id], c);
      else await q(`UPDATE live_quiz_sessions SET current_index = ?, status = 'question', question_started_at = ${nowSql} WHERE id = ?`, [next, s.id], c);
      return row('live_quiz_sessions', await one('SELECT * FROM live_quiz_sessions WHERE id = ?', [s.id], c));
    });
  },
  async submit_live_quiz_answer(ctx, a) {
    return tx(async c => {
      const p = await me(ctx, c); if (!p) throw raise('Profil tapılmadı');
      const s = await one('SELECT * FROM live_quiz_sessions WHERE id = ? FOR UPDATE', [a.p_session_id], c);
      if (!s) throw raise('Sessiya tapılmadı');
      if (s.status !== 'question' || s.current_index !== Number(a.p_question_index)) throw raise('Bu sual artıq bağlıdır');
      const part = await one('SELECT * FROM live_quiz_participants WHERE session_id = ? AND username = ? FOR UPDATE', [s.id, p.username], c);
      if (!part) throw raise('Bu yarışmaya qoşulmamısınız');
      if (part.last_answered_index >= Number(a.p_question_index)) throw raise('Bu suala artıq cavab vermisiniz');
      const question = (jsonArr(s.questions) || [])[Number(a.p_question_index)] || {};
      const correctAnswer = question.correct == null ? null : String(question.correct);
      const isCorrect = a.p_answer != null && correctAnswer != null && String(a.p_answer) === correctAnswer;
      const started = s.question_started_at ? new Date(isoFromMysql(s.question_started_at)).getTime() : Date.now();
      const elapsed = Math.max(0, Date.now() - started);
      const points = isCorrect ? Math.max(20, 100 - Math.floor(elapsed / 150)) : 0;
      await q('UPDATE live_quiz_participants SET last_answered_index = ?, last_correct = ?, last_points = ?, score = score + ? WHERE id = ?',
        [Number(a.p_question_index), isCorrect ? 1 : 0, points, points, part.id], c);
      if (points > 0) { await addXp(c, p.username, 2); await logXp(c, p.username, todayUtc(), 2); }
      return { correct: isCorrect, points, correctAnswer };
    });
  },
  async end_live_quiz(ctx, a) {
    const p = await me(ctx); if (!p) return null;
    await q("UPDATE live_quiz_sessions SET status = 'finished' WHERE id = ? AND teacher_username = ?", [a.p_session_id, p.username]);
    return null;
  },
  async award_live_quiz_podium(ctx, a) {
    return tx(async c => {
      const s = await one('SELECT * FROM live_quiz_sessions WHERE id = ? FOR UPDATE', [a.p_session_id], c);
      if (!s || s.status !== 'finished' || s.xp_awarded) return null;
      await q('UPDATE live_quiz_sessions SET xp_awarded = 1 WHERE id = ?', [s.id], c);
      const top = await q('SELECT username FROM live_quiz_participants WHERE session_id = ? ORDER BY score DESC, joined_at ASC LIMIT 3', [s.id], c);
      for (const [i, t] of top.entries()) { const b = [15, 10, 5][i]; await addXp(c, t.username, b); await logXp(c, t.username, todayUtc(), b); }
      return null;
    });
  },

  // ── sinif bossu ──
  async create_boss_session(ctx, a) {
    return tx(async c => {
      const p = await me(ctx, c); if (!p) throw raise('Profil tapılmadı');
      if (p.role !== 'teacher' || !p.teacher_class) throw raise('Yalnız sinfi olan müəllimlər Boss döyüşü başlada bilər');
      const qs = jsonArr(a.p_questions); if (!qs || qs.length < 1 || qs.length > 60) throw raise('Yanlış sual formatı');
      const hp = Math.max(20, Math.min(2000, a.p_boss_hp ?? 200)), dmg = Math.max(1, Math.min(100, a.p_damage_per_correct ?? 5));
      const code = await uniqueCode(c, 'class_boss_sessions');
      const name = String(a.p_boss_name ?? '').trim() || 'Söz Divi';
      const r = await insertWithDefaults(c, 'class_boss_sessions', { code, teacher_username: p.username, class_grade: p.teacher_class,
        boss_name: name, boss_max_hp: hp, boss_hp: hp, damage_per_correct: dmg, questions: qs, status: 'waiting', current_index: -1 });
      return row('class_boss_sessions', await one('SELECT * FROM class_boss_sessions WHERE id = ?', [r.insertId], c));
    });
  },
  async join_boss_session(ctx, a) {
    return tx(async c => {
      const p = await me(ctx, c); if (!p) throw raise('Profil tapılmadı');
      if (p.role !== 'user') throw raise('Yalnız şagirdlər Boss döyüşünə qoşula bilər');
      const s = await one('SELECT * FROM class_boss_sessions WHERE UPPER(code) = UPPER(TRIM(?))', [a.p_code || ''], c);
      if (!s) throw raise('Kod tapılmadı — yenidən yoxlayın');
      if (s.class_grade !== (p.class_grade || '')) throw raise('Bu döyüş sizin sinfiniz üçün deyil');
      if (s.status === 'finished') throw raise('Bu döyüş artıq bitib');
      await q('INSERT IGNORE INTO class_boss_participants (session_id, username, display_name) VALUES (?, ?, ?)', [s.id, p.username, p.display_name ?? p.username], c);
      return row('class_boss_sessions', s);
    });
  },
  async start_boss_question(ctx, a) {
    return tx(async c => {
      const p = await me(ctx, c);
      const s = await one('SELECT * FROM class_boss_sessions WHERE id = ? FOR UPDATE', [a.p_session_id], c);
      if (!s) throw raise('Sessiya tapılmadı');
      if (!p || s.teacher_username !== p.username) throw raise('Yalnız döyüşü başladan müəllim idarə edə bilər');
      const next = s.current_index + 1, total = jsonArr(s.questions)?.length || 0;
      if (s.defeated || s.boss_hp <= 0 || next >= total) await q("UPDATE class_boss_sessions SET status = 'finished' WHERE id = ?", [s.id], c);
      else await q(`UPDATE class_boss_sessions SET current_index = ?, status = 'question', question_started_at = ${nowSql} WHERE id = ?`, [next, s.id], c);
      return row('class_boss_sessions', await one('SELECT * FROM class_boss_sessions WHERE id = ?', [s.id], c));
    });
  },
  async submit_boss_answer(ctx, a) {
    return tx(async c => {
      const p = await me(ctx, c); if (!p) throw raise('Profil tapılmadı');
      const s = await one('SELECT * FROM class_boss_sessions WHERE id = ? FOR UPDATE', [a.p_session_id], c);
      if (!s) throw raise('Sessiya tapılmadı');
      const qi = Number(a.p_question_index);
      if (s.status !== 'question' || s.current_index !== qi) throw raise('Bu sual artıq bağlıdır');
      const part = await one('SELECT * FROM class_boss_participants WHERE session_id = ? AND username = ? FOR UPDATE', [s.id, p.username], c);
      if (!part) throw raise('Bu döyüşə qoşulmamısınız');
      if (part.last_answered_index >= qi) throw raise('Bu suala artıq cavab vermisiniz');
      const question = (jsonArr(s.questions) || [])[qi] || {};
      const correctAnswer = question.correct == null ? null : String(question.correct);
      const isCorrect = a.p_answer != null && correctAnswer != null && String(a.p_answer) === correctAnswer;
      await q('UPDATE class_boss_participants SET last_answered_index = ? WHERE id = ?', [qi, part.id], c);
      let dmg = 0, hp;
      if (isCorrect) {
        dmg = s.damage_per_correct;
        await q('UPDATE class_boss_participants SET damage_dealt = damage_dealt + ?, hits = hits + 1 WHERE id = ?', [dmg, part.id], c);
        hp = Math.max(0, s.boss_hp - dmg);
        await q('UPDATE class_boss_sessions SET boss_hp = ? WHERE id = ?', [hp, s.id], c);
        await addXp(c, p.username, 2); await logXp(c, p.username, todayUtc(), 2);
        if (hp <= 0) await q("UPDATE class_boss_sessions SET status = 'finished', defeated = 1 WHERE id = ?", [s.id], c);
      } else hp = s.boss_hp;
      return { correct: isCorrect, damage: dmg, bossHp: hp, correctAnswer };
    });
  },
  async end_boss_session(ctx, a) {
    const p = await me(ctx); if (!p) return null;
    await q("UPDATE class_boss_sessions SET status = 'finished' WHERE id = ? AND teacher_username = ?", [a.p_session_id, p.username]);
    return null;
  },
  async award_boss_damage_bonus(ctx, a) {
    return tx(async c => {
      const s = await one('SELECT * FROM class_boss_sessions WHERE id = ? FOR UPDATE', [a.p_session_id], c);
      if (!s || s.status !== 'finished' || s.xp_awarded) return null;
      await q('UPDATE class_boss_sessions SET xp_awarded = 1 WHERE id = ?', [s.id], c);
      if (!s.defeated) return null;
      const top = await q('SELECT username FROM class_boss_participants WHERE session_id = ? AND hits > 0 ORDER BY damage_dealt DESC, joined_at ASC LIMIT 3', [s.id], c);
      for (const [i, t] of top.entries()) { const b = [15, 10, 5][i]; await addXp(c, t.username, b); await logXp(c, t.username, todayUtc(), b); }
      return null;
    });
  },

  // ── 205 SMART SCHOOL ekosistemi ──
  async ss_award_points(ctx, a, internal) {
    return tx(async c => awardPoints(ctx, a, c, internal));
  },
  async ss_claim_reward(ctx, a) {
    return tx(async c => {
      const p = await me(ctx, c); if (!p) throw raise('Giriş tələb olunur');
      const r = await one('SELECT cost, name, active FROM ss_rewards WHERE id = ?', [a.p_reward_id], c);
      if (!r) throw raise('Mükafat tapılmadı');
      if (!r.active) throw raise('Bu mükafat artıq aktiv deyil');
      if (await one('SELECT 1 AS x FROM ss_reward_claims WHERE username = ? AND reward_id = ?', [p.username, a.p_reward_id], c)) throw raise('Bu mükafatı artıq almısan');
      await awardPoints(ctx, { p_username: p.username, p_amount: -r.cost, p_reason: 'Mükafat: ' + r.name, p_source: 'reward', p_ref_id: a.p_reward_id }, c, true);
      await insertWithDefaults(c, 'ss_reward_claims', { username: p.username, reward_id: a.p_reward_id });
      await insertWithDefaults(c, 'ss_achievements', { username: p.username, code: 'reward_' + a.p_reward_id, title: r.name, detail: 'Mükafat mağazasından alındı', icon: '🎁', module: 'bank', ref_id: a.p_reward_id });
      return r.name;
    });
  },
  async ss_vote_startup(ctx, a) {
    return tx(async c => {
      const p = await me(ctx, c); if (!p) throw raise('Giriş tələb olunur');
      await q('INSERT IGNORE INTO ss_startup_votes (startup_id, username) VALUES (?, ?)', [a.p_startup_id, p.username], c);
      const { n } = await one('SELECT COUNT(*) AS n FROM ss_startup_votes WHERE startup_id = ?', [a.p_startup_id], c);
      await q('UPDATE ss_startups SET votes = ? WHERE id = ?', [n, a.p_startup_id], c);
      return Number(n);
    });
  },
  async ss_mark_problem_solved(ctx, a) {
    return tx(async c => {
      const p = await me(ctx, c); if (!p || !isSsStaff(p.role)) throw raise('İcazə yoxdur');
      const prob = await one('SELECT title, points, solved_by FROM ss_problems WHERE id = ? FOR UPDATE', [a.p_problem_id], c);
      const sol = await one('SELECT author, team_id FROM ss_solutions WHERE id = ?', [a.p_solution_id], c);
      if (!sol || !sol.author) throw raise('Həll tapılmadı');
      await q("UPDATE ss_solutions SET status = 'implemented', stage = 'implemented' WHERE id = ?", [a.p_solution_id], c);
      const solved = [...new Set([...(jsonArr(prob?.solved_by) || []), sol.author])];
      await q(`UPDATE ss_problems SET status = 'solved', solved_at = ${nowSql}, solved_by = ? WHERE id = ?`, [JSON.stringify(solved), a.p_problem_id], c);
      const team = sol.team_id ? await one('SELECT members FROM ss_teams WHERE id = ?', [sol.team_id], c) : null;
      const members = [sol.author, ...(jsonArr(team?.members) || [])];
      for (const m of members) {
        if (!m) continue;
        await awardPoints(ctx, { p_username: m, p_amount: prob?.points ?? 75, p_reason: 'Problem həll edildi: ' + (prob?.title ?? ''), p_source: 'problem', p_ref_id: a.p_problem_id }, c, true);
        await insertWithDefaults(c, 'ss_achievements', { username: m, code: 'problem_solved', title: 'Problem Solved by 205 Students', detail: prob?.title ?? '', icon: '🧩', module: 'problem', ref_id: a.p_problem_id });
      }
      return null;
    });
  },
  async ss_my_summary(ctx) {
    const p = await me(ctx); if (!p) return {};
    const u = p.username, n = async (sql, prm = [u]) => Number((await one(sql, prm)).n || 0);
    const balance = await n('SELECT COALESCE(SUM(amount),0) AS n FROM ss_points_ledger WHERE username = ?');
    return {
      username: u, balance,
      earned: await n('SELECT COALESCE(SUM(amount),0) AS n FROM ss_points_ledger WHERE username = ? AND amount > 0'),
      spent: await n('SELECT COALESCE(-SUM(amount),0) AS n FROM ss_points_ledger WHERE username = ? AND amount < 0'),
      achievements: await n('SELECT COUNT(*) AS n FROM ss_achievements WHERE username = ?'),
      startups: await n('SELECT COUNT(*) AS n FROM ss_startups WHERE founder = ?'),
      solutions: await n('SELECT COUNT(*) AS n FROM ss_solutions WHERE author = ?'),
      humanity: await n('SELECT COUNT(*) AS n FROM ss_humanity_projects WHERE author = ?'),
      humanity_points: await n('SELECT COALESCE(SUM(impact_points),0) AS n FROM ss_humanity_projects WHERE author = ?'),
      submissions: await n('SELECT COUNT(*) AS n FROM ss_submissions WHERE author = ?'),
      olympics: await n('SELECT COUNT(*) AS n FROM ss_olympics_results WHERE username = ?'),
      medals: await n('SELECT COUNT(*) AS n FROM ss_olympics_results WHERE username = ? AND medal IS NOT NULL'),
      teams: await n('SELECT COUNT(*) AS n FROM ss_teams WHERE owner = ? OR JSON_CONTAINS(members, JSON_QUOTE(?))', [u, u]),
      rank: 1 + await n('SELECT COUNT(*) AS n FROM (SELECT username, SUM(amount) AS b FROM ss_points_ledger GROUP BY username) w WHERE w.b > ?', [balance]),
    };
  },
  async ss_school_analytics(ctx) {
    const p = await me(ctx); if (!p || !isSsStaff(p.role)) throw raise('İcazə yoxdur');
    const n = async sql => Number((await one(sql)).n || 0);
    const obj = rows => Object.fromEntries(rows.map(r => [r.k, Number(r.n)]));
    return {
      students: await n("SELECT COUNT(*) AS n FROM profiles WHERE role = 'user'"),
      active_students: await n(`SELECT COUNT(DISTINCT l.username) AS n FROM ss_points_ledger l JOIN profiles p ON p.username = l.username AND p.role = 'user'
                                WHERE l.created_at > UTC_TIMESTAMP(3) - INTERVAL 30 DAY`),
      startups: await n('SELECT COUNT(*) AS n FROM ss_startups'),
      startups_by_stage: obj(await q('SELECT stage AS k, COUNT(*) AS n FROM ss_startups GROUP BY stage')),
      problems: await n('SELECT COUNT(*) AS n FROM ss_problems'),
      problems_solved: await n("SELECT COUNT(*) AS n FROM ss_problems WHERE status IN ('solved','implemented')"),
      solutions: await n('SELECT COUNT(*) AS n FROM ss_solutions'),
      challenges: await n('SELECT COUNT(*) AS n FROM ss_challenges'),
      submissions: await n('SELECT COUNT(*) AS n FROM ss_submissions'),
      humanity: await n('SELECT COUNT(*) AS n FROM ss_humanity_projects'),
      connections: await n("SELECT COUNT(*) AS n FROM ss_schools WHERE status = 'connected' AND NOT is_home"),
      olympics_events: await n('SELECT COUNT(*) AS n FROM ss_olympics_events'),
      olympics_participants: await n('SELECT COUNT(DISTINCT username) AS n FROM ss_olympics_results'),
      points_total: await n('SELECT COALESCE(SUM(amount),0) AS n FROM ss_points_ledger WHERE amount > 0'),
      teams: await n('SELECT COUNT(*) AS n FROM ss_teams'),
      by_category: obj(await q('SELECT category AS k, COUNT(*) AS n FROM ss_problems GROUP BY category')),
      monthly: (await q(`SELECT DATE_FORMAT(created_at, '%Y-%m') AS ym, COUNT(*) AS n FROM ss_points_ledger
                         WHERE created_at > UTC_TIMESTAMP(3) - INTERVAL 6 MONTH GROUP BY ym ORDER BY ym`)).map(r => ({ ym: r.ym, n: Number(r.n) })),
    };
  },
};

// ss_award_points — sərtləşdirilmiş versiya (yuxarıdakı izaha bax)
async function awardPoints(ctx, a, c, internal) {
  const username = a.p_username, amount = Number(a.p_amount), source = a.p_source || 'system';
  if (!username) return 0;
  if (!amount) return 0;
  if (!internal) {
    const p = await me(ctx, c);
    if (!p) throw raise('İcazə yoxdur');
    if (!isSsStaff(p.role)) {
      // Şagird: yalnız özünə, yalnız saytın özünün verdiyi iki hadisə üçün
      if (username !== p.username || amount < 0) throw raise('İcazə yoxdur');
      if (source === 'startup') {
        if (amount > 200) throw raise('İcazə yoxdur');
        const { founded } = await one('SELECT COUNT(*) AS founded FROM ss_startups WHERE founder = ?', [p.username], c);
        const { claimed } = await one("SELECT COUNT(*) AS claimed FROM ss_points_ledger WHERE username = ? AND source = 'startup' AND reason LIKE 'Startap quruldu:%'", [p.username], c);
        if (Number(claimed) >= Number(founded) || !String(a.p_reason || '').startsWith('Startap quruldu:')) throw raise('İcazə yoxdur');
      } else if (source === 'olympics') {
        if (amount > 150 || !a.p_ref_id) throw raise('İcazə yoxdur');
        if (!(await one('SELECT 1 AS x FROM ss_olympics_results WHERE username = ? AND event_id = ?', [p.username, a.p_ref_id], c))) throw raise('İcazə yoxdur');
        if (await one("SELECT 1 AS x FROM ss_points_ledger WHERE username = ? AND source = 'olympics' AND ref_id = ?", [p.username, a.p_ref_id], c)) return balanceOf(c, username);
      } else throw raise('İcazə yoxdur');
    }
  }
  if (amount < 0) {
    const b = await balanceOf(c, username, true);
    if (b + amount < 0) throw raise('205 Points kifayət etmir');
  }
  if (source === 'admin' && !isSsStaff(ctx.role)) throw raise('İcazə yoxdur');
  await insertWithDefaults(c, 'ss_points_ledger', { username, amount, reason: a.p_reason ?? '', source, ref_id: a.p_ref_id ?? null });
  return balanceOf(c, username);
}
async function balanceOf(c, username, lock) {
  if (lock) await q('SELECT id FROM ss_points_ledger WHERE username = ? FOR UPDATE', [username], c);
  return Number((await one('SELECT COALESCE(SUM(amount),0) AS n FROM ss_points_ledger WHERE username = ?', [username], c)).n);
}

// is_low_quality_definition — Postgres regex-lərinin eynisi
function isLowQuality(pDef) {
  const d = String(pDef || '').trim().toLowerCase();
  if (/(.)\1{3,}/u.test(d)) return true;
  if (/(asdf|asdas|qwer|zxcv|qwerty|jkl;|hjkl|lkjh)/.test(d)) return true;
  if (!/[aeəiıoöuü]/.test(d)) return true;
  const letters = d.replace(/[^a-zəiıöüşçğ]/gi, '');
  if ([...letters].length >= 6 && new Set([...letters]).size < 4) return true;
  const tokens = d.replace(/[^\p{L}\p{N}əiıöüşçğ]/giu, ' ').trim().split(/\s+/).filter(Boolean);
  if (tokens.length < 2) return true;
  return false;
}

async function handleRpc(ctx, name, args) {
  const fn = Object.prototype.hasOwnProperty.call(RPC, name) ? RPC[name] : null;
  if (!fn) throw apiError(404, 'PGRST202', `Could not find the function public.${name} in the schema cache`);
  return fn(ctx, args || {});
}

module.exports = { handleRpc, RPC, isLowQuality };
