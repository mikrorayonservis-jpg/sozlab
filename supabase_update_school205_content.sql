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
