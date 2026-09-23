-- ══════════════════════════════════════════════════════════════════════════
-- 205 SMART SCHOOL — EKOSİSTEM SXEMİ
-- Bakı şəhəri, R. İmanov adına 205 nömrəli tam orta ümumtəhsil məktəbi
--
-- BU MİQRASİYA HEÇ NƏ SİLMİR.
-- Mövcud SözLab cədvəlləri (profiles, school_news, school_events,
-- school_achievements, school_submissions, duels, live_quiz_sessions və s.)
-- olduğu kimi qalır. Burada YALNIZ yeni "ss_" prefiksli cədvəllər yaradılır.
--
-- Şagird kimliyi üçün ayrıca cədvəl AÇILMIR — mövcud public.profiles
-- istifadə olunur (username əsas açar kimi), çünki bütün SözLab sistemi
-- onun üzərində qurulub.
--
-- Supabase → SQL Editor → bu faylı yapışdır → Run. Təkrar işlətmək təhlükəsizdir.
-- ══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- 0) KÖMƏKÇİ FUNKSİYALAR
-- ─────────────────────────────────────────────────────────────

-- Mentor rolu: mövcud role yoxlamasını genişləndirir.
-- profiles.role artıq ('user','admin','teacher','director') dəyərlərini qəbul
-- edir; 'mentor' rolunu əlavə edirik ki, startapları qiymətləndirən müəllim
-- və ya kənar mentor ayrıca işarələnə bilsin.
do $$
begin
  alter table public.profiles drop constraint if exists profiles_role_check;
  alter table public.profiles
    add constraint profiles_role_check
    check (role in ('user','admin','teacher','director','mentor'));
exception when others then null;
end $$;

create or replace function public.ss_username()
returns text language sql stable security definer set search_path = public as $$
  select username from public.profiles where id = auth.uid();
$$;

create or replace function public.ss_is_staff(uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles
    where id = uid and role in ('admin','director','teacher','mentor')
  );
$$;

create or replace function public.ss_is_mentor(uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles
    where id = uid and role in ('admin','director','teacher','mentor')
  );
$$;

grant execute on function public.ss_username() to authenticated;
grant execute on function public.ss_is_staff(uuid) to authenticated, anon;
grant execute on function public.ss_is_mentor(uuid) to authenticated, anon;


-- ═════════════════════════════════════════════════════════════
-- 1) 205 WORLD — qlobal məktəb əlaqələri
-- ═════════════════════════════════════════════════════════════

create table if not exists public.ss_schools (
  id           bigint generated always as identity primary key,
  name         text not null,
  country      text not null,
  country_code text not null default '',        -- ISO-2, bayraq üçün
  city         text not null default '',
  lat          numeric(6,3),                     -- dünya xəritəsi üçün
  lng          numeric(6,3),
  student_count integer not null default 0,
  status       text not null default 'pending'
               check (status in ('connected','pending','invited')),
  website      text not null default '',
  note         text not null default '',
  is_home      boolean not null default false,   -- 205 özü
  created_at   timestamptz not null default now()
);
comment on table public.ss_schools is '205 World — əlaqə qurulan və ya dəvət olunan məktəblər.';

create table if not exists public.ss_challenges (
  id          bigint generated always as identity primary key,
  scope       text not null default 'world'
              check (scope in ('world','humanity')),   -- 205 World / Humanity Lab
  title       text not null,
  slug        text unique,
  category    text not null default '',
  icon        text not null default '🌍',
  summary     text not null default '',
  problem     text not null default '',      -- "Problem"
  why         text not null default '',      -- "Why it matters"
  research    text not null default '',      -- "Research"
  approaches  text not null default '',      -- "Possible approaches"
  difficulty  text not null default 'orta' check (difficulty in ('asan','orta','çətin')),
  points      integer not null default 50,
  deadline    date,
  status      text not null default 'open' check (status in ('open','judging','closed')),
  created_by  text not null default '',
  created_at  timestamptz not null default now()
);
comment on table public.ss_challenges is 'Beynəlxalq çağırışlar (World) və qlobal problem çağırışları (Humanity Lab).';

-- Komandalar — həm çağırış, həm startap, həm problem üçün ortaqdır
create table if not exists public.ss_teams (
  id           bigint generated always as identity primary key,
  name         text not null,
  purpose      text not null default 'challenge'
               check (purpose in ('challenge','startup','problem','humanity','olympics')),
  ref_id       bigint,                        -- aid olduğu çağırış/problem/startap
  owner        text not null,                 -- profiles.username
  members      text[] not null default '{}',  -- profiles.username siyahısı
  school_ids   bigint[] not null default '{}',-- beynəlxalq komanda üçün
  created_at   timestamptz not null default now()
);
comment on table public.ss_teams is 'Bütün ekosistem üçün ortaq komanda cədvəli.';

-- Çağırışa göndərilən işlər (World + Humanity ortaq)
create table if not exists public.ss_submissions (
  id            bigint generated always as identity primary key,
  challenge_id  bigint not null references public.ss_challenges(id) on delete cascade,
  team_id       bigint references public.ss_teams(id) on delete set null,
  author        text not null,                -- profiles.username
  title         text not null,
  description   text not null default '',
  link          text not null default '',
  image_url     text not null default '',
  status        text not null default 'submitted'
                check (status in ('submitted','reviewed','winner','rejected')),
  score         integer,
  feedback      text not null default '',
  created_at    timestamptz not null default now()
);


