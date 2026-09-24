-- ══════════════════════════════════════════════════════════════════════════
-- SözLab — YENİ SUPABASE LAYİHƏSİ ÜÇÜN TAM QURAŞDIRMA
-- Layihə: https://skijahzkjlzhejrzomai.supabase.co
--
-- BU FAYLI BİR DƏFƏ RUN ETMƏK KİFAYƏTDİR.
-- Supabase Dashboard → SQL Editor → New query → bu faylın HAMISINI yapışdır → Run.
--
-- 25 skript REAL asılılıqlara görə sıralanıb: hər funksiya/cədvəl istifadə
-- olunmazdan ƏVVƏL yaradılır. Sıra kodun özündən çıxarılıb və təmiz
-- PostgreSQL 16 bazasında Supabase mühiti imitasiya edilərək başdan-sona
-- xətasız işlədilib (iki dəfə ardıcıl — təkrar run da təhlükəsizdir).
--
-- QEYD: service_role açarı HEÇ BİR YERDƏ istifadə olunmur və olunmamalıdır.
-- ══════════════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════════
-- [01/25]  supabase_setup.sql
-- Əsas sxem: profiles, XP, hekayələr, elanlar
-- ════════════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════
-- SözLab — Supabase SQL Quraşdırılması (TAM SKRİPT)
-- Bu faylı Supabase Dashboard → SQL Editor-da açıb "Run" edin.
-- Layihə: https://skijahzkjlzhejrzomai.supabase.co
-- ════════════════════════════════════════════════════════════════
-- QEYD: Bu skript yalnız "anon" (publishable) açarla frontend-dən
-- işləyəcək təhlükəsizlik modelini qurur. service_role/secret açar
-- heç vaxt frontend kodunda istifadə OLUNMUR və olunmamalıdır.
-- ════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────
-- 1) PROFİLLƏR CƏDVƏLİ
-- ─────────────────────────────────────────────
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null,
  display_name text not null default '',
  xp integer not null default 0,
  level integer not null default 1,
  streak integer not null default 0,
  last_visit text,
  learned text[] not null default '{}',
  badges text[] not null default '{}',
  role text not null default 'user' check (role in ('user','admin')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint username_format check (username ~ '^[a-z0-9_]{3,20}$')
);

create index if not exists idx_profiles_xp on public.profiles (xp desc);
create index if not exists idx_profiles_username on public.profiles (username);
create index if not exists idx_profiles_role on public.profiles (role);

-- ─────────────────────────────────────────────
-- 2) HEKAYƏLƏR (Creative / Yaradıcılıq bölməsi)
-- ─────────────────────────────────────────────
create table if not exists public.stories (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  username text not null,
  display_name text not null default '',
  text text not null check (char_length(text) between 1 and 2000),
  likes integer not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists idx_stories_user on public.stories (user_id);
create index if not exists idx_stories_created on public.stories (created_at desc);

-- ─────────────────────────────────────────────
-- 3) ELANLAR (Announcements — yalnız admin yaza bilər)
-- ─────────────────────────────────────────────
create table if not exists public.announcements (
  id bigint generated always as identity primary key,
  title text not null,
  content text not null,
  type text not null default 'info',
  created_at timestamptz not null default now()
);
create index if not exists idx_announcements_created on public.announcements (created_at desc);

-- ─────────────────────────────────────────────
-- 4) updated_at AVTOMATİK YENİLƏNMƏSİ
-- ─────────────────────────────────────────────
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_profiles_updated_at on public.profiles;
create trigger trg_profiles_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- ─────────────────────────────────────────────
-- 5) YENİ QEYDİYYATDA AVTOMATİK PROFİL YARADILMASI
--    (auth.users-ə yeni sətir daxil olanda tetiklənir)
-- ─────────────────────────────────────────────
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_username text;
  v_display_name text;
begin
  v_username := lower(coalesce(new.raw_user_meta_data->>'username', 'user_' || substr(new.id::text, 1, 8)));
  v_display_name := coalesce(new.raw_user_meta_data->>'display_name', v_username);

  -- əgər username formatı yanlışdırsa və ya artıq tutulubsa, unikal fallback yarat
  if v_username !~ '^[a-z0-9_]{3,20}$' or exists (select 1 from public.profiles p where p.username = v_username) then
    v_username := 'user_' || substr(new.id::text, 1, 8);
  end if;

  insert into public.profiles (id, username, display_name, xp, level, streak, learned, badges, role, last_visit)
  values (new.id, v_username, v_display_name, 0, 1, 0, '{}', '{}', 'user', null)
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ─────────────────────────────────────────────
-- 6) is_admin() KÖMƏKÇİ FUNKSİYASI (RLS siyasətlərində istifadə üçün)
--    SECURITY DEFINER ilə RLS-i bypass edərək sonsuz rekursiyanın qarşısını alır.
-- ─────────────────────────────────────────────
create or replace function public.is_admin(uid uuid)
returns boolean
language sql
security definer set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles where id = uid and role = 'admin'
  );
$$;

-- ─────────────────────────────────────────────
-- 7) is_username_taken() — qeydiyyat zamanı unikal ad yoxlanışı üçün
--    (RLS-i bypass edir, YALNIZ true/false qaytarır, heç bir data sızdırmır)
-- ─────────────────────────────────────────────
create or replace function public.is_username_taken(p_username text)
returns boolean
language sql
security definer set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles where username = lower(p_username)
  );
$$;

grant execute on function public.is_username_taken(text) to anon, authenticated;
grant execute on function public.is_admin(uuid) to authenticated;

-- ─────────────────────────────────────────────
-- 8) get_public_stats() — giriş ekranındakı ümumi statistikalar üçün
--    (heç bir fərdi istifadəçi datası açılmır, yalnız cəm ədədlər)
-- ─────────────────────────────────────────────
create or replace function public.get_public_stats()
returns json
language sql
security definer set search_path = public
stable
as $$
  select json_build_object(
    'users', (select count(*) from public.profiles),
    'stories', (select count(*) from public.stories)
  );
$$;

grant execute on function public.get_public_stats() to anon, authenticated;

-- ─────────────────────────────────────────────
-- 9) public_profiles VIEW — Liderborddan üçün TƏHLÜKƏSİZ, MƏHDUD sütunlu görünüş
--    (yalnız username/display_name/xp/level/streak — heç bir həssas sahə yoxdur)
-- ─────────────────────────────────────────────
-- QEYD: security_invoker QƏSDƏN true DEYİL (default buraxılır) — bu view
-- Liderbord üçün BÜTÜN istifadəçilərin (yalnız bu 5 sahəsini) göstərməlidir,
-- profiles cədvəlinin "yalnız öz sətrin" RLS qaydasını bu görünüşə tətbiq
-- etməməlidir. Görünüş yalnız bu 5 həssas olmayan sütunu ifşa edir.
-- [QURAŞDIRMA QEYDİ] public_profiles görünüşü sonrakı skriptlərdə genişlənir
-- (title, kosmetika sütunları). Faylı təkrar run edəndə daha dar tərif sütun
-- silməyə çalışıb "cannot drop columns from view" verirdi — ona görə əvvəlcə silinir.
-- Heç bir başqa obyekt bu görünüşdən asılı deyil (yoxlanılıb).
drop view if exists public.public_profiles;
create or replace view public.public_profiles as
  select username, display_name, xp, level, streak
  from public.profiles;

grant select on public.public_profiles to anon, authenticated;

-- ─────────────────────────────────────────────
-- 10) ROW LEVEL SECURITY — AKTİVLƏŞDİRMƏ
-- ─────────────────────────────────────────────
alter table public.profiles enable row level security;
alter table public.stories enable row level security;
alter table public.announcements enable row level security;

-- ---------- PROFILES siyasətləri ----------
drop policy if exists "profiles_select_own_or_admin" on public.profiles;
create policy "profiles_select_own_or_admin"
  on public.profiles for select
  to authenticated
  using (id = auth.uid() or public.is_admin(auth.uid()));

drop policy if exists "profiles_update_own_or_admin" on public.profiles;
create policy "profiles_update_own_or_admin"
  on public.profiles for update
  to authenticated
  using (id = auth.uid() or public.is_admin(auth.uid()))
  with check (
    id = auth.uid() and role = 'user' -- adi istifadəçi öz sətrini yeniləyə bilər, AMMA öz rolunu admin edə bilməz
    or public.is_admin(auth.uid())     -- admin istənilən sətri (rol daxil) yeniləyə bilər
  );

drop policy if exists "profiles_delete_own_or_admin" on public.profiles;
create policy "profiles_delete_own_or_admin"
  on public.profiles for delete
  to authenticated
  using (id = auth.uid() or public.is_admin(auth.uid()));

-- Qeyd: INSERT üçün ayrıca policy YOXDUR — profil sətri YALNIZ
-- handle_new_user() trigger-i vasitəsilə (SECURITY DEFINER) yaradılır,
-- beləliklə heç bir istifadəçi özü birbaşa saxta profil yarada bilməz.

-- ---------- STORIES siyasətləri ----------
drop policy if exists "stories_select_all_authenticated" on public.stories;
create policy "stories_select_all_authenticated"
  on public.stories for select
  to authenticated
  using (true); -- hekayələr icma ilə paylaşılır, hamı oxuya bilər

drop policy if exists "stories_insert_own" on public.stories;
create policy "stories_insert_own"
  on public.stories for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists "stories_update_own_or_admin" on public.stories;
create policy "stories_update_own_or_admin"
  on public.stories for update
  to authenticated
  using (user_id = auth.uid() or public.is_admin(auth.uid()));

drop policy if exists "stories_delete_own_or_admin" on public.stories;
create policy "stories_delete_own_or_admin"
  on public.stories for delete
  to authenticated
  using (user_id = auth.uid() or public.is_admin(auth.uid()));

-- ---------- ANNOUNCEMENTS siyasətləri ----------
drop policy if exists "announcements_select_all" on public.announcements;
create policy "announcements_select_all"
  on public.announcements for select
  to anon, authenticated
  using (true); -- elanlar hamı üçün açıqdır (login ekranında da göstərilə bilər)

drop policy if exists "announcements_write_admin_only" on public.announcements;
create policy "announcements_write_admin_only"
  on public.announcements for insert
  to authenticated
  with check (public.is_admin(auth.uid()));

drop policy if exists "announcements_update_admin_only" on public.announcements;
create policy "announcements_update_admin_only"
  on public.announcements for update
  to authenticated
  using (public.is_admin(auth.uid()));

drop policy if exists "announcements_delete_admin_only" on public.announcements;
create policy "announcements_delete_admin_only"
  on public.announcements for delete
  to authenticated
  using (public.is_admin(auth.uid()));

-- ════════════════════════════════════════════════════════════════
-- 11) İLK ADMİNİ TƏYİN ETMƏK (skripti işə saldıqdan sonra, əl ilə)
-- ════════════════════════════════════════════════════════════════
-- Əvvəlcə tətbiqdə normal qeydiyyatdan keçin, sonra aşağıdakı sətri
-- öz istifadəçi adınızla işə salın (yalnız SQL Editor-da, service_role
-- kontekstində RLS-i bypass edərək işləyir):
--
-- update public.profiles set role = 'admin' where username = 'BURAYA_ISTIFADECI_ADINIZI_YAZIN';
--
-- ════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════════
-- [02/25]  supabase_update_students.sql
-- Şagird sinif sistemi
-- ════════════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════
-- SözLab — Şagird Sinif Sistemi üçün əlavə SQL
-- Bu skripti Supabase Dashboard → SQL Editor-da açıb "Run" edin.
-- Mövcud cədvəlləri POZMUR, sadəcə yeni sütunlar əlavə edir və
-- handle_new_user() trigger-ini yeniləyir ki, qeydiyyatda daxil edilən
-- Ad/Soyad/Sinif məlumatları avtomatik profilə yazılsın.
-- ════════════════════════════════════════════════════════════════

-- 1) Yeni sütunlar: Ad, Soyad, Sinif (məs. "5B")
alter table public.profiles
  add column if not exists first_name text not null default '';
alter table public.profiles
  add column if not exists last_name text not null default '';
alter table public.profiles
  add column if not exists class_grade text not null default '';

-- Sinif formatını yoxlayan constraint (1-11 rəqəm + A/B/C/D hərfi, və ya boş —
-- mövcud istifadəçilər üçün geriyə uyğunluq saxlanılsın deyə boş qiymətə icazə verilir)
alter table public.profiles drop constraint if exists class_grade_format;
alter table public.profiles add constraint class_grade_format
  check (class_grade = '' or class_grade ~ '^(1[01]|[1-9])[A-D]$');

create index if not exists idx_profiles_class_grade on public.profiles (class_grade);

-- 2) handle_new_user() trigger-ini yenilə: indi first_name/last_name/class_grade də yazsın
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_username text;
  v_display_name text;
  v_first_name text;
  v_last_name text;
  v_class_grade text;
begin
  v_username := lower(coalesce(new.raw_user_meta_data->>'username', 'user_' || substr(new.id::text, 1, 8)));
  v_display_name := coalesce(new.raw_user_meta_data->>'display_name', v_username);
  v_first_name := coalesce(new.raw_user_meta_data->>'first_name', '');
  v_last_name := coalesce(new.raw_user_meta_data->>'last_name', '');
  v_class_grade := coalesce(new.raw_user_meta_data->>'class_grade', '');

  -- əgər username formatı yanlışdırsa və ya artıq tutulubsa, unikal fallback yarat
  if v_username !~ '^[a-z0-9_]{3,20}$' or exists (select 1 from public.profiles p where p.username = v_username) then
    v_username := 'user_' || substr(new.id::text, 1, 8);
  end if;

  -- sinif formatı yanlışdırsa sakitcə boş buraxılır (constraint pozulmasın deyə)
  if v_class_grade !~ '^(1[01]|[1-9])[A-D]$' then
    v_class_grade := '';
  end if;

  insert into public.profiles (id, username, display_name, first_name, last_name, class_grade, xp, level, streak, learned, badges, role, last_visit)
  values (new.id, v_username, v_display_name, v_first_name, v_last_name, v_class_grade, 0, 1, 0, '{}', '{}', 'user', null)
  on conflict (id) do nothing;

  return new;
end;
$$;

-- ════════════════════════════════════════════════════════════════
-- QEYD: first_name/last_name/class_grade QƏSDƏN public_profiles
-- görünüşünə (liderbord üçün istifadə olunur) ƏLAVƏ EDİLMİR — real
-- ad/soyad və sinif məlumatı bütün saytda hamıya açıq olmamalıdır,
-- yalnız admin panelində (birbaşa profiles cədvəlindən, mövcud RLS
-- "own row or admin" qaydası ilə) görünəcək.
-- ════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════════
-- [03/25]  supabase_update_teacher_and_league.sql
-- Müəllim paneli + sinif liqası (is_teacher_of)
-- ════════════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════
-- SözLab — Müəllim Paneli + Sinif Liqası üçün əlavə SQL
-- Bu skripti Supabase Dashboard → SQL Editor-da açıb "Run" edin.
-- Mövcud cədvəlləri POZMUR, sadəcə yeni sütun/rol/görünüş əlavə edir.
-- ÖNCƏ supabase_update_students.sql skriptinin run edildiyini fərz edir
-- (class_grade sütunu artıq mövcud olmalıdır).
-- ════════════════════════════════════════════════════════════════

-- 1) role sütununa 'teacher' dəyərini əlavə et (mövcud constraint-i genişləndirir)
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  check (role in ('user','admin','teacher'));

-- 2) Müəllimin hansı sinfə təyin olunduğunu saxlayan sütun (məs. "10B")
alter table public.profiles
  add column if not exists teacher_class text not null default '';

create index if not exists idx_profiles_teacher_class on public.profiles (teacher_class);

-- 3) is_teacher_of() — RLS siyasətində istifadə üçün, SECURITY DEFINER ilə
--    RLS-i bypass edərək sonsuz rekursiyanın qarşısını alır (is_admin() ilə eyni məntiq).
create or replace function public.is_teacher_of(uid uuid, cls text)
returns boolean
language sql
security definer set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = uid and role = 'teacher' and teacher_class = cls and cls <> ''
  );
$$;

grant execute on function public.is_teacher_of(uuid, text) to authenticated;

-- 4) profiles SELECT siyasətini yenilə: indi müəllim öz sinfinin şagirdlərini
--    də görə bilsin (yalnız oxumaq — UPDATE/DELETE hüququ verilmir).
drop policy if exists "profiles_select_own_or_admin" on public.profiles;
create policy "profiles_select_own_or_admin"
  on public.profiles for select
  to authenticated
  using (
    id = auth.uid()
    or public.is_admin(auth.uid())
    or (class_grade <> '' and public.is_teacher_of(auth.uid(), class_grade))
  );

-- 5) SİNİF LİQASI — yalnız toplu/anonimləşdirilmiş rəqəmlər, heç bir şəxsi
--    ad, username və ya digər fərdi məlumat açıqlanmır (məxfilik qorunur).
create or replace view public.class_leaderboard as
  select
    class_grade,
    count(*) as student_count,
    sum(xp) as total_xp,
    round(avg(xp)) as avg_xp,
    max(streak) as top_streak
  from public.profiles
  where class_grade <> ''
  group by class_grade
  order by total_xp desc;

grant select on public.class_leaderboard to anon, authenticated;

-- ════════════════════════════════════════════════════════════════
-- QEYD: Müəllim rolunu təyin etmək üçün Admin Panel → İstifadəçilər
-- bölməsində müvafiq şəxsin yanındakı "👨‍🏫 Müəllim et" düyməsini basıb
-- sinif daxil edin (məs. 10B). Əl ilə etmək istəsəniz:
--
-- update public.profiles set role='teacher', teacher_class='10B'
--   where username='BURAYA_ISTIFADECI_ADINIZI_YAZIN';
-- ════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════════
-- [04/25]  supabase_update_director_and_tasks.sql
-- Direktor rolu (is_director) + müəllim tapşırıqları
-- ════════════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════
-- SözLab — Direktor rolu + Müəllim Tapşırıqları üçün əlavə SQL
-- Bu skripti Supabase Dashboard → SQL Editor-da açıb "Run" edin.
-- Mövcud cədvəlləri POZMUR. ÖNCƏ bu iki skriptin run edildiyini fərz edir:
--   1) supabase_update_students.sql   (class_grade sütunu)
--   2) supabase_update_teacher_and_league.sql  (teacher_class, is_teacher_of())
-- ════════════════════════════════════════════════════════════════

-- 1) role sütununa 'director' dəyərini əlavə et
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  check (role in ('user','admin','teacher','director'));

-- 2) is_director() — RLS siyasətlərində istifadə üçün, SECURITY DEFINER ilə
--    RLS-i bypass edərək sonsuz rekursiyanın qarşısını alır (is_admin() ilə eyni məntiq).
create or replace function public.is_director(uid uuid)
returns boolean
language sql
security definer set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles where id = uid and role = 'director'
  );
$$;

grant execute on function public.is_director(uuid) to authenticated;

-- 3) ÖZ SƏTRİNİ ROL ESKALASİYASINDAN QORUYAN TRİGGER
--    (RLS WITH CHECK əvəzinə trigger istifadə edirik ki, teacher/director öz XP-sini,
--    streak-ini, adını s. dəyişə bilsin — sadəcə ÖZ rolunu/sinfini dəyişə bilməsin.)
create or replace function public.prevent_self_role_escalation()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if auth.uid() = old.id and not public.is_admin(auth.uid()) and not public.is_director(auth.uid()) then
    new.role := old.role;
    new.teacher_class := old.teacher_class;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_self_role_escalation on public.profiles;
create trigger trg_prevent_self_role_escalation
  before update on public.profiles
  for each row execute function public.prevent_self_role_escalation();

-- 4) PROFİLLƏR RLS siyasətlərini yenilə:
--    SELECT — direktor hamını görür (admin daxil).
--    UPDATE/DELETE — direktor admin XARİC hər kəsi dəyişə/silə bilər.
--    (Köhnə "id=auth.uid() and role='user'" WITH CHECK şərti silinir, çünki artıq
--    rol-eskalasiya qorunması yuxarıdakı trigger ilə edilir — əks halda teacher/director
--    öz XP-sini belə yeniləyə bilməzdi.)
drop policy if exists "profiles_select_own_or_admin" on public.profiles;
create policy "profiles_select_own_or_admin"
  on public.profiles for select
  to authenticated
  using (
    id = auth.uid()
    or public.is_admin(auth.uid())
    or public.is_director(auth.uid())
    or (class_grade <> '' and public.is_teacher_of(auth.uid(), class_grade))
  );

drop policy if exists "profiles_update_own_or_admin" on public.profiles;
create policy "profiles_update_own_or_admin"
  on public.profiles for update
  to authenticated
  using (
    id = auth.uid()
    or public.is_admin(auth.uid())
    or (public.is_director(auth.uid()) and role <> 'admin')
  )
  with check (
    id = auth.uid()
    or public.is_admin(auth.uid())
    or (public.is_director(auth.uid()) and role <> 'admin')
  );

drop policy if exists "profiles_delete_own_or_admin" on public.profiles;
create policy "profiles_delete_own_or_admin"
  on public.profiles for delete
  to authenticated
  using (
    id = auth.uid()
    or public.is_admin(auth.uid())
    or (public.is_director(auth.uid()) and role <> 'admin')
  );

-- 5) Direktora elan (announcement) və hekayə moderasiyası səlahiyyəti də verilir
--    (məktəb rəhbərliyi bunları idarə edə bilməlidir; söz bankı YOX — bu admin-ə məxsus qalır).
drop policy if exists "announcements_write_admin_only" on public.announcements;
create policy "announcements_write_admin_only"
  on public.announcements for insert
  to authenticated
  with check (public.is_admin(auth.uid()) or public.is_director(auth.uid()));

drop policy if exists "announcements_update_admin_only" on public.announcements;
create policy "announcements_update_admin_only"
  on public.announcements for update
  to authenticated
  using (public.is_admin(auth.uid()) or public.is_director(auth.uid()));

drop policy if exists "announcements_delete_admin_only" on public.announcements;
create policy "announcements_delete_admin_only"
  on public.announcements for delete
  to authenticated
  using (public.is_admin(auth.uid()) or public.is_director(auth.uid()));

drop policy if exists "stories_update_own_or_admin" on public.stories;
create policy "stories_update_own_or_admin"
  on public.stories for update
  to authenticated
  using (user_id = auth.uid() or public.is_admin(auth.uid()) or public.is_director(auth.uid()));

drop policy if exists "stories_delete_own_or_admin" on public.stories;
create policy "stories_delete_own_or_admin"
  on public.stories for delete
  to authenticated
  using (user_id = auth.uid() or public.is_admin(auth.uid()) or public.is_director(auth.uid()));

