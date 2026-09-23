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