-- ═════════════════════════════════════════════════════════════
-- 2) 205 STUDENT BANK — virtual nailiyyət iqtisadiyyatı
--    DİQQƏT: real pul DEYİL. Yalnız motivasiya üçün xal sistemi.
-- ═════════════════════════════════════════════════════════════

create table if not exists public.ss_points_ledger (
  id         bigint generated always as identity primary key,
  username   text not null,                  -- profiles.username
  amount     integer not null,               -- müsbət = qazanc, mənfi = xərc
  reason     text not null,                  -- "Quiz", "Startap", "Mükafat" …
  source     text not null default 'system'
             check (source in ('system','quiz','challenge','project','startup',
                               'olympics','problem','help','teacher','reward','admin')),
  ref_id     bigint,
  created_at timestamptz not null default now()
);
comment on table public.ss_points_ledger is
  '205 Points hərəkatı. Balans = bu cədvəlin cəmi (heç vaxt birbaşa yazılmır).';
create index if not exists ss_points_user_idx on public.ss_points_ledger(username, created_at desc);

-- Balansı və statistikanı bir yerdə verən görünüş
create or replace view public.ss_wallets as
  select
    username,
    coalesce(sum(amount), 0)                             as balance,
    coalesce(sum(amount) filter (where amount > 0), 0)   as earned,
    coalesce(-sum(amount) filter (where amount < 0), 0)  as spent,
    count(*)                                             as tx_count,
    max(created_at)                                      as last_activity
  from public.ss_points_ledger
  group by username;
grant select on public.ss_wallets to anon, authenticated;

-- Mükafat mağazası (virtual)
create table if not exists public.ss_rewards (
  id          bigint generated always as identity primary key,
  code        text unique not null,
  name        text not null,
  description text not null default '',
  icon        text not null default '🎁',
  cost        integer not null check (cost >= 0),
  kind        text not null default 'badge'
              check (kind in ('badge','theme','booster','rank','pass','frame')),
  stock       integer,                      -- null = limitsiz
  active      boolean not null default true,
  sort_order  integer not null default 0
);

create table if not exists public.ss_reward_claims (
  id         bigint generated always as identity primary key,
  username   text not null,
  reward_id  bigint not null references public.ss_rewards(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (username, reward_id)
);


-- ═════════════════════════════════════════════════════════════
-- 3) 205 STARTUP FACTORY
-- ═════════════════════════════════════════════════════════════

create table if not exists public.ss_startups (
  id           bigint generated always as identity primary key,
  name         text not null,
  tagline      text not null default '',
  problem      text not null default '',
  solution     text not null default '',
  target_users text not null default '',
  category     text not null default '',
  description  text not null default '',
  logo_url     text not null default '',
  deck_url     text not null default '',      -- təqdimat
  demo_url     text not null default '',      -- demo linki
  founder      text not null,                 -- profiles.username
  team_id      bigint references public.ss_teams(id) on delete set null,
  -- 8 mərhələ: idea → validation → team → prototype → mvp → mentor → pitch → demoday
  stage        text not null default 'idea'
               check (stage in ('idea','validation','team','prototype','mvp',
                                'mentor','pitch','demoday')),
  status       text not null default 'active'
               check (status in ('active','paused','graduated','archived')),
  votes        integer not null default 0,
  demo_day     text not null default '',      -- "205 DEMO DAY 2026"
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create table if not exists public.ss_startup_votes (
  startup_id bigint not null references public.ss_startups(id) on delete cascade,
  username   text not null,
  created_at timestamptz not null default now(),
  primary key (startup_id, username)
);

create table if not exists public.ss_mentor_feedback (
  id         bigint generated always as identity primary key,
  startup_id bigint not null references public.ss_startups(id) on delete cascade,
  mentor     text not null,                  -- profiles.username
  stage      text not null default '',
  verdict    text not null default 'comment'
             check (verdict in ('comment','approved','changes','rejected')),
  body       text not null default '',
  created_at timestamptz not null default now()
);


-- ═════════════════════════════════════════════════════════════
-- 4) 205 PROBLEM MARKET — məktəbin real problemləri
-- ═════════════════════════════════════════════════════════════

create table if not exists public.ss_problems (
  id           bigint generated always as identity primary key,
  title        text not null,
  body         text not null default '',
  category     text not null default 'Məktəb həyatı',
  difficulty   text not null default 'orta' check (difficulty in ('asan','orta','çətin')),
  status       text not null default 'open'
               check (status in ('open','progress','solved','implemented')),
  points       integer not null default 75,
  created_by   text not null default '',      -- müəllim/direktor username
  deadline     date,
  solved_by    text[] not null default '{}',  -- problemi həll edən şagirdlər
  solved_at    timestamptz,
  created_at   timestamptz not null default now()
);

create table if not exists public.ss_solutions (
  id          bigint generated always as identity primary key,
  problem_id  bigint not null references public.ss_problems(id) on delete cascade,
  author      text not null,
  team_id     bigint references public.ss_teams(id) on delete set null,
  title       text not null,
  idea        text not null default '',
  solution    text not null default '',
  prototype   text not null default '',       -- link və ya təsvir
  -- boru xətti: idea → team → solution → prototype → review → implemented
  stage       text not null default 'idea'
              check (stage in ('idea','team','solution','prototype','review','implemented')),
  status      text not null default 'submitted'
              check (status in ('submitted','accepted','implemented','rejected')),
  feedback    text not null default '',
  created_at  timestamptz not null default now()
);