-- ─────────────────────────────────────────────
-- 6) MÜƏLLİM TAPŞIRIQLARI (class_tasks + class_task_completions)
-- ─────────────────────────────────────────────
create table if not exists public.class_tasks (
  id bigint generated always as identity primary key,
  teacher_username text not null,
  class_grade text not null check (class_grade ~ '^(1[01]|[1-9])[A-D]$'),
  title text not null check (char_length(title) between 1 and 200),
  target_xp integer not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists idx_class_tasks_class on public.class_tasks (class_grade, created_at desc);

create table if not exists public.class_task_completions (
  task_id bigint not null references public.class_tasks(id) on delete cascade,
  username text not null,
  completed_at timestamptz not null default now(),
  primary key (task_id, username)
);

alter table public.class_tasks enable row level security;
alter table public.class_task_completions enable row level security;

-- class_tasks: görmə hüququ — admin, direktor, tapşırığı yaradan müəllim, və ya
-- həmin sinifdəki şagirdlər. Yazma/silmə — YALNIZ admin, direktor, ya da o sinfin müəllimi.
drop policy if exists "class_tasks_select" on public.class_tasks;
create policy "class_tasks_select"
  on public.class_tasks for select
  to authenticated
  using (
    public.is_admin(auth.uid())
    or public.is_director(auth.uid())
    or public.is_teacher_of(auth.uid(), class_grade)
    or exists(select 1 from public.profiles p where p.id = auth.uid() and p.class_grade = class_tasks.class_grade)
  );

drop policy if exists "class_tasks_insert" on public.class_tasks;
create policy "class_tasks_insert"
  on public.class_tasks for insert
  to authenticated
  with check (
    public.is_admin(auth.uid())
    or public.is_director(auth.uid())
    or public.is_teacher_of(auth.uid(), class_grade)
  );

drop policy if exists "class_tasks_delete" on public.class_tasks;
create policy "class_tasks_delete"
  on public.class_tasks for delete
  to authenticated
  using (
    public.is_admin(auth.uid())
    or public.is_director(auth.uid())
    or public.is_teacher_of(auth.uid(), class_grade)
  );

-- class_task_completions: görmə hüququ eyni qayda ilə (müəllim/admin/direktor,
-- ya da öz tamamlama qeydini görən şagirdin özü). Yazma — YALNIZ öz adına.
drop policy if exists "class_task_completions_select" on public.class_task_completions;
create policy "class_task_completions_select"
  on public.class_task_completions for select
  to authenticated
  using (
    public.is_admin(auth.uid())
    or public.is_director(auth.uid())
    or exists(select 1 from public.profiles p where p.id = auth.uid() and p.username = class_task_completions.username)
    or exists(
      select 1 from public.class_tasks t
      where t.id = class_task_completions.task_id
        and public.is_teacher_of(auth.uid(), t.class_grade)
    )
  );

drop policy if exists "class_task_completions_insert" on public.class_task_completions;
create policy "class_task_completions_insert"
  on public.class_task_completions for insert
  to authenticated
  with check (
    exists(select 1 from public.profiles p where p.id = auth.uid() and p.username = class_task_completions.username)
  );

-- ════════════════════════════════════════════════════════════════
-- QEYD 1: Direktor rolunu təyin etmək (bunun üçün UI düyməsi YOXDUR —
-- admin/direktor yaratmaq YALNIZ birbaşa SQL ilə edilir, təhlükəsizlik üçün):
--
-- update public.profiles set role='director'
--   where username='BURAYA_ISTIFADECI_ADINIZI_YAZIN';
--
-- QEYD 2: Direktor "🛠️ Admin" nişanlı istifadəçilərə TOXUNA BİLMİR (RLS server
-- tərəfdə bloklayır, admin panelində "🔒 Admin — redaktə edilə bilməz" göstərilir),
-- amma onları siyahıda GÖRƏ BİLİR. Söz bankı (Sözlər tabı) YALNIZ admin üçündür.
-- ════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════════
-- [05/25]  supabase_update_titles.sql
-- Oyunçu ünvanları
-- ════════════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════
-- SözLab — Oyunçu Ünvanları (Player Titles) üçün əlavə SQL
-- Bu skripti Supabase Dashboard → SQL Editor-da açıb "Run" edin.
-- Mövcud cədvəlləri POZMUR, sadəcə yeni sütun əlavə edir.
-- ════════════════════════════════════════════════════════════════

-- 1) Yeni sütun: fərqli fəal günlərin sayı (streak-dən fərqli olaraq
--    bir gün buraxılsa belə sıfırlanmır — ünvan sistemi bunun üzərində qurulub)
alter table public.profiles
  add column if not exists days_active integer not null default 0;

-- 2) Mövcud istifadəçilər üçün başlanğıc dəyər (streak-ə əsasən təxmini backfill,
--    heç kimin ünvanı geriyə getməsin deyə)
update public.profiles
  set days_active = greatest(streak, 0)
  where days_active = 0;

-- 3) Liderbordda ünvanların düzgün görünməsi üçün public_profiles görünüşünü yenilə
create or replace view public.public_profiles as
  select username, display_name, xp, level, streak, days_active
  from public.profiles;

grant select on public.public_profiles to anon, authenticated;

-- ════════════════════════════════════════════════════════════════
-- Bundan sonra "Peşəkar" və "Əfsanə" kimi ən yüksək ünvanlar YALNIZ
-- kifayət qədər XP TOPLAYIB, eyni zamanda günlərlə davamlı oynayan
-- istifadəçilərə açılacaq — tək sessiyada (1-2 saat) mümkün deyil.
-- ════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════════
-- [06/25]  supabase_update_cosmetics.sql
-- Döyüş bileti / kosmetika
-- ════════════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════
-- SözLab — "Döyüş Bileti" (Battle Pass) — DAİMİ, itməyən kosmetik
-- çərçivə/tema sistemi. Bu skripti Supabase Dashboard → SQL Editor-da
-- açıb "Run" edin. Mövcud cədvəlləri POZMUR.
--
-- QƏSDƏN "mövsümlük"/vaxt-təzyiqli DEYİL: real oyunlardakı Battle Pass-lar
-- adətən mövsüm bitəndə əldə edilməyən mükafatı həmişəlik itirir (FOMO
-- yaradır) — məktəb kontekstində bu, zəif/yavaş öyrənən şagirdi
-- demotivasiya edə bilər. Ona görə burda hər kosmetik element sadəcə
-- ÜMUMİ XP həddinə görə açılır və BİR DƏFƏ açılandan sonra HEÇ VAXT
-- itmir — "Ünvan" (TITLES) sistemi ilə eyni fəlsəfə.
-- ════════════════════════════════════════════════════════════════

-- 1) KATALOQ CƏDVƏLİ — həm frontend, həm backend RPC eyni mənbədən oxuyur
--    ki, "neçə XP-də nə açılır" məlumatı İKİ yerdə (JS + SQL) təkrarlanıb
--    bir-birindən aralı düşməsin.
create table if not exists public.cosmetics_catalog (
  id text primary key,
  type text not null check (type in ('frame','theme')),
  name text not null,
  icon text not null default '',
  min_xp integer not null default 0,
  sort_order integer not null default 0
);

insert into public.cosmetics_catalog(id,type,name,icon,min_xp,sort_order) values
  ('frame_none','frame','Sadə','',0,0),
  ('frame_bronze','frame','Bürünc Çərçivə','🥉',200,1),
  ('frame_silver','frame','Gümüş Çərçivə','🥈',800,2),
  ('frame_gold','frame','Qızıl Çərçivə','🥇',2000,3),
  ('frame_diamond','frame','Almaz Çərçivə','💎',5000,4),
  ('theme_default','theme','Standart Tema','',0,0),
  ('theme_sunset','theme','Gün Batımı','🌇',500,1),
  ('theme_ocean','theme','Okean','🌊',1500,2),
  ('theme_neon','theme','Neon','⚡',3500,3)
on conflict (id) do nothing;

alter table public.cosmetics_catalog enable row level security;

drop policy if exists "cosmetics_catalog_select" on public.cosmetics_catalog;
create policy "cosmetics_catalog_select"
  on public.cosmetics_catalog for select
  to anon, authenticated
  using (true);

-- QEYD: insert/update/delete siyasəti YOXDUR — kataloqu genişləndirmək
-- lazım gələrsə, Supabase Dashboard → Table Editor-dan admin əl ilə əlavə edir.

-- 2) PROFİLƏ İKİ YENİ SÜTUN — hazırda taxılmış çərçivə/tema.
alter table public.profiles add column if not exists equipped_frame text not null default 'frame_none';
alter table public.profiles add column if not exists equipped_theme text not null default 'theme_default';

-- 3) equip_cosmetic() — YALNIZ XP həddinə çatmış istifadəçi bir elementi
--    taxa bilər. Bunu RPC ilə (birbaşa profiles update yerinə) etməyimizin
--    səbəbi: əks halda bir şagird brauzer konsolundan `equipped_frame`
--    sahəsini birbaşa dəyişib hələ açmadığı bir çərçivəni "saxta" taxa bilərdi.
create or replace function public.equip_cosmetic(p_cosmetic_id text)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_xp integer;
  v_cat record;
begin
  select xp into v_xp from public.profiles where id = auth.uid();
  if v_xp is null then
    raise exception 'Profil tapılmadı';
  end if;

  select * into v_cat from public.cosmetics_catalog where id = p_cosmetic_id;
  if v_cat is null then
    raise exception 'Naməlum kosmetik element';
  end if;
  if v_xp < v_cat.min_xp then
    raise exception 'Bu elementi hələ açmamısınız (lazımi XP: %)', v_cat.min_xp;
  end if;

  if v_cat.type = 'frame' then
    update public.profiles set equipped_frame = p_cosmetic_id where id = auth.uid();
  else
    update public.profiles set equipped_theme = p_cosmetic_id where id = auth.uid();
  end if;
end;
$$;

grant execute on function public.equip_cosmetic(text) to authenticated;
grant select on public.cosmetics_catalog to anon, authenticated;

-- 4) public_profiles görünüşünə çərçivə/tema sütunlarını əlavə edirik ki,
--    liderbordda da (gələcəkdə istəsək) başqalarının çərçivəsi görünə bilsin.
create or replace view public.public_profiles as
  select username, display_name, xp, level, streak, days_active, equipped_frame, equipped_theme
  from public.profiles;

grant select on public.public_profiles to anon, authenticated;


-- ════════════════════════════════════════════════════════════════════════
-- [07/25]  supabase_update_newsletter.sql
-- Bülleten qutusu
-- ════════════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════
-- SözLab — Giriş ekranındakı footer-dəki "Yeniliklərdən xəbərdar olun"
-- bülleten qutusu üçün. Bu skripti Supabase Dashboard → SQL Editor-da
-- açıb "Run" edin.
--
-- Qeyd: bu, HEÇ BİR şəxsi məlumatla (profillə) bağlı deyil — sadəcə
-- giriş etməmiş bir ziyarətçinin könüllü buraxdığı e-poçtu saxlayır.
-- Yalnız admin bu siyahını görə bilər (Supabase Dashboard → Table
-- Editor → newsletter_signups, və ya SQL Editor-da sorğu ilə).
-- ════════════════════════════════════════════════════════════════

create table if not exists public.newsletter_signups (
  id bigint generated always as identity primary key,
  email text not null,
  created_at timestamptz not null default now()
);
create unique index if not exists idx_newsletter_email on public.newsletter_signups (lower(email));

alter table public.newsletter_signups enable row level security;

-- Giriş etməmiş (anon) VƏ giriş etmiş hər kəs öz e-poçtunu əlavə edə bilər —
-- amma yalnız insert, heç kim (admin xaric) siyahını oxuya/silə bilməz.
drop policy if exists "newsletter_insert_public" on public.newsletter_signups;
create policy "newsletter_insert_public"
  on public.newsletter_signups for insert
  to anon, authenticated
  with check (
    email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
    and length(email) < 200
  );

drop policy if exists "newsletter_select_admin" on public.newsletter_signups;
create policy "newsletter_select_admin"
  on public.newsletter_signups for select
  to authenticated
  using (public.is_admin(auth.uid()));


-- ════════════════════════════════════════════════════════════════════════
-- [08/25]  supabase_update_features_batch2.sql
-- Dəvət, analitika, zəif sözlər (compute_level, log_xp_gain)
-- ════════════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════
-- SözLab — Dəvət Sistemi + Şəxsi Analitika + Zəif Sözlər + İmtahan
-- Simulyasiyası üçün əlavə SQL.
-- Bu skripti Supabase Dashboard → SQL Editor-da açıb "Run" edin.
-- Mövcud cədvəlləri POZMUR, sadəcə yeni sütun/cədvəl/funksiya əlavə edir.
-- ÖNCƏ bütün əvvəlki SQL skriptlərinin (titles, students, teacher_and_league,
-- director_and_tasks) run edildiyini fərz edir.
-- ════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────
-- 1) YENİ SÜTUNLAR (profiles)
-- ─────────────────────────────────────────────
alter table public.profiles add column if not exists weak_words jsonb not null default '{}'::jsonb;
alter table public.profiles add column if not exists games_played jsonb not null default '{}'::jsonb;
alter table public.profiles add column if not exists longest_streak integer not null default 0;
alter table public.profiles add column if not exists referred_by text not null default '';

-- Mövcud istifadəçilər üçün ən uzun seriyanın geriyə doğru təxmini backfill-i
-- (heç kimin "ən uzun seriya" göstəricisi indiki seriyasından az görünməsin deyə)
update public.profiles set longest_streak = streak where longest_streak < streak;

-- ─────────────────────────────────────────────
-- 2) SƏVİYYƏ HESABLAMA KÖMƏKÇİSİ (yalnız serverdə, dəvət bonusu üçün lazımdır)
--    Client tərəfdəki levelFromXP(xp) funksiyası ilə EYNİ məntiq: hər səviyyə
--    l*100 XP tələb edir, kumulyativ şəkildə.
-- ─────────────────────────────────────────────
create or replace function public.compute_level(p_xp integer)
returns integer
language plpgsql
immutable
as $$
declare
  l integer := 1;
  remaining integer := greatest(p_xp,0);
begin
  while remaining >= l*100 loop
    remaining := remaining - l*100;
    l := l + 1;
  end loop;
  return l;
end;
$$;

-- ─────────────────────────────────────────────
-- 3) handle_new_user() TRIGGER-İNİ YENİLƏ — indi referral bonusunu da idarə edir.
--    Yeni istifadəçi düzgün mövcud username-i "dəvət kodu" kimi yazıbsa (özü
--    deyil), hər ikisinə +20 XP verilir. Dəvət kodu YANLIŞ/BOŞ olsa, sakitcə
--    0 bonusla davam edir (qeydiyyat pozulmur).
-- ─────────────────────────────────────────────
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_username text;
  v_display_name text;
  v_first_name text;
  v_last_name text;
  v_class_grade text;
  v_referred_by text;
  v_bonus_xp integer := 0;
begin
  v_username := lower(coalesce(new.raw_user_meta_data->>'username', 'user_' || substr(new.id::text, 1, 8)));
  v_display_name := coalesce(new.raw_user_meta_data->>'display_name', v_username);
  v_first_name := coalesce(new.raw_user_meta_data->>'first_name', '');
  v_last_name := coalesce(new.raw_user_meta_data->>'last_name', '');
  v_class_grade := coalesce(new.raw_user_meta_data->>'class_grade', '');
  v_referred_by := lower(coalesce(new.raw_user_meta_data->>'referred_by', ''));

  if v_username !~ '^[a-z0-9_]{3,20}$' or exists (select 1 from public.profiles p where p.username = v_username) then
    v_username := 'user_' || substr(new.id::text, 1, 8);
  end if;

  if v_class_grade !~ '^(1[01]|[1-9])[A-D]$' then
    v_class_grade := '';
  end if;

  -- Dəvət kodu = dəvət edənin username-i. Özünə istinad və mövcud olmayan
  -- kodlar sakitcə görməzdən gəlinir (constraint pozulmasın, xəta çıxmasın deyə).
  if v_referred_by <> '' and v_referred_by <> v_username and exists(select 1 from public.profiles p where p.username = v_referred_by) then
    v_bonus_xp := 20;
    update public.profiles
      set xp = xp + 20, level = public.compute_level(xp + 20)
      where username = v_referred_by;
  else
    v_referred_by := '';
  end if;

  insert into public.profiles (id, username, display_name, first_name, last_name, class_grade, xp, level, streak, learned, badges, role, last_visit, referred_by)
  values (new.id, v_username, v_display_name, v_first_name, v_last_name, v_class_grade, v_bonus_xp, public.compute_level(v_bonus_xp), 0, '{}', '{}', 'user', null, v_referred_by)
  on conflict (id) do nothing;

  return new;
end;
$$;

-- ─────────────────────────────────────────────
-- 4) GÜNDƏLİK XP JURNALI (Şəxsi Analitikadakı "son 14 gün" qrafiki üçün)
-- ─────────────────────────────────────────────
create table if not exists public.xp_log (
  username text not null,
  log_date date not null,
  xp_gained integer not null default 0,
  primary key (username, log_date)
);

alter table public.xp_log enable row level security;

drop policy if exists "xp_log_select" on public.xp_log;
create policy "xp_log_select"
  on public.xp_log for select
  to authenticated
  using (
    exists(select 1 from public.profiles p where p.id = auth.uid() and p.username = xp_log.username)
    or public.is_admin(auth.uid())
    or public.is_director(auth.uid())
  );
-- QEYD: insert/update siyasəti YOXDUR — yeganə yazma yolu aşağıdakı
-- log_xp_gain() SECURITY DEFINER funksiyasıdır, o RLS-i bypass edir.

create or replace function public.log_xp_gain(p_username text, p_date date, p_amount integer)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if p_amount is null or p_amount <= 0 then return; end if;
  insert into public.xp_log(username, log_date, xp_gained)
  values (p_username, p_date, p_amount)
  on conflict (username, log_date) do update set xp_gained = xp_log.xp_gained + excluded.xp_gained;
end;
$$;

grant execute on function public.log_xp_gain(text,date,integer) to authenticated;

-- ════════════════════════════════════════════════════════════════
-- QEYD: Zəif Sözlərin Təkrarlanması (weak_words) və İmtahan Simulyasiyası
-- heç bir yeni cədvəl/RLS tələb etmir — ikisi də mövcud profiles.weak_words
-- sütunundan və mövcud söz banklarından (WORDS/AZ_WORDS) işləyir, yalnız
-- frontend məntiqidir.
-- ════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════════
-- [09/25]  supabase_update_duel.sql
-- Canlı duel (1v1)
-- ════════════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════
-- SözLab — Canlı Duel (1v1) üçün əlavə SQL.
-- Bu skripti Supabase Dashboard → SQL Editor-da açıb "Run" edin.
-- Mövcud cədvəlləri POZMUR, sadəcə yeni cədvəl/funksiya əlavə edir.
-- ÖNCƏ bütün əvvəlki SQL skriptlərinin run edildiyini fərz edir
-- (xüsusilə supabase_update_features_batch2.sql — compute_level() funksiyası
-- buradan istifadə olunur).
-- ════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────
-- 1) DUELS CƏDVƏLİ
--    Hər iki oyunçu EYNİ sual dəstini öz sürəti ilə cavablandırır (yarış
--    rejimi). Bütün vəziyyət dəyişiklikləri YALNIZ aşağıdakı SECURITY
--    DEFINER funksiyaları vasitəsilə edilir — cədvələ birbaşa
--    insert/update icazəsi YOXDUR (yalnız select).
-- ─────────────────────────────────────────────
create table if not exists public.duels (
  id bigint generated always as identity primary key,
  p1_username text not null,
  p2_username text not null,
  status text not null default 'pending' check (status in ('pending','active','declined','finished')),
  questions jsonb not null,
  p1_score integer not null default 0,
  p1_progress integer not null default 0,
  p1_finished_at timestamptz,
  p2_score integer not null default 0,
  p2_progress integer not null default 0,
  p2_finished_at timestamptz,
  winner_username text,
  xp_awarded boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists idx_duels_p1 on public.duels (p1_username, created_at desc);
create index if not exists idx_duels_p2 on public.duels (p2_username, created_at desc);

alter table public.duels enable row level security;

-- SELECT — yalnız duelin iki tərəfi, ya da admin/direktor görə bilər.
drop policy if exists "duels_select" on public.duels;
create policy "duels_select"
  on public.duels for select
  to authenticated
  using (
    exists(select 1 from public.profiles p where p.id = auth.uid() and (p.username = duels.p1_username or p.username = duels.p2_username))
    or public.is_admin(auth.uid())
    or public.is_director(auth.uid())
  );

-- QEYD: insert/update/delete siyasəti QƏSDƏN yoxdur — bütün yazma
-- əməliyyatları aşağıdakı üç SECURITY DEFINER funksiyası ilə edilir ki,
-- oyunçular öz XP-lərini və ya nəticəni birbaşa dəyişə bilməsinlər.

-- ─────────────────────────────────────────────
-- 1b) "Sürətli Düello" (reflex) rejimi üçün əlavə sütun.
--     Bu, ayrı bir infrastruktur (WebRTC/P2P) YOXDUR — eyni duels
--     cədvəli/RPC-ləri üzərində işləyir, sadəcə klient tərəfdə hər
--     suala qısa taymer qoyur və rəqib zolağını daha tez yeniləyir
--     ("tənəffüs turniri" hissini P2P-nin mürəkkəbliyi/kövrəkliyi
--     olmadan verir).
-- ─────────────────────────────────────────────
alter table public.duels add column if not exists mode text not null default 'normal';
alter table public.duels drop constraint if exists duels_mode_check;
alter table public.duels add constraint duels_mode_check check (mode in ('normal','sureli'));

-- ─────────────────────────────────────────────
-- 2) create_duel() — çağırış göndərmək
--    Köhnə 2-arqumentli overload-u qəsdən silirik ki, Supabase RPC
--    çağırışında iki funksiya arasında qeyri-müəyyənlik yaranmasın.
-- ─────────────────────────────────────────────
drop function if exists public.create_duel(text, jsonb);

create or replace function public.create_duel(p_opponent_username text, p_questions jsonb, p_mode text default 'normal')
returns bigint
language plpgsql
security definer set search_path = public
as $$
declare
  v_username text;
  v_opponent text := lower(p_opponent_username);
  v_mode text := coalesce(p_mode, 'normal');
  v_id bigint;
begin
  select username into v_username from public.profiles where id = auth.uid();
  if v_username is null then
    raise exception 'Profil tapılmadı';
  end if;
  if v_opponent = v_username then
    raise exception 'Özünüzə duel göndərə bilməzsiniz';
  end if;
  if not exists(select 1 from public.profiles where username = v_opponent) then
    raise exception 'İstifadəçi tapılmadı';
  end if;
  if jsonb_typeof(p_questions) <> 'array' or jsonb_array_length(p_questions) < 1 or jsonb_array_length(p_questions) > 20 then
    raise exception 'Yanlış sual formatı';
  end if;
  if v_mode not in ('normal','sureli') then
    raise exception 'Yanlış rejim';
  end if;

  insert into public.duels(p1_username, p2_username, questions, status, mode)
  values (v_username, v_opponent, p_questions, 'pending', v_mode)
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function public.create_duel(text, jsonb, text) to authenticated;

-- ─────────────────────────────────────────────
-- 3) respond_duel() — çağırışı qəbul/rədd etmək (yalnız p2 çağıra bilər)
-- ─────────────────────────────────────────────
create or replace function public.respond_duel(p_duel_id bigint, p_accept boolean)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_username text;
begin
  select username into v_username from public.profiles where id = auth.uid();
  update public.duels
    set status = case when p_accept then 'active' else 'declined' end
    where id = p_duel_id and p2_username = v_username and status = 'pending';
end;
$$;

grant execute on function public.respond_duel(bigint, boolean) to authenticated;

-- ─────────────────────────────────────────────
-- 4) submit_duel_answer() — sual cavablandırıldıqda çağırılır.
--    Xalı/irəliləyişi atomik yeniləyir; hər iki tərəf bitirəndə qalibi
--    müəyyən edir və XP-ni birbaşa hər iki profilə (server tərəfdə,
--    referral bonusundakı kimi) yazır. "for update" sətir kilidi eyni
--    duelə iki paralel sorğunun toqquşmasının qarşısını alır.
-- ─────────────────────────────────────────────
create or replace function public.submit_duel_answer(p_duel_id bigint, p_correct boolean)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_username text;
  v_duel record;
  v_is_p1 boolean;
  v_total_q integer;
  v_winner text;
  v_xp_p1 integer;
  v_xp_p2 integer;
