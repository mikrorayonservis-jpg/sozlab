-- ════════════════════════════════════════════════════════════════
-- SözLab — DÜZƏLİŞ: qeydiyyat trigger-i (ad/soyad itirdi, dəvət kodu işləmirdi)
-- Bu skripti Supabase Dashboard → SQL Editor-da açıb "Run" edin (bir dəfə).
-- Təkrar run etmək təhlükəsizdir.
--
-- PROBLEM: handle_new_user() funksiyası 4 skriptdə ayrı-ayrı yazılmışdı və
-- sonuncu (supabase_update_school205_content.sql) əvvəlkiləri əvəz edərək
-- ad, soyad və dəvət bonusunu itirmişdi. Nəticə:
--   • yeni şagirdlərin profilində first_name / last_name BOŞ qalırdı;
--   • dəvət kodu yazılsa da heç kim +20 XP almırdı.
--
-- HƏLL:
--   1) bütün sahələri birlikdə saxlayan tək trigger;
--   2) artıq qeydiyyatdan keçmiş hesablar üçün boş qalan ad/soyad/telefon/sinif
--      qeydiyyat anında göndərilmiş məlumatdan BƏRPA olunur (mövcud dəyərə toxunulmur).
--   Keçmiş dəvətlərə geriyə XP verilmir — kimin kimi dəvət etdiyi yoxlanılmadan
--   xal yazmaq düzgün olmazdı.
-- ════════════════════════════════════════════════════════════════

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

-- Trigger-in özü (auth.users-ə yeni sətir düşəndə işləyir)
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Artıq qeydiyyatdan keçmiş hesablar: boş sahələri bərpa et
update public.profiles p set
  first_name  = case when p.first_name  = '' then trim(coalesce(u.raw_user_meta_data->>'first_name',''))  else p.first_name  end,
  last_name   = case when p.last_name   = '' then trim(coalesce(u.raw_user_meta_data->>'last_name',''))   else p.last_name   end,
  phone       = case when p.phone       = '' then trim(coalesce(u.raw_user_meta_data->>'phone',''))       else p.phone       end,
  class_grade = case when coalesce(p.class_grade,'') = ''
                      and upper(trim(coalesce(u.raw_user_meta_data->>'class_grade',''))) ~ '^(1[01]|[1-9])[A-D]$'
                     then upper(trim(u.raw_user_meta_data->>'class_grade')) else p.class_grade end
from auth.users u
where u.id = p.id
  and (p.first_name = '' or p.last_name = '' or p.phone = '' or coalesce(p.class_grade,'') = '');