-- ═════════════════════════════════════════════════════════════
-- 5) 205 HUMANITY LAB
--    Çağırışlar ss_challenges (scope='humanity') içindədir.
--    Layihələr ayrıca saxlanılır, çünki onların öz mərhələləri var.
-- ═════════════════════════════════════════════════════════════

create table if not exists public.ss_humanity_projects (
  id           bigint generated always as identity primary key,
  challenge_id bigint references public.ss_challenges(id) on delete set null,
  title        text not null,
  category     text not null default '',
  author       text not null,
  team_id      bigint references public.ss_teams(id) on delete set null,
  research     text not null default '',
  idea         text not null default '',
  solution     text not null default '',
  prototype    text not null default '',
  link         text not null default '',
  stage        text not null default 'research'
               check (stage in ('research','idea','team','solution','prototype','presentation')),
  status       text not null default 'active'
               check (status in ('active','completed','featured','archived')),
  impact_points integer not null default 0,
  created_at   timestamptz not null default now()
);


-- ═════════════════════════════════════════════════════════════
-- 6) 205 OLYMPICS
-- ═════════════════════════════════════════════════════════════

create table if not exists public.ss_olympics_events (
  id          bigint generated always as identity primary key,
  season      text not null default '205 OLYMPICS 2026',
  category    text not null,                 -- Məntiq, Söz ehtiyatı, Kodlaşdırma…
  icon        text not null default '🏅',
  -- mərhələlər: qualification → class → grade → final → championship
  stage       text not null default 'qualification'
              check (stage in ('qualification','class','grade','final','championship')),
  status      text not null default 'upcoming'
              check (status in ('upcoming','live','finished')),
  starts_at   timestamptz,
  duration_min integer not null default 15,
  question_count integer not null default 12,
  description text not null default '',
  created_by  text not null default '',
  created_at  timestamptz not null default now()
);

create table if not exists public.ss_olympics_results (
  id          bigint generated always as identity primary key,
  event_id    bigint not null references public.ss_olympics_events(id) on delete cascade,
  username    text not null,
  class_grade text not null default '',
  score       integer not null default 0,
  accuracy    integer not null default 0,     -- %
  best_combo  integer not null default 0,
  duration_s  integer not null default 0,
  medal       text check (medal in ('gold','silver','bronze')),
  rank        integer,
  created_at  timestamptz not null default now(),
  unique (event_id, username)
);
create index if not exists ss_olympics_results_event_idx
  on public.ss_olympics_results(event_id, score desc);

-- Şöhrət Zalı — mövsüm bitəndə qalıcı qeyd
create table if not exists public.ss_hall_of_fame (
  id          bigint generated always as identity primary key,
  season      text not null,
  category    text not null,
  username    text not null,
  display_name text not null default '',
  class_grade text not null default '',
  medal       text not null check (medal in ('gold','silver','bronze')),
  score       integer not null default 0,
  note        text not null default '',
  created_at  timestamptz not null default now()
);


-- ═════════════════════════════════════════════════════════════
-- 7) NAİLİYYƏTLƏR — ekosistem boyu ortaq
-- ═════════════════════════════════════════════════════════════

create table if not exists public.ss_achievements (
  id         bigint generated always as identity primary key,
  username   text not null,
  code       text not null,                  -- 'problem_solved', 'startup_demoday'…
  title      text not null,
  detail     text not null default '',
  icon       text not null default '🏆',
  module     text not null default 'world'
             check (module in ('world','bank','startup','problem','humanity','olympics')),
  ref_id     bigint,
  created_at timestamptz not null default now()
);
create index if not exists ss_achievements_user_idx on public.ss_achievements(username, created_at desc);


-- ═════════════════════════════════════════════════════════════
-- 8) XAL VERMƏ — yeganə giriş nöqtəsi
--    Şagird özünə xal yaza bilməsin deyə ledger-ə birbaşa insert
--    YALNIZ bu funksiya vasitəsilə mümkündür.
-- ═════════════════════════════════════════════════════════════

create or replace function public.ss_award_points(
  p_username text, p_amount integer, p_reason text,
  p_source text default 'system', p_ref_id bigint default null
) returns integer
language plpgsql security definer set search_path = public as $$
declare v_balance integer;
begin
  if p_username is null or p_username = '' then return 0; end if;
  if p_amount is null or p_amount = 0 then return 0; end if;

  -- Mənfi (xərcləmə) yalnız öz balansından və balans çatdıqda
  if p_amount < 0 then
    select coalesce(sum(amount),0) into v_balance
      from public.ss_points_ledger where username = p_username;
    if v_balance + p_amount < 0 then
      raise exception '205 Points kifayət etmir';
    end if;
  end if;

  -- Şagird yalnız sistem hadisəsi ilə xal ala bilər; əl ilə xal vermək
  -- yalnız məktəb heyətinin ixtiyarındadır.
  if p_source = 'admin' and not public.ss_is_staff(auth.uid()) then
    raise exception 'İcazə yoxdur';
  end if;

  insert into public.ss_points_ledger(username, amount, reason, source, ref_id)
  values (p_username, p_amount, p_reason, p_source, p_ref_id);

  select coalesce(sum(amount),0) into v_balance
    from public.ss_points_ledger where username = p_username;
  return v_balance;
end;
$$;
grant execute on function public.ss_award_points(text,integer,text,text,bigint) to authenticated;

