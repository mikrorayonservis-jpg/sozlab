'use strict';
// ══════════════════════════════════════════════════════════════════════════
// SƏTİR SƏVİYYƏSİNDƏ TƏHLÜKƏSİZLİK (Supabase RLS-in MySQL üçün əvəzi)
//
// Supabase-də 93 RLS qaydası bazanın özündə idi. MySQL-də RLS yoxdur, ona görə
// hər qayda burada yenidən yazılıb — PostgreSQL mətni (pg/policies.json) ilə
// sətir-sətir uyğunlaşdırılaraq.
//
// Hər qayda KİÇİK İFADƏ DİLİ ilə BİR DƏFƏ yazılır və iki formaya çevrilir:
//   .sql(ctx)       → WHERE üçün SQL parçası (hansı sətirləri görə/dəyişə bilərsən)
//   .test(ctx,row)  → yeni sətrin yoxlanması (INSERT/UPDATE "WITH CHECK")
// Beləcə "görmə" və "yazma" qaydaları heç vaxt bir-birindən ayrıla bilməz.
//
// ctx = { uid, username, role, classGrade, teacherClass }  (qonaq: uid=null, role='anon')
// Eyni əmr üçün bir neçə qayda varsa, Postgres kimi OR ilə birləşir.
// Qaydası olmayan əmr QADAĞANDIR (məs. xal dəftərinə birbaşa yazmaq).
// ══════════════════════════════════════════════════════════════════════════

const S = (sql, params = []) => ({ sql, params });

// ── ifadə dili ──────────────────────────────────────────────────────────
const node = (sqlFn, testFn) => ({ sql: sqlFn, test: testFn });
const TRUE = node(() => S('1=1'), () => true);
const FALSE = node(() => S('1=0'), () => false);
// kontekstdən asılı sabit (məs. "admindir")
const when = pred => node(c => S(pred(c) ? '1=1' : '1=0'), c => !!pred(c));
// t.col = <kontekst dəyəri>   (dəyər null/boşdursa — false, SQL-dəki NULL kimi)
const colEqCtx = (col, get) => node(
  c => { const v = get(c); return v == null ? S('1=0') : S(`t.\`${col}\` = ?`, [v]); },
  (c, r) => { const v = get(c); return v != null && r[col] === v; });
const colEq = (col, lit) => node(() => S(`t.\`${col}\` = ?`, [lit]), (c, r) => r[col] === lit);
const colNe = (col, lit) => node(() => S(`t.\`${col}\` <> ?`, [lit]), (c, r) => r[col] != null && r[col] !== lit);
const colTrue = col => node(() => S(`t.\`${col}\` = 1`), (c, r) => r[col] === true || r[col] === 1);
// is_teacher_of(auth.uid(), t.col): müəllimin öz sinfi, boş sinif heç vaxt uyğun deyil
const teacherOfCol = col => node(
  c => (c.role === 'teacher' && c.teacherClass) ? S(`t.\`${col}\` = ?`, [c.teacherClass]) : S('1=0'),
  (c, r) => c.role === 'teacher' && !!c.teacherClass && r[col] === c.teacherClass);
// yalnız SELECT-də işlənən alt sorğular (başqa cədvələ baxır)
const sqlOnly = fn => node(fn, () => { throw new Error('bu qayda yalnız oxuma üçündür'); });
const or = (...xs) => node(
  c => { const p = xs.map(x => x.sql(c)); return S('(' + p.map(x => x.sql).join(' OR ') + ')', p.flatMap(x => x.params)); },
  (c, r) => xs.some(x => x.test(c, r)));
const and = (...xs) => node(
  c => { const p = xs.map(x => x.sql(c)); return S('(' + p.map(x => x.sql).join(' AND ') + ')', p.flatMap(x => x.params)); },
  (c, r) => xs.every(x => x.test(c, r)));