begin
  select username into v_username from public.profiles where id = auth.uid();
  select * into v_duel from public.duels where id = p_duel_id for update;
  if v_duel is null then return; end if;
  if v_duel.status <> 'active' then return; end if;

  if v_duel.p1_username = v_username then v_is_p1 := true;
  elsif v_duel.p2_username = v_username then v_is_p1 := false;
  else return; end if;

  v_total_q := jsonb_array_length(v_duel.questions);

  if v_is_p1 then
    if v_duel.p1_finished_at is not null then return; end if;
    update public.duels set
      p1_score = p1_score + (case when p_correct then 1 else 0 end),
      p1_progress = p1_progress + 1
    where id = p_duel_id;
  else
    if v_duel.p2_finished_at is not null then return; end if;
    update public.duels set
      p2_score = p2_score + (case when p_correct then 1 else 0 end),
      p2_progress = p2_progress + 1
    where id = p_duel_id;
  end if;

  select * into v_duel from public.duels where id = p_duel_id for update;

  if v_is_p1 and v_duel.p1_progress >= v_total_q and v_duel.p1_finished_at is null then
    update public.duels set p1_finished_at = now() where id = p_duel_id;
  elsif not v_is_p1 and v_duel.p2_progress >= v_total_q and v_duel.p2_finished_at is null then
    update public.duels set p2_finished_at = now() where id = p_duel_id;
  end if;

  select * into v_duel from public.duels where id = p_duel_id for update;

  if v_duel.p1_finished_at is not null and v_duel.p2_finished_at is not null and v_duel.status = 'active' then
    if v_duel.p1_score > v_duel.p2_score then v_winner := v_duel.p1_username;
    elsif v_duel.p2_score > v_duel.p1_score then v_winner := v_duel.p2_username;
    else v_winner := null;
    end if;

    if v_winner is null then
      v_xp_p1 := 20; v_xp_p2 := 20;
    elsif v_winner = v_duel.p1_username then
      v_xp_p1 := 30; v_xp_p2 := 10;
    else
      v_xp_p1 := 10; v_xp_p2 := 30;
    end if;

    update public.profiles set xp = xp + v_xp_p1, level = public.compute_level(xp + v_xp_p1) where username = v_duel.p1_username;
    update public.profiles set xp = xp + v_xp_p2, level = public.compute_level(xp + v_xp_p2) where username = v_duel.p2_username;
    -- xp_log-a da yazırıq ki, "Ayın Söz Ustası" sertifikatı və şəxsi 14-günlük
    -- qrafik duel qazanclarını da düzgün hesablasın (əvvəllər YALNIZ client-trusted
    -- addXP() yolları buraya yazırdı, RPC-əsaslı qazanclar hesaba düşmürdü).
    perform public.log_xp_gain(v_duel.p1_username, (now() at time zone 'UTC')::date, v_xp_p1);
    perform public.log_xp_gain(v_duel.p2_username, (now() at time zone 'UTC')::date, v_xp_p2);

    update public.duels set status = 'finished', winner_username = v_winner, xp_awarded = true where id = p_duel_id;
  end if;
end;
$$;

grant execute on function public.submit_duel_answer(bigint, boolean) to authenticated;

-- ════════════════════════════════════════════════════════════════
-- QEYD: Direktor üçün "🏫 Məktəb Hesabatı" paneli YENİ SQL TƏLƏB ETMİR —
-- mövcud class_leaderboard görünüşündən (supabase_update_teacher_and_league.sql-də
-- yaradılıb) və profiles cədvəlindən (role='teacher' filtri ilə) istifadə edir.
-- Əgər həmin skripti əvvəllər run etməmisinizsə, əvvəlcə onu run edin.
-- ════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════════
-- [10/25]  supabase_update_duel_cancel.sql
-- Duel ləğvi
-- ════════════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════
-- SözLab — Duel-i ləğv etmə (abandon/cancel) imkanı.
-- Bu skripti Supabase Dashboard → SQL Editor-da açıb "Run" edin.
-- ÖNCƏ supabase_update_duel.sql-in run edildiyini fərz edir.
--
-- Nə üçün: bəzən bir duel (şəbəkə problemi, brauzer dondurması və s.
-- səbəbdən) ilişib qalırsa, indiyədək oyunçunun onu siyahıdan silmək
-- imkanı yox idi — "Davam edən Duellər" bölməsində əbədi qalırdı.
-- İndi hər iki tərəf istənilən vaxt (pending və ya active statusunda)
-- öz duelini ləğv edə bilər.
-- ════════════════════════════════════════════════════════════════

-- 1) status sahəsinə 'cancelled' dəyərini əlavə et
alter table public.duels drop constraint if exists duels_status_check;
alter table public.duels add constraint duels_status_check
  check (status in ('pending','active','declined','finished','cancelled'));

-- 2) cancel_duel() — YALNIZ duelin özündəki iki tərəfdən biri çağıra bilər,
--    və YALNIZ hələ bitməmiş (pending/active) duel ləğv edilə bilər —
--    artıq 'finished' olan bir duelin nəticəsini/XP-sini geri ala bilməz.
create or replace function public.cancel_duel(p_duel_id bigint)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_username text;
begin
  select username into v_username from public.profiles where id = auth.uid();
  if v_username is null then
    raise exception 'Profil tapılmadı';
  end if;

  update public.duels
    set status = 'cancelled'
    where id = p_duel_id
      and (p1_username = v_username or p2_username = v_username)
      and status in ('pending','active');
end;
$$;

grant execute on function public.cancel_duel(bigint) to authenticated;


-- ════════════════════════════════════════════════════════════════════════
-- [11/25]  supabase_update_live_quiz.sql
-- Canlı sinif yarışması
-- ════════════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════
-- SözLab — Canlı Sinif Yarışması (Kahoot-tərzi).
-- Bu skripti Supabase Dashboard → SQL Editor-da açıb "Run" edin.
-- ÖNCƏ bütün əvvəlki SQL skriptlərinin (xüsusilə supabase_update_duel.sql
-- və supabase_update_teacher_and_league.sql) run edildiyini fərz edir —
-- compute_level(), is_teacher_of(), is_admin(), is_director() buradan
-- istifadə olunur. Mövcud cədvəlləri POZMUR, sadəcə yeni cədvəl/funksiya
-- əlavə edir.
--
-- Necə işləyir: Müəllim öz sinfi üçün bir "sessiya" yaradır (6 rəqəmli/
-- hərfli kod alır), şagirdlər həmin kodla qoşulur. Müəllim "Növbəti sual"
-- düyməsi ilə sualları bir-bir açır, hamısı EYNİ ANDA eyni sualı görür
-- (Kahoot kimi), sürətli və düzgün cavab daha çox xal qazandırır. Bütün
-- xal/vəziyyət hesablaması server tərəfdə (bu fayldakı funksiyalarda) baş
-- verir ki, şagird öz xalını saxtalaşdıra bilməsin.
-- ════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────
-- 1) LIVE_QUIZ_SESSIONS CƏDVƏLİ
-- ─────────────────────────────────────────────
create table if not exists public.live_quiz_sessions (
  id bigint generated always as identity primary key,
  code text not null unique,
  teacher_username text not null,
  class_grade text not null,
  status text not null default 'waiting' check (status in ('waiting','question','reveal','finished')),
  questions jsonb not null,
  current_index integer not null default -1,
  question_started_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists idx_lq_sessions_code on public.live_quiz_sessions (code);
create index if not exists idx_lq_sessions_class on public.live_quiz_sessions (class_grade, created_at desc);

alter table public.live_quiz_sessions enable row level security;

drop policy if exists "lq_sessions_select" on public.live_quiz_sessions;
create policy "lq_sessions_select"
  on public.live_quiz_sessions for select
  to authenticated
  using (
    public.is_admin(auth.uid())
    or public.is_director(auth.uid())
    or exists(select 1 from public.profiles p where p.id = auth.uid() and p.username = live_quiz_sessions.teacher_username)
    or exists(select 1 from public.profiles p where p.id = auth.uid() and p.class_grade = live_quiz_sessions.class_grade and p.class_grade <> '')
  );

-- QEYD: insert/update/delete siyasəti QƏSDƏN yoxdur — bütün yazma
-- əməliyyatları aşağıdakı SECURITY DEFINER funksiyaları ilə edilir.

-- ─────────────────────────────────────────────
-- 2) LIVE_QUIZ_PARTICIPANTS CƏDVƏLİ
-- ─────────────────────────────────────────────
create table if not exists public.live_quiz_participants (
  id bigint generated always as identity primary key,
  session_id bigint not null references public.live_quiz_sessions(id) on delete cascade,
  username text not null,
  display_name text not null default '',
  score integer not null default 0,
  last_answered_index integer not null default -1,
  last_correct boolean,
  last_points integer not null default 0,
  joined_at timestamptz not null default now(),
  unique(session_id, username)
);
create index if not exists idx_lq_participants_session on public.live_quiz_participants (session_id);

alter table public.live_quiz_participants enable row level security;

drop policy if exists "lq_participants_select" on public.live_quiz_participants;
create policy "lq_participants_select"
  on public.live_quiz_participants for select
  to authenticated
  using (
    public.is_admin(auth.uid())
    or public.is_director(auth.uid())
    or exists(
      select 1 from public.live_quiz_sessions s
      join public.profiles p on p.id = auth.uid()
      where s.id = live_quiz_participants.session_id
        and (p.username = s.teacher_username or (p.class_grade = s.class_grade and p.class_grade <> ''))
    )
  );

-- QEYD: bu cədvələ də birbaşa insert/update icazəsi YOXDUR.

-- ─────────────────────────────────────────────
-- 3) create_live_quiz() — müəllim öz sinfi üçün yeni sessiya yaradır.
-- ─────────────────────────────────────────────
create or replace function public.create_live_quiz(p_questions jsonb)
returns public.live_quiz_sessions
language plpgsql
security definer set search_path = public
as $$
declare
  v_username text;
  v_role text;
  v_class text;
  v_code text;
  v_row public.live_quiz_sessions;
  v_chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  i integer;
begin
  select username, role, teacher_class into v_username, v_role, v_class from public.profiles where id = auth.uid();
  if v_username is null then
    raise exception 'Profil tapılmadı';
  end if;
  if v_role <> 'teacher' or coalesce(v_class,'') = '' then
    raise exception 'Yalnız sinfi olan müəllimlər canlı yarışma başlada bilər';
  end if;
  if jsonb_typeof(p_questions) <> 'array' or jsonb_array_length(p_questions) < 1 or jsonb_array_length(p_questions) > 30 then
    raise exception 'Yanlış sual formatı';
  end if;

  loop
    v_code := '';
    for i in 1..6 loop
      v_code := v_code || substr(v_chars, floor(random()*length(v_chars))::int + 1, 1);
    end loop;
    exit when not exists(select 1 from public.live_quiz_sessions where code = v_code);
  end loop;

  insert into public.live_quiz_sessions(code, teacher_username, class_grade, questions, status, current_index)
  values (v_code, v_username, v_class, p_questions, 'waiting', -1)
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.create_live_quiz(jsonb) to authenticated;

-- ─────────────────────────────────────────────
-- 4) join_live_quiz() — şagird kodla qoşulur (yalnız öz sinfinin sessiyası).
-- ─────────────────────────────────────────────
create or replace function public.join_live_quiz(p_code text)
returns public.live_quiz_sessions
language plpgsql
security definer set search_path = public
as $$
declare
  v_username text;
  v_display text;
  v_role text;
  v_class text;
  v_session public.live_quiz_sessions;
begin
  select username, display_name, role, class_grade into v_username, v_display, v_role, v_class
    from public.profiles where id = auth.uid();
  if v_username is null then
    raise exception 'Profil tapılmadı';
  end if;
  if v_role <> 'user' then
    raise exception 'Yalnız şagirdlər yarışmaya qoşula bilər';
  end if;

  select * into v_session from public.live_quiz_sessions where upper(code) = upper(trim(p_code));
  if v_session is null then
    raise exception 'Kod tapılmadı — yenidən yoxlayın';
  end if;
  if v_session.class_grade <> coalesce(v_class,'') then
    raise exception 'Bu yarışma sizin sinfiniz üçün deyil';
  end if;
  if v_session.status = 'finished' then
    raise exception 'Bu yarışma artıq bitib';
  end if;

  insert into public.live_quiz_participants(session_id, username, display_name)
  values (v_session.id, v_username, coalesce(v_display, v_username))
  on conflict (session_id, username) do nothing;

  return v_session;
end;
$$;

grant execute on function public.join_live_quiz(text) to authenticated;

-- ─────────────────────────────────────────────
-- 5) start_live_quiz_question() — müəllim növbəti suala keçir (və ya bitirir).
-- ─────────────────────────────────────────────
create or replace function public.start_live_quiz_question(p_session_id bigint)
returns public.live_quiz_sessions
language plpgsql
security definer set search_path = public
as $$
declare
  v_username text;
  v_session public.live_quiz_sessions;
  v_total integer;
  v_next integer;
begin
  select username into v_username from public.profiles where id = auth.uid();
  select * into v_session from public.live_quiz_sessions where id = p_session_id for update;
  if v_session is null then
    raise exception 'Sessiya tapılmadı';
  end if;
  if v_session.teacher_username <> v_username then
    raise exception 'Yalnız yarışmanı başladan müəllim idarə edə bilər';
  end if;

  v_total := jsonb_array_length(v_session.questions);
  v_next := v_session.current_index + 1;

  if v_next >= v_total then
    update public.live_quiz_sessions set status = 'finished' where id = p_session_id returning * into v_session;
  else
    update public.live_quiz_sessions
      set current_index = v_next, status = 'question', question_started_at = now()
      where id = p_session_id
      returning * into v_session;
  end if;

  return v_session;
end;
$$;

grant execute on function public.start_live_quiz_question(bigint) to authenticated;

-- ─────────────────────────────────────────────
-- 6) end_live_quiz() — müəllim yarışmanı vaxtından əvvəl bitirə bilər.
-- ─────────────────────────────────────────────
create or replace function public.end_live_quiz(p_session_id bigint)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_username text;
begin
  select username into v_username from public.profiles where id = auth.uid();
  update public.live_quiz_sessions set status = 'finished'
    where id = p_session_id and teacher_username = v_username;
end;
$$;

grant execute on function public.end_live_quiz(bigint) to authenticated;

-- ─────────────────────────────────────────────
-- 7) submit_live_quiz_answer() — şagird cavab verir. Düzgünlüyü server
--    tərəfdə yoxlayır (client-in göndərdiyi "düzgündür" bayrağına ETİBAR
--    ETMİR), sürətə görə xal verir (Kahoot-vari: nə qədər tez, o qədər
--    çox xal) və dərhal profilə XP əlavə edir. Eyni suala iki dəfə cavab
--    vermək (last_answered_index yoxlaması ilə) və sessiya sualından fərqli
--    indeksə cavab vermək (köhnə sual üçün gec gələn sorğu) qarşısı alınır.
-- ─────────────────────────────────────────────
create or replace function public.submit_live_quiz_answer(p_session_id bigint, p_question_index integer, p_answer text)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_username text;
  v_session public.live_quiz_sessions;
  v_participant public.live_quiz_participants;
  v_question jsonb;
  v_correct_answer text;
  v_is_correct boolean;
  v_elapsed_ms integer;
  v_points integer;
begin
  select username into v_username from public.profiles where id = auth.uid();
  if v_username is null then
    raise exception 'Profil tapılmadı';
  end if;

  select * into v_session from public.live_quiz_sessions where id = p_session_id for update;
  if v_session is null then
    raise exception 'Sessiya tapılmadı';
  end if;
  if v_session.status <> 'question' or v_session.current_index <> p_question_index then
    raise exception 'Bu sual artıq bağlıdır';
  end if;

  select * into v_participant from public.live_quiz_participants
    where session_id = p_session_id and username = v_username for update;
  if v_participant is null then
    raise exception 'Bu yarışmaya qoşulmamısınız';
  end if;
  if v_participant.last_answered_index >= p_question_index then
    raise exception 'Bu suala artıq cavab vermisiniz';
  end if;

  v_question := v_session.questions -> p_question_index;
  v_correct_answer := v_question ->> 'correct';
  v_is_correct := (p_answer = v_correct_answer);

  v_elapsed_ms := greatest(0, extract(epoch from (now() - coalesce(v_session.question_started_at, now()))) * 1000)::integer;
  v_points := case when v_is_correct then greatest(20, 100 - floor(v_elapsed_ms / 150.0)::integer) else 0 end;

  update public.live_quiz_participants
    set last_answered_index = p_question_index,
        last_correct = v_is_correct,
        last_points = v_points,
        score = score + v_points
    where id = v_participant.id;

  if v_points > 0 then
    update public.profiles set xp = xp + 2, level = public.compute_level(xp + 2) where username = v_username;
    perform public.log_xp_gain(v_username, (now() at time zone 'UTC')::date, 2);
  end if;

  return jsonb_build_object('correct', v_is_correct, 'points', v_points, 'correctAnswer', v_correct_answer);
end;
$$;

grant execute on function public.submit_live_quiz_answer(bigint, integer, text) to authenticated;

-- ─────────────────────────────────────────────
-- 8) award_live_quiz_podium() — yarışma bitəndə (client "finished" statusunu
--    ilk dəfə görəndə çağırır) ilk 3 yerə bonus XP verir. "xp_awarded"
--    sütunu iki dəfə mükafat verilməsinin qarşısını alır.
-- ─────────────────────────────────────────────
alter table public.live_quiz_sessions add column if not exists xp_awarded boolean not null default false;

create or replace function public.award_live_quiz_podium(p_session_id bigint)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_session public.live_quiz_sessions;
  v_top record;
  v_rank integer := 0;
  v_bonus integer;
begin
  select * into v_session from public.live_quiz_sessions where id = p_session_id for update;
  if v_session is null or v_session.status <> 'finished' or v_session.xp_awarded then
    return;
  end if;

  update public.live_quiz_sessions set xp_awarded = true where id = p_session_id;

  for v_top in
    select username from public.live_quiz_participants
      where session_id = p_session_id order by score desc, joined_at asc limit 3
  loop
    v_rank := v_rank + 1;
    v_bonus := case v_rank when 1 then 15 when 2 then 10 else 5 end;
    update public.profiles set xp = xp + v_bonus, level = public.compute_level(xp + v_bonus) where username = v_top.username;
    perform public.log_xp_gain(v_top.username, (now() at time zone 'UTC')::date, v_bonus);
  end loop;
end;
$$;

grant execute on function public.award_live_quiz_podium(bigint) to authenticated;


-- ════════════════════════════════════════════════════════════════════════
-- [12/25]  supabase_fix_livequiz_class.sql
-- DÜZƏLİŞ: yarışmaya qoşulma
-- ════════════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════════════
-- DÜZƏLİŞ: Canlı Sinif Yarışmasına heç kim qoşula bilmirdi ("sinif boş")
--
-- PROBLEM:
--   join_live_quiz() şagirdin sinfini sessiyanın sinfi ilə HƏRFİ-HƏRFİNƏ
--   müqayisə edirdi:
--       if v_session.class_grade <> coalesce(v_class,'') then ...
--   Sessiyanın sinfi müəllimin profilindəki `teacher_class`-dan gəlir
--   (məs. "10b" və ya "10 B"), şagirdinki isə qeydiyyatda seçilən
--   `class_grade`-dır (məs. "10B"). Bir hərfin registri və ya bir boşluq
--   fərqli olan kimi müqayisə uğursuz olurdu və HƏR şagird
--   "Bu yarışma sizin sinfiniz üçün deyil" xətası alırdı — nəticədə
--   müəllimin ekranında iştirakçı siyahısı boş qalırdı.
--
-- HƏLL:
--   Hər iki tərəf müqayisədən əvvəl normallaşdırılır: böyük hərflərə salınır,
--   boşluq/defis kimi simvollar silinir. Yəni "10b", "10 B", "10-B" və "10B"
--   artıq eyni sinif sayılır. Xəta mesajı da hansı sinfin gözlənildiyini
--   göstərir ki, uyğunsuzluq olsa müəllim dərhal görsün.
--
-- Supabase → SQL Editor → bu faylı yapışdır → Run.
-- Təkrar işlətmək təhlükəsizdir.
-- ══════════════════════════════════════════════════════════════════════════

-- Sinif adını müqayisə üçün normal hala salan köməkçi funksiya
create or replace function public.norm_class(p text)
returns text
language sql
immutable
as $$
  select upper(regexp_replace(coalesce(p, ''), '[^a-zA-Z0-9]', '', 'g'));
$$;

comment on function public.norm_class(text) is
  'Sinif adını müqayisə üçün normallaşdırır: "10 b" → "10B"';


create or replace function public.join_live_quiz(p_code text)
returns public.live_quiz_sessions
language plpgsql
security definer set search_path = public
as $$
declare
  v_username text;
  v_display text;
  v_role text;
  v_class text;
  v_session public.live_quiz_sessions;
begin
  select username, display_name, role, class_grade into v_username, v_display, v_role, v_class
    from public.profiles where id = auth.uid();
  if v_username is null then
    raise exception 'Profil tapılmadı';
  end if;
  if v_role <> 'user' then
    raise exception 'Yalnız şagirdlər yarışmaya qoşula bilər';
  end if;

  select * into v_session from public.live_quiz_sessions where upper(code) = upper(trim(p_code));
  if v_session is null then
    raise exception 'Kod tapılmadı — yenidən yoxlayın';
  end if;

  -- Normallaşdırılmış müqayisə (əsas düzəliş).
  -- Sessiyanın sinfi boşdursa, yarışma bütün siniflərə açıq sayılır.
  if coalesce(v_session.class_grade,'') <> ''
     and public.norm_class(v_session.class_grade) <> public.norm_class(v_class) then
    raise exception 'Bu yarışma % sinfi üçündür, sizin sinfiniz isə %',
      v_session.class_grade, coalesce(nullif(v_class,''), 'təyin edilməyib');
  end if;

  if v_session.status = 'finished' then
    raise exception 'Bu yarışma artıq bitib';
  end if;

  insert into public.live_quiz_participants(session_id, username, display_name)
  values (v_session.id, v_username, coalesce(v_display, v_username))
  on conflict (session_id, username) do nothing;

  return v_session;
end;
$$;

grant execute on function public.join_live_quiz(text) to authenticated;


-- ─────────────────────────────────────────────────────────────
-- YOXLAMA: müəllimlərin sinfi ilə şagirdlərin sinfi uyğun gəlirmi?
-- Bu sorğu hər müəllim sinfi üçün neçə şagirdin tapıldığını göstərir.
-- Əgər "sagird_sayi" 0-dırsa, həmin müəllimin teacher_class dəyəri
-- şagirdlərin class_grade dəyəri ilə uyğun gəlmir.
-- ─────────────────────────────────────────────────────────────
select
  t.username            as muellim,
  t.teacher_class       as muellim_sinfi,
  count(s.id)           as sagird_sayi
from public.profiles t
left join public.profiles s
  on s.role = 'user'
 and public.norm_class(s.class_grade) = public.norm_class(t.teacher_class)
where t.role = 'teacher' and coalesce(t.teacher_class,'') <> ''
group by t.username, t.teacher_class
order by sagird_sayi asc;


-- ════════════════════════════════════════════════════════════════════════
-- [13/25]  supabase_fix_duel_stuck.sql
-- DÜZƏLİŞ: duel ilişməsi
-- ════════════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════════════
-- DÜZƏLİŞ: Duel "Rəqibin bitirməsini gözləyirik..." ekranında ilişib qalır
--
-- PROBLEM:
--   Duel YALNIZ submit_duel_answer() daxilində yekunlaşır — yəni hər iki
--   oyunçunun p1_finished_at / p2_finished_at dəyəri dolduqda. Cavablar
--   brauzerdən "göndər və unut" şəklində yollanırdı və xəta səssizcə
--   udulurdu. Şəbəkə bir anlıq kəsilsə (mobil internet, səhifə arxa plana
--   keçsə və s.) bir cavab itir → həmin oyunçunun progress-i heç vaxt sual
--   sayına çatmır → finished_at yazılmır → duel ƏBƏDİ 'active' qalır və
--   HƏR İKİ oyunçu "gözləyirik..." ekranında donur.
--
-- HƏLL (iki hissədən ibarətdir):
--   1) index.html tərəfdə: cavablar təkrar cəhdlə göndərilir və bitməzdən
--      əvvəl hamısının serverə çatdığı gözlənilir.
--   2) BU FAYL: ilişib qalmış duelləri yekunlaşdırmaq üçün finalize_duel()
--      funksiyası. Oyunçu gözləmə ekranında "Nəticəni yekunlaşdır" düyməsi
--      ilə çağıra bilər; cavabsız qalan suallar səhv sayılır.
--
-- Supabase → SQL Editor → bu faylı yapışdır → Run.
-- Təkrar işlətmək təhlükəsizdir.
-- ══════════════════════════════════════════════════════════════════════════

create or replace function public.finalize_duel(p_duel_id bigint)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_username text;
  v_duel record;
  v_winner text;
  v_xp_p1 integer;
  v_xp_p2 integer;