-- Mükafat alma (balansdan çıxır, təkrar alınmır)
create or replace function public.ss_claim_reward(p_reward_id bigint)
returns text language plpgsql security definer set search_path = public as $$
declare v_user text; v_cost integer; v_name text; v_active boolean;
begin
  v_user := public.ss_username();
  if v_user is null then raise exception 'Giriş tələb olunur'; end if;

  select cost, name, active into v_cost, v_name, v_active
    from public.ss_rewards where id = p_reward_id;
  if v_cost is null then raise exception 'Mükafat tapılmadı'; end if;
  if not v_active then raise exception 'Bu mükafat artıq aktiv deyil'; end if;

  if exists (select 1 from public.ss_reward_claims
             where username = v_user and reward_id = p_reward_id) then
    raise exception 'Bu mükafatı artıq almısan';
  end if;

  perform public.ss_award_points(v_user, -v_cost, 'Mükafat: '||v_name, 'reward', p_reward_id);
  insert into public.ss_reward_claims(username, reward_id) values (v_user, p_reward_id);
  insert into public.ss_achievements(username, code, title, detail, icon, module, ref_id)
    values (v_user, 'reward_'||p_reward_id, v_name, 'Mükafat mağazasından alındı', '🎁', 'bank', p_reward_id);
  return v_name;
end;
$$;
grant execute on function public.ss_claim_reward(bigint) to authenticated;

-- Startapa səs vermə (bir şagird bir dəfə)
create or replace function public.ss_vote_startup(p_startup_id bigint)
returns integer language plpgsql security definer set search_path = public as $$
declare v_user text; v_votes integer;
begin
  v_user := public.ss_username();
  if v_user is null then raise exception 'Giriş tələb olunur'; end if;
  insert into public.ss_startup_votes(startup_id, username)
    values (p_startup_id, v_user) on conflict do nothing;
  select count(*) into v_votes from public.ss_startup_votes where startup_id = p_startup_id;
  update public.ss_startups set votes = v_votes where id = p_startup_id;
  return v_votes;
end;
$$;
grant execute on function public.ss_vote_startup(bigint) to authenticated;

-- Problemi həll edilmiş elan etmək (yalnız heyət) + nailiyyət + xal
create or replace function public.ss_mark_problem_solved(
  p_problem_id bigint, p_solution_id bigint
) returns void language plpgsql security definer set search_path = public as $$
declare v_author text; v_title text; v_points integer; v_member text; v_team bigint;
begin
  if not public.ss_is_staff(auth.uid()) then raise exception 'İcazə yoxdur'; end if;

  select title, points into v_title, v_points from public.ss_problems where id = p_problem_id;
  select author, team_id into v_author, v_team from public.ss_solutions where id = p_solution_id;
  if v_author is null then raise exception 'Həll tapılmadı'; end if;

  update public.ss_solutions set status = 'implemented', stage = 'implemented'
    where id = p_solution_id;
  update public.ss_problems
    set status = 'solved', solved_at = now(),
        solved_by = array(select distinct unnest(solved_by || array[v_author]))
    where id = p_problem_id;

  -- Müəllif və komanda üzvlərinin hamısı xal və nailiyyət alır
  for v_member in
    select unnest(array[v_author] ||
      coalesce((select members from public.ss_teams where id = v_team), '{}'))
  loop
    if v_member is null or v_member = '' then continue; end if;
    perform public.ss_award_points(v_member, coalesce(v_points,75),
      'Problem həll edildi: '||v_title, 'problem', p_problem_id);
    insert into public.ss_achievements(username, code, title, detail, icon, module, ref_id)
      values (v_member, 'problem_solved', 'Problem Solved by 205 Students',
              v_title, '🧩', 'problem', p_problem_id);
  end loop;
end;
$$;
grant execute on function public.ss_mark_problem_solved(bigint,bigint) to authenticated;

-- Şagirdin ekosistem xülasəsi (dashboard üçün tək sorğu)
create or replace function public.ss_my_summary()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_user text; v_out jsonb;
begin
  v_user := public.ss_username();
  if v_user is null then return '{}'::jsonb; end if;
  select jsonb_build_object(
    'username', v_user,
    'balance',  coalesce((select sum(amount) from public.ss_points_ledger where username=v_user),0),
    'earned',   coalesce((select sum(amount) from public.ss_points_ledger where username=v_user and amount>0),0),
    'spent',    coalesce((select -sum(amount) from public.ss_points_ledger where username=v_user and amount<0),0),
    'achievements', (select count(*) from public.ss_achievements where username=v_user),
    'startups',  (select count(*) from public.ss_startups where founder=v_user),
    'solutions', (select count(*) from public.ss_solutions where author=v_user),
    'humanity',  (select count(*) from public.ss_humanity_projects where author=v_user),
    'humanity_points', coalesce((select sum(impact_points) from public.ss_humanity_projects where author=v_user),0),
    'submissions', (select count(*) from public.ss_submissions where author=v_user),
    'olympics',  (select count(*) from public.ss_olympics_results where username=v_user),
    'medals',    (select count(*) from public.ss_olympics_results where username=v_user and medal is not null),
    'teams',     (select count(*) from public.ss_teams where owner=v_user or v_user = any(members)),
    'rank',      (select count(*)+1 from public.ss_wallets w
                   where w.balance > coalesce((select sum(amount) from public.ss_points_ledger where username=v_user),0))
  ) into v_out;
  return v_out;