// ── rollar (Postgres köməkçi funksiyalarının eyni tərifi) ───────────────
const isAdmin = c => c.role === 'admin';                                        // is_admin()
const isDirector = c => c.role === 'director';                                  // is_director()
const isSchoolStaff = c => ['admin', 'director', 'teacher'].includes(c.role);   // is_school_staff()
const isSsStaff = c => ['admin', 'director', 'teacher', 'mentor'].includes(c.role); // ss_is_staff() = ss_is_mentor()
const ADMIN = when(isAdmin), DIRECTOR = when(isDirector);
const SCHOOL_STAFF = when(isSchoolStaff), SS_STAFF = when(isSsStaff);
const ME_UID = col => colEqCtx(col, c => c.uid);                // col = auth.uid()
const ME_USER = col => colEqCtx(col, c => c.username);          // EXISTS(profiles p WHERE p.id=auth.uid() AND p.username=t.col)
const MY_CLASS = col => node(                                    // p.class_grade = t.col AND p.class_grade <> ''
  c => c.classGrade ? S(`t.\`${col}\` = ?`, [c.classGrade]) : S('1=0'),
  (c, r) => !!c.classGrade && r[col] === c.classGrade);

const ANY = ['anon', 'authenticated'], AUTH = ['authenticated'];
const p = (roles, using, check) => ({ roles, using, check });   // check yoxdursa UPDATE-də using işləyir