begin
  select username into v_username from public.profiles where id = auth.uid();
  if v_username is null then return; end if;

  select * into v_duel from public.duels where id = p_duel_id for update;
  if v_duel is null then return; end if;
  if v_duel.status <> 'active' then return; end if;

  -- Yalnız duelin iştirakçısı yekunlaşdıra bilər
  if v_duel.p1_username <> v_username and v_duel.p2_username <> v_username then
    return;
  end if;

  -- Cavab verməyən tərəfin vaxtı bağlanır (qalan suallar səhv sayılır)
  if v_duel.p1_finished_at is null then
    update public.duels set p1_finished_at = now() where id = p_duel_id;
  end if;
  if v_duel.p2_finished_at is null then
    update public.duels set p2_finished_at = now() where id = p_duel_id;
  end if;

  select * into v_duel from public.duels where id = p_duel_id for update;

  if v_duel.p1_score > v_duel.p2_score then v_winner := v_duel.p1_username;
  elsif v_duel.p2_score > v_duel.p1_score then v_winner := v_duel.p2_username;
  else v_winner := null;
  end if;

  if v_winner is null then
    v_xp_p1 := 20; v_xp_p2 := 20;
  elsif v_winner = v_duel.p1_username then
    v_xp_p1 := 30; v_xp_p2 := 10;
  else
    v_xp_p1 := 10; v_xp_p2 := 30;
  end if;

  update public.profiles set xp = xp + v_xp_p1, level = public.compute_level(xp + v_xp_p1)
    where username = v_duel.p1_username;
  update public.profiles set xp = xp + v_xp_p2, level = public.compute_level(xp + v_xp_p2)
    where username = v_duel.p2_username;

  update public.duels
    set status = 'finished', winner_username = v_winner, finished_at = now()
    where id = p_duel_id;
end;
$$;

grant execute on function public.finalize_duel(bigint) to authenticated;

comment on function public.finalize_duel(bigint) is
  'İlişib qalmış və ya rəqibi tərk etmiş dueli cari xallara görə yekunlaşdırır.';


-- ─────────────────────────────────────────────────────────────
-- İNDİ İLİŞİB QALMIŞ DUELLƏRİ TƏMİZLƏ
-- 30 dəqiqədən çox 'active' qalmış duelləri ləğv edirik ki,
-- oyunçuların "Davam edən Duellər" siyahısı təmizlənsin.
-- (Ləğv olunan duelə görə XP verilmir.)
-- ─────────────────────────────────────────────────────────────
update public.duels
  set status = 'cancelled'
  where status = 'active'
    and created_at < now() - interval '30 minutes';


-- ─────────────────────────────────────────────────────────────
-- YOXLAMA: hazırda ilişib qalan duel qalıbmı?
-- ─────────────────────────────────────────────────────────────
select id, p1_username, p2_username, status,
       p1_progress, p2_progress,
       jsonb_array_length(questions) as sual_sayi,
       p1_finished_at is not null as p1_bitirdi,
       p2_finished_at is not null as p2_bitirdi,
       created_at
from public.duels
where status = 'active'
order by created_at desc;


-- ════════════════════════════════════════════════════════════════════════
-- [14/25]  supabase_update_boss.sql
-- Sinif Bossu
-- ════════════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════
-- SözLab — "Sinif Boss'u" (Kollektiv Reyd Rejimi).
-- Bu skripti Supabase Dashboard → SQL Editor-da açıb "Run" edin.
-- ÖNCƏ supabase_update_live_quiz.sql-in (və dolayısı ilə onun asılı olduğu
-- bütün əvvəlki skriptlərin) run edildiyini fərz edir — compute_level(),
-- is_admin(), log_xp_gain() buradan istifadə olunur, arxitektur da eynidir.
--
-- Necə işləyir: müəllim öz sinfi üçün bir "Boss döyüşü" sessiyası yaradır
-- (Canlı Yarışma ilə EYNİ kod-ilə-qoşulma mexanizmi). Amma fərdi xal yerinə
-- BÜTÜN sinif ORTAQ bir "Boss HP" zolağını azaldır — kim sualı düzgün
-- cavablandırsa, zərbə vurur. HP sıfıra enəndə boss "məğlub" olur.
--
-- TEXNİKİ QEYD (WebRTC/P2P ƏVƏZİNƏ): bu, ayrı bir infrastruktur (WebSocket/
-- P2P) tələb etmir — Canlı Yarışmadakı eyni sadə "poll" (1-2 saniyəlik
-- sorğu) üsulu ilə işləyir. HP-nin konkurrent (eyni anda 20-30 şagirdin
-- zərbə vurması) düzgün azalması Postgres-in `for update` sətir kilidi ilə
-- TAM TƏHLÜKƏSİZDİR — heç bir zərbə itmir, HP heç vaxt yanlış hesablanmır.
-- ════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────
-- 1) CLASS_BOSS_SESSIONS CƏDVƏLİ
-- ─────────────────────────────────────────────
create table if not exists public.class_boss_sessions (
  id bigint generated always as identity primary key,
  code text not null unique,
  teacher_username text not null,
  class_grade text not null,
  boss_name text not null default 'Söz Divi',
  boss_max_hp integer not null default 200,
  boss_hp integer not null default 200,
  damage_per_correct integer not null default 5,
  questions jsonb not null,
  status text not null default 'waiting' check (status in ('waiting','question','reveal','finished')),
  defeated boolean not null default false,
  current_index integer not null default -1,
  question_started_at timestamptz,
  xp_awarded boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists idx_boss_sessions_code on public.class_boss_sessions (code);
create index if not exists idx_boss_sessions_class on public.class_boss_sessions (class_grade, created_at desc);

alter table public.class_boss_sessions enable row level security;

drop policy if exists "boss_sessions_select" on public.class_boss_sessions;
create policy "boss_sessions_select"
  on public.class_boss_sessions for select
  to authenticated
  using (
    public.is_admin(auth.uid())
    or public.is_director(auth.uid())
    or exists(select 1 from public.profiles p where p.id = auth.uid() and p.username = class_boss_sessions.teacher_username)
    or exists(select 1 from public.profiles p where p.id = auth.uid() and p.class_grade = class_boss_sessions.class_grade and p.class_grade <> '')
  );

-- QEYD: insert/update/delete siyasəti QƏSDƏN yoxdur — bütün yazma
-- əməliyyatları aşağıdakı SECURITY DEFINER funksiyaları ilə edilir.

-- ─────────────────────────────────────────────
-- 2) CLASS_BOSS_PARTICIPANTS CƏDVƏLİ (zərbə vuranların statistikası)
-- ─────────────────────────────────────────────
create table if not exists public.class_boss_participants (
  id bigint generated always as identity primary key,
  session_id bigint not null references public.class_boss_sessions(id) on delete cascade,
  username text not null,
  display_name text not null default '',
  damage_dealt integer not null default 0,
  hits integer not null default 0,
  last_answered_index integer not null default -1,
  joined_at timestamptz not null default now(),
  unique(session_id, username)
);
create index if not exists idx_boss_participants_session on public.class_boss_participants (session_id);

alter table public.class_boss_participants enable row level security;

drop policy if exists "boss_participants_select" on public.class_boss_participants;
create policy "boss_participants_select"
  on public.class_boss_participants for select
  to authenticated
  using (
    public.is_admin(auth.uid())
    or public.is_director(auth.uid())
    or exists(
      select 1 from public.class_boss_sessions s
      join public.profiles p on p.id = auth.uid()
      where s.id = class_boss_participants.session_id
        and (p.username = s.teacher_username or (p.class_grade = s.class_grade and p.class_grade <> ''))
    )
  );

-- ─────────────────────────────────────────────
-- 3) create_boss_session() — müəllim öz sinfi üçün yeni boss döyüşü yaradır.
-- ─────────────────────────────────────────────
create or replace function public.create_boss_session(
  p_questions jsonb, p_boss_name text default 'Söz Divi',
  p_boss_hp integer default 200, p_damage_per_correct integer default 5
)
returns public.class_boss_sessions
language plpgsql
security definer set search_path = public
as $$
declare
  v_username text;
  v_role text;
  v_class text;
  v_code text;
  v_row public.class_boss_sessions;
  v_chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  i integer;
  v_hp integer := greatest(20, least(2000, coalesce(p_boss_hp, 200)));
  v_dmg integer := greatest(1, least(100, coalesce(p_damage_per_correct, 5)));
begin
  select username, role, teacher_class into v_username, v_role, v_class from public.profiles where id = auth.uid();
  if v_username is null then
    raise exception 'Profil tapılmadı';
  end if;
  if v_role <> 'teacher' or coalesce(v_class,'') = '' then
    raise exception 'Yalnız sinfi olan müəllimlər Boss döyüşü başlada bilər';
  end if;
  if jsonb_typeof(p_questions) <> 'array' or jsonb_array_length(p_questions) < 1 or jsonb_array_length(p_questions) > 60 then
    raise exception 'Yanlış sual formatı';
  end if;

  loop
    v_code := '';
    for i in 1..6 loop
      v_code := v_code || substr(v_chars, floor(random()*length(v_chars))::int + 1, 1);
    end loop;
    exit when not exists(select 1 from public.class_boss_sessions where code = v_code);
  end loop;

  insert into public.class_boss_sessions(
    code, teacher_username, class_grade, boss_name, boss_max_hp, boss_hp,
    damage_per_correct, questions, status, current_index
  )
  values (
    v_code, v_username, v_class, coalesce(nullif(trim(p_boss_name),''),'Söz Divi'), v_hp, v_hp,
    v_dmg, p_questions, 'waiting', -1
  )
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.create_boss_session(jsonb, text, integer, integer) to authenticated;

-- ─────────────────────────────────────────────
-- 4) join_boss_session() — şagird kodla qoşulur (yalnız öz sinfinin döyüşü).
-- ─────────────────────────────────────────────
create or replace function public.join_boss_session(p_code text)
returns public.class_boss_sessions
language plpgsql
security definer set search_path = public
as $$
declare
  v_username text;
  v_display text;
  v_role text;
  v_class text;
  v_session public.class_boss_sessions;
begin
  select username, display_name, role, class_grade into v_username, v_display, v_role, v_class
    from public.profiles where id = auth.uid();
  if v_username is null then
    raise exception 'Profil tapılmadı';
  end if;
  if v_role <> 'user' then
    raise exception 'Yalnız şagirdlər Boss döyüşünə qoşula bilər';
  end if;

  select * into v_session from public.class_boss_sessions where upper(code) = upper(trim(p_code));
  if v_session is null then
    raise exception 'Kod tapılmadı — yenidən yoxlayın';
  end if;
  if v_session.class_grade <> coalesce(v_class,'') then
    raise exception 'Bu döyüş sizin sinfiniz üçün deyil';
  end if;
  if v_session.status = 'finished' then
    raise exception 'Bu döyüş artıq bitib';
  end if;

  insert into public.class_boss_participants(session_id, username, display_name)
  values (v_session.id, v_username, coalesce(v_display, v_username))
  on conflict (session_id, username) do nothing;

  return v_session;
end;
$$;

grant execute on function public.join_boss_session(text) to authenticated;

-- ─────────────────────────────────────────────
-- 5) start_boss_question() — müəllim növbəti suala keçir (və ya bitirir).
--    Boss artıq məğlub olubsa (dəf edilib), yeni sual açmır — birbaşa bitirir.
-- ─────────────────────────────────────────────
create or replace function public.start_boss_question(p_session_id bigint)
returns public.class_boss_sessions
language plpgsql
security definer set search_path = public
as $$
declare
  v_username text;
  v_session public.class_boss_sessions;
  v_total integer;
  v_next integer;
begin
  select username into v_username from public.profiles where id = auth.uid();
  select * into v_session from public.class_boss_sessions where id = p_session_id for update;
  if v_session is null then
    raise exception 'Sessiya tapılmadı';
  end if;
  if v_session.teacher_username <> v_username then
    raise exception 'Yalnız döyüşü başladan müəllim idarə edə bilər';
  end if;

  if v_session.defeated or v_session.boss_hp <= 0 then
    update public.class_boss_sessions set status = 'finished' where id = p_session_id returning * into v_session;
    return v_session;
  end if;

  v_total := jsonb_array_length(v_session.questions);
  v_next := v_session.current_index + 1;

  if v_next >= v_total then
    update public.class_boss_sessions set status = 'finished' where id = p_session_id returning * into v_session;
  else
    update public.class_boss_sessions
      set current_index = v_next, status = 'question', question_started_at = now()
      where id = p_session_id
      returning * into v_session;
  end if;

  return v_session;
end;
$$;

grant execute on function public.start_boss_question(bigint) to authenticated;

-- ─────────────────────────────────────────────
-- 6) end_boss_session() — müəllim vaxtından əvvəl bitirə bilər.
-- ─────────────────────────────────────────────
create or replace function public.end_boss_session(p_session_id bigint)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_username text;
begin
  select username into v_username from public.profiles where id = auth.uid();
  update public.class_boss_sessions set status = 'finished'
    where id = p_session_id and teacher_username = v_username;
end;
$$;

grant execute on function public.end_boss_session(bigint) to authenticated;

-- ─────────────────────────────────────────────
-- 7) submit_boss_answer() — şagird cavab verir. Düzgünlüyü SERVERDƏ yoxlayır
--    (klientə etibar etmir). Düzgündürsə, boss_hp-ni ATOMİK azaldır — "for
--    update" sətir kiliditi sayəsində eyni anda 30 şagird cavab versə belə,
--    HEÇ BİR zərbə itmir və HP həmişə düzgün hesablanır (Postgres bunları
--    növbə ilə, bir-bir tətbiq edir). HP sıfıra enəndə döyüş dərhal bitir.
-- ─────────────────────────────────────────────
create or replace function public.submit_boss_answer(p_session_id bigint, p_question_index integer, p_answer text)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_username text;
  v_session public.class_boss_sessions;
  v_participant public.class_boss_participants;
  v_question jsonb;
  v_correct_answer text;
  v_is_correct boolean;
  v_new_hp integer;
  v_dmg integer := 0;
begin
  select username into v_username from public.profiles where id = auth.uid();
  if v_username is null then
    raise exception 'Profil tapılmadı';
  end if;

  select * into v_session from public.class_boss_sessions where id = p_session_id for update;
  if v_session is null then
    raise exception 'Sessiya tapılmadı';
  end if;
  if v_session.status <> 'question' or v_session.current_index <> p_question_index then
    raise exception 'Bu sual artıq bağlıdır';
  end if;

  select * into v_participant from public.class_boss_participants
    where session_id = p_session_id and username = v_username for update;
  if v_participant is null then
    raise exception 'Bu döyüşə qoşulmamısınız';
  end if;
  if v_participant.last_answered_index >= p_question_index then
    raise exception 'Bu suala artıq cavab vermisiniz';
  end if;

  v_question := v_session.questions -> p_question_index;
  v_correct_answer := v_question ->> 'correct';
  v_is_correct := (p_answer = v_correct_answer);

  update public.class_boss_participants
    set last_answered_index = p_question_index
    where id = v_participant.id;

  if v_is_correct then
    v_dmg := v_session.damage_per_correct;

    update public.class_boss_participants
      set damage_dealt = damage_dealt + v_dmg, hits = hits + 1
      where id = v_participant.id;

    update public.class_boss_sessions
      set boss_hp = greatest(0, boss_hp - v_dmg)
      where id = p_session_id
      returning boss_hp into v_new_hp;

    update public.profiles set xp = xp + 2, level = public.compute_level(xp + 2) where username = v_username;
    perform public.log_xp_gain(v_username, (now() at time zone 'UTC')::date, 2);

    if v_new_hp <= 0 then
      update public.class_boss_sessions set status = 'finished', defeated = true where id = p_session_id;
    end if;
  else
    select boss_hp into v_new_hp from public.class_boss_sessions where id = p_session_id;
  end if;

  return jsonb_build_object('correct', v_is_correct, 'damage', v_dmg, 'bossHp', v_new_hp, 'correctAnswer', v_correct_answer);
end;
$$;

grant execute on function public.submit_boss_answer(bigint, integer, text) to authenticated;

-- ─────────────────────────────────────────────
-- 8) award_boss_damage_bonus() — döyüş bitəndə (client "finished" statusunu
--    ilk dəfə görəndə çağırır) ən çox zərbə vurana bonus XP. "xp_awarded"
--    sütunu iki dəfə mükafat verilməsinin qarşısını alır. Yalnız BOSS DƏF
--    EDİLİBSƏ bonus verilir (vaxt bitib boss sağ qalıbsa, bonus yoxdur).
-- ─────────────────────────────────────────────
create or replace function public.award_boss_damage_bonus(p_session_id bigint)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_session public.class_boss_sessions;
  v_top record;
  v_rank integer := 0;
  v_bonus integer;
begin
  select * into v_session from public.class_boss_sessions where id = p_session_id for update;
  if v_session is null or v_session.status <> 'finished' or v_session.xp_awarded then
    return;
  end if;

  update public.class_boss_sessions set xp_awarded = true where id = p_session_id;

  if not v_session.defeated then
    return;
  end if;

  for v_top in
    select username from public.class_boss_participants
      where session_id = p_session_id and hits > 0 order by damage_dealt desc, joined_at asc limit 3
  loop
    v_rank := v_rank + 1;
    v_bonus := case v_rank when 1 then 15 when 2 then 10 else 5 end;
    update public.profiles set xp = xp + v_bonus, level = public.compute_level(xp + v_bonus) where username = v_top.username;
    perform public.log_xp_gain(v_top.username, (now() at time zone 'UTC')::date, v_bonus);
  end loop;
end;
$$;

grant execute on function public.award_boss_damage_bonus(bigint) to authenticated;


-- ════════════════════════════════════════════════════════════════════════
-- [15/25]  supabase_update_display_mode.sql
-- Böyük Ekran rejimi
-- ════════════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════
-- SözLab — "Böyük Ekran" rejimi üçün ictimai (login TƏLƏB ETMƏYƏN) məlumat RPC-si.
-- Bu skripti Supabase Dashboard → SQL Editor-da açıb "Run" edin.
-- ÖNCƏ bu skriptlərin run edildiyini fərz edir: supabase_setup.sql,
-- supabase_update_duel.sql, supabase_update_live_quiz.sql.
--
-- Nə üçün: dəhlizdəki/akt zalındakı televizor və ya proyektora qoşulan
-- brauzerdə HEÇ KİM daxil olmadan (login etmədən) canlı lent göstərilir.
-- Ona görə bu RPC anon (login etməmiş) istifadəçiyə də açıqdır — amma
-- YALNIZ artıq digər liderbord funksiyalarında (public_profiles,
-- class_leaderboard) göstərilən səviyyədə ictimai məlumatı (ad, xal,
-- sinif) qaytarır, heç bir yeni həssas sahə (email, sual mətnləri və s.)
-- açmır.
-- ════════════════════════════════════════════════════════════════

create or replace function public.get_display_activity()
returns jsonb
language plpgsql
security definer set search_path = public
stable
as $$
declare
  v_duels jsonb;
  v_quizzes jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
      'p1', p1_username, 'p2', p2_username,
      'p1_score', p1_score, 'p2_score', p2_score,
      'winner', winner_username
    ) order by created_at desc), '[]'::jsonb)
  into v_duels
  from (
    select * from public.duels where status = 'finished' order by created_at desc limit 8
  ) d;

  select coalesce(jsonb_agg(jsonb_build_object(
      'class', class_grade, 'top', top_list
    ) order by created_at desc), '[]'::jsonb)
  into v_quizzes
  from (
    select s.id, s.class_grade, s.created_at,
      (select coalesce(jsonb_agg(jsonb_build_object('name', lp.display_name, 'score', lp.score) order by lp.score desc), '[]'::jsonb)
       from (select * from public.live_quiz_participants where session_id = s.id order by score desc limit 3) lp
      ) as top_list
    from public.live_quiz_sessions s
    where s.status = 'finished'
    order by s.created_at desc
    limit 5
  ) s;

  return jsonb_build_object('duels', v_duels, 'quizzes', v_quizzes);
end;
$$;

grant execute on function public.get_display_activity() to anon, authenticated;


-- ════════════════════════════════════════════════════════════════════════
-- [16/25]  supabase_update_lessons.sql
-- Dərs materialları (+ storage bucket)
-- ════════════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════
-- SözLab — "Dərs Materialları" (Müəllim Slaydları) üçün SQL.
-- Bu skripti Supabase Dashboard → SQL Editor-da açıb "Run" edin.
-- Mövcud cədvəlləri POZMUR, sadəcə yeni cədvəl/bucket/funksiya əlavə edir.
--
-- FƏLSƏFƏ: hər müəllim YALNIZ ÖZ yüklədiyi dərsləri görür/idarə edir (sinif
-- yoldaşı müəllim başqasının materialına toxuna bilməz) — bax "teacher_lessons"
-- cədvəlinin RLS siyasəti. Hər dərs bir neçə "slayd"dan ibarətdir (mətn və ya
-- şəkil), bunlar "slides" sütununda JSON massiv kimi saxlanılır. Şəkillər isə
-- Supabase Storage-da ("lesson-images" bucket) saxlanılır ki, cədvəl şişməsin
-- və böyük şəkillər PostgREST sorğularını yavaşlatmasın.
-- ════════════════════════════════════════════════════════════════

-- 1) CƏDVƏL
create table if not exists public.teacher_lessons (
  id bigint generated always as identity primary key,
  teacher_username text not null,
  title text not null,
  slides jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_teacher_lessons_owner on public.teacher_lessons(teacher_username, created_at desc);

alter table public.teacher_lessons enable row level security;

-- Yalnız yükləyən müəllim öz dərslərini görə/dəyişə/silə bilər. Insert/update
-- üçün əlavə olaraq profilin role='teacher' olması tələb olunur ki, şagird
-- öz adına saxta dərs sətri yaza bilməsin (select/delete-də bu şərt yoxdur ki,
-- rolu sonradan dəyişən istifadəçi köhnə materiallarını itirməsin).
drop policy if exists "teacher_lessons_select" on public.teacher_lessons;
create policy "teacher_lessons_select"
  on public.teacher_lessons for select
  to authenticated
  using (exists(select 1 from public.profiles p where p.id = auth.uid() and p.username = teacher_lessons.teacher_username));

drop policy if exists "teacher_lessons_insert" on public.teacher_lessons;
create policy "teacher_lessons_insert"
  on public.teacher_lessons for insert
  to authenticated
  with check (exists(select 1 from public.profiles p where p.id = auth.uid() and p.username = teacher_lessons.teacher_username and p.role = 'teacher'));

drop policy if exists "teacher_lessons_update" on public.teacher_lessons;
create policy "teacher_lessons_update"
  on public.teacher_lessons for update
  to authenticated
  using (exists(select 1 from public.profiles p where p.id = auth.uid() and p.username = teacher_lessons.teacher_username))
  with check (exists(select 1 from public.profiles p where p.id = auth.uid() and p.username = teacher_lessons.teacher_username and p.role = 'teacher'));

drop policy if exists "teacher_lessons_delete" on public.teacher_lessons;
create policy "teacher_lessons_delete"
  on public.teacher_lessons for delete
  to authenticated
  using (exists(select 1 from public.profiles p where p.id = auth.uid() and p.username = teacher_lessons.teacher_username));

-- 2) STORAGE BUCKET — dərs şəkilləri üçün. "public: true" sayəsində şəkillər
-- birbaşa ictimai URL ilə açılır (proyektorda/tələbə cihazında yükləmə üçün
-- ayrıca giriş tələb olunmur), amma YÜKLƏMƏ/SİLMƏ yalnız öz qovluğuna icazəlidir.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('lesson-images', 'lesson-images', true, 8388608, array['image/png','image/jpeg','image/webp','image/gif'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Hər müəllim yalnız öz istifadəçi adı ilə başlayan qovluğa ("username/...")
-- yükləyə/silə bilər — "storage.foldername(name)" faylın yolunu "/" ilə
-- hissələrə bölür, birinci hissə qovluq adıdır.
--
-- QEYD (real Postgres ilə tapılmış incəlik): DELETE-in "WHERE" şərtinə görə
-- sətri tapa bilməsi üçün, DELETE siyasətindən ƏLAVƏ, HƏMİN ROL üçün bir
-- SELECT siyasəti də olmalıdır — əks halda DELETE sətri "görə bilmədiyi"
-- üçün sükutla 0 sətir siləcək (öz faylını belə silə bilməyəcək). Ona görə
-- aşağıda ayrıca SELECT siyasəti də var (ictimai "public" bucket bayrağı
-- ilə qarışdırılmasın — o, YALNIZ ictimai URL endpoint-inə aiddir, storage
-- API-dən (list/remove) sətri görmək üçün bu SELECT siyasəti lazımdır).
drop policy if exists "lesson_images_select" on storage.objects;
create policy "lesson_images_select"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'lesson-images'
    and exists(select 1 from public.profiles p where p.id = auth.uid() and p.username = (storage.foldername(name))[1])
  );

drop policy if exists "lesson_images_insert" on storage.objects;
create policy "lesson_images_insert"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'lesson-images'
    and exists(select 1 from public.profiles p where p.id = auth.uid() and p.role = 'teacher' and p.username = (storage.foldername(name))[1])
  );