end;
$$;
grant execute on function public.ss_my_summary() to authenticated;

-- Məktəb analitikası (direktor paneli üçün)
create or replace function public.ss_school_analytics()
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.ss_is_staff(auth.uid()) then raise exception 'İcazə yoxdur'; end if;
  return jsonb_build_object(
    'students',        (select count(*) from public.profiles where role='user'),
    -- Yalnız ŞAGİRDLƏR sayılır: əvvəl admin/müəllim/direktorun xalları da sayılırdı,
    -- məxrəc isə yalnız şagird idi — iştirak faizi 100%-dən çox çıxırdı (məs. 133%).
    'active_students', (select count(distinct l.username) from public.ss_points_ledger l
                         join public.profiles p on p.username = l.username and p.role = 'user'
                         where l.created_at > now() - interval '30 days'),
    'startups',        (select count(*) from public.ss_startups),
    'startups_by_stage', (select coalesce(jsonb_object_agg(stage, n),'{}'::jsonb)
                           from (select stage, count(*) n from public.ss_startups group by stage) t),
    'problems',        (select count(*) from public.ss_problems),
    'problems_solved', (select count(*) from public.ss_problems where status in ('solved','implemented')),
    'solutions',       (select count(*) from public.ss_solutions),
    'challenges',      (select count(*) from public.ss_challenges),
    'submissions',     (select count(*) from public.ss_submissions),
    'humanity',        (select count(*) from public.ss_humanity_projects),
    'connections',     (select count(*) from public.ss_schools where status='connected' and not is_home),
    'olympics_events', (select count(*) from public.ss_olympics_events),
    'olympics_participants', (select count(distinct username) from public.ss_olympics_results),
    'points_total',    (select coalesce(sum(amount),0) from public.ss_points_ledger where amount>0),
    'teams',           (select count(*) from public.ss_teams),
    'by_category',     (select coalesce(jsonb_object_agg(category, n),'{}'::jsonb)
                         from (select category, count(*) n from public.ss_problems group by category) t),
    'monthly',         (select coalesce(jsonb_agg(row_to_json(m) order by m.ym),'[]'::jsonb) from (
                          select to_char(date_trunc('month',created_at),'YYYY-MM') ym, count(*) n
                          from public.ss_points_ledger
                          where created_at > now() - interval '6 months'
                          group by 1) m)
  );
end;
$$;
grant execute on function public.ss_school_analytics() to authenticated;


-- ═════════════════════════════════════════════════════════════
-- 9) RLS — oxumaq hamıya açıq, yazmaq roldan asılı
-- ═════════════════════════════════════════════════════════════

do $$
declare t text;
begin
  foreach t in array array[
    'ss_schools','ss_challenges','ss_teams','ss_submissions','ss_points_ledger',
    'ss_rewards','ss_reward_claims','ss_startups','ss_startup_votes',
    'ss_mentor_feedback','ss_problems','ss_solutions','ss_humanity_projects',
    'ss_olympics_events','ss_olympics_results','ss_hall_of_fame','ss_achievements']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "%s_read" on public.%I', t, t);
    execute format(
      'create policy "%s_read" on public.%I for select to anon, authenticated using (true)', t, t);
  end loop;
end $$;

-- ── Şagirdin özü yarada/dəyişə bildikləri ──
drop policy if exists "ss_teams_write" on public.ss_teams;
create policy "ss_teams_write" on public.ss_teams for all to authenticated
  using (owner = public.ss_username() or public.ss_is_staff(auth.uid()))
  with check (owner = public.ss_username() or public.ss_is_staff(auth.uid()));

drop policy if exists "ss_submissions_write" on public.ss_submissions;
create policy "ss_submissions_write" on public.ss_submissions for all to authenticated
  using (author = public.ss_username() or public.ss_is_staff(auth.uid()))
  with check (author = public.ss_username() or public.ss_is_staff(auth.uid()));

drop policy if exists "ss_startups_write" on public.ss_startups;
create policy "ss_startups_write" on public.ss_startups for all to authenticated
  using (founder = public.ss_username() or public.ss_is_staff(auth.uid()))
  with check (founder = public.ss_username() or public.ss_is_staff(auth.uid()));

drop policy if exists "ss_solutions_write" on public.ss_solutions;
create policy "ss_solutions_write" on public.ss_solutions for all to authenticated
  using (author = public.ss_username() or public.ss_is_staff(auth.uid()))
  with check (author = public.ss_username() or public.ss_is_staff(auth.uid()));

drop policy if exists "ss_humanity_write" on public.ss_humanity_projects;
create policy "ss_humanity_write" on public.ss_humanity_projects for all to authenticated
  using (author = public.ss_username() or public.ss_is_staff(auth.uid()))
  with check (author = public.ss_username() or public.ss_is_staff(auth.uid()));

-- Olimpiada nəticəsi: şagird yalnız ÖZ nəticəsini yaza bilər
drop policy if exists "ss_olympics_results_write" on public.ss_olympics_results;
create policy "ss_olympics_results_write" on public.ss_olympics_results for insert to authenticated
  with check (username = public.ss_username());
drop policy if exists "ss_olympics_results_update" on public.ss_olympics_results;
create policy "ss_olympics_results_update" on public.ss_olympics_results for update to authenticated
  using (username = public.ss_username() or public.ss_is_staff(auth.uid()));