// ── cədvəllər ───────────────────────────────────────────────────────────
// Açarlar: select / insert / update / delete / all (all = hər əmr)
const POLICIES = {
  announcements: {
    select: [p(ANY, TRUE)],
    insert: [p(AUTH, null, or(ADMIN, DIRECTOR))],
    update: [p(AUTH, or(ADMIN, DIRECTOR))],
    delete: [p(AUTH, or(ADMIN, DIRECTOR))],
  },
  class_boss_participants: {
    select: [p(AUTH, or(ADMIN, DIRECTOR, sqlOnly(c => S(
      'EXISTS (SELECT 1 FROM `class_boss_sessions` s WHERE s.id = t.session_id AND (s.teacher_username = ? OR (? <> \'\' AND s.class_grade = ?)))',
      [c.username, c.classGrade || '', c.classGrade || '']))))],
  },
  class_boss_sessions: {
    select: [p(AUTH, or(ADMIN, DIRECTOR, ME_USER('teacher_username'), MY_CLASS('class_grade')))],
  },
  class_task_completions: {
    insert: [p(AUTH, null, ME_USER('username'))],
    select: [p(AUTH, or(ADMIN, DIRECTOR, ME_USER('username'), sqlOnly(c =>
      (c.role === 'teacher' && c.teacherClass)
        ? S('EXISTS (SELECT 1 FROM `class_tasks` k WHERE k.id = t.task_id AND k.class_grade = ?)', [c.teacherClass])
        : S('1=0'))))],
  },
  class_tasks: {
    delete: [p(AUTH, or(ADMIN, DIRECTOR, teacherOfCol('class_grade')))],
    insert: [p(AUTH, null, or(ADMIN, DIRECTOR, teacherOfCol('class_grade')))],
    select: [p(AUTH, or(ADMIN, DIRECTOR, teacherOfCol('class_grade'), colEqCtx('class_grade', c => c.uid ? c.classGrade : null)))],
  },
  community_words: { select: [p(AUTH, TRUE)] },
  cosmetics_catalog: { select: [p(ANY, TRUE)] },
  duels: {
    select: [p(AUTH, or(ME_USER('p1_username'), ME_USER('p2_username'), ADMIN, DIRECTOR))],
  },
  live_quiz_participants: {
    select: [p(AUTH, or(ADMIN, DIRECTOR, sqlOnly(c => S(
      'EXISTS (SELECT 1 FROM `live_quiz_sessions` s WHERE s.id = t.session_id AND (s.teacher_username = ? OR (? <> \'\' AND s.class_grade = ?)))',
      [c.username, c.classGrade || '', c.classGrade || '']))))],
  },
  live_quiz_sessions: {
    select: [p(AUTH, or(ADMIN, DIRECTOR, ME_USER('teacher_username'), MY_CLASS('class_grade')))],
  },
  newsletter_signups: {
    insert: [p(ANY, null, node(() => S('1=0'), (c, r) =>
      typeof r.email === 'string' && /^[^@\s]+@[^@\s]+\.[^@\s]+$/i.test(r.email) && r.email.length < 200))],
    select: [p(AUTH, ADMIN)],
  },
  profiles: {
    delete: [p(AUTH, or(ME_UID('id'), ADMIN, and(DIRECTOR, colNe('role', 'admin'))))],
    select: [p(AUTH, or(ME_UID('id'), ADMIN, DIRECTOR, and(colNe('class_grade', ''), teacherOfCol('class_grade'))))],
    update: [p(AUTH, or(ME_UID('id'), ADMIN, and(DIRECTOR, colNe('role', 'admin'))),
                      or(ME_UID('id'), ADMIN, and(DIRECTOR, colNe('role', 'admin'))))],
  },
  school_achievements: staffWrites({ select: [p(ANY, TRUE)] }),
  school_events: staffWrites({ select: [p(ANY, TRUE)] }),
  school_teachers: staffWrites({ select: [p(ANY, TRUE)] }),
  school_info: {
    select: [p(ANY, TRUE)],
    update: [p(AUTH, SCHOOL_STAFF, SCHOOL_STAFF)],
  },
  school_news: staffWrites({ select: [p(ANY, or(colTrue('published'), SCHOOL_STAFF))] }),
  school_submissions: {
    delete: [p(AUTH, or(and(ME_UID('student_id'), colEq('status', 'pending')), SCHOOL_STAFF))],
    insert: [p(AUTH, null, ME_UID('student_id'))],
    select: [p(ANY, or(colEq('status', 'approved'), ME_UID('student_id'), SCHOOL_STAFF))],
    update: [p(AUTH, or(and(ME_UID('student_id'), colEq('status', 'pending')), SCHOOL_STAFF),
                      or(ME_UID('student_id'), SCHOOL_STAFF))],
  },
  ss_achievements: ssStaffAll(), ss_challenges: ssStaffAll(), ss_hall_of_fame: ssStaffAll(),
  ss_olympics_events: ssStaffAll(), ss_problems: ssStaffAll(), ss_rewards: ssStaffAll(), ss_schools: ssStaffAll(),
  ss_humanity_projects: ownerOrStaffAll('author'),
  ss_solutions: ownerOrStaffAll('author'),
  ss_submissions: ownerOrStaffAll('author'),
  ss_startups: ownerOrStaffAll('founder'),
  ss_teams: ownerOrStaffAll('owner'),
  ss_mentor_feedback: { select: [p(ANY, TRUE)], all: [p(AUTH, SS_STAFF, SS_STAFF)] },
  ss_olympics_results: {
    insert: [p(AUTH, null, ME_USER('username'))],
    select: [p(ANY, TRUE)],
    update: [p(AUTH, or(ME_USER('username'), SS_STAFF))],
  },
  // Xal dəftəri və mükafat alışları: YALNIZ oxumaq. Yazmaq yalnız server
  // funksiyaları (ss_award_points, ss_claim_reward ...) ilə mümkündür.
  ss_points_ledger: { select: [p(ANY, TRUE)] },
  ss_reward_claims: { select: [p(ANY, TRUE)] },
  ss_startup_votes: {
    insert: [p(AUTH, null, ME_USER('username'))],
    select: [p(ANY, TRUE)],
  },
  stories: {
    delete: [p(AUTH, or(ME_UID('user_id'), ADMIN, DIRECTOR))],
    insert: [p(AUTH, null, ME_UID('user_id'))],
    select: [p(AUTH, TRUE)],
    update: [p(AUTH, or(ME_UID('user_id'), ADMIN, DIRECTOR))],
  },
  support_messages: {
    select: [p(AUTH, or(ME_USER('username'), ADMIN, DIRECTOR, sqlOnly(c =>
      (c.role === 'teacher' && c.teacherClass)
        ? S('EXISTS (SELECT 1 FROM `profiles` pp WHERE pp.username = t.username AND pp.class_grade <> \'\' AND pp.class_grade = ?)', [c.teacherClass])
        : S('1=0'))))],
  },
  teacher_lessons: {
    delete: [p(AUTH, ME_USER('teacher_username'))],
    insert: [p(AUTH, null, and(ME_USER('teacher_username'), when(c => c.role === 'teacher')))],
    select: [p(AUTH, ME_USER('teacher_username'))],
    update: [p(AUTH, ME_USER('teacher_username'), and(ME_USER('teacher_username'), when(c => c.role === 'teacher')))],
  },
  word_submissions: { select: [p(AUTH, or(ADMIN, ME_USER('username')))] },
  xp_log: { select: [p(AUTH, or(ME_USER('username'), ADMIN, DIRECTOR))] },
};

