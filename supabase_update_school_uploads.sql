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