-- ── Yalnız məktəb heyəti ──
drop policy if exists "ss_problems_write" on public.ss_problems;
create policy "ss_problems_write" on public.ss_problems for all to authenticated
  using (public.ss_is_staff(auth.uid())) with check (public.ss_is_staff(auth.uid()));

drop policy if exists "ss_challenges_write" on public.ss_challenges;
create policy "ss_challenges_write" on public.ss_challenges for all to authenticated
  using (public.ss_is_staff(auth.uid())) with check (public.ss_is_staff(auth.uid()));

drop policy if exists "ss_schools_write" on public.ss_schools;
create policy "ss_schools_write" on public.ss_schools for all to authenticated
  using (public.ss_is_staff(auth.uid())) with check (public.ss_is_staff(auth.uid()));

drop policy if exists "ss_olympics_events_write" on public.ss_olympics_events;
create policy "ss_olympics_events_write" on public.ss_olympics_events for all to authenticated
  using (public.ss_is_staff(auth.uid())) with check (public.ss_is_staff(auth.uid()));

drop policy if exists "ss_hall_write" on public.ss_hall_of_fame;
create policy "ss_hall_write" on public.ss_hall_of_fame for all to authenticated
  using (public.ss_is_staff(auth.uid())) with check (public.ss_is_staff(auth.uid()));

drop policy if exists "ss_rewards_write" on public.ss_rewards;
create policy "ss_rewards_write" on public.ss_rewards for all to authenticated
  using (public.ss_is_staff(auth.uid())) with check (public.ss_is_staff(auth.uid()));

-- Mentor rəyi — yalnız mentor/heyət yaza bilər
drop policy if exists "ss_mentor_feedback_write" on public.ss_mentor_feedback;
create policy "ss_mentor_feedback_write" on public.ss_mentor_feedback for all to authenticated
  using (public.ss_is_mentor(auth.uid())) with check (public.ss_is_mentor(auth.uid()));

-- Xal dəftəri: BİRBAŞA yazmaq qadağandır (yalnız ss_award_points funksiyası ilə)
drop policy if exists "ss_points_no_direct_write" on public.ss_points_ledger;
-- (insert/update/delete siyasəti yaradılmır → heç kim birbaşa yaza bilməz)

-- Səsvermə və mükafat tələbi funksiyalarla gedir
drop policy if exists "ss_startup_votes_write" on public.ss_startup_votes;
create policy "ss_startup_votes_write" on public.ss_startup_votes for insert to authenticated
  with check (username = public.ss_username());

-- Nailiyyətlər yalnız funksiyalarla yazılır (security definer RLS-i keçir)
drop policy if exists "ss_achievements_staff_write" on public.ss_achievements;
create policy "ss_achievements_staff_write" on public.ss_achievements for all to authenticated
  using (public.ss_is_staff(auth.uid())) with check (public.ss_is_staff(auth.uid()));


-- ═════════════════════════════════════════════════════════════
-- 10) BAŞLANĞIC MƏLUMATI
--     Ekosistem boş açılmasın deyə real, mənalı başlanğıc məzmun.
-- ═════════════════════════════════════════════════════════════

-- 205 özü + dəvət olunan məktəblər
insert into public.ss_schools (name, country, country_code, city, lat, lng, student_count, status, is_home, note)
select * from (values
  ('R. İmanov adına 205 nömrəli tam orta məktəb','Azərbaycan','AZ','Bakı, Binəqədi',40.430,49.826,780,'connected',true,'Ekosistemin mərkəzi'),
  ('Ankara Fen Lisesi','Türkiyə','TR','Ankara',39.933,32.859,640,'connected',false,'STEM yönümlü lisey'),
  ('Tbilisi Public School №1','Gürcüstan','GE','Tbilisi',41.716,44.783,520,'connected',false,'Regional tərəfdaş'),
  ('Astana IT Lyceum','Qazaxıstan','KZ','Astana',51.169,71.449,700,'pending',false,'Kodlaşdırma çağırışları'),
  ('Tallinn Innovation School','Estoniya','EE','Tallinn',59.437,24.754,430,'pending',false,'Rəqəmsal təhsil təcrübəsi'),
  ('Kyoto Global Academy','Yaponiya','JP','Kyoto',35.011,135.768,610,'invited',false,'Mədəni mübadilə'),
  ('Nairobi STEM Academy','Keniya','KE','Nairobi',-1.286,36.817,480,'invited',false,'Təmiz su layihəsi'),
  ('Lisboa Escola Futuro','Portuqaliya','PT','Lissabon',38.722,-9.139,550,'invited',false,'Dayanıqlılıq çağırışı')
) v(name,country,country_code,city,lat,lng,student_count,status,is_home,note)
where not exists (select 1 from public.ss_schools);