drop policy if exists "lesson_images_delete" on storage.objects;
create policy "lesson_images_delete"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'lesson-images'
    and exists(select 1 from public.profiles p where p.id = auth.uid() and p.username = (storage.foldername(name))[1])
  );


-- ════════════════════════════════════════════════════════════════════════
-- [17/25]  supabase_update_support_chat.sql
-- Dəstək söhbəti
-- ════════════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════
-- SözLab — Dəstək Söhbəti (sayt-daxili mesajlaşma, Tawk.to-ya əlavə)
-- Bu skripti Supabase Dashboard → SQL Editor-da açıb "Run" edin.
-- Mövcud cədvəlləri POZMUR, sadəcə yeni cədvəl/funksiya əlavə edir.
-- ════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────
-- 1) SUPPORT_MESSAGES CƏDVƏLİ
--    Hər sətir bir mesajdır. "username" HƏMİŞƏ şagirdin (thread sahibinin)
--    adıdır — admin/direktor cavab yazanda da eyni username-ə yazılır,
--    sender_role kimin yazdığını göstərir. Cədvələ birbaşa insert/update
--    icazəsi YOXDUR — yalnız aşağıdakı iki SECURITY DEFINER funksiyası
--    yazır ki, istifadəçi başqasının adına mesaj yaza və ya "oxunub"
--    bayrağını özü saxtalaşdıra bilməsin.
-- ─────────────────────────────────────────────
create table if not exists public.support_messages (
  id bigint generated always as identity primary key,
  username text not null,
  sender_role text not null check (sender_role in ('user','admin','director')),
  sender_name text not null default '',
  body text not null check (char_length(body) between 1 and 1000),
  read boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists idx_support_messages_username on public.support_messages (username, created_at);

alter table public.support_messages enable row level security;

drop policy if exists "support_messages_select" on public.support_messages;
create policy "support_messages_select"
  on public.support_messages for select
  to authenticated
  using (
    exists(select 1 from public.profiles p where p.id = auth.uid() and p.username = support_messages.username)
    or public.is_admin(auth.uid())
    or public.is_director(auth.uid())
  );

-- QEYD: insert/update siyasəti QƏSDƏN yoxdur.

-- ─────────────────────────────────────────────
-- 2) send_support_message() — mesaj göndərmək.
--    Adi istifadəçi YALNIZ öz thread-inə yaza bilər (p_username input-u
--    onun üçün görməzdən gəlinir — özünü başqası kimi göstərə bilməsin
--    deyə). Admin/direktor istənilən şagirdin thread-inə yaza bilər.
-- ─────────────────────────────────────────────
create or replace function public.send_support_message(p_username text, p_body text)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_caller_username text;
  v_role text;
  v_is_staff boolean;
  v_body text := trim(coalesce(p_body,''));
begin
  select username, role into v_caller_username, v_role from public.profiles where id = auth.uid();
  if v_caller_username is null then
    raise exception 'Profil tapılmadı';
  end if;
  if char_length(v_body) = 0 or char_length(v_body) > 1000 then
    raise exception 'Mesaj boş və ya çox uzundur';
  end if;

  v_is_staff := (v_role = 'admin' or v_role = 'director');

  if v_is_staff then
    if not exists(select 1 from public.profiles where username = p_username) then
      raise exception 'İstifadəçi tapılmadı';
    end if;
    insert into public.support_messages(username, sender_role, sender_name, body)
    values (p_username, v_role, v_caller_username, v_body);
  else
    insert into public.support_messages(username, sender_role, sender_name, body)
    values (v_caller_username, 'user', v_caller_username, v_body);
  end if;
end;
$$;

grant execute on function public.send_support_message(text, text) to authenticated;

-- ─────────────────────────────────────────────
-- 3) mark_support_read() — söhbət açılanda qarşı tərəfin mesajlarını
--    "oxunub" işarələyir (şagird üçün: admin/direktor mesajlarını;
--    admin/direktor üçün: o şagirdin öz mesajlarını).
-- ─────────────────────────────────────────────
create or replace function public.mark_support_read(p_username text)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_caller_username text;
  v_is_staff boolean;
begin
  select username, (role = 'admin' or role = 'director') into v_caller_username, v_is_staff
    from public.profiles where id = auth.uid();

  if v_is_staff then
    update public.support_messages set read = true
      where username = p_username and sender_role = 'user' and read = false;
  elsif v_caller_username = p_username then
    update public.support_messages set read = true
      where username = p_username and sender_role in ('admin','director') and read = false;
  end if;
end;
$$;

grant execute on function public.mark_support_read(text) to authenticated;


-- ════════════════════════════════════════════════════════════════════════
-- [18/25]  supabase_update_support_chat_v2.sql
-- Dəstək söhbəti — müəllim səlahiyyəti
-- ════════════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════
-- SözLab — Dəstək Söhbətinə MÜƏLLİM səlahiyyəti əlavə edir.
-- Bu skripti Supabase Dashboard → SQL Editor-da açıb "Run" edin.
-- ÖNCƏ supabase_update_support_chat.sql-in run edildiyini fərz edir.
-- Nə dəyişir: indi müəllim də ÖZ SİNFİNİN şagirdləri ilə dəstək söhbəti
-- apara bilər (admin/direktor kimi bütün şagirdlər YOX, yalnız öz sinfi).
-- ════════════════════════════════════════════════════════════════

-- 1) sender_role-a 'teacher' dəyərini əlavə et
alter table public.support_messages drop constraint if exists support_messages_sender_role_check;
alter table public.support_messages add constraint support_messages_sender_role_check
  check (sender_role in ('user','admin','director','teacher'));

-- 2) SELECT siyasətini yenilə — müəllim öz sinfinin şagirdlərinin söhbətini görə bilsin
drop policy if exists "support_messages_select" on public.support_messages;
create policy "support_messages_select"
  on public.support_messages for select
  to authenticated
  using (
    exists(select 1 from public.profiles p where p.id = auth.uid() and p.username = support_messages.username)
    or public.is_admin(auth.uid())
    or public.is_director(auth.uid())
    or exists(
      select 1 from public.profiles p
      where p.username = support_messages.username
        and p.class_grade <> ''
        and public.is_teacher_of(auth.uid(), p.class_grade)
    )
  );

-- 3) send_support_message() — müəllim YALNIZ öz sinfinin şagirdinə yaza bilər
create or replace function public.send_support_message(p_username text, p_body text)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_caller_username text;
  v_role text;
  v_teacher_class text;
  v_body text := trim(coalesce(p_body,''));
begin
  select username, role, teacher_class into v_caller_username, v_role, v_teacher_class
    from public.profiles where id = auth.uid();
  if v_caller_username is null then
    raise exception 'Profil tapılmadı';
  end if;
  if char_length(v_body) = 0 or char_length(v_body) > 1000 then
    raise exception 'Mesaj boş və ya çox uzundur';
  end if;

  if v_role = 'admin' or v_role = 'director' then
    if not exists(select 1 from public.profiles where username = p_username) then
      raise exception 'İstifadəçi tapılmadı';
    end if;
    insert into public.support_messages(username, sender_role, sender_name, body)
    values (p_username, v_role, v_caller_username, v_body);
  elsif v_role = 'teacher' then
    if not exists(select 1 from public.profiles where username = p_username and class_grade = v_teacher_class) then
      raise exception 'Bu şagird sizin sinfinizdə deyil';
    end if;
    insert into public.support_messages(username, sender_role, sender_name, body)
    values (p_username, 'teacher', v_caller_username, v_body);
  else
    insert into public.support_messages(username, sender_role, sender_name, body)
    values (v_caller_username, 'user', v_caller_username, v_body);
  end if;
end;
$$;

grant execute on function public.send_support_message(text, text) to authenticated;

-- 4) mark_support_read() — müəllim öz sinfinin şagird mesajlarını "oxunub" işarələyə bilsin,
--    şagird isə artıq admin/direktor/müəllim mesajlarının hamısını "oxunub" işarələsin.
create or replace function public.mark_support_read(p_username text)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_caller_username text;
  v_role text;
  v_teacher_class text;
begin
  select username, role, teacher_class into v_caller_username, v_role, v_teacher_class
    from public.profiles where id = auth.uid();

  if v_role = 'admin' or v_role = 'director' then
    update public.support_messages set read = true
      where username = p_username and sender_role = 'user' and read = false;
  elsif v_role = 'teacher' and exists(select 1 from public.profiles where username = p_username and class_grade = v_teacher_class) then
    update public.support_messages set read = true
      where username = p_username and sender_role = 'user' and read = false;
  elsif v_caller_username = p_username then
    update public.support_messages set read = true
      where username = p_username and sender_role in ('admin','director','teacher') and read = false;
  end if;
end;
$$;

grant execute on function public.mark_support_read(text) to authenticated;


-- ════════════════════════════════════════════════════════════════════════
-- [19/25]  supabase_update_word_contrib.sql
-- Söz Kəşf Et
-- ════════════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════
-- SözLab — Söz Kəşf Et (şagirdlərin yeni söz mənası əlavə etməsi).
-- Bu skripti Supabase Dashboard → SQL Editor-da açıb "Run" edin.
-- ÖNCƏ supabase_setup.sql və supabase_update_teacher_and_league.sql-in
-- run edildiyini fərz edir (compute_level(), is_admin() buradan istifadə olunur).
-- (Bu skripti əvvəllər bir dəfə run etmisinizsə, təkrar run etmək TAM
--  TƏHLÜKƏSİZDİR — bütün "create/alter" sətirləri idempotentdir və mövcud
--  məlumatları silmir, sadəcə yeni "flagged" statusunu/məntiqini əlavə edir.)
--
-- Necə işləyir: sayta "word_pool.json" faylından (SözLab lüğətində hələ
-- olmayan ~82 000 Azərbaycan sözü) təsadüfi söz göstərilir, şagird onun
-- mənasını (məs. azleks.az saytından və ya bildiyi kimi) yazıb göndərir.
--
-- KEYFİYYƏT NƏZARƏTİ: göndərilən məna serverdə avtomatik yoxlanılır
-- (public.is_low_quality_definition() — klaviatura-mələşdirmə, hərf təkrarı,
-- saitsiz "söz", tək tokenli cavab və s.). Real izah kimi görünürsə → dərhal
-- "pending" olur və şagird DƏRHAL +1 XP alır (əvvəlki kimi). Şübhəli
-- görünürsə → "flagged" statusu ilə admin panelində 🚩 işarəsi ilə göstərilir
-- və şagird XP-ni YALNIZ admin bəyənəndə alır (admin rədd etsə, heç vaxt).
-- Beləliklə heç bir göndəriş itmir/avtomatik silinmir — sadəcə açıq-aşkar
-- uydurma cavablar XP-ni "admin təsdiqinə qədər" gözlədir.
--
-- Admin bəyənəndə söz "community_words" cədvəlinə keçir və HƏMİN AN
-- bütün saytda (lüğət, oyunlar, canlı yarışma və s.) görünməyə başlayır —
-- kodu yenidən deploy etməyə ehtiyac YOXDUR.
-- ════════════════════════════════════════════════════════════════

-- 1) GÖNDƏRİŞLƏR CƏDVƏLİ
create table if not exists public.word_submissions (
  id bigint generated always as identity primary key,
  username text not null,
  display_name text not null default '',
  word text not null,
  definition text not null,
  example text not null default '',
  status text not null default 'pending' check (status in ('pending','flagged','approved','rejected')),
  xp_awarded boolean not null default false,
  submitted_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by text
);
-- Skript əvvəllər run edilibsə, köhnə "status" check-i "flagged" dəyərini
-- qəbul etməyəcək və sütun yeni olmaya bilər — hər ikisini təhlükəsiz yenilə:
alter table public.word_submissions add column if not exists xp_awarded boolean not null default false;
alter table public.word_submissions drop constraint if exists word_submissions_status_check;
alter table public.word_submissions add constraint word_submissions_status_check
  check (status in ('pending','flagged','approved','rejected'));
-- Əvvəllər "pending" olaraq göndərilib artıq XP almış sətirləri qeyd et (geriyə uyğunluq).
update public.word_submissions set xp_awarded = true where status in ('pending','approved') and xp_awarded = false;

create index if not exists idx_word_sub_username on public.word_submissions (username, submitted_at desc);
create index if not exists idx_word_sub_status on public.word_submissions (status, submitted_at desc);

alter table public.word_submissions enable row level security;

drop policy if exists "word_sub_select" on public.word_submissions;
create policy "word_sub_select"
  on public.word_submissions for select
  to authenticated
  using (
    public.is_admin(auth.uid())
    or exists(select 1 from public.profiles p where p.id = auth.uid() and p.username = word_submissions.username)
  );

-- QEYD: insert/update birbaşa YOXDUR — yalnız aşağıdakı RPC-lər vasitəsilə.

-- 2) TƏSDİQLƏNMİŞ SÖZLƏR CƏDVƏLİ (canlı lüğətə əlavə olunanlar)
create table if not exists public.community_words (
  id bigint generated always as identity primary key,
  en text not null,
  az text not null,
  ex text not null default '',
  ex_az text not null default '',
  tags jsonb not null default '[]'::jsonb,
  difficulty integer not null default 2,
  added_by text not null default '',
  added_at timestamptz not null default now(),
  source_submission_id bigint references public.word_submissions(id) on delete set null
);

alter table public.community_words enable row level security;

-- Bütün daxil olmuş istifadəçilər oxuya bilir — çünki hər cihaz açılışda
-- bunları öz lüğətinə (WORDS massivinə) əlavə edir.
drop policy if exists "community_words_select" on public.community_words;
create policy "community_words_select"
  on public.community_words for select
  to authenticated
  using (true);

-- QEYD: insert/update birbaşa YOXDUR — yalnız admin RPC-si vasitəsilə.

-- 3) is_low_quality_definition() — sadə, sürətli "uydurma cavab" filtri.
--    Real söz/cümlədə həmişə olan xüsusiyyətlərin YOXLUĞUNU axtarır:
--    klaviatura-mələşdirmə, 4+ ardıcıl eyni hərf, saitsiz mətn, çox aşağı
--    hərf müxtəlifliyi, tək tokenli (2-dən az sözlü) cavab. Heç biri 100%
--    dəqiq deyil — ona görə HEÇ NƏYİ avtomatik RƏDD ETMİR, sadəcə admin
--    təsdiqinə qədər XP-ni gecikdirir ("flagged").
create or replace function public.is_low_quality_definition(p_def text)
returns boolean
language plpgsql
immutable
as $$
declare
  v_def text := lower(trim(p_def));
  v_letters text;
  v_unique_count integer;
  v_tokens text[];
  v_has_vowel boolean;
begin
  if v_def ~ '(.)\1{3,}' then return true; end if;
  if v_def ~ '(asdf|asdas|qwer|zxcv|qwerty|jkl;|hjkl|lkjh)' then return true; end if;

  v_has_vowel := v_def ~ '[aeəiıoöuü]';
  if not v_has_vowel then return true; end if;

  v_letters := regexp_replace(v_def, '[^a-zəiıöüşçğ]', '', 'gi');
  if length(v_letters) >= 6 then
    select count(distinct x) into v_unique_count from unnest(string_to_array(v_letters, null)) as x;
    if v_unique_count < 4 then return true; end if;
  end if;

  v_tokens := array_remove(
    regexp_split_to_array(trim(regexp_replace(v_def, '[^[:alnum:]əiıöüşçğ]', ' ', 'gi')), '\s+'),
    ''
  );
  if array_length(v_tokens, 1) is null or array_length(v_tokens, 1) < 2 then return true; end if;

  return false;
end;
$$;

-- 4) submit_word_definition() — şagird yeni söz mənası göndərir.
--    Gündə maksimum 100 göndəriş (bax "flagged" olanlar da limitə daxildir —
--    əks halda zibil göndərişlə admin növbəsi sonsuz doldurula bilər).
--    Keyfiyyətli görünən cavaba DƏRHAL +1 XP, şübhəli olana admin bəyənəndə.
create or replace function public.submit_word_definition(p_word text, p_definition text, p_example text default '')
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_username text;
  v_display text;
  v_role text;
  v_today_count integer;
  v_word text := trim(p_word);
  v_def text := trim(p_definition);
  v_ex text := trim(coalesce(p_example, ''));
  v_new_xp integer;
  v_flagged boolean;
  v_status text;
begin
  select username, display_name, role into v_username, v_display, v_role from public.profiles where id = auth.uid();
  if v_username is null then
    raise exception 'Profil tapılmadı';
  end if;
  if v_role <> 'user' then
    raise exception 'Yalnız şagirdlər söz göndərə bilər';
  end if;
  if v_word = '' or length(v_word) < 2 then
    raise exception 'Söz düzgün deyil';
  end if;
  if v_def = '' or length(v_def) < 5 then
    raise exception 'Məna ən azı 5 hərf olmalıdır';
  end if;
  if lower(v_def) = lower(v_word) then
    raise exception 'Məna sözün özü ola bilməz';
  end if;

  if exists(select 1 from public.word_submissions where username = v_username and lower(word) = lower(v_word)) then
    raise exception 'Bu sözü artıq göndərmisiniz';
  end if;

  select count(*) into v_today_count
    from public.word_submissions
    where username = v_username and submitted_at::date = (now() at time zone 'UTC')::date;
  if v_today_count >= 100 then
    raise exception 'Bugünlük limitə çatdınız (100/100) — sabah davam edin';
  end if;

  v_flagged := public.is_low_quality_definition(v_def);
  v_status := case when v_flagged then 'flagged' else 'pending' end;

  insert into public.word_submissions(username, display_name, word, definition, example, status, xp_awarded)
  values (v_username, coalesce(v_display, v_username), v_word, v_def, v_ex, v_status, not v_flagged);

  if v_flagged then
    select xp into v_new_xp from public.profiles where username = v_username;
  else
    update public.profiles set xp = xp + 1, level = public.compute_level(xp + 1) where username = v_username
      returning xp into v_new_xp;
    perform public.log_xp_gain(v_username, (now() at time zone 'UTC')::date, 1);
  end if;

  return jsonb_build_object('today_count', v_today_count + 1, 'xp', v_new_xp, 'flagged', v_flagged);
end;
$$;

grant execute on function public.submit_word_definition(text, text, text) to authenticated;

-- 5) admin_review_word_submission() — admin göndərişi bəyənir/rədd edir.
--    "pending" VƏ "flagged" hər ikisi baxıla bilər. Bəyənilsə, söz dərhal
--    community_words-a keçir (canlı görünür). Əgər bu göndəriş "flagged" idisə
--    və hələ XP alınmayıbsa, MƏHZ İNDİ (bəyənilmə anında) +1 XP verilir.
create or replace function public.admin_review_word_submission(
  p_submission_id bigint, p_approve boolean, p_difficulty integer default 2, p_tags jsonb default '["Community"]'::jsonb
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_admin text;
  v_row public.word_submissions;
begin
  select username into v_admin from public.profiles where id = auth.uid();
  if not public.is_admin(auth.uid()) then
    raise exception 'Yalnız adminlər baxa bilər';
  end if;

  select * into v_row from public.word_submissions where id = p_submission_id for update;
  if v_row is null then
    raise exception 'Göndəriş tapılmadı';
  end if;
  if v_row.status not in ('pending','flagged') then
    raise exception 'Bu göndəriş artıq baxılıb';
  end if;

  update public.word_submissions
    set status = case when p_approve then 'approved' else 'rejected' end,
        reviewed_at = now(), reviewed_by = v_admin
    where id = p_submission_id;

  if p_approve and not v_row.xp_awarded then
    update public.profiles set xp = xp + 1, level = public.compute_level(xp + 1) where username = v_row.username;
    update public.word_submissions set xp_awarded = true where id = p_submission_id;
    perform public.log_xp_gain(v_row.username, (now() at time zone 'UTC')::date, 1);
  end if;

  if p_approve then
    insert into public.community_words(en, az, ex, ex_az, tags, difficulty, added_by, source_submission_id)
    values (v_row.word, v_row.definition, coalesce(nullif(v_row.example,''), v_row.word || '.'), v_row.example,
            p_tags, p_difficulty, v_row.username, v_row.id);
  end if;
end;
$$;

grant execute on function public.admin_review_word_submission(bigint, boolean, integer, jsonb) to authenticated;

-- 6) admin_export_community_words() — admin üçün JSON ixracı (istəsə xarici
--    ehtiyat nüsxə/sənəd kimi saxlasın).
create or replace function public.admin_export_community_words()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'Yalnız adminlər ixrac edə bilər';
  end if;

  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'en', en, 'az', az, 'ex', ex, 'exAz', ex_az, 'tags', tags, 'difficulty', difficulty
    ) order by added_at), '[]'::jsonb)
    from public.community_words
  );
end;
$$;

grant execute on function public.admin_export_community_words() to authenticated;

-- 7) admin_add_word_direct() — admin panelindəki "➕ Yeni Söz Əlavə Et"
--    formasından SÖZÜ BİRBAŞA lüğətə əlavə edir (Söz Kəşf Et göndərişindən
--    fərqli olaraq — bura heç bir şagird göndərişi yoxdur, admin özü yazır).
--    ƏVVƏLLƏR bu, YALNIZ brauzer yaddaşına (WORDS.push) yazılırdı və səhifə
--    yenilənəndə/başqa cihazda itirdi. İndi community_words cədvəlinə yazılır
--    və digər söz mənbələri kimi bütün saytda/cihazlarda dərhal görünür.
create or replace function public.admin_add_word_direct(
  p_en text, p_az text, p_ex text default '', p_ex_az text default '',
  p_tags jsonb default '["B2"]'::jsonb, p_difficulty integer default 2
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_en text := trim(p_en);
  v_az text := trim(p_az);
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'Yalnız adminlər söz əlavə edə bilər';
  end if;
  if v_en = '' or v_az = '' then
    raise exception 'Söz və məna mütləqdir';
  end if;
  if exists(select 1 from public.community_words where lower(en) = lower(v_en)) then
    raise exception 'Bu söz artıq lüğətdədir';
  end if;

  insert into public.community_words(en, az, ex, ex_az, tags, difficulty, added_by, source_submission_id)
  values (
    v_en, v_az,
    coalesce(nullif(trim(p_ex), ''), v_en || '.'),
    trim(coalesce(p_ex_az, '')),
    coalesce(p_tags, '["B2"]'::jsonb),
    coalesce(p_difficulty, 2),
    coalesce((select username from public.profiles where id = auth.uid()), ''),
    null
  );
end;
$$;

grant execute on function public.admin_add_word_direct(text, text, text, text, jsonb, integer) to authenticated;


-- ════════════════════════════════════════════════════════════════════════
-- [20/25]  supabase_update_school205.sql
-- 205 məktəb portalı
-- ════════════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════
-- SözLab — "205 Smart School" inteqrasiyası üçün əlavə SQL
-- Bu skripti Supabase Dashboard → SQL Editor-da açıb "Run" edin.
-- Mövcud cədvəlləri POZMUR. ÖNCƏ bu skriptlərin run edildiyini fərz edir:
--   1) supabase_update_teacher_and_league.sql   (teacher_class, is_teacher_of())
--   2) supabase_update_director_and_tasks.sql   (is_director())
-- ════════════════════════════════════════════════════════════════