function staffWrites(base) {       // school_achievements / events / teachers / news
  return { ...base,
    insert: [p(AUTH, null, SCHOOL_STAFF)],
    update: [p(AUTH, SCHOOL_STAFF)],
    delete: [p(AUTH, SCHOOL_STAFF)] };
}
function ssStaffAll() { return { select: [p(ANY, TRUE)], all: [p(AUTH, SS_STAFF, SS_STAFF)] }; }
function ownerOrStaffAll(col) {
  const rule = or(ME_USER(col), SS_STAFF);
  return { select: [p(ANY, TRUE)], all: [p(AUTH, rule, rule)] };
}

// Bir əmr üçün tətbiq olunan qaydalar (rol filtri ilə)
function rulesFor(table, cmd, ctx) {
  const t = POLICIES[table];
  if (!t) return [];
  const role = ctx.uid ? 'authenticated' : 'anon';
  return [...(t[cmd] || []), ...(t.all || [])].filter(r => r.roles.includes(role));
}

// USING → SQL (heç bir qayda yoxdursa: heç nə görünmür)
function usingSql(table, cmd, ctx) {
  const rules = rulesFor(table, cmd, ctx).filter(r => r.using);
  if (!rules.length) return S('1=0');
  const parts = rules.map(r => r.using.sql(ctx));
  return S('(' + parts.map(x => x.sql).join(' OR ') + ')', parts.flatMap(x => x.params));
}

// WITH CHECK → yeni sətir (UPDATE-də check yoxdursa using istifadə olunur)
function checkRow(table, cmd, ctx, row) {
  const rules = rulesFor(table, cmd, ctx);
  if (!rules.length) return false;
  return rules.some(r => {
    const expr = r.check || (cmd === 'update' ? r.using : null);
    return expr ? expr.test(ctx, row) : false;
  });
}

// ── Postgres trigger-lərinin əvəzi (sütun qoruyucuları) ─────────────────
// before-update: old/new sətirlər üzərində dəyişiklik
const BEFORE_UPDATE = {
  profiles(ctx, oldRow, newRow, now) {
    // prevent_self_role_escalation: özünə rol / sinif verə bilməz (admin/direktor istisna)
    if (ctx.uid && ctx.uid === oldRow.id && !isAdmin(ctx) && !isDirector(ctx)) {
      newRow.role = oldRow.role;
      newRow.teacher_class = oldRow.teacher_class;
    }
    newRow.updated_at = now;                                   // set_updated_at
  },
  school_submissions(ctx, oldRow, newRow, now) {
    // prevent_submission_self_review: şagird öz işini təsdiqləyə bilməz
    if (ctx.uid && ctx.uid === oldRow.student_id && !isSchoolStaff(ctx)) {
      newRow.status = oldRow.status;
      newRow.admin_note = oldRow.admin_note;
      newRow.reviewed_by = oldRow.reviewed_by;
      newRow.reviewed_at = oldRow.reviewed_at;
    }
    if (isSchoolStaff(ctx) && newRow.status !== oldRow.status) {
      newRow.reviewed_by = ctx.uid;
      newRow.reviewed_at = now;
    }
  },
};