-- Beynəlxalq çağırışlar (205 World)
insert into public.ss_challenges (scope,title,slug,category,icon,summary,problem,why,difficulty,points,status)
select * from (values
  ('world','Climate Challenge','climate-challenge','İqlim','🌡️',
   'Məktəbinin karbon izini ölç və azaltmaq üçün real plan təklif et.',
   'Məktəblər gündəlik fəaliyyətində nəzərə alınmayan miqdarda enerji və resurs sərf edir.',
   'İqlim dəyişikliyi bu nəslin ən böyük problemidir; dəyişiklik kiçik mühitlərdən başlayır.',
   'orta',60,'open'),
  ('world','Future Education Challenge','future-education','Təhsil','📚',
   '2035-ci ilin dərs otağını layihələndir.',
   'Dərs formatı 100 ildir demək olar ki, dəyişməyib, halbuki dünya dəyişib.',
   'Təhsilin forması gələcək peşələri müəyyən edir.','orta',60,'open'),
  ('world','AI for Good','ai-for-good','Texnologiya','🤖',
   'Süni intellektdən cəmiyyətə fayda verən bir həll qur.',
   'AI çox vaxt əyləncə üçün işlənir, sosial problemlər üçün isə az.',
   'Texnologiyanın istiqamətini onu quranlar seçir.','çətin',80,'open'),
  ('world','Water Challenge','water-challenge','Su','💧',
   'Təmiz suya çıxışı artıran və ya su israfını azaldan həll təklif et.',
   'Dünyada hər 4 nəfərdən biri təhlükəsiz içməli su ilə tam təmin olunmur.',
   'Su olmadan nə sağlamlıq, nə təhsil, nə də iqtisadiyyat mümkündür.','orta',70,'open'),
  ('world','Smart City Challenge','smart-city','Şəhər','🏙',
   'Bakının bir məhəlləsini daha ağıllı və rahat edən ideya qur.',
   'Şəhər infrastrukturu çox vaxt insanın gündəlik marşrutunu nəzərə almır.',
   'Şəhəri yaxşılaşdırmaq onu hər gün yaşayanların işidir.','orta',65,'open'),
  ('world','Sustainable Future Challenge','sustainable-future','Dayanıqlılıq','🌱',
   'Məktəbdə tullantını azaldan davamlı sistem qur.',
   'Tullantıların böyük hissəsi düzgün ayrılmadığı üçün təkrar emala getmir.',
   'Dayanıqlılıq vərdişi məktəbdə formalaşır.','asan',50,'open')
) v(scope,title,slug,category,icon,summary,problem,why,difficulty,points,status)
where not exists (select 1 from public.ss_challenges where scope='world');

-- Humanity Lab çağırışları
insert into public.ss_challenges (scope,title,slug,category,icon,summary,problem,why,difficulty,points,status)
select * from (values
  ('humanity','İqlim və Enerji','h-climate','Climate','🌍',
   'Qlobal istiləşməni azaldan yerli həllər.',
   'Karbon emissiyası artmaqda davam edir.',
   'Bugünkü qərarlar 50 il sonranı müəyyən edir.','çətin',90,'open'),
  ('humanity','Təmiz Su','h-water','Clean Water','💧',
   'Su çatışmazlığı və çirklənməsi ilə mübarizə.',
   '2 milyard insan təhlükəsiz su xidmətindən məhrumdur.',
   'Su əsas insan hüququdur.','çətin',90,'open'),
  ('humanity','Hamı üçün Təhsil','h-education','Education','📚',
   'Təhsilə çıxışı olmayan uşaqlar üçün həllər.',
   'Dünyada 250 milyondan çox uşaq məktəbdən kənardadır.',
   'Təhsil yoxsulluqdan çıxışın ən qısa yoludur.','orta',80,'open'),
  ('humanity','Əlçatanlıq','h-accessibility','Accessibility','♿',
   'Məhdud imkanlı insanlar üçün maneələri aradan qaldır.',
   'İctimai məkanların çoxu hərəkət məhdudiyyəti olanlar üçün nəzərdə tutulmayıb.',
   'Əlçatanlıq bir azlığın deyil, hamının rahatlığıdır.','orta',80,'open'),
  ('humanity','Ətraf Mühit','h-environment','Environment','🌱',
   'Biomüxtəlifliyin qorunması və tullantının azaldılması.',
   'Növlərin yox olma sürəti təbii fondan yüzlərlə dəfə yüksəkdir.',
   'Ekosistem pozulanda ilk zərbəni insan alır.','orta',75,'open'),
  ('humanity','Ağıllı Şəhərlər','h-cities','Smart Cities','🏙',
   'Şəhər həyatını daha səmərəli və insani etmək.',
   'Şəhərlərdə əhalinin yarısından çoxu yaşayır və bu rəqəm artır.',
   'Yaxşı şəhər dizaynı milyonların gününü dəyişir.','orta',75,'open'),
  ('humanity','Qida Təhlükəsizliyi','h-food','Food','🍎',
   'Qida israfı və çatışmazlığı problemləri.',
   'İstehsal olunan qidanın təxminən üçdə biri israf olunur.',
   'İsrafı azaltmaq aclığı azaltmağın ən sürətli yoludur.','orta',75,'open'),
  ('humanity','Təmiz Enerji','h-energy','Clean Energy','🔋',
   'Bərpa olunan enerji həlləri.',
   'Enerjinin böyük hissəsi hələ də qazma yanacaqlardan gəlir.',
   'Enerji keçidi iqlim məsələsinin mərkəzidir.','çətin',85,'open'),
  ('humanity','Sosial Birlik','h-inclusion','Social Inclusion','🤝',
   'Cəmiyyətdə təcridin və ayrı-seçkiliyin azaldılması.',
   'Bir çox qrup ictimai həyatdan kənarda qalır.',
   'Birlik olmayan cəmiyyət inkişaf edə bilmir.','orta',75,'open')
) v(scope,title,slug,category,icon,summary,problem,why,difficulty,points,status)
where not exists (select 1 from public.ss_challenges where scope='humanity');