-- 0) Ümumi köməkçi funksiya: admin/direktor/müəllim (istənilən sinif) — "məktəb heyəti"
create or replace function public.is_school_staff(uid uuid)
returns boolean
language sql
security definer set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = uid and role in ('admin','director','teacher')
  );
$$;

grant execute on function public.is_school_staff(uuid) to authenticated;

-- ─────────────────────────────────────────────
-- 1) MƏKTƏB HAQQINDA — tək sətirlik "ayarlar" cədvəli (missiya mətni, ünvan və s.)
-- ─────────────────────────────────────────────
create table if not exists public.school_info (
  id smallint primary key default 1 check (id = 1),
  school_name text not null default '',
  about_text text not null default '',
  address text not null default '',
  phone text not null default '',
  email text not null default '',
  cover_image_url text not null default '',
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now()
);
insert into public.school_info (id) values (1) on conflict (id) do nothing;

alter table public.school_info enable row level security;

drop policy if exists "school_info_select_all" on public.school_info;
create policy "school_info_select_all"
  on public.school_info for select
  to anon, authenticated
  using (true);

drop policy if exists "school_info_update_staff" on public.school_info;
create policy "school_info_update_staff"
  on public.school_info for update
  to authenticated
  using (public.is_school_staff(auth.uid()))
  with check (public.is_school_staff(auth.uid()));

-- ─────────────────────────────────────────────
-- 2) XƏBƏRLƏR
-- ─────────────────────────────────────────────
create table if not exists public.school_news (
  id bigint generated always as identity primary key,
  title text not null check (char_length(title) between 1 and 200),
  body text not null default '',
  image_url text not null default '',
  published boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create index if not exists idx_school_news_created on public.school_news (published, created_at desc);

alter table public.school_news enable row level security;

drop policy if exists "school_news_select" on public.school_news;
create policy "school_news_select"
  on public.school_news for select
  to anon, authenticated
  using (published or public.is_school_staff(auth.uid()));

drop policy if exists "school_news_write_staff" on public.school_news;
create policy "school_news_write_staff"
  on public.school_news for insert
  to authenticated
  with check (public.is_school_staff(auth.uid()));

drop policy if exists "school_news_update_staff" on public.school_news;
create policy "school_news_update_staff"
  on public.school_news for update
  to authenticated
  using (public.is_school_staff(auth.uid()));

drop policy if exists "school_news_delete_staff" on public.school_news;
create policy "school_news_delete_staff"
  on public.school_news for delete
  to authenticated
  using (public.is_school_staff(auth.uid()));

-- ─────────────────────────────────────────────
-- 3) TƏDBİRLƏR
-- ─────────────────────────────────────────────
create table if not exists public.school_events (
  id bigint generated always as identity primary key,
  title text not null check (char_length(title) between 1 and 200),
  description text not null default '',
  event_date date,
  location text not null default '',
  image_url text not null default '',
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create index if not exists idx_school_events_date on public.school_events (event_date desc);

alter table public.school_events enable row level security;

drop policy if exists "school_events_select_all" on public.school_events;
create policy "school_events_select_all"
  on public.school_events for select
  to anon, authenticated
  using (true);

drop policy if exists "school_events_write_staff" on public.school_events;
create policy "school_events_write_staff"
  on public.school_events for insert
  to authenticated
  with check (public.is_school_staff(auth.uid()));

drop policy if exists "school_events_update_staff" on public.school_events;
create policy "school_events_update_staff"
  on public.school_events for update
  to authenticated
  using (public.is_school_staff(auth.uid()));

drop policy if exists "school_events_delete_staff" on public.school_events;
create policy "school_events_delete_staff"
  on public.school_events for delete
  to authenticated
  using (public.is_school_staff(auth.uid()));

-- ─────────────────────────────────────────────
-- 4) MÜƏLLİMLƏR (ictimai profil kartları — profiles-dan ayrı, çünki hər müəllimin
--    SözLab hesabı olmaya bilər, sadəcə vizit kartı kimi göstərilir)
-- ─────────────────────────────────────────────
create table if not exists public.school_teachers (
  id bigint generated always as identity primary key,
  full_name text not null check (char_length(full_name) between 1 and 120),
  subject text not null default '',
  photo_url text not null default '',
  bio text not null default '',
  sort_order int not null default 0,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create index if not exists idx_school_teachers_sort on public.school_teachers (sort_order, full_name);

alter table public.school_teachers enable row level security;

drop policy if exists "school_teachers_select_all" on public.school_teachers;
create policy "school_teachers_select_all"
  on public.school_teachers for select
  to anon, authenticated
  using (true);

drop policy if exists "school_teachers_write_staff" on public.school_teachers;
create policy "school_teachers_write_staff"
  on public.school_teachers for insert
  to authenticated
  with check (public.is_school_staff(auth.uid()));

drop policy if exists "school_teachers_update_staff" on public.school_teachers;
create policy "school_teachers_update_staff"
  on public.school_teachers for update
  to authenticated
  using (public.is_school_staff(auth.uid()));

drop policy if exists "school_teachers_delete_staff" on public.school_teachers;
create policy "school_teachers_delete_staff"
  on public.school_teachers for delete
  to authenticated
  using (public.is_school_staff(auth.uid()));

-- ─────────────────────────────────────────────
-- 5) NAİLİYYƏTLƏR (məktəb səviyyəli, admin/müəllim əlavə edir)
-- ─────────────────────────────────────────────
create table if not exists public.school_achievements (
  id bigint generated always as identity primary key,
  title text not null check (char_length(title) between 1 and 200),
  description text not null default '',
  achieved_on date,
  image_url text not null default '',
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create index if not exists idx_school_achievements_date on public.school_achievements (achieved_on desc);

alter table public.school_achievements enable row level security;

drop policy if exists "school_achievements_select_all" on public.school_achievements;
create policy "school_achievements_select_all"
  on public.school_achievements for select
  to anon, authenticated
  using (true);

drop policy if exists "school_achievements_write_staff" on public.school_achievements;
create policy "school_achievements_write_staff"
  on public.school_achievements for insert
  to authenticated
  with check (public.is_school_staff(auth.uid()));

drop policy if exists "school_achievements_update_staff" on public.school_achievements;
create policy "school_achievements_update_staff"
  on public.school_achievements for update
  to authenticated
  using (public.is_school_staff(auth.uid()));

drop policy if exists "school_achievements_delete_staff" on public.school_achievements;
create policy "school_achievements_delete_staff"
  on public.school_achievements for delete
  to authenticated
  using (public.is_school_staff(auth.uid()));

-- ─────────────────────────────────────────────
-- 6) ŞAGİRD TƏQDİMATLARI — Layihələr / İdeya bankı / Startap (vahid cədvəl,
--    "type" sütunu ilə ayrılır — moderasiya axını üçün ortaq).
-- ─────────────────────────────────────────────
create table if not exists public.school_submissions (
  id bigint generated always as identity primary key,
  student_id uuid not null references auth.users(id) on delete cascade,
  type text not null check (type in ('project','idea','startup')),
  title text not null check (char_length(title) between 1 and 200),
  description text not null default '',
  file_url text not null default '',
  image_url text not null default '',
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  admin_note text not null default '',
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists idx_school_submissions_student on public.school_submissions (student_id, created_at desc);
create index if not exists idx_school_submissions_status on public.school_submissions (type, status, created_at desc);

alter table public.school_submissions enable row level security;

-- Görmə: öz təqdimatını hər zaman görür; heyət hamısını görür;
-- "approved" olanlar hamıya açıqdır (portfolio/nailiyyət kimi göstərmək üçün).
drop policy if exists "school_submissions_select" on public.school_submissions;
create policy "school_submissions_select"
  on public.school_submissions for select
  to anon, authenticated
  using (
    status = 'approved'
    or student_id = auth.uid()
    or public.is_school_staff(auth.uid())
  );

drop policy if exists "school_submissions_insert_own" on public.school_submissions;
create policy "school_submissions_insert_own"
  on public.school_submissions for insert
  to authenticated
  with check (student_id = auth.uid());

-- Yeniləmə: şagird YALNIZ "pending" vəziyyətdə öz mətnini redaktə edə bilər
-- (status/admin_note/reviewed_* sahələrini dəyişə bilməz — bunu trigger qoruyur).
-- Heyət isə status/qeyd təyin edə bilər.
drop policy if exists "school_submissions_update" on public.school_submissions;
create policy "school_submissions_update"
  on public.school_submissions for update
  to authenticated
  using (
    (student_id = auth.uid() and status = 'pending')
    or public.is_school_staff(auth.uid())
  )
  with check (
    (student_id = auth.uid())
    or public.is_school_staff(auth.uid())
  );

create or replace function public.prevent_submission_self_review()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if auth.uid() = old.student_id and not public.is_school_staff(auth.uid()) then
    new.status := old.status;
    new.admin_note := old.admin_note;
    new.reviewed_by := old.reviewed_by;
    new.reviewed_at := old.reviewed_at;
  end if;
  if public.is_school_staff(auth.uid()) and new.status is distinct from old.status then
    new.reviewed_by := auth.uid();
    new.reviewed_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_submission_self_review on public.school_submissions;
create trigger trg_prevent_submission_self_review
  before update on public.school_submissions
  for each row execute function public.prevent_submission_self_review();

drop policy if exists "school_submissions_delete" on public.school_submissions;
create policy "school_submissions_delete"
  on public.school_submissions for delete
  to authenticated
  using (
    (student_id = auth.uid() and status = 'pending')
    or public.is_school_staff(auth.uid())
  );

-- ─────────────────────────────────────────────
-- 7) ŞAGİRD PORTFOLİOSU — approved təqdimatlar + profil məlumatı birləşdirilmiş görünüş
-- ─────────────────────────────────────────────
create or replace view public.school_portfolio as
  select
    s.id, s.type, s.title, s.description, s.image_url, s.created_at,
    p.username, p.display_name, p.class_grade, p.equipped_frame
  from public.school_submissions s
  join public.profiles p on p.id = s.student_id
  where s.status = 'approved';

grant select on public.school_portfolio to anon, authenticated;

-- ─────────────────────────────────────────────
-- 8) STORAGE — "school-uploads" bucket (şəkil/fayl üçün)
--    QEYD: bucket-i Supabase Dashboard → Storage bölməsindən "New bucket" ilə
--    "school-uploads" adıyla, Public = ON olaraq YARADIN (bu skript onu yaratmır,
--    yalnız access policy-lərini qurur).
-- ─────────────────────────────────────────────
drop policy if exists "school_uploads_read_all" on storage.objects;
create policy "school_uploads_read_all"
  on storage.objects for select
  to anon, authenticated
  using (bucket_id = 'school-uploads');

drop policy if exists "school_uploads_insert_own" on storage.objects;
create policy "school_uploads_insert_own"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'school-uploads'
    and (owner = auth.uid() or public.is_school_staff(auth.uid()))
  );

drop policy if exists "school_uploads_delete_own" on storage.objects;
create policy "school_uploads_delete_own"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'school-uploads'
    and (owner = auth.uid() or public.is_school_staff(auth.uid()))
  );

-- ════════════════════════════════════════════════════════════════
-- QEYD: "school_info" cədvəlinin ilk sətrini doldurmaq üçün (Məktəb haqqında
-- mətni, ünvan, telefon və s.) — məlumatlar hazır olanda bunu run edin:
--
-- update public.school_info set
--   school_name = 'Rövşən İmanov adına 205 nömrəli tam orta məktəb',
--   address     = 'Mətbuat 107, Binəqədi, Bakı, AZ1053',
--   phone       = '(+994 12) 411-19-98',
--   email       = '205mekteb@bakuedu.gov.az',
--   about_text  = 'BURAYA MƏKTƏBİN HAQQINDA MƏTNİ YAZILACAQ'
-- where id = 1;
-- ════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════════
-- [21/25]  supabase_update_school205_content.sql
-- 205 portal məzmunu
-- ════════════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════════════
-- SözLab — 205 nömrəli məktəb portalı: rəsmi məzmun + qeydiyyat inteqrasiyası
--
-- Bu fayl SIFIRDAN yeni sistem qurmur — MÖVCUD SözLab cədvəllərinin üzərinə
-- əlavə edir:
--   • profiles            → telefon sütunu (qeydiyyatda tələb olunur)
--   • handle_new_user()   → telefon/ad/soyad/sinif metadata-dan profilə yazılır
--   • school_info         → Rövşən İmanovun həyat və döyüş yolu, əlaqə
--   • school_teachers     → məktəb rəhbərliyi (9 nəfər)
--   • school_news         → kateqoriya/bölmə/müəllif/açar söz + 7 rəsmi xəbər
--   • school_events       → 5 tədbir
--   • school_achievements → 6 şagird nailiyyəti
--
-- ƏVVƏLCƏ supabase_update_school205.sql işlədilməlidir (cədvəlləri o yaradır).
-- Supabase → SQL Editor → bu faylı yapışdır → Run.
-- Təkrar-təkrar işlətmək təhlükəsizdir (idempotent).
-- ══════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────
-- 1) PROFİLƏ TELEFON SÜTUNU
--    Qeydiyyat formasında ad, soyad, e-poçt artıq var idi;
--    telefon nömrəsi əlavə olunur.
-- ─────────────────────────────────────────────────────────────
alter table public.profiles add column if not exists phone text not null default '';

comment on column public.profiles.phone is '205 portalı qeydiyyatında tələb olunan əlaqə nömrəsi';


-- ─────────────────────────────────────────────────────────────
-- 2) QEYDİYYAT TRIGGER-İNİ GENİŞLƏNDİR
--    Əvvəllər yalnız username + display_name köçürülürdü.
--    İndi telefon, ad, soyad və sinif də auth metadata-dan profilə keçir.
-- ─────────────────────────────────────────────────────────────
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $fn$
-- BİRLƏŞDİRİLMİŞ QEYDİYYAT TRIGGER-İ
-- Bu funksiya əvvəl 4 ayrı skriptdə yazılmışdı və hər biri əvvəlkini üst-üstə
-- yazırdı. Sonuncu variant (205 portalı) telefonu əlavə etmiş, amma ad/soyadı
-- və dəvət bonusunu itirmişdi — yeni şagirdlərin profilində ad-soyad boş
-- qalırdı, dəvət kodu işləmirdi. İndi hamısı birlikdədir:
--   username · display_name · ad · soyad · sinif · telefon · dəvət (+20 XP)
declare
  v_username     text;
  v_display_name text;
  v_first_name   text;
  v_last_name    text;
  v_class_grade  text;
  v_phone        text;
  v_referred_by  text;
  v_bonus_xp     integer := 0;
begin
  v_username     := lower(coalesce(new.raw_user_meta_data->>'username', 'user_' || substr(new.id::text, 1, 8)));
  v_first_name   := trim(coalesce(new.raw_user_meta_data->>'first_name', ''));
  v_last_name    := trim(coalesce(new.raw_user_meta_data->>'last_name', ''));
  v_display_name := coalesce(nullif(trim(new.raw_user_meta_data->>'display_name'), ''),
                             nullif(trim(v_first_name || ' ' || v_last_name), ''), v_username);
  v_class_grade  := upper(trim(coalesce(new.raw_user_meta_data->>'class_grade', '')));
  v_phone        := trim(coalesce(new.raw_user_meta_data->>'phone', ''));
  v_referred_by  := lower(trim(coalesce(new.raw_user_meta_data->>'referred_by', '')));

  if v_username !~ '^[a-z0-9_]{3,20}$' or exists (select 1 from public.profiles p where p.username = v_username) then
    v_username := 'user_' || substr(new.id::text, 1, 8);
  end if;

  -- Form 1–11 və A–D təklif edir; başqa dəyər gəlsə boş saxlanılır
  if v_class_grade !~ '^(1[01]|[1-9])[A-D]$' then
    v_class_grade := '';
  end if;

  -- Dəvət kodu = dəvət edənin username-i. Özünə istinad və mövcud olmayan
  -- kod sakitcə görməzdən gəlinir (qeydiyyat heç vaxt buna görə sınmamalıdır).
  if v_referred_by <> '' and v_referred_by <> v_username
     and exists (select 1 from public.profiles p where p.username = v_referred_by) then
    v_bonus_xp := 20;
    update public.profiles
       set xp = xp + 20, level = public.compute_level(xp + 20)
     where username = v_referred_by;
  else
    v_referred_by := '';
  end if;

  insert into public.profiles
    (id, username, display_name, first_name, last_name, class_grade, phone,
     xp, level, streak, learned, badges, role, last_visit, referred_by)
  values
    (new.id, v_username, v_display_name, v_first_name, v_last_name, v_class_grade, v_phone,
     v_bonus_xp, public.compute_level(v_bonus_xp), 0, '{}', '{}', 'user', null, v_referred_by)
  on conflict (id) do nothing;

  return new;
end;
$fn$;


-- ─────────────────────────────────────────────────────────────
-- 3) MƏZMUN CƏDVƏLLƏRİNƏ TAKSONOMİYA SÜTUNLARI
--    category → istifadəçinin təsdiqlədiyi 11 kateqoriyadan biri
--    section  → daha dar alt-bölmə
--    author   → materialın müəllifi / mənbəyi
--    keywords → AI köməkçinin axtarışı üçün açar sözlər
-- ─────────────────────────────────────────────────────────────
alter table public.school_news         add column if not exists category text not null default 'Məktəb həyatı';
alter table public.school_news         add column if not exists section  text not null default '';
alter table public.school_news         add column if not exists author   text not null default 'Məktəb rəhbərliyi';
alter table public.school_news         add column if not exists keywords text[] not null default '{}';
alter table public.school_news         add column if not exists published_at date not null default current_date;
alter table public.school_news         add column if not exists gallery text[] not null default '{}';

alter table public.school_events       add column if not exists category text not null default 'Tədbirlər';
alter table public.school_events       add column if not exists section  text not null default '';
alter table public.school_events       add column if not exists author   text not null default 'Məktəb rəhbərliyi';
alter table public.school_events       add column if not exists keywords text[] not null default '{}';

alter table public.school_achievements add column if not exists category text not null default 'Şagird nailiyyətləri';
alter table public.school_achievements add column if not exists section  text not null default '';
alter table public.school_achievements add column if not exists author   text not null default 'Məktəb rəhbərliyi';
alter table public.school_achievements add column if not exists keywords text[] not null default '{}';
alter table public.school_achievements add column if not exists student_name text not null default '';
alter table public.school_achievements add column if not exists class_name   text not null default '';

create index if not exists idx_school_news_category on public.school_news (category, published_at desc);


-- ─────────────────────────────────────────────────────────────
-- 4) MƏKTƏB HAQQINDA — Rövşən İmanovun həyat və döyüş yolu
-- ─────────────────────────────────────────────────────────────
update public.school_info set
  school_name = $$Rövşən İmanov adına 205 nömrəli tam orta məktəb$$,
  about_text = $$Rövşən İmanov 1969-cu il iyunun 27-də Bakı şəhərində anadan olub.

Hələ uşaqlıq illərindən vətənpərvər ruhda böyüyən Rövşən daim Vətəni qorumaq və onun keşiyində durmaq arzusu ilə yaşayıb.

O, 1976-cı ildə 205 nömrəli orta məktəbin birinci sinfinə daxil olub. 1984-cü ildə səkkizillik orta təhsilini başa vurduqdan sonra 68 nömrəli texniki-peşə məktəbində ixtisas təhsili alıb.

1987–1989-cu illərdə ordu sıralarında hərbi xidmətini uğurla başa vurub.

1991-ci ildə Xüsusi Polis Dəstəsinə daxil olan Rövşən Daşaltı, Kərkicahan, Şuşa, Goranboy və digər yaşayış məntəqələri ətrafında baş verən döyüşlərdə qəhrəmanlıq göstərib.

1992-ci il iyulun 22-də Ağdərədə düşmənin hücumunu dəf edərkən qəhrəmancasına şəhid olub.

Elə həmin il Rövşən Nadir oğlu İmanovun adı 205 nömrəli tam orta məktəbə verilib.$$,
  address = $$Mətbuat prospekti 107, Binəqədi rayonu, Bakı, AZ1053$$,
  phone   = $$(+994 12) 411-19-98$$,
  email   = $$205mekteb@bakuedu.gov.az$$,
  cover_image_url = $$school205/sagird-toplantisi.jpg$$,
  updated_at = now()
where id = 1;


-- ─────────────────────────────────────────────────────────────
-- 5) MƏKTƏB RƏHBƏRLİYİ (material 08)
-- ─────────────────────────────────────────────────────────────
delete from public.school_teachers;

insert into public.school_teachers (full_name, subject, photo_url, bio, sort_order) values
  ($$Əliheydər Əlifli Elman$$,   $$Direktor$$,                                                        $$school205/direktor-cixisi.jpg$$, $$Məktəb-valideyn əməkdaşlığının şagird uğurundakı rolunu daim vurğulayır; sağlam və nizamlı təhsil mühitinin yaradılmasını prioritet sayır.$$, 1),
  ($$Aynur Ələsgərova Cavid$$,   $$Təlim-tərbiyə işləri üzrə direktor müavini$$,                       $$$$, $$Tədrisin keyfiyyətinin yüksəldilməsi, şagird nailiyyətlərinin artırılması və təhsil nəticələrinin yaxşılaşdırılması istiqamətində işləri əlaqələndirir.$$, 2),
  ($$Vüsalə Rəcəbova Fərhad$$,   $$Məktəbdənkənar və sinifdənxaric tərbiyə işi üzrə təşkilatçı$$,      $$$$, $$$$, 3),
  ($$Zilfi Zilfiyev Baxış$$,     $$Direktorun təsərrüfat işləri üzrə müavini (təsərrüfat müdiri)$$,    $$$$, $$$$, 4),
  ($$Emin Əliyev Telman$$,       $$Çağırışaqədərki hazırlıq rəhbəri$$,                                 $$$$, $$$$, 5),
  ($$Zülfiyyə Məsimova Qənbər$$, $$Məktəb psixoloqu$$,                                                 $$$$, $$$$, 6),
  ($$Aytən Məmmədova Səadət$$,   $$Məktəb psixoloqu$$,                                                 $$$$, $$I sinif şagirdlərinin məktəbə uğurlu adaptasiyası üzrə valideynlərlə psixoprofilaktik söhbətlər aparır.$$, 7),
  ($$İlahə Babayeva Səadətdin$$, $$Kitabxana müdiri$$,                                                 $$$$, $$$$, 8),
  ($$Rüxsarə Qocayeva Qahir$$,   $$Uşaq birliyi rəhbəri$$,                                             $$$$, $$$$, 9);


-- ─────────────────────────────────────────────────────────────
-- 6) XƏBƏRLƏR (materiallar 01–07)
-- ─────────────────────────────────────────────────────────────
delete from public.school_news;

insert into public.school_news (title, body, image_url, gallery, category, section, author, keywords, published_at, published) values

($$15 Sentyabr – Bilik Günü!$$,
$$Bu gün məktəbimizin həyəti yenidən uşaqların səsi, gülüşü və böyük arzuları ilə canlandı!

Yeni tədris ilinin ilk günündə məktəbimizdə Bilik Günü münasibətilə tədbir keçirildi. Şagirdlər, müəllimlər və valideynlər üçün yeni bir başlanğıcın həyəcanı yaşandı.

Mərasimdə məktəb direktoru Əliheydər Əlifli şagirdləri və pedaqoji kollektivi yeni tədris ili münasibətilə təbrik edib, xüsusilə ilk dəfə məktəb həyətinə qədəm qoyan birinci sinif şagirdlərinə uğurlar arzulayıb.

Qoy 2026–2027-ci tədris ili hər bir şagirdimiz üçün yeni biliklər, yeni dostluqlar, gözəl xatirələr və böyük uğurlarla yadda qalsın!

Yeni dərs ili uğurlu olsun!$$,
$$school205/sagird-toplantisi.jpg$$,
array[$$school205/bilik-gunu-sinif.jpg$$,$$school205/direktor-cixisi.jpg$$],
$$Məktəb həyatı$$, $$Bilik Günü$$, $$Məktəb rəhbərliyi$$,
array[$$Bilik Günü$$,$$15 sentyabr$$,$$yeni tədris ili$$,$$2026-2027$$,$$birinci sinif$$,$$açılış$$],
date $$2026-09-15$$, true),