// ── Əlavə qoruyucular (Supabase versiyasında YOX idi — boşluqlar bağlanıb) ──
// Şagird "təsdiq / qiymət / səs / medal" sütunlarını özü yaza bilməz; bunları
// yalnız heyət (və ya server funksiyaları) dəyişir. Saytın normal işinə təsir
// etmir: sayt bu sütunları şagird adından onsuz da göndərmir.
const REVIEW_COLS = {
  ss_submissions:       { staff: isSsStaff, insert: { status: 'submitted', score: null, feedback: '' }, keep: ['status', 'score', 'feedback'] },
  ss_solutions:         { staff: isSsStaff, insert: { status: 'submitted', feedback: '' },              keep: ['status', 'feedback'],
                          fix: (row, old) => { if (row.stage === 'implemented' && (!old || old.stage !== 'implemented')) row.stage = old ? old.stage : 'idea'; } },
  ss_startups:          { staff: isSsStaff, insert: { votes: 0, stage: 'idea', status: 'active' },       keep: ['votes', 'stage', 'status', 'demo_day'] },
  ss_humanity_projects: { staff: isSsStaff, insert: { stage: 'research', status: 'active' },            keep: ['status'],
                          // Humanity Points mərhələdən hesablanır (saytın düsturu: 20 × mərhələ nömrəsi)
                          fix: row => { row.impact_points = 20 * (Math.max(0, HUM_STAGES.indexOf(row.stage)) + 1); } },
  ss_olympics_results:  { staff: isSsStaff, insert: { medal: null, rank: null },                         keep: ['medal', 'rank'] },
  school_submissions:   { staff: isSchoolStaff, insert: { status: 'pending', admin_note: '', reviewed_by: null, reviewed_at: null }, keep: [] },
  stories:              { staff: c => isAdmin(c) || isDirector(c), insert: { likes: 0 }, keep: [] },
};
const HUM_STAGES = ['research', 'idea', 'team', 'solution', 'prototype', 'presentation'];
const BEFORE_INSERT = {};
for (const [t, r] of Object.entries(REVIEW_COLS)) {
  BEFORE_INSERT[t] = (ctx, row) => { if (!r.staff(ctx)) { Object.assign(row, r.insert); if (r.fix) r.fix(row, null); } };
  if (r.keep.length || r.fix) {
    const prev = BEFORE_UPDATE[t];
    BEFORE_UPDATE[t] = (ctx, oldRow, newRow, now) => {
      if (prev) prev(ctx, oldRow, newRow, now);
      if (!r.staff(ctx)) { for (const k of r.keep) newRow[k] = oldRow[k]; if (r.fix) r.fix(newRow, oldRow); }
    };
  }
}

// ── görünüşlər (views) — yalnız oxunur, Postgres-də də RLS-dən keçmirdi ──
const VIEWS = {
  public_profiles: {
    roles: ANY,
    from: 'SELECT username, display_name, xp, level, streak, days_active, equipped_frame, equipped_theme FROM `profiles`',
    columns: { username: 'text', display_name: 'text', xp: 'int', level: 'int', streak: 'int', days_active: 'int', equipped_frame: 'text', equipped_theme: 'text' },
  },
  class_leaderboard: {
    roles: ANY,
    from: "SELECT class_grade, COUNT(*) AS student_count, SUM(xp) AS total_xp, ROUND(AVG(xp)) AS avg_xp, MAX(streak) AS top_streak FROM `profiles` WHERE class_grade <> '' GROUP BY class_grade",
    columns: { class_grade: 'text', student_count: 'bigint', total_xp: 'bigint', avg_xp: 'decimal', top_streak: 'int' },
    defaultOrder: 'total_xp DESC',
  },
  school_portfolio: {
    roles: ANY,
    from: "SELECT s.id, s.type, s.title, s.description, s.image_url, s.created_at, p.username, p.display_name, p.class_grade, p.equipped_frame FROM `school_submissions` s JOIN `profiles` p ON p.id = s.student_id WHERE s.status = 'approved'",
    columns: { id: 'bigint', type: 'text', title: 'text', description: 'text', image_url: 'text', created_at: 'datetime', username: 'text', display_name: 'text', class_grade: 'text', equipped_frame: 'text' },
  },
  ss_wallets: {
    roles: ANY,
    from: 'SELECT username, COALESCE(SUM(amount),0) AS balance, COALESCE(SUM(CASE WHEN amount > 0 THEN amount END),0) AS earned, COALESCE(-SUM(CASE WHEN amount < 0 THEN amount END),0) AS spent, COUNT(*) AS tx_count, MAX(created_at) AS last_activity FROM `ss_points_ledger` GROUP BY username',
    columns: { username: 'text', balance: 'bigint', earned: 'bigint', spent: 'bigint', tx_count: 'bigint', last_activity: 'datetime' },
  },
};

module.exports = { POLICIES, VIEWS, BEFORE_UPDATE, BEFORE_INSERT, usingSql, checkRow, rulesFor, roles: { isAdmin, isDirector, isSchoolStaff, isSsStaff } };