-- Məktəbin real problemləri (Problem Market)
insert into public.ss_problems (title, body, category, difficulty, points, status, created_by)
select * from (values
  ('Kitabxanada kitab tapmaq necə asanlaşdırıla bilər?',
   'Şagirdlər kitabxanada axtardıqları kitabı tapmaqda çətinlik çəkir: kataloq kağız üzərindədir, rəflərdə naviqasiya işarəsi azdır. Məqsəd — şagirdin 2 dəqiqə ərzində kitabı tapmasını təmin edən həll.',
   'Təhsil','orta',75,'open',''),
  ('Məktəbdə enerji sərfiyyatını necə azalda bilərik?',
   'Dərsdən sonra bəzi otaqlarda işıq və avadanlıq açıq qalır. Məqsəd — davranış və ya texniki həll ilə aylıq elektrik sərfini ölçülə bilən şəkildə azaltmaq.',
   'Ekologiya','orta',85,'open',''),
  ('Məktəbdə təkrar emalı necə yaxşılaşdıra bilərik?',
   'Tullantı qabları var, amma ayrılma düzgün getmir. Məqsəd — şagirdlərin düzgün ayırmasını təbii hala gətirən sistem.',
   'Ekologiya','asan',60,'open',''),
  ('Şagirdlər vaxtlarını necə daha yaxşı idarə edə bilər?',
   'Sınaqlar və tapşırıqlar üst-üstə düşəndə şagirdlər planlaşdıra bilmir. Məqsəd — sadə, istifadəsi asan planlaşdırma həlli.',
   'Məktəb həyatı','orta',70,'open',''),
  ('Məktəb tədbirlərini hamı üçün necə əlçatan edə bilərik?',
   'Tədbirlər haqqında məlumat hamıya çatmır; bəzi şagirdlər üçün fiziki çıxış da çətindir. Məqsəd — məlumat və məkan baxımından əlçatanlığı artırmaq.',
   'Əlçatanlıq','orta',80,'open','')
) v(title,body,category,difficulty,points,status,created_by)
where not exists (select 1 from public.ss_problems);

-- Mükafat mağazası
insert into public.ss_rewards (code,name,description,icon,cost,kind,sort_order)
select * from (values
  ('badge_innovator','İnnovator nişanı','Profilində görünən xüsusi nişan.','🎖️',150,'badge',1),
  ('theme_aurora','Aurora teması','Profil üçün xüsusi rəng teması.','🎨',250,'theme',2),
  ('booster_xp','XP Booster (7 gün)','Bir həftə ərzində oyunlardan 1.5× XP.','⚡',300,'booster',3),
  ('rank_pioneer','Pioner rütbəsi','Liderbordda xüsusi rütbə adı.','🏅',400,'rank',4),
  ('pass_challenge','Challenge Pass','Növbəti beynəlxalq çağırışa prioritet qeydiyyat.','🎫',350,'pass',5),
  ('badge_founder','Founder nişanı','Startap quranlar üçün xüsusi nişan.','🚀',500,'badge',6),
  ('frame_exclusive','Eksklüziv avatar çərçivəsi','Profil şəklinə xüsusi çərçivə.','🖼️',600,'frame',7)
) v(code,name,description,icon,cost,kind,sort_order)
where not exists (select 1 from public.ss_rewards);

-- Olimpiada kateqoriyaları (qaralama mərhələ)
insert into public.ss_olympics_events (season,category,icon,stage,status,question_count,description)
select * from (values
  ('205 OLYMPICS 2026','Məntiq','🧠','qualification','upcoming',12,'Məntiqi ardıcıllıq və problem həlli.'),
  ('205 OLYMPICS 2026','Söz ehtiyatı','📚','qualification','upcoming',15,'SözLab lüğəti üzrə yarış.'),
  ('205 OLYMPICS 2026','Kodlaşdırma','💻','qualification','upcoming',10,'Alqoritm və məntiq tapşırıqları.'),
  ('205 OLYMPICS 2026','Elm','🔬','qualification','upcoming',12,'Fizika, kimya, biologiya.'),
  ('205 OLYMPICS 2026','Coğrafiya','🗺️','qualification','upcoming',12,'Dünya və Azərbaycan coğrafiyası.'),
  ('205 OLYMPICS 2026','Dizayn','🎨','qualification','upcoming',8,'Vizual həll və kompozisiya.'),
  ('205 OLYMPICS 2026','Natiqlik','🎤','class','upcoming',5,'Çıxış və arqumentasiya.'),
  ('205 OLYMPICS 2026','Yaradıcı yazı','✍️','class','upcoming',5,'Mətn yaratma bacarığı.'),
  ('205 OLYMPICS 2026','Texnologiya','⚙️','qualification','upcoming',12,'Rəqəmsal savadlılıq.'),
  ('205 OLYMPICS 2026','Məktəb fəaliyyəti','🏃','class','upcoming',6,'Komanda və fiziki fəaliyyət.')
) v(season,category,icon,stage,status,question_count,description)
where not exists (select 1 from public.ss_olympics_events);


-- ─────────────────────────────────────────────────────────────
-- YOXLAMA
-- ─────────────────────────────────────────────────────────────
select 'ss_schools' t, count(*) n from public.ss_schools
union all select 'ss_challenges', count(*) from public.ss_challenges
union all select 'ss_problems',   count(*) from public.ss_problems
union all select 'ss_rewards',    count(*) from public.ss_rewards
union all select 'ss_olympics_events', count(*) from public.ss_olympics_events
order by t;