($$Yeni tədris ilinə birlikdə və məqsədyönlü şəkildə!$$,
$$Bu gün məktəb rəhbərliyi tərəfindən valideyn komitələrinin iştirakı ilə yeni tədris ilinə hazırlıqla bağlı görüş keçirilib.

Görüşdə məktəbli formaları, davamiyyət və punktuallıq, nizam-intizam, eləcə də tədris prosesinin səmərəli təşkili ilə bağlı mühüm məsələlər müzakirə olunub.

Direktor Əliheydər Əlifli çıxışında məktəb-valideyn əməkdaşlığının şagird uğurundakı rolunu vurğulayıb, sağlam və nizamlı təhsil mühitinin yaradılmasının prioritet olduğunu qeyd edib.

Təlim-tərbiyə işləri üzrə direktor müavini Aynur Ələsgərova isə tədrisin keyfiyyətinin yüksəldilməsi, şagird nailiyyətlərinin artırılması və təhsil nəticələrinin yaxşılaşdırılması istiqamətində vacib məsələlərə toxunub.

Görüş qarşılıqlı fikir və təkliflərin dinlənilməsi baxımından səmərəli davam edib.$$,
$$school205/valideyn-yiginciagi.jpg$$,
array[]::text[],
$$Məktəb həyatı$$, $$Valideyn əməkdaşlığı$$, $$Məktəb rəhbərliyi$$,
array[$$valideyn$$,$$tədris ili$$,$$görüş$$,$$nizam-intizam$$,$$davamiyyət$$,$$direktor$$],
date $$2026-08-29$$, true),

($$Məktəbə ilk addım – sevgi, anlayış və dəstək!$$,
$$Bu gün məktəbimizin psixoloqu Aytən Məmmədova I sinif şagirdlərinin valideyn iclasında iştirak edərək psixoprofilaktik söhbət aparıb.

Şagirdlərin məktəbə uğurlu adaptasiyasını dəstəkləmək məqsədilə valideynlərə aşağıdakı tövsiyələr verilib:

• Uşağa qarşı səbirli və anlayışlı olmaq;
• Məktəb və müəllim haqqında pozitiv fikir formalaşdırmaq;
• Uşağı digər şagirdlərlə müqayisə etməmək;
• Onun narahatlıqlarını dinləmək və hisslərini qəbul etmək;
• Dərs və istirahət rejiminə diqqət yetirmək;
• Kiçik uğurlarını belə təqdir və motivasiya etmək.

Uşağın məktəbə uğurlu adaptasiyası ailə və məktəbin qarşılıqlı əməkdaşlığı, sevgisi və dəstəyi ilə daha da möhkəmlənir.$$,
$$school205/ilk-zeng-1.jpg$$,
array[]::text[],
$$Psixoloji xidmət$$, $$Məktəbə adaptasiya$$, $$Aytən Məmmədova, məktəb psixoloqu$$,
array[$$psixoloq$$,$$adaptasiya$$,$$birinci sinif$$,$$valideyn$$,$$tövsiyə$$],
date $$2026-09-05$$, true),

($$Məktəbin uğurlu nəticələri$$,
$$Bakı şəhəri 205 nömrəli tam orta ümumtəhsil məktəbindən uğurlu nəticələr!

2025/2026-cı tədris ilində 139 məzunumuz qəbul imtahanında iştirak edib. Onlardan 63 nəfəri ali təhsil müəssisələrinə qəbul olub.

4 məzunumuz 600-dən yüksək bal toplayıb!

Ümumi qəbul göstəricisi – 45,3%.

Məzunlarımızı və müəllimlərimizi bu uğur münasibətilə təbrik edir, onlara gələcək fəaliyyətlərində yeni nailiyyətlər arzulayırıq!$$,
$$school205/qebul-hesabati.jpg$$,
array[]::text[],
$$Təhsil və nəticələr$$, $$Ali məktəbə qəbul göstəriciləri$$, $$Məktəb rəhbərliyi$$,
array[$$qəbul$$,$$məzun$$,$$600 bal$$,$$ali təhsil$$,$$nəticə$$,$$imtahan$$],
date $$2026-08-15$$, true),

($$Paytaxt təhsil işçilərinin sentyabr konfransına start verilib$$,
$$Bakı şəhərindəki ümumi təhsil və məktəbdənkənar təhsil müəssisələri rəhbərlərinin iştirakı ilə keçirilən konfransın I hissəsində Məktəbəqədər və Ümumi Təhsil üzrə Dövlət Agentliyinin (MÜTDA) direktor müavini, Bakı Şəhəri üzrə Təhsil İdarəsinin (BŞTİ) müdiri vəzifəsini müvəqqəti icra edən Nərminə Hüseynova, Azərbaycan Respublikası Təhsil İnstitutunun (ARTİ) Təhsilverənlərin peşəkar inkişaf mərkəzinin direktoru Nəzakət Mehdiyeva, Elm və Təhsil Nazirliyinin, MÜTDA və BŞTİ-nin müvafiq struktur bölmə rəhbərləri, ümumi təhsil müəssisələrinin rəhbərləri və metodistlər iştirak ediblər.

Konfrans Dövlət Himninin səsləndirilməsi və Vətən şəhidlərinin əziz xatirəsinin bir dəqiqəlik sükutla yad edilməsi ilə başlayıb.

Konfrans iştirakçılarını salamlayan Nərminə Hüseynova yeni tədris ilinin başlanması münasibətilə təhsil işçilərini təbrik edib və onlara uğurlar arzulayıb.

2025–2026-cı tədris ili ərzində təhsil müəssisələrində görülən işlər və əldə olunan nəticələr barədə təqdimatla çıxış edən Nərminə Hüseynova əsas göstəricilər üzrə dinamikanı diqqətə çatdırıb, mövcud məsələlər və onların həlli istiqamətində həyata keçirilən tədbirlərdən bəhs edib, yeni tədris ili üzrə prioritetlərə toxunaraq qarşıda duran əsas hədəfləri diqqətə çatdırıb.

Nərminə Hüseynova bildirib ki, yeni tədris ilində də ümumi təhsilin keyfiyyətinin yüksəldilməsi, qabaqcıl pedaqoji təcrübələrin yayılması, rəqəmsal və innovativ yanaşmaların tətbiqinin genişləndirilməsi, istedadlı şagirdlərin dəstəklənməsi, həmçinin məktəb-valideyn əməkdaşlığının daha da möhkəmləndirilməsi paytaxt təhsilinin qarşısında duran əsas hədəflərdəndir.

BŞTİ-nin müdir müavini Turanə Məcidli, ARTİ-nin Təhsilverənlərin peşəkar inkişaf mərkəzinin direktoru Nəzakət Mehdiyeva, BŞTİ-nin Keyfiyyətə nəzarət sektorunun müdiri Zinyət Əmirova, Məktəbdənkənar fəaliyyətlərin təşkili sektorunun müdiri Günay Qurbanova müxtəlif istiqamətlər üzrə təqdimatlar ediblər.

Təqdimatlarda məktəbdaxili qiymətləndirmənin obyektivliyi, zəif nəticə göstərən şagirdlərlə iş, müəllimlər arasında əməkdaşlıq və təcrübə mübadiləsi, keyfiyyət monitorinqləri, buraxılış imtahanlarının nəticələrinin müqayisəli təhlili, məktəbdənkənar fəaliyyətlərin əhatəliliyi və nəticəyönümlülüyü ilə bağlı məsələlər müzakirə olunub.

Konfransın II hissəsinin paytaxt üzrə məktəbəqədər təhsil müəssisələri rəhbərlərinin iştirakı ilə keçirilməsi nəzərdə tutulub.

Qeyd edək ki, konfrans növbəti gün də işini davam etdirəcək. BŞTİ-nin tabeliyindəki təhsil müəssisələrinin rəhbərləri, fənn müəllimləri, metodistlər və məktəb psixoloqlarının iştirakı ilə panel müzakirələr təşkil olunacaq, növbəti dərs ili üçün fəaliyyət planı hazırlanacaq və müvafiq təkliflər təqdim olunacaq.$$,
$$school205/muellim-konfransi.jpg$$,
array[]::text[],
$$Tədbirlər$$, $$Konfranslar$$, $$Bakı Şəhəri üzrə Təhsil İdarəsi$$,
array[$$konfrans$$,$$MÜTDA$$,$$BŞTİ$$,$$sentyabr$$,$$təhsil$$,$$prioritet$$],
date $$2026-09-01$$, true),

($$IX sinif buraxılış imtahanı nəticələrinin təhlili$$,
$$IX sinif buraxılış imtahanının nəticələri təhlil olunub.

Son üç ilin müqayisəsi göstərir ki, məktəbimiz 2024-cü illə müqayisədə irəliləyiş əldə etsə də, 2025-ci ilin nəticələri ilə müqayisədə geriləmə müşahidə olunub.

Bu, xüsusilə 0–30 bal aralığında nəticə göstərən şagirdlərin sayı və reytinq göstəricilərində özünü göstərib.

Növbəti tədris ilində təkmilləşdirilmiş iş prinsipi və komanda əməkdaşlığı ilə nəticələrimizi daha da yaxşılaşdırmaq üçün əzmlə çalışacağıq.$$,
$$school205/mutda-hesabat.jpg$$,
array[]::text[],
$$Təhsil və nəticələr$$, $$Analitika$$, $$Məktəb rəhbərliyi$$,
array[$$buraxılış imtahanı$$,$$IX sinif$$,$$təhlil$$,$$reytinq$$,$$bal$$],
date $$2026-07-20$$, true),

($$2025/2026-cı tədris ilinin təlim nəticələrinin illik hesabatı təqdim olundu$$,
$$2025/2026-cı tədris ili üzrə 2A–11D siniflərinin təlim nəticələrinin geniş təhlili başa çatdırılıb.

Hesabatda:

• Məktəb üzrə müvəffəqiyyət və keyfiyyət göstəriciləri;
• Fənlər üzrə orta bal nəticələri;
• Əla, yaxşı, kafi və qeyri-kafi qiymətlərin sayı;
• Buraxılış fənləri üzrə əldə olunmuş nəticələrin müqayisəli təhlili

öz əksini tapıb.

Təhlil göstərir ki, buraxılış fənləri arasında ən yüksək nəticə Azərbaycan dili, ən aşağı nəticə isə riyaziyyat fənni üzrə qeydə alınıb.

Əldə edilmiş nəticələr növbəti tədris ilində həyata keçiriləcək fəaliyyətlərin planlaşdırılması üçün əsas istiqamətləri müəyyən edir.

Bununla əlaqədar olaraq 2026/2027-ci tədris ili üzrə Fəaliyyət Planı hazırlanacaq, təlim nəticələrinin daha da yaxşılaşdırılması məqsədilə fənn müəllimləri və metodbirləşmə rəhbərlərinin iştirakı ilə məqsədyönlü tədbirlər həyata keçiriləcək.

Təhsildə davamlı inkişafın əsasında dəqiq təhlil, düzgün planlaşdırma və səmərəli əməkdaşlıq dayanır.$$,
$$school205/hesabat-2025-2026.jpg$$,
array[]::text[],
$$Hesabatlar və statistika$$, $$İllik təlim hesabatı$$, $$Məktəb rəhbərliyi$$,
array[$$hesabat$$,$$təlim nəticələri$$,$$müvəffəqiyyət$$,$$keyfiyyət$$,$$orta bal$$,$$riyaziyyat$$,$$Azərbaycan dili$$],
date $$2026-06-30$$, true),

($$Əməyə verilən yüksək qiymət!$$,
$$Məktəbimizin bir qrup kişi müəllimi və əməkdaşı 26 İyun – Azərbaycan Respublikasının Silahlı Qüvvələri Günü münasibətilə, digər bir qrup müəllimi isə 50 illik yubileyləri münasibətilə Elm və Təhsil İşçiləri Həmkarlar İttifaqı Binəqədi Rayon Komitəsi tərəfindən təltif olunublar.

Onlar gənc nəslin müstəqil həyata hazırlanmasında göstərdikləri şərəfli və fədakar əməyə, şagirdlərin təlim-tərbiyəsində üzərlərinə düşən vəzifələri layiqincə yerinə yetirdiklərinə görə Təşəkkürnamə və hədiyyələrlə mükafatlandırılıblar.

Təltif olunan bütün əməkdaşlarımızı ürəkdən təbrik edir, onlara gələcək fəaliyyətlərində yeni-yeni uğurlar arzulayırıq!$$,
$$school205/teltif-merasimi-a.jpg$$,
array[]::text[],
$$Müəllim nailiyyətləri$$, $$Təltiflər$$, $$Məktəb rəhbərliyi$$,
array[$$təltif$$,$$Silahlı Qüvvələr Günü$$,$$yubiley$$,$$həmkarlar ittifaqı$$,$$təşəkkürnamə$$],
date $$2026-06-26$$, true);


-- ─────────────────────────────────────────────────────────────
-- 7) TƏDBİRLƏR (materiallar 16–20)
-- ─────────────────────────────────────────────────────────────
delete from public.school_events;

insert into public.school_events (title, description, event_date, location, image_url, category, section, author, keywords) values

($$Aprel şəhidlərinin xatirəsinə həsr olunmuş görüş$$,
$$Bu gün məktəbin tarix müəllimi Billurə Əliyeva və "Kiçik Akademiya" üzvlərinin birgə təşkilatçılığı ilə "Aprel faciəsi" mövzusuna həsr olunmuş görüş keçirilib.

Görüşdə ilk olaraq Azərbaycan Respublikasının Dövlət Himni səsləndirilib, daha sonra Vətənimizin ərazi bütövlüyü uğrunda qəhrəmancasına döyüşərək canından keçmiş şəhidlərimizin əziz xatirəsi bir dəqiqəlik sükutla yad edilib.

Tədbirdə şagirdlərin hazırladığı videoçarxlar nümayiş olunub, şəhidlərimizin döyüş yolu barədə məlumat verilib.

Bu kimi tədbirlər şagirdlərimizdə vətənpərvərlik ruhunu daha da yüksəldir və onların Vətənə olan məhəbbətini gücləndirir.$$,
date $$2026-04-02$$, $$Məktəbin tarix kabinəsi$$, $$school205/tarix-ders-aprel.jpg$$,
$$Vətənpərvərlik$$, $$Anım tədbirləri$$, $$Billurə Əliyeva, tarix müəllimi$$,
array[$$Aprel döyüşləri$$,$$şəhid$$,$$vətənpərvərlik$$,$$Kiçik Akademiya$$]),

($$"Bir millətin qan yaddaşı – Xocalı"$$,
$$Bu gün məktəbin tarix müəllimi Billurə Əliyeva və "Kiçik Akademiya" üzvlərinin təşkilatçılığı ilə Xocalı faciəsinin 34-cü ildönümü ilə əlaqədar "Bir millətin qan yaddaşı – Xocalı" adlı xüsusi dərs keçirilib.

Tədbirin əsas məqsədi şagirdlərə xalqımızın yaşadığı bu ağır və faciəli tarixi hadisə haqqında ətraflı məlumat vermək, onlarda vətənpərvərlik hisslərini gücləndirməkdən ibarət olub.

Dərs Azərbaycan Respublikasının Dövlət Himninin səsləndirilməsi ilə başlayıb.

Daha sonra tarix müəllimi 1992-ci ilin fevralın 25-dən 26-na keçən gecə baş verən hadisələr haqqında məlumat verib, faciənin mahiyyəti, səbəbləri və nəticələrindən danışıb.

Xüsusi dərsdə "Kiçik Akademiya"nın üzvləri tərəfindən hazırlanmış təqdimatlar nümayiş olunub, tarixi faktlar səsləndirilib, şeirlər və ədəbi-bədii kompozisiyalar təqdim edilib.$$,
date $$2026-02-26$$, $$Məktəbin akt zalı$$, $$$$,
$$Tarixi yaddaş$$, $$Xüsusi dərslər$$, $$Billurə Əliyeva, tarix müəllimi$$,
array[$$Xocalı$$,$$faciə$$,$$34-cü ildönümü$$,$$tarixi yaddaş$$,$$Kiçik Akademiya$$]),

($$"20 Yanvar – Unudulmayan Gün" adlı dəyirmi masa keçirilib$$,
$$Bu gün məktəbin rus dili müəllimi Səbinə Əkbərova və "Kiçik Akademiya" üzvlərinin iştirakı ilə "20 Yanvar – Unudulmayan Gün" adlı dəyirmi masa keçirilib.

Tədbirin məqsədi şagirdlərə 20 Yanvar faciəsi haqqında sadə və aydın məlumat vermək, şəhidlərimizin xatirəsini yad etməkdən ibarət olub.

Tədbir zamanı şagirdlər 20 Yanvar hadisələri barədə danışıb, həmin gün baş verənlər haqqında fikirlərini bildiriblər.

Şagirdlər vətənpərvərlik mövzusunda şeirlər söyləyib və qısa çıxışlar ediblər.

Müəllim S. Əkbərova çıxış edərək 20 Yanvarın Azərbaycan xalqının azadlıq yolunda mühüm bir gün olduğunu qeyd edib.

Sonda şagirdlər şəhidlər haqqında videoçarx izləyiblər.$$,
date $$2026-01-20$$, $$Məktəbin kitabxanası$$, $$$$,
$$Tarixi yaddaş$$, $$Dəyirmi masa$$, $$Səbinə Əkbərova, rus dili müəllimi$$,
array[$$20 Yanvar$$,$$şəhid$$,$$azadlıq$$,$$dəyirmi masa$$]),

($$"Heydər Əliyev – Unudulmayan Lider"$$,
$$Ümummilli Lider Heydər Əliyevin Anım Günü ilə əlaqədar məktəbdə seminarlar, dəyirmi masalar, sinif təşkilat saatları və konfranslar keçirilib.

Bu məqsədlə məktəbin ingilis dili müəllimi Aydan Məlikova və "Kiçik Akademiya" üzvləri "Heydər Əliyev – Unudulmayan Lider" başlığı altında dəyirmi masa keçiriblər.

Tədbirin məqsədi şagirdlərə Ulu Öndərin həyat yolu, dövlətçilik fəaliyyəti və Azərbaycan gəncliyinin inkişafına verdiyi töhfələr barədə dolğun məlumat təqdim etmək olub.

İlk olaraq Heydər Əliyevin əziz xatirəsi bir dəqiqəlik sükutla yad edilib.

Tədbirin təşkilatçısı Aydan Məlikova Heydər Əliyevin milli-mənəvi dəyərlərin qorunması, təhsilin inkişafı və gənclərin dünyagörüşünün genişləndirilməsinə göstərdiyi diqqət haqqında məlumat verib.

Daha sonra "Kiçik Akademiya" üzvləri hazırladıqları təqdimatlarla çıxış ediblər.

Onlar Heydər Əliyevin həyat və fəaliyyətinin müxtəlif dövrlərini əks etdirən slaydlar, fotolar və maraqlı faktları nümayiş etdiriblər.

Şagirdlərin təqdimatlarında Ulu Öndərin təhsilə verdiyi önəm və xarici dillərin öyrənilməsinə yaratdığı imkanlar xüsusi vurğulanıb.$$,
date $$2025-12-12$$, $$Məktəbin akt zalı$$, $$$$,
$$Tarixi yaddaş$$, $$Anım günü$$, $$Aydan Məlikova, ingilis dili müəllimi$$,
array[$$Heydər Əliyev$$,$$Anım Günü$$,$$Ulu Öndər$$,$$dəyirmi masa$$]),

($$Heydər Əliyevi anırıq$$,
$$Məktəbimizdə Ulu Öndər Heydər Əliyevin xatirəsinə həsr olunmuş silsilə tədbirlər keçirilir.

Bu çərçivədə məktəbin tarix müəllimi Billurə Əliyeva və "Kiçik Akademiya" üzvləri Ulu Öndər Heydər Əliyevin xatirəsinə həsr olunmuş sinif təşkilat saatı keçiriblər.

Tədbirin məqsədi şagirdlərə Heydər Əliyevin həyatı, Azərbaycan üçün gördüyü işlər və gənclərə olan qayğısı haqqında məlumat verməkdən ibarət olub.

Müəllim giriş sözündə Heydər Əliyevin ölkəmizin inkişafına böyük töhfə verdiyini, xüsusilə təhsilə və məktəblilərə daim diqqət göstərdiyini qeyd edib.

Daha sonra "Kiçik Akademiya" üzvləri hazırladıqları qısa çıxışlarla Ulu Öndərin həyat yolu, fəaliyyəti və gənclərə verdiyi dəyər haqqında məlumat paylaşıblar.

Şagirdlər onun "Gənclər bizim gələcəyimizdir" fikrini xatırladaraq Ulu Öndərin gənc nəslə göstərdiyi etimadı vurğulayıblar.

Tədbirdə Heydər Əliyevin şəkilləri və haqqında məlumatlar təqdim edilib.

Sonda Ulu Öndərin əziz xatirəsi bir dəqiqəlik sükutla yad edilib.$$,
date $$2025-12-12$$, $$Sinif otaqları$$, $$$$,
$$Tarixi yaddaş$$, $$Sinif təşkilat saatı$$, $$Billurə Əliyeva, tarix müəllimi$$,
array[$$Heydər Əliyev$$,$$sinif saatı$$,$$gənclər$$,$$Ulu Öndər$$]);


-- ─────────────────────────────────────────────────────────────
-- 8) ŞAGİRD NAİLİYYƏTLƏRİ (materiallar 09–14)
-- ─────────────────────────────────────────────────────────────
delete from public.school_achievements;

insert into public.school_achievements (title, description, achieved_on, image_url, category, section, author, student_name, class_name, keywords) values

($$"Birlik" Uşaq Musiqi və Rəqs Festivalında uğur$$,
$$Məktəbimizin V D sinif şagirdi Babayeva Səma Taleh qızı Azərbaycan Uşaq Fondu tərəfindən təşkil olunan "Birlik" Uşaq Musiqi və Rəqs Festivalı layihəsinin seçim turunda uğurla çıxış edərək yüksək nəticə əldə edib.

Bu münasibətlə məktəb rəhbərliyi tərəfindən Səma fəxri fərmanla təltif olunub.

Səmanın bu uğuru onun zəhmətinin, istedadının və sənətə olan sevgisinin parlaq göstəricisidir.

Məktəb kollektivi olaraq onunla qürur duyur, gələcək müsabiqələrdə daha böyük nailiyyətlər qazanmasını arzulayırıq!$$,
date $$2026-03-12$$, $$$$,
$$Şagird nailiyyətləri$$, $$Musiqi və rəqs$$, $$Məktəb rəhbərliyi$$,
$$Səma Babayeva$$, $$V D$$,
array[$$Birlik festivalı$$,$$musiqi$$,$$rəqs$$,$$fəxri fərman$$,$$Uşaq Fondu$$]),

($$KİNQS Beynəlxalq Məktəb Olimpiadasında qızıl medal$$,
$$Məktəbimizin IV sinif şagirdi Səyavuş Bağırzadə Bağır oğlu KİNQS Beynəlxalq Məktəb Olimpiadasının payız liqasında iştirak edərək qızıl medal qazanıb.

Şagirdimizi bu böyük uğur münasibətilə təbrik edir, gələcəkdə daha böyük nailiyyətlər arzulayırıq!$$,
date $$2025-11-20$$, $$$$,
$$Olimpiadalar$$, $$Beynəlxalq olimpiada$$, $$Məktəb rəhbərliyi$$,
$$Səyavuş Bağırzadə$$, $$IV$$,
array[$$KİNQS$$,$$olimpiada$$,$$qızıl medal$$,$$beynəlxalq$$]),

($$Pifaqor Riyaziyyat Olimpiadasının qalibləri$$,
$$Məktəbin IV sinif şagirdləri Bağırzadə Səyavuş Bağır oğlu və Məsimov Rizvan Rauf oğlu Beyin Olimpiada Mərkəzi tərəfindən 27.12.2025-ci il tarixində keçirilən Pifaqor Riyaziyyat Olimpiadasında iştirak edərək gümüş medal qazanıblar.

Şagirdlərimizi bu böyük uğur münasibətilə təbrik edir, gələcəkdə daha böyük nailiyyətlər arzulayırıq!$$,
date $$2025-12-27$$, $$school205/olimpiada-qalibleri.png$$,
$$Olimpiadalar$$, $$Riyaziyyat$$, $$Məktəb rəhbərliyi$$,
$$Səyavuş Bağırzadə, Rizvan Məsimov$$, $$IV$$,
array[$$Pifaqor$$,$$riyaziyyat$$,$$olimpiada$$,$$gümüş medal$$]),

($$"Kunq-Fu" sanda üzrə Azərbaycan birinciliyində I yer$$,
$$Məktəbimizin VI sinif şagirdi Seyidzadə Sahib Tərlan oğlu "Kunq-Fu" sanda üzrə Azərbaycan birinciliyində 42 kq çəki dərəcəsində I yerə layiq görülüb.

Şagirdimiz turnirdə göstərdiyi yüksək hazırlıq, əzmkarlıq və peşəkarlığı ilə fərqlənib.

Bu uğur onun idmana olan böyük marağının və zəhmətinin nəticəsidir.

Məktəb kollektivi olaraq şagirdimizi təbrik edir, ona gələcək yarışlarda yeni nailiyyətlər arzulayırıq!$$,
date $$2026-02-15$$, $$$$,
$$İdman$$, $$Kunq-Fu sanda$$, $$Məktəb rəhbərliyi$$,
$$Sahib Seyidzadə$$, $$VI$$,
array[$$Kunq-Fu$$,$$sanda$$,$$Azərbaycan birinciliyi$$,$$I yer$$,$$idman$$]),

($$"Legion Döyüş Liqası" turnirində I yer$$,
$$Məktəbimizin IX sinif şagirdi Əlistanova Nəzrin Tofiq qızı MMA və Grappling idman növləri üzrə yeniyetmələr, gənclər və böyüklər arasında Ümummilli Lider Heydər Əliyevin xatirəsinə həsr olunmuş "Legion Döyüş Liqası" turnirində iştirak edərək I yerə layiq görülüb.

Şagirdimiz turnirdə göstərdiyi yüksək hazırlıq, əzmkarlıq və peşəkarlıqla fərqlənib.

Məktəb kollektivi olaraq şagirdimizi təbrik edir, ona gələcək yarışlarda yeni nailiyyətlər arzulayırıq!$$,
date $$2025-12-10$$, $$$$,
$$İdman$$, $$MMA və Grappling$$, $$Məktəb rəhbərliyi$$,
$$Nəzrin Əlistanova$$, $$IX$$,
array[$$MMA$$,$$Grappling$$,$$Legion Döyüş Liqası$$,$$I yer$$,$$idman$$]),

($$SASMO olimpiadasında gümüş medal$$,
$$Məktəbimizin V D sinif şagirdi Məmmədzadə Fatimə SASMO olimpiadasında II yerə layiq görülərək gümüş medal qazanıb.

Şagirdimizi təbrik edir, uğurlarının davamlı olmasını arzulayırıq!$$,
date $$2026-02-10$$, $$$$,
$$Olimpiadalar$$, $$SASMO$$, $$Məktəb rəhbərliyi$$,
$$Fatimə Məmmədzadə$$, $$V D$$,
array[$$SASMO$$,$$olimpiada$$,$$gümüş medal$$,$$II yer$$]);


-- ─────────────────────────────────────────────────────────────
-- 9) YOXLAMA
-- ─────────────────────────────────────────────────────────────
select 'school_news' as cedvel, count(*) from public.school_news
union all select 'school_events', count(*) from public.school_events
union all select 'school_achievements', count(*) from public.school_achievements
union all select 'school_teachers', count(*) from public.school_teachers;


-- ════════════════════════════════════════════════════════════════════════
-- [22/25]  supabase_seed_school205_content.sql
-- 205 portalı üçün ilk real məzmun
-- ════════════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════
-- SözLab — "205 Smart School" üçün REAL MƏZMUN (ilk doldurma)
-- ÖNCƏ supabase_update_school205.sql skriptini run edin, SONRA bunu.
-- Şəkillər school205/ qovluğundan (index.html ilə eyni qovluqda) istifadə edir —
-- deploy edərkən bu qovluğun da serverə yükləndiyinə əmin olun.
-- ════════════════════════════════════════════════════════════════

-- 1) MƏKTƏB HAQQINDA
update public.school_info set
  school_name = 'Bakı şəhəri R.İmanov adına 205 nömrəli tam orta məktəb',
  address     = 'Mətbuat 107, Binəqədi, Bakı, AZ1053',
  phone       = '(+994 12) 411-19-98',
  email       = '205mekteb@bakuedu.gov.az',
  cover_image_url = 'school205/ilk-zeng-2.jpg',
  about_text  = $$FƏXRİMİZ

Rövşən İmanov 1969-cu il iyunun 27-də Bakı şəhərində anadan olub. Hələ uşaqlıq illərindən vətənpərvər ruhda böyümüş və daim Vətəni qorumaq, onun keşiyində durmaq arzusu ilə yaşayıb. O, 1976-cı ildə 205 nömrəli orta məktəbin birinci sinfinə daxil olub. 1984-cü ildə səkkizillik orta təhsilini başa vurduqdan sonra 68 nömrəli texniki-peşə məktəbində ixtisas təhsili alıb. 1987-1989-cu illərdə ordu sıralarında hərbi xidməti uğurla başa vurub.

1991-ci ildə Xüsusi Polis Dəstəsinə daxil olan Rövşən Daşaltı, Kərkicahan, Şuşa, Goranboy və digər yaşayış məntəqələri ətrafında baş verən qanlı döyüşlərdə qəhrəmanlıq göstərib.

1992-ci il iyulun 22-də Ağdərədə düşmənin hücumunu dəf edərkən qəhrəmancasına şəhid olub.

Elə həmin il Rövşən Nadir oğlu İmanovun adı 205 nömrəli tam orta məktəbə verilib.

BU GÜN MƏKTƏBİMİZ

2025/2026-cı tədris ilində 45 sinifdə (2A–11D) 1270 şagird təhsil alır. Məktəb üzrə müvəffəqiyyət 98,5%, keyfiyyət göstəricisi isə 66,3%-dir. Həmin tədris ilində 139 məzunumuzdan 63 nəfəri ali təhsil müəssisələrinə qəbul olub, onlardan 4 nəfəri 600-dən yüksək bal toplayıb.$$
where id = 1;

-- ─────────────────────────────────────────────
-- 2) MÜƏLLİMLƏR / RƏHBƏRLİK
-- ─────────────────────────────────────────────
insert into public.school_teachers (full_name, subject, bio, sort_order) values
('Əliheydər Əlifli Elman', 'Direktor', '', 1),
('Aynur Ələsgərova Cavid', 'Təlim-tərbiyə işləri üzrə direktor müavini', '', 2),
('Vüsalə Rəcəbova Fərhad', 'Məktəbdənkənar və sinifdənxaric tərbiyə işi üzrə təşkilatçı', '', 3),
('Zilfi Zilfiyev Baxış', 'Direktorun təsərrüfat işləri üzrə müavini', '', 4),
('Emin Əliyev Telman', 'Çağırışaqədərki hazırlıq rəhbəri', '', 5),
('Zülfiyyə Məsimova Qənbər', 'Məktəb psixoloqu', '', 6),
('Aytən Məmmədova Səadət', 'Məktəb psixoloqu', '', 7),
('İlahə Babayeva Səadətdin', 'Kitabxana müdiri', '', 8),
('Rüxsarə Qocayeva Qahir', 'Uşaq birliyi rəhbəri', '', 9),
('Billurə Əliyeva', 'Tarix müəllimi', '', 10),
('Səbinə Əkbərova', 'Rus dili müəllimi', '', 11),
('Aydan Məlikova', 'İngilis dili müəllimi', '', 12)
on conflict do nothing;

-- ─────────────────────────────────────────────
-- 3) XƏBƏRLƏR
-- ─────────────────────────────────────────────
insert into public.school_news (title, body, image_url, created_at) values
(
  'Yeni tədris ilinə birlikdə və məqsədyönlü şəkildə!',
  $$Məktəb rəhbərliyi tərəfindən valideyn komitələrinin iştirakı ilə yeni tədris ilinə hazırlıqla bağlı görüş keçirilib. Görüşdə məktəbli formaları, davamiyyət və punktuallıq, nizam-intizam, eləcə də tədris prosesinin səmərəli təşkili ilə bağlı mühüm məsələlər müzakirə olunub.

Direktor Əliheydər Əlifli çıxışında məktəb-valideyn əməkdaşlığının şagird uğurundakı rolunu vurğulayıb, sağlam və nizamlı təhsil mühitinin yaradılmasının prioritet olduğunu qeyd edib.

Təlim-tərbiyə işləri üzrə direktor müavini Aynur Ələsgərova isə tədrisin keyfiyyətinin yüksəldilməsi, şagird nailiyyətlərinin artırılması və təhsil nəticələrinin yaxşılaşdırılması istiqamətində vacib məsələlərə toxunub.$$,
  'school205/valideyn-yiginciagi.jpg', now() - interval '2 days'
),
(
  'Məktəbə ilk addım – sevgi, anlayış və dəstək!',
  $$Məktəbimizin psixoloqu Aytən Məmmədova I sinif şagirdlərinin valideyn iclasında iştirak edərək psixoprofilaktik söhbət aparıb.

Şagirdlərin məktəbə uğurlu adaptasiyasını dəstəkləmək məqsədilə valideynlərə tövsiyələr verilib: uşağa qarşı səbirli və anlayışlı olmaq, məktəb və müəllim haqqında pozitiv fikir formalaşdırmaq, uşağı digər şagirdlərlə müqayisə etməmək, onun narahatlıqlarını dinləmək, dərs-istirahət rejiminə diqqət yetirmək və kiçik uğurlarını belə təqdir etmək.$$,
  'school205/ilk-zeng-1.jpg', now() - interval '3 days'
),
(
  'Məktəbin uğurlu nəticələri',
  $$2025/2026-cı tədris ilində 139 məzunumuz qəbul imtahanında iştirak edib. Onlardan 63 nəfəri ali təhsil müəssisələrinə qəbul olub. 4 məzunumuz 600-dən yüksək bal toplayıb! Ümumi qəbul göstəricisi — 45,3%.

Məzunlarımızı və müəllimlərimizi bu uğur münasibətilə təbrik edirik!$$,
  'school205/qebul-hesabati.jpg', now() - interval '5 days'
),
(
  'Paytaxt təhsil işçilərinin sentyabr konfransına start verilib',
  $$Bakı şəhərindəki ümumi təhsil və məktəbdənkənar təhsil müəssisələri rəhbərlərinin iştirakı ilə keçirilən konfrans Dövlət Himninin səsləndirilməsi və şəhidlərimizin xatirəsinin bir dəqiqəlik sükutla yad edilməsi ilə başlayıb.

Konfransda yeni tədris ilində ümumi təhsilin keyfiyyətinin yüksəldilməsi, qabaqcıl pedaqoji təcrübələrin yayılması, rəqəmsal və innovativ yanaşmaların tətbiqinin genişləndirilməsi, istedadlı şagirdlərin dəstəklənməsi və məktəb-valideyn əməkdaşlığının möhkəmləndirilməsi əsas prioritetlər kimi vurğulanıb.$$,
  'school205/muellim-konfransi.jpg', now() - interval '10 days'
),
(
  'IX sinif buraxılış imtahanı nəticələrinin təhlili',
  $$IX sinif buraxılış imtahanının nəticələri təhlil olunub. Son üç ilin müqayisəsi göstərir ki, məktəbimiz 2024-cü illə müqayisədə irəliləyiş əldə etsə də, 2025-ci ilin nəticələri ilə müqayisədə geriləmə müşahidə olunub. Növbəti tədris ilində təkmilləşdirilmiş iş prinsipi və komanda əməkdaşlığı ilə nəticələrimizi daha da yaxşılaşdırmaq üçün əzmlə çalışacağıq.$$,
  'school205/mutda-hesabat.jpg', now() - interval '14 days'
),
(
  '2025/2026-cı tədris ilinin təlim nəticələrinin illik hesabatı təqdim olundu',
  $$2025/2026-cı tədris ili üzrə 2A–11D siniflərinin təlim nəticələrinin geniş təhlili başa çatdırılmışdır. Hesabatda məktəb üzrə müvəffəqiyyət və keyfiyyət göstəriciləri, fənlər üzrə orta bal nəticələri, əla/yaxşı/kafi/qeyri-kafi qiymətlərin sayı əks olunub.

Təhlil göstərir ki, buraxılış fənləri arasında ən yüksək nəticə Azərbaycan dili, ən aşağı nəticə isə riyaziyyat fənni üzrə qeydə alınmışdır. 2026/2027-ci tədris ili üzrə Fəaliyyət Planı hazırlanacaq.$$,
  'school205/hesabat-2025-2026.jpg', now() - interval '16 days'
),
(
  'Əməyə verilən yüksək qiymət!',
  $$Məktəbimizin bir qrup kişi müəllimi və əməkdaşı 26 İyun – Azərbaycan Respublikasının Silahlı Qüvvələri Günü münasibətilə, digər bir qrup müəllimi isə "50 illik yubiley"ləri münasibətilə Elm və Təhsil İşçiləri Həmkarlar İttifaqı Binəqədi Rayon Komitəsi tərəfindən təltif olunublar.

Təltif olunan bütün əməkdaşlarımızı ürəkdən təbrik edir, onlara gələcək fəaliyyətlərində yeni-yeni uğurlar arzulayırıq!$$,
  'school205/teltif-merasimi-a.jpg', now() - interval '20 days'
),
(
  'Aprel Şəhidlərinin Xatirəsinə həsr olunmuş görüş',
  $$Məktəbin tarix müəllimi Billurə Əliyeva və "Kiçik Akademiya" üzvlərinin birgə təşkilatçılığı ilə "Aprel faciəsi" mövzusuna həsr olunmuş görüş keçirilib. Görüşdə Dövlət Himni səsləndirilib, şəhidlərimizin əziz xatirəsi bir dəqiqəlik sükutla yad edilib, şagirdlərin hazırladığı videoçarxlar nümayiş olunub.$$,
  'school205/tarix-ders-aprel.jpg', now() - interval '25 days'
)
on conflict do nothing;

-- ─────────────────────────────────────────────
-- 4) NAİLİYYƏTLƏR
-- ─────────────────────────────────────────────
insert into public.school_achievements (title, description, image_url, achieved_on) values
(
  'Olimpiada qalibləri',
  $$Məhəmməd Teymurlu (Riyaziyyat), İbrahim Məmmədov (Riyaziyyat), Rəvan Ağayev (Coğrafiya), Ceyhun Qarayev (Riyaziyyat), Şövqü Hüseynov (Azərbaycan dili), Emilya Əhmədzadə (Riyaziyyat), Raul Məmmədov (Riyaziyyat) və Nigar Hüseynli (Azərbaycan dili) müxtəlif fənn olimpiadalarında məktəbimizi uğurla təmsil ediblər.$$,
  'school205/olimpiada-qalibleri.png', '2026-01-15'
),
(
  '4 məzunumuz 600-dən yüksək bal topladı',
  $$Əzimova Çınara Vüqar — 624,5 bal, Bakı Dövlət Universiteti Hüquq fakültəsi. Hüseynli Sadiq Elşən — 602 bal, Bakı Dövlət Universiteti İctimai münasibətlər. Sadıxzada Arzu Sadıx — 602 bal, Qarabağ Universiteti Hüquq fakültəsi. Hümbətova Fidan Mərdan — 600 bal, Azərbaycan Tibb Universiteti Müalicə işi.$$,
  'school205/qebul-hesabati.jpg', '2026-07-01'
),
(
  '"Birlik" Uşaq Musiqi və Rəqs Festivalı',
  $$VD sinif şagirdi Babayeva Səma Azərbaycan Uşaq Fondu tərəfindən təşkil olunan "Birlik" Uşaq Musiqi və Rəqs Festivalı layihəsinin seçim turunda uğurla çıxış edərək yüksək nəticə əldə etmişdir və fəxri fərmanla təltif olunmuşdur.$$,
  '', '2026-02-01'
),
(
  'KİNQS Beynəlxalq məktəb olimpiadası — qızıl medal',
  $$4Ç sinif şagirdi Səyavuş Bağırzadə KİNQS Beynəlxalq məktəb olimpiadasının payız liqasında iştirak edərək qızıl medal qazanıb.$$,
  '', '2025-11-01'
),
(
  'Pifaqor Riyaziyyat Olimpiadası — gümüş medal',
  $$IV sinif şagirdləri Bağırzadə Səyavuş və Məsimov Rizvan Beyin Olimpiada Mərkəzi tərəfindən 27.12.2025-ci il tarixində keçirilən Pifaqor Riyaziyyat Olimpiadasında gümüş medal qazanıblar.$$,
  '', '2025-12-27'
),
(
  'Kunq-Fu sanda Azərbaycan birinciliyi — I yer',
  $$VI sinif şagirdi Seyidzadə Sahib "Kunq-Fu" sanda üzrə Azərbaycan birinciliyi 42 kq çəki dərəcəsində I yerə layiq görülüb.$$,
  '', '2026-03-01'
),
(
  '"Legion Döyüş Liqası" — I yer',
  $$IX sinif şagirdi Əlistanova Nəzrin MMA və Grappling idman növləri üzrə Ümummilli Lider Heydər Əliyevin xatirəsinə həsr olunmuş "Legion Döyüş Liqası" turnirində I yerə layiq görülüb.$$,
  '', '2026-03-15'
),
(
  'SASMO Olimpiadası — gümüş medal',
  $$5D sinif şagirdi Məmmədzadə Fatimə SASMO olimpiadasından 2-ci yer, gümüş medal qazanmışdır.$$,
  '', '2026-02-15'
)
on conflict do nothing;

-- ─────────────────────────────────────────────
-- 5) TƏDBİRLƏR
-- ─────────────────────────────────────────────
insert into public.school_events (title, description, event_date, image_url) values
(
  'Yeni tədris ilinə hazırlıq görüşü',
  'Valideyn komitələri ilə birgə keçirilən görüşdə məktəbli formaları, davamiyyət, nizam-intizam və tədris prosesinin təşkili müzakirə olunub.',
  current_date - 2, 'school205/valideyn-yiginciagi.jpg'
),
(
  'I sinif valideyn iclası — psixoprofilaktik söhbət',
  'Məktəb psixoloqu Aytən Məmmədova I sinif şagirdlərinin valideynləri ilə uşağın məktəbə uğurlu adaptasiyası mövzusunda görüş keçirib.',
  current_date - 3, 'school205/ilk-zeng-1.jpg'
),
(
  'Paytaxt təhsil işçilərinin sentyabr konfransı',
  'Bakı üzrə ümumi təhsil müəssisələri rəhbərlərinin iştirakı ilə keçirilən illik konfrans.',
  current_date - 10, 'school205/muellim-konfransi.jpg'
),
(
  'Əməyə verilən yüksək qiymət — təltif mərasimi',
  'Silahlı Qüvvələr Günü və 50 illik yubiley münasibətilə əməkdaşların təltifi.',
  current_date - 20, 'school205/teltif-merasimi-a.jpg'
),
(
  'Aprel faciəsinə həsr olunmuş anım tədbiri',
  '"Kiçik Akademiya" üzvlərinin təşkilatçılığı ilə keçirilən tarix dərsi və video nümayişi.',
  current_date - 25, 'school205/tarix-ders-aprel.jpg'
)
on conflict do nothing;


-- ════════════════════════════════════════════════════════════════════════
-- [23/25]  supabase_update_school_uploads.sql
-- 205 portalı şəkil yükləmə bucket-i (yeni)
-- ════════════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════
-- SözLab — 205 portalı üçün şəkil yükləmə bucket-i ("school-uploads")
-- Bu skripti Supabase Dashboard → SQL Editor-da açıb "Run" edin.
-- ÖNCƏ supabase_update_school205.sql run edilmiş olmalıdır.
--
-- NƏ ÜÇÜN: supabase_update_school205.sql bu bucket üçün storage siyasətlərini
-- yaradır, amma bucket-in ÖZÜNÜ yaratmır ("Dashboard-dan əl ilə yaradın"
-- yazılıb). Köhnə layihədə əl ilə yaradılmışdı; yeni layihədə bu addım
-- unudulsa, şagird layihəsinə şəkil əlavə edəndə yükləmə
-- "Bucket not found" xətası ilə sınır. Bu skript həmin əl addımını əvəz edir.
--
-- Siyasətlərə TOXUNMUR — onlar supabase_update_school205.sql-dədir.
-- ════════════════════════════════════════════════════════════════

-- Public = ON: sayt şəkilləri getPublicUrl() ilə <img src> kimi göstərir.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('school-uploads', 'school-uploads', true, 5242880,
        array['image/png','image/jpeg','image/webp','image/gif'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;


-- ════════════════════════════════════════════════════════════════════════
-- [24/25]  supabase_update_205_ecosystem.sql
-- 205 SMART SCHOOL ekosistemi
-- ════════════════════════════════════════════════════════════════════════

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


-- ════════════════════════════════════════════════════════════════════════
-- [25/25]  supabase_update_backup.sql
-- Ehtiyat nüsxə RPC-si
-- ════════════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════
-- SözLab — Ehtiyat nüsxə (backup) RPC-si.
-- Bu skripti Supabase Dashboard → SQL Editor-da açıb "Run" edin.
-- ÖNCƏ bütün əvvəlki SQL skriptlərinin run edildiyini fərz edir
-- (public.is_admin() funksiyası buradan istifadə olunur).
--
-- Nə üçün: Supabase bulud xidmətidir — nəzəri olaraq xidmət kəsilsə,
-- səhv silinsə və ya plan/hesab problemi yaransa, məlumat itkisi riski
-- var. Bu RPC ilə admin istənilən vaxt BÜTÜN cədvəlləri tək bir JSON
-- faylına köçürüb öz kompüterinə saxlaya bilər — Supabase-in özündəki
-- avtomatik "Backups" funksiyasından (Dashboard → Database → Backups,
-- plana görə fərqlənir) ƏLAVƏ, ikinci bir təhlükəsizlik qatı kimi.
--
-- Təhlükəsizlik: yalnız role='admin' olan istifadəçi çağıra bilər
-- (digər admin-only RPC-lərlə eyni is_admin() yoxlaması). Heç bir
-- yeni "service role" açarı və ya xarici kimlik lazım deyil — admin
-- sadəcə öz mövcud hesabı ilə tətbiqdən bir düyməyə basır.
-- ════════════════════════════════════════════════════════════════

create or replace function public.admin_export_backup()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_result jsonb;
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'Yalnız adminlər ehtiyat nüsxə ala bilər';
  end if;

  select jsonb_build_object(
    'exported_at', now(),
    'profiles', (select coalesce(jsonb_agg(t), '[]'::jsonb) from public.profiles t),
    'stories', (select coalesce(jsonb_agg(t), '[]'::jsonb) from public.stories t),
    'announcements', (select coalesce(jsonb_agg(t), '[]'::jsonb) from public.announcements t),
    'class_tasks', (select coalesce(jsonb_agg(t), '[]'::jsonb) from public.class_tasks t),
    'class_task_completions', (select coalesce(jsonb_agg(t), '[]'::jsonb) from public.class_task_completions t),
    'duels', (select coalesce(jsonb_agg(t), '[]'::jsonb) from public.duels t),
    'xp_log', (select coalesce(jsonb_agg(t), '[]'::jsonb) from public.xp_log t),
    'live_quiz_sessions', (select coalesce(jsonb_agg(t), '[]'::jsonb) from public.live_quiz_sessions t),
    'live_quiz_participants', (select coalesce(jsonb_agg(t), '[]'::jsonb) from public.live_quiz_participants t),
    'support_messages', (select coalesce(jsonb_agg(t), '[]'::jsonb) from public.support_messages t)
  ) into v_result;

  return v_result;
end;
$$;

grant execute on function public.admin_export_backup() to authenticated;
