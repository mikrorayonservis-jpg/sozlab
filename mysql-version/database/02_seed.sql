-- ══════════════════════════════════════════════════════════════════════════
-- SözLab — başlanğıc məlumat (205 məktəb portalı, ekosistem, kosmetika və s.)
-- 01_schema.sql-dən SONRA import edin. Təkrar import etmək təhlükəsizdir.
-- Avtomatik yaradılıb (gen_schema.py).
-- ══════════════════════════════════════════════════════════════════════════
SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;
SET time_zone = '+00:00';

INSERT INTO `cosmetics_catalog` (`id`, `type`, `name`, `icon`, `min_xp`, `sort_order`) VALUES
('frame_bronze', 'frame', 'Bürünc Çərçivə', '🥉', 200, 1),
('frame_diamond', 'frame', 'Almaz Çərçivə', '💎', 5000, 4),
('frame_gold', 'frame', 'Qızıl Çərçivə', '🥇', 2000, 3),
('frame_none', 'frame', 'Sadə', '', 0, 0),
('frame_silver', 'frame', 'Gümüş Çərçivə', '🥈', 800, 2),
('theme_default', 'theme', 'Standart Tema', '', 0, 0),
('theme_neon', 'theme', 'Neon', '⚡', 3500, 3),
('theme_ocean', 'theme', 'Okean', '🌊', 1500, 2),
('theme_sunset', 'theme', 'Gün Batımı', '🌇', 500, 1)
ON DUPLICATE KEY UPDATE `type`=VALUES(`type`), `name`=VALUES(`name`), `icon`=VALUES(`icon`), `min_xp`=VALUES(`min_xp`), `sort_order`=VALUES(`sort_order`);

INSERT INTO `school_achievements` (`id`, `title`, `description`, `achieved_on`, `image_url`, `created_by`, `created_at`, `category`, `section`, `author`, `keywords`, `student_name`, `class_name`) VALUES
(1, '"Birlik" Uşaq Musiqi və Rəqs Festivalında uğur', 'Məktəbimizin V D sinif şagirdi Babayeva Səma Taleh qızı Azərbaycan Uşaq Fondu tərəfindən təşkil olunan "Birlik" Uşaq Musiqi və Rəqs Festivalı layihəsinin seçim turunda uğurla çıxış edərək yüksək nəticə əldə edib.

Bu münasibətlə məktəb rəhbərliyi tərəfindən Səma fəxri fərmanla təltif olunub.

Səmanın bu uğuru onun zəhmətinin, istedadının və sənətə olan sevgisinin parlaq göstəricisidir.

Məktəb kollektivi olaraq onunla qürur duyur, gələcək müsabiqələrdə daha böyük nailiyyətlər qazanmasını arzulayırıq!', '2026-03-12', '', NULL, '2026-09-25 20:20:00.195', 'Şagird nailiyyətləri', 'Musiqi və rəqs', 'Məktəb rəhbərliyi', '["Birlik festivalı", "musiqi", "rəqs", "fəxri fərman", "Uşaq Fondu"]', 'Səma Babayeva', 'V D'),
(2, 'KİNQS Beynəlxalq Məktəb Olimpiadasında qızıl medal', 'Məktəbimizin IV sinif şagirdi Səyavuş Bağırzadə Bağır oğlu KİNQS Beynəlxalq Məktəb Olimpiadasının payız liqasında iştirak edərək qızıl medal qazanıb.

Şagirdimizi bu böyük uğur münasibətilə təbrik edir, gələcəkdə daha böyük nailiyyətlər arzulayırıq!', '2025-11-20', '', NULL, '2026-09-25 20:20:00.195', 'Olimpiadalar', 'Beynəlxalq olimpiada', 'Məktəb rəhbərliyi', '["KİNQS", "olimpiada", "qızıl medal", "beynəlxalq"]', 'Səyavuş Bağırzadə', 'IV'),
(3, 'Pifaqor Riyaziyyat Olimpiadasının qalibləri', 'Məktəbin IV sinif şagirdləri Bağırzadə Səyavuş Bağır oğlu və Məsimov Rizvan Rauf oğlu Beyin Olimpiada Mərkəzi tərəfindən 27.12.2025-ci il tarixində keçirilən Pifaqor Riyaziyyat Olimpiadasında iştirak edərək gümüş medal qazanıblar.

Şagirdlərimizi bu böyük uğur münasibətilə təbrik edir, gələcəkdə daha böyük nailiyyətlər arzulayırıq!', '2025-12-27', 'school205/olimpiada-qalibleri.png', NULL, '2026-09-25 20:20:00.195', 'Olimpiadalar', 'Riyaziyyat', 'Məktəb rəhbərliyi', '["Pifaqor", "riyaziyyat", "olimpiada", "gümüş medal"]', 'Səyavuş Bağırzadə, Rizvan Məsimov', 'IV'),
(4, '"Kunq-Fu" sanda üzrə Azərbaycan birinciliyində I yer', 'Məktəbimizin VI sinif şagirdi Seyidzadə Sahib Tərlan oğlu "Kunq-Fu" sanda üzrə Azərbaycan birinciliyində 42 kq çəki dərəcəsində I yerə layiq görülüb.

Şagirdimiz turnirdə göstərdiyi yüksək hazırlıq, əzmkarlıq və peşəkarlığı ilə fərqlənib.

Bu uğur onun idmana olan böyük marağının və zəhmətinin nəticəsidir.

Məktəb kollektivi olaraq şagirdimizi təbrik edir, ona gələcək yarışlarda yeni nailiyyətlər arzulayırıq!', '2026-02-15', '', NULL, '2026-09-25 20:20:00.195', 'İdman', 'Kunq-Fu sanda', 'Məktəb rəhbərliyi', '["Kunq-Fu", "sanda", "Azərbaycan birinciliyi", "I yer", "idman"]', 'Sahib Seyidzadə', 'VI'),
(5, '"Legion Döyüş Liqası" turnirində I yer', 'Məktəbimizin IX sinif şagirdi Əlistanova Nəzrin Tofiq qızı MMA və Grappling idman növləri üzrə yeniyetmələr, gənclər və böyüklər arasında Ümummilli Lider Heydər Əliyevin xatirəsinə həsr olunmuş "Legion Döyüş Liqası" turnirində iştirak edərək I yerə layiq görülüb.

Şagirdimiz turnirdə göstərdiyi yüksək hazırlıq, əzmkarlıq və peşəkarlıqla fərqlənib.

Məktəb kollektivi olaraq şagirdimizi təbrik edir, ona gələcək yarışlarda yeni nailiyyətlər arzulayırıq!', '2025-12-10', '', NULL, '2026-09-25 20:20:00.195', 'İdman', 'MMA və Grappling', 'Məktəb rəhbərliyi', '["MMA", "Grappling", "Legion Döyüş Liqası", "I yer", "idman"]', 'Nəzrin Əlistanova', 'IX'),
(6, 'SASMO olimpiadasında gümüş medal', 'Məktəbimizin V D sinif şagirdi Məmmədzadə Fatimə SASMO olimpiadasında II yerə layiq görülərək gümüş medal qazanıb.

Şagirdimizi təbrik edir, uğurlarının davamlı olmasını arzulayırıq!', '2026-02-10', '', NULL, '2026-09-25 20:20:00.195', 'Olimpiadalar', 'SASMO', 'Məktəb rəhbərliyi', '["SASMO", "olimpiada", "gümüş medal", "II yer"]', 'Fatimə Məmmədzadə', 'V D'),
(7, 'Olimpiada qalibləri', 'Məhəmməd Teymurlu (Riyaziyyat), İbrahim Məmmədov (Riyaziyyat), Rəvan Ağayev (Coğrafiya), Ceyhun Qarayev (Riyaziyyat), Şövqü Hüseynov (Azərbaycan dili), Emilya Əhmədzadə (Riyaziyyat), Raul Məmmədov (Riyaziyyat) və Nigar Hüseynli (Azərbaycan dili) müxtəlif fənn olimpiadalarında məktəbimizi uğurla təmsil ediblər.', '2026-01-15', 'school205/olimpiada-qalibleri.png', NULL, '2026-09-25 20:20:00.207', 'Şagird nailiyyətləri', '', 'Məktəb rəhbərliyi', '[]', '', ''),
(8, '4 məzunumuz 600-dən yüksək bal topladı', 'Əzimova Çınara Vüqar — 624,5 bal, Bakı Dövlət Universiteti Hüquq fakültəsi. Hüseynli Sadiq Elşən — 602 bal, Bakı Dövlət Universiteti İctimai münasibətlər. Sadıxzada Arzu Sadıx — 602 bal, Qarabağ Universiteti Hüquq fakültəsi. Hümbətova Fidan Mərdan — 600 bal, Azərbaycan Tibb Universiteti Müalicə işi.', '2026-07-01', 'school205/qebul-hesabati.jpg', NULL, '2026-09-25 20:20:00.207', 'Şagird nailiyyətləri', '', 'Məktəb rəhbərliyi', '[]', '', ''),
(9, '"Birlik" Uşaq Musiqi və Rəqs Festivalı', 'VD sinif şagirdi Babayeva Səma Azərbaycan Uşaq Fondu tərəfindən təşkil olunan "Birlik" Uşaq Musiqi və Rəqs Festivalı layihəsinin seçim turunda uğurla çıxış edərək yüksək nəticə əldə etmişdir və fəxri fərmanla təltif olunmuşdur.', '2026-02-01', '', NULL, '2026-09-25 20:20:00.207', 'Şagird nailiyyətləri', '', 'Məktəb rəhbərliyi', '[]', '', ''),
(10, 'KİNQS Beynəlxalq məktəb olimpiadası — qızıl medal', '4Ç sinif şagirdi Səyavuş Bağırzadə KİNQS Beynəlxalq məktəb olimpiadasının payız liqasında iştirak edərək qızıl medal qazanıb.', '2025-11-01', '', NULL, '2026-09-25 20:20:00.207', 'Şagird nailiyyətləri', '', 'Məktəb rəhbərliyi', '[]', '', ''),
(11, 'Pifaqor Riyaziyyat Olimpiadası — gümüş medal', 'IV sinif şagirdləri Bağırzadə Səyavuş və Məsimov Rizvan Beyin Olimpiada Mərkəzi tərəfindən 27.12.2025-ci il tarixində keçirilən Pifaqor Riyaziyyat Olimpiadasında gümüş medal qazanıblar.', '2025-12-27', '', NULL, '2026-09-25 20:20:00.207', 'Şagird nailiyyətləri', '', 'Məktəb rəhbərliyi', '[]', '', ''),
(12, 'Kunq-Fu sanda Azərbaycan birinciliyi — I yer', 'VI sinif şagirdi Seyidzadə Sahib "Kunq-Fu" sanda üzrə Azərbaycan birinciliyi 42 kq çəki dərəcəsində I yerə layiq görülüb.', '2026-03-01', '', NULL, '2026-09-25 20:20:00.207', 'Şagird nailiyyətləri', '', 'Məktəb rəhbərliyi', '[]', '', ''),
(13, '"Legion Döyüş Liqası" — I yer', 'IX sinif şagirdi Əlistanova Nəzrin MMA və Grappling idman növləri üzrə Ümummilli Lider Heydər Əliyevin xatirəsinə həsr olunmuş "Legion Döyüş Liqası" turnirində I yerə layiq görülüb.', '2026-03-15', '', NULL, '2026-09-25 20:20:00.207', 'Şagird nailiyyətləri', '', 'Məktəb rəhbərliyi', '[]', '', ''),
(14, 'SASMO Olimpiadası — gümüş medal', '5D sinif şagirdi Məmmədzadə Fatimə SASMO olimpiadasından 2-ci yer, gümüş medal qazanmışdır.', '2026-02-15', '', NULL, '2026-09-25 20:20:00.207', 'Şagird nailiyyətləri', '', 'Məktəb rəhbərliyi', '[]', '', '')
ON DUPLICATE KEY UPDATE `title`=VALUES(`title`), `description`=VALUES(`description`), `achieved_on`=VALUES(`achieved_on`), `image_url`=VALUES(`image_url`), `created_by`=VALUES(`created_by`), `created_at`=VALUES(`created_at`), `category`=VALUES(`category`), `section`=VALUES(`section`), `author`=VALUES(`author`), `keywords`=VALUES(`keywords`), `student_name`=VALUES(`student_name`), `class_name`=VALUES(`class_name`);

INSERT INTO `school_events` (`id`, `title`, `description`, `event_date`, `location`, `image_url`, `created_by`, `created_at`, `category`, `section`, `author`, `keywords`) VALUES
(1, 'Aprel şəhidlərinin xatirəsinə həsr olunmuş görüş', 'Bu gün məktəbin tarix müəllimi Billurə Əliyeva və "Kiçik Akademiya" üzvlərinin birgə təşkilatçılığı ilə "Aprel faciəsi" mövzusuna həsr olunmuş görüş keçirilib.

Görüşdə ilk olaraq Azərbaycan Respublikasının Dövlət Himni səsləndirilib, daha sonra Vətənimizin ərazi bütövlüyü uğrunda qəhrəmancasına döyüşərək canından keçmiş şəhidlərimizin əziz xatirəsi bir dəqiqəlik sükutla yad edilib.

Tədbirdə şagirdlərin hazırladığı videoçarxlar nümayiş olunub, şəhidlərimizin döyüş yolu barədə məlumat verilib.

Bu kimi tədbirlər şagirdlərimizdə vətənpərvərlik ruhunu daha da yüksəldir və onların Vətənə olan məhəbbətini gücləndirir.', '2026-04-02', 'Məktəbin tarix kabinəsi', 'school205/tarix-ders-aprel.jpg', NULL, '2026-09-25 20:20:00.191', 'Vətənpərvərlik', 'Anım tədbirləri', 'Billurə Əliyeva, tarix müəllimi', '["Aprel döyüşləri", "şəhid", "vətənpərvərlik", "Kiçik Akademiya"]'),
(2, '"Bir millətin qan yaddaşı – Xocalı"', 'Bu gün məktəbin tarix müəllimi Billurə Əliyeva və "Kiçik Akademiya" üzvlərinin təşkilatçılığı ilə Xocalı faciəsinin 34-cü ildönümü ilə əlaqədar "Bir millətin qan yaddaşı – Xocalı" adlı xüsusi dərs keçirilib.

Tədbirin əsas məqsədi şagirdlərə xalqımızın yaşadığı bu ağır və faciəli tarixi hadisə haqqında ətraflı məlumat vermək, onlarda vətənpərvərlik hisslərini gücləndirməkdən ibarət olub.

Dərs Azərbaycan Respublikasının Dövlət Himninin səsləndirilməsi ilə başlayıb.

Daha sonra tarix müəllimi 1992-ci ilin fevralın 25-dən 26-na keçən gecə baş verən hadisələr haqqında məlumat verib, faciənin mahiyyəti, səbəbləri və nəticələrindən danışıb.

Xüsusi dərsdə "Kiçik Akademiya"nın üzvləri tərəfindən hazırlanmış təqdimatlar nümayiş olunub, tarixi faktlar səsləndirilib, şeirlər və ədəbi-bədii kompozisiyalar təqdim edilib.', '2026-02-26', 'Məktəbin akt zalı', '', NULL, '2026-09-25 20:20:00.191', 'Tarixi yaddaş', 'Xüsusi dərslər', 'Billurə Əliyeva, tarix müəllimi', '["Xocalı", "faciə", "34-cü ildönümü", "tarixi yaddaş", "Kiçik Akademiya"]'),
(3, '"20 Yanvar – Unudulmayan Gün" adlı dəyirmi masa keçirilib', 'Bu gün məktəbin rus dili müəllimi Səbinə Əkbərova və "Kiçik Akademiya" üzvlərinin iştirakı ilə "20 Yanvar – Unudulmayan Gün" adlı dəyirmi masa keçirilib.

Tədbirin məqsədi şagirdlərə 20 Yanvar faciəsi haqqında sadə və aydın məlumat vermək, şəhidlərimizin xatirəsini yad etməkdən ibarət olub.

Tədbir zamanı şagirdlər 20 Yanvar hadisələri barədə danışıb, həmin gün baş verənlər haqqında fikirlərini bildiriblər.

Şagirdlər vətənpərvərlik mövzusunda şeirlər söyləyib və qısa çıxışlar ediblər.

Müəllim S. Əkbərova çıxış edərək 20 Yanvarın Azərbaycan xalqının azadlıq yolunda mühüm bir gün olduğunu qeyd edib.

Sonda şagirdlər şəhidlər haqqında videoçarx izləyiblər.', '2026-01-20', 'Məktəbin kitabxanası', '', NULL, '2026-09-25 20:20:00.191', 'Tarixi yaddaş', 'Dəyirmi masa', 'Səbinə Əkbərova, rus dili müəllimi', '["20 Yanvar", "şəhid", "azadlıq", "dəyirmi masa"]'),
(4, '"Heydər Əliyev – Unudulmayan Lider"', 'Ümummilli Lider Heydər Əliyevin Anım Günü ilə əlaqədar məktəbdə seminarlar, dəyirmi masalar, sinif təşkilat saatları və konfranslar keçirilib.

Bu məqsədlə məktəbin ingilis dili müəllimi Aydan Məlikova və "Kiçik Akademiya" üzvləri "Heydər Əliyev – Unudulmayan Lider" başlığı altında dəyirmi masa keçiriblər.

Tədbirin məqsədi şagirdlərə Ulu Öndərin həyat yolu, dövlətçilik fəaliyyəti və Azərbaycan gəncliyinin inkişafına verdiyi töhfələr barədə dolğun məlumat təqdim etmək olub.

İlk olaraq Heydər Əliyevin əziz xatirəsi bir dəqiqəlik sükutla yad edilib.

Tədbirin təşkilatçısı Aydan Məlikova Heydər Əliyevin milli-mənəvi dəyərlərin qorunması, təhsilin inkişafı və gənclərin dünyagörüşünün genişləndirilməsinə göstərdiyi diqqət haqqında məlumat verib.

Daha sonra "Kiçik Akademiya" üzvləri hazırladıqları təqdimatlarla çıxış ediblər.

Onlar Heydər Əliyevin həyat və fəaliyyətinin müxtəlif dövrlərini əks etdirən slaydlar, fotolar və maraqlı faktları nümayiş etdiriblər.

Şagirdlərin təqdimatlarında Ulu Öndərin təhsilə verdiyi önəm və xarici dillərin öyrənilməsinə yaratdığı imkanlar xüsusi vurğulanıb.', '2025-12-12', 'Məktəbin akt zalı', '', NULL, '2026-09-25 20:20:00.191', 'Tarixi yaddaş', 'Anım günü', 'Aydan Məlikova, ingilis dili müəllimi', '["Heydər Əliyev", "Anım Günü", "Ulu Öndər", "dəyirmi masa"]'),
(5, 'Heydər Əliyevi anırıq', 'Məktəbimizdə Ulu Öndər Heydər Əliyevin xatirəsinə həsr olunmuş silsilə tədbirlər keçirilir.

Bu çərçivədə məktəbin tarix müəllimi Billurə Əliyeva və "Kiçik Akademiya" üzvləri Ulu Öndər Heydər Əliyevin xatirəsinə həsr olunmuş sinif təşkilat saatı keçiriblər.

Tədbirin məqsədi şagirdlərə Heydər Əliyevin həyatı, Azərbaycan üçün gördüyü işlər və gənclərə olan qayğısı haqqında məlumat verməkdən ibarət olub.

Müəllim giriş sözündə Heydər Əliyevin ölkəmizin inkişafına böyük töhfə verdiyini, xüsusilə təhsilə və məktəblilərə daim diqqət göstərdiyini qeyd edib.

Daha sonra "Kiçik Akademiya" üzvləri hazırladıqları qısa çıxışlarla Ulu Öndərin həyat yolu, fəaliyyəti və gənclərə verdiyi dəyər haqqında məlumat paylaşıblar.

Şagirdlər onun "Gənclər bizim gələcəyimizdir" fikrini xatırladaraq Ulu Öndərin gənc nəslə göstərdiyi etimadı vurğulayıblar.

Tədbirdə Heydər Əliyevin şəkilləri və haqqında məlumatlar təqdim edilib.

Sonda Ulu Öndərin əziz xatirəsi bir dəqiqəlik sükutla yad edilib.', '2025-12-12', 'Sinif otaqları', '', NULL, '2026-09-25 20:20:00.191', 'Tarixi yaddaş', 'Sinif təşkilat saatı', 'Billurə Əliyeva, tarix müəllimi', '["Heydər Əliyev", "sinif saatı", "gənclər", "Ulu Öndər"]'),
(6, 'Yeni tədris ilinə hazırlıq görüşü', 'Valideyn komitələri ilə birgə keçirilən görüşdə məktəbli formaları, davamiyyət, nizam-intizam və tədris prosesinin təşkili müzakirə olunub.', '2026-09-23', '', 'school205/valideyn-yiginciagi.jpg', NULL, '2026-09-25 20:20:00.208', 'Tədbirlər', '', 'Məktəb rəhbərliyi', '[]'),
(7, 'I sinif valideyn iclası — psixoprofilaktik söhbət', 'Məktəb psixoloqu Aytən Məmmədova I sinif şagirdlərinin valideynləri ilə uşağın məktəbə uğurlu adaptasiyası mövzusunda görüş keçirib.', '2026-09-22', '', 'school205/ilk-zeng-1.jpg', NULL, '2026-09-25 20:20:00.208', 'Tədbirlər', '', 'Məktəb rəhbərliyi', '[]'),
(8, 'Paytaxt təhsil işçilərinin sentyabr konfransı', 'Bakı üzrə ümumi təhsil müəssisələri rəhbərlərinin iştirakı ilə keçirilən illik konfrans.', '2026-09-15', '', 'school205/muellim-konfransi.jpg', NULL, '2026-09-25 20:20:00.208', 'Tədbirlər', '', 'Məktəb rəhbərliyi', '[]'),
(9, 'Əməyə verilən yüksək qiymət — təltif mərasimi', 'Silahlı Qüvvələr Günü və 50 illik yubiley münasibətilə əməkdaşların təltifi.', '2026-09-05', '', 'school205/teltif-merasimi-a.jpg', NULL, '2026-09-25 20:20:00.208', 'Tədbirlər', '', 'Məktəb rəhbərliyi', '[]'),
(10, 'Aprel faciəsinə həsr olunmuş anım tədbiri', '"Kiçik Akademiya" üzvlərinin təşkilatçılığı ilə keçirilən tarix dərsi və video nümayişi.', '2026-08-31', '', 'school205/tarix-ders-aprel.jpg', NULL, '2026-09-25 20:20:00.208', 'Tədbirlər', '', 'Məktəb rəhbərliyi', '[]')
ON DUPLICATE KEY UPDATE `title`=VALUES(`title`), `description`=VALUES(`description`), `event_date`=VALUES(`event_date`), `location`=VALUES(`location`), `image_url`=VALUES(`image_url`), `created_by`=VALUES(`created_by`), `created_at`=VALUES(`created_at`), `category`=VALUES(`category`), `section`=VALUES(`section`), `author`=VALUES(`author`), `keywords`=VALUES(`keywords`);

INSERT INTO `school_info` (`id`, `school_name`, `about_text`, `address`, `phone`, `email`, `cover_image_url`, `updated_by`, `updated_at`) VALUES
(1, 'Bakı şəhəri R.İmanov adına 205 nömrəli tam orta məktəb', 'FƏXRİMİZ

Rövşən İmanov 1969-cu il iyunun 27-də Bakı şəhərində anadan olub. Hələ uşaqlıq illərindən vətənpərvər ruhda böyümüş və daim Vətəni qorumaq, onun keşiyində durmaq arzusu ilə yaşayıb. O, 1976-cı ildə 205 nömrəli orta məktəbin birinci sinfinə daxil olub. 1984-cü ildə səkkizillik orta təhsilini başa vurduqdan sonra 68 nömrəli texniki-peşə məktəbində ixtisas təhsili alıb. 1987-1989-cu illərdə ordu sıralarında hərbi xidməti uğurla başa vurub.

1991-ci ildə Xüsusi Polis Dəstəsinə daxil olan Rövşən Daşaltı, Kərkicahan, Şuşa, Goranboy və digər yaşayış məntəqələri ətrafında baş verən qanlı döyüşlərdə qəhrəmanlıq göstərib.

1992-ci il iyulun 22-də Ağdərədə düşmənin hücumunu dəf edərkən qəhrəmancasına şəhid olub.

Elə həmin il Rövşən Nadir oğlu İmanovun adı 205 nömrəli tam orta məktəbə verilib.

BU GÜN MƏKTƏBİMİZ

2025/2026-cı tədris ilində 45 sinifdə (2A–11D) 1270 şagird təhsil alır. Məktəb üzrə müvəffəqiyyət 98,5%, keyfiyyət göstəricisi isə 66,3%-dir. Həmin tədris ilində 139 məzunumuzdan 63 nəfəri ali təhsil müəssisələrinə qəbul olub, onlardan 4 nəfəri 600-dən yüksək bal toplayıb.', 'Mətbuat 107, Binəqədi, Bakı, AZ1053', '(+994 12) 411-19-98', '205mekteb@bakuedu.gov.az', 'school205/ilk-zeng-2.jpg', NULL, '2026-09-25 20:20:00.178')
ON DUPLICATE KEY UPDATE `school_name`=VALUES(`school_name`), `about_text`=VALUES(`about_text`), `address`=VALUES(`address`), `phone`=VALUES(`phone`), `email`=VALUES(`email`), `cover_image_url`=VALUES(`cover_image_url`), `updated_by`=VALUES(`updated_by`), `updated_at`=VALUES(`updated_at`);

INSERT INTO `school_news` (`id`, `title`, `body`, `image_url`, `published`, `created_by`, `created_at`, `category`, `section`, `author`, `keywords`, `published_at`, `gallery`) VALUES
(1, '15 Sentyabr – Bilik Günü!', 'Bu gün məktəbimizin həyəti yenidən uşaqların səsi, gülüşü və böyük arzuları ilə canlandı!

Yeni tədris ilinin ilk günündə məktəbimizdə Bilik Günü münasibətilə tədbir keçirildi. Şagirdlər, müəllimlər və valideynlər üçün yeni bir başlanğıcın həyəcanı yaşandı.

Mərasimdə məktəb direktoru Əliheydər Əlifli şagirdləri və pedaqoji kollektivi yeni tədris ili münasibətilə təbrik edib, xüsusilə ilk dəfə məktəb həyətinə qədəm qoyan birinci sinif şagirdlərinə uğurlar arzulayıb.

Qoy 2026–2027-ci tədris ili hər bir şagirdimiz üçün yeni biliklər, yeni dostluqlar, gözəl xatirələr və böyük uğurlarla yadda qalsın!

Yeni dərs ili uğurlu olsun!', 'school205/sagird-toplantisi.jpg', 1, NULL, '2026-09-25 20:20:00.187', 'Məktəb həyatı', 'Bilik Günü', 'Məktəb rəhbərliyi', '["Bilik Günü", "15 sentyabr", "yeni tədris ili", "2026-2027", "birinci sinif", "açılış"]', '2026-09-15', '["school205/bilik-gunu-sinif.jpg", "school205/direktor-cixisi.jpg"]'),
(2, 'Yeni tədris ilinə birlikdə və məqsədyönlü şəkildə!', 'Bu gün məktəb rəhbərliyi tərəfindən valideyn komitələrinin iştirakı ilə yeni tədris ilinə hazırlıqla bağlı görüş keçirilib.

Görüşdə məktəbli formaları, davamiyyət və punktuallıq, nizam-intizam, eləcə də tədris prosesinin səmərəli təşkili ilə bağlı mühüm məsələlər müzakirə olunub.

Direktor Əliheydər Əlifli çıxışında məktəb-valideyn əməkdaşlığının şagird uğurundakı rolunu vurğulayıb, sağlam və nizamlı təhsil mühitinin yaradılmasının prioritet olduğunu qeyd edib.

Təlim-tərbiyə işləri üzrə direktor müavini Aynur Ələsgərova isə tədrisin keyfiyyətinin yüksəldilməsi, şagird nailiyyətlərinin artırılması və təhsil nəticələrinin yaxşılaşdırılması istiqamətində vacib məsələlərə toxunub.

Görüş qarşılıqlı fikir və təkliflərin dinlənilməsi baxımından səmərəli davam edib.', 'school205/valideyn-yiginciagi.jpg', 1, NULL, '2026-09-25 20:20:00.187', 'Məktəb həyatı', 'Valideyn əməkdaşlığı', 'Məktəb rəhbərliyi', '["valideyn", "tədris ili", "görüş", "nizam-intizam", "davamiyyət", "direktor"]', '2026-08-29', '[]'),
(3, 'Məktəbə ilk addım – sevgi, anlayış və dəstək!', 'Bu gün məktəbimizin psixoloqu Aytən Məmmədova I sinif şagirdlərinin valideyn iclasında iştirak edərək psixoprofilaktik söhbət aparıb.

Şagirdlərin məktəbə uğurlu adaptasiyasını dəstəkləmək məqsədilə valideynlərə aşağıdakı tövsiyələr verilib:

• Uşağa qarşı səbirli və anlayışlı olmaq;
• Məktəb və müəllim haqqında pozitiv fikir formalaşdırmaq;
• Uşağı digər şagirdlərlə müqayisə etməmək;
• Onun narahatlıqlarını dinləmək və hisslərini qəbul etmək;
• Dərs və istirahət rejiminə diqqət yetirmək;
• Kiçik uğurlarını belə təqdir və motivasiya etmək.

Uşağın məktəbə uğurlu adaptasiyası ailə və məktəbin qarşılıqlı əməkdaşlığı, sevgisi və dəstəyi ilə daha da möhkəmlənir.', 'school205/ilk-zeng-1.jpg', 1, NULL, '2026-09-25 20:20:00.187', 'Psixoloji xidmət', 'Məktəbə adaptasiya', 'Aytən Məmmədova, məktəb psixoloqu', '["psixoloq", "adaptasiya", "birinci sinif", "valideyn", "tövsiyə"]', '2026-09-05', '[]'),
(4, 'Məktəbin uğurlu nəticələri', 'Bakı şəhəri 205 nömrəli tam orta ümumtəhsil məktəbindən uğurlu nəticələr!

2025/2026-cı tədris ilində 139 məzunumuz qəbul imtahanında iştirak edib. Onlardan 63 nəfəri ali təhsil müəssisələrinə qəbul olub.

4 məzunumuz 600-dən yüksək bal toplayıb!

Ümumi qəbul göstəricisi – 45,3%.

Məzunlarımızı və müəllimlərimizi bu uğur münasibətilə təbrik edir, onlara gələcək fəaliyyətlərində yeni nailiyyətlər arzulayırıq!', 'school205/qebul-hesabati.jpg', 1, NULL, '2026-09-25 20:20:00.187', 'Təhsil və nəticələr', 'Ali məktəbə qəbul göstəriciləri', 'Məktəb rəhbərliyi', '["qəbul", "məzun", "600 bal", "ali təhsil", "nəticə", "imtahan"]', '2026-08-15', '[]'),
(5, 'Paytaxt təhsil işçilərinin sentyabr konfransına start verilib', 'Bakı şəhərindəki ümumi təhsil və məktəbdənkənar təhsil müəssisələri rəhbərlərinin iştirakı ilə keçirilən konfransın I hissəsində Məktəbəqədər və Ümumi Təhsil üzrə Dövlət Agentliyinin (MÜTDA) direktor müavini, Bakı Şəhəri üzrə Təhsil İdarəsinin (BŞTİ) müdiri vəzifəsini müvəqqəti icra edən Nərminə Hüseynova, Azərbaycan Respublikası Təhsil İnstitutunun (ARTİ) Təhsilverənlərin peşəkar inkişaf mərkəzinin direktoru Nəzakət Mehdiyeva, Elm və Təhsil Nazirliyinin, MÜTDA və BŞTİ-nin müvafiq struktur bölmə rəhbərləri, ümumi təhsil müəssisələrinin rəhbərləri və metodistlər iştirak ediblər.

Konfrans Dövlət Himninin səsləndirilməsi və Vətən şəhidlərinin əziz xatirəsinin bir dəqiqəlik sükutla yad edilməsi ilə başlayıb.

Konfrans iştirakçılarını salamlayan Nərminə Hüseynova yeni tədris ilinin başlanması münasibətilə təhsil işçilərini təbrik edib və onlara uğurlar arzulayıb.

2025–2026-cı tədris ili ərzində təhsil müəssisələrində görülən işlər və əldə olunan nəticələr barədə təqdimatla çıxış edən Nərminə Hüseynova əsas göstəricilər üzrə dinamikanı diqqətə çatdırıb, mövcud məsələlər və onların həlli istiqamətində həyata keçirilən tədbirlərdən bəhs edib, yeni tədris ili üzrə prioritetlərə toxunaraq qarşıda duran əsas hədəfləri diqqətə çatdırıb.

Nərminə Hüseynova bildirib ki, yeni tədris ilində də ümumi təhsilin keyfiyyətinin yüksəldilməsi, qabaqcıl pedaqoji təcrübələrin yayılması, rəqəmsal və innovativ yanaşmaların tətbiqinin genişləndirilməsi, istedadlı şagirdlərin dəstəklənməsi, həmçinin məktəb-valideyn əməkdaşlığının daha da möhkəmləndirilməsi paytaxt təhsilinin qarşısında duran əsas hədəflərdəndir.

BŞTİ-nin müdir müavini Turanə Məcidli, ARTİ-nin Təhsilverənlərin peşəkar inkişaf mərkəzinin direktoru Nəzakət Mehdiyeva, BŞTİ-nin Keyfiyyətə nəzarət sektorunun müdiri Zinyət Əmirova, Məktəbdənkənar fəaliyyətlərin təşkili sektorunun müdiri Günay Qurbanova müxtəlif istiqamətlər üzrə təqdimatlar ediblər.

Təqdimatlarda məktəbdaxili qiymətləndirmənin obyektivliyi, zəif nəticə göstərən şagirdlərlə iş, müəllimlər arasında əməkdaşlıq və təcrübə mübadiləsi, keyfiyyət monitorinqləri, buraxılış imtahanlarının nəticələrinin müqayisəli təhlili, məktəbdənkənar fəaliyyətlərin əhatəliliyi və nəticəyönümlülüyü ilə bağlı məsələlər müzakirə olunub.

Konfransın II hissəsinin paytaxt üzrə məktəbəqədər təhsil müəssisələri rəhbərlərinin iştirakı ilə keçirilməsi nəzərdə tutulub.

Qeyd edək ki, konfrans növbəti gün də işini davam etdirəcək. BŞTİ-nin tabeliyindəki təhsil müəssisələrinin rəhbərləri, fənn müəllimləri, metodistlər və məktəb psixoloqlarının iştirakı ilə panel müzakirələr təşkil olunacaq, növbəti dərs ili üçün fəaliyyət planı hazırlanacaq və müvafiq təkliflər təqdim olunacaq.', 'school205/muellim-konfransi.jpg', 1, NULL, '2026-09-25 20:20:00.187', 'Tədbirlər', 'Konfranslar', 'Bakı Şəhəri üzrə Təhsil İdarəsi', '["konfrans", "MÜTDA", "BŞTİ", "sentyabr", "təhsil", "prioritet"]', '2026-09-01', '[]'),
(6, 'IX sinif buraxılış imtahanı nəticələrinin təhlili', 'IX sinif buraxılış imtahanının nəticələri təhlil olunub.

Son üç ilin müqayisəsi göstərir ki, məktəbimiz 2024-cü illə müqayisədə irəliləyiş əldə etsə də, 2025-ci ilin nəticələri ilə müqayisədə geriləmə müşahidə olunub.

Bu, xüsusilə 0–30 bal aralığında nəticə göstərən şagirdlərin sayı və reytinq göstəricilərində özünü göstərib.

Növbəti tədris ilində təkmilləşdirilmiş iş prinsipi və komanda əməkdaşlığı ilə nəticələrimizi daha da yaxşılaşdırmaq üçün əzmlə çalışacağıq.', 'school205/mutda-hesabat.jpg', 1, NULL, '2026-09-25 20:20:00.187', 'Təhsil və nəticələr', 'Analitika', 'Məktəb rəhbərliyi', '["buraxılış imtahanı", "IX sinif", "təhlil", "reytinq", "bal"]', '2026-07-20', '[]'),
(7, '2025/2026-cı tədris ilinin təlim nəticələrinin illik hesabatı təqdim olundu', '2025/2026-cı tədris ili üzrə 2A–11D siniflərinin təlim nəticələrinin geniş təhlili başa çatdırılıb.

Hesabatda:

• Məktəb üzrə müvəffəqiyyət və keyfiyyət göstəriciləri;
• Fənlər üzrə orta bal nəticələri;
• Əla, yaxşı, kafi və qeyri-kafi qiymətlərin sayı;
• Buraxılış fənləri üzrə əldə olunmuş nəticələrin müqayisəli təhlili

öz əksini tapıb.

Təhlil göstərir ki, buraxılış fənləri arasında ən yüksək nəticə Azərbaycan dili, ən aşağı nəticə isə riyaziyyat fənni üzrə qeydə alınıb.

Əldə edilmiş nəticələr növbəti tədris ilində həyata keçiriləcək fəaliyyətlərin planlaşdırılması üçün əsas istiqamətləri müəyyən edir.

Bununla əlaqədar olaraq 2026/2027-ci tədris ili üzrə Fəaliyyət Planı hazırlanacaq, təlim nəticələrinin daha da yaxşılaşdırılması məqsədilə fənn müəllimləri və metodbirləşmə rəhbərlərinin iştirakı ilə məqsədyönlü tədbirlər həyata keçiriləcək.

Təhsildə davamlı inkişafın əsasında dəqiq təhlil, düzgün planlaşdırma və səmərəli əməkdaşlıq dayanır.', 'school205/hesabat-2025-2026.jpg', 1, NULL, '2026-09-25 20:20:00.187', 'Hesabatlar və statistika', 'İllik təlim hesabatı', 'Məktəb rəhbərliyi', '["hesabat", "təlim nəticələri", "müvəffəqiyyət", "keyfiyyət", "orta bal", "riyaziyyat", "Azərbaycan dili"]', '2026-06-30', '[]'),
(8, 'Əməyə verilən yüksək qiymət!', 'Məktəbimizin bir qrup kişi müəllimi və əməkdaşı 26 İyun – Azərbaycan Respublikasının Silahlı Qüvvələri Günü münasibətilə, digər bir qrup müəllimi isə 50 illik yubileyləri münasibətilə Elm və Təhsil İşçiləri Həmkarlar İttifaqı Binəqədi Rayon Komitəsi tərəfindən təltif olunublar.

Onlar gənc nəslin müstəqil həyata hazırlanmasında göstərdikləri şərəfli və fədakar əməyə, şagirdlərin təlim-tərbiyəsində üzərlərinə düşən vəzifələri layiqincə yerinə yetirdiklərinə görə Təşəkkürnamə və hədiyyələrlə mükafatlandırılıblar.

Təltif olunan bütün əməkdaşlarımızı ürəkdən təbrik edir, onlara gələcək fəaliyyətlərində yeni-yeni uğurlar arzulayırıq!', 'school205/teltif-merasimi-a.jpg', 1, NULL, '2026-09-25 20:20:00.187', 'Müəllim nailiyyətləri', 'Təltiflər', 'Məktəb rəhbərliyi', '["təltif", "Silahlı Qüvvələr Günü", "yubiley", "həmkarlar ittifaqı", "təşəkkürnamə"]', '2026-06-26', '[]'),
(9, 'Yeni tədris ilinə birlikdə və məqsədyönlü şəkildə!', 'Məktəb rəhbərliyi tərəfindən valideyn komitələrinin iştirakı ilə yeni tədris ilinə hazırlıqla bağlı görüş keçirilib. Görüşdə məktəbli formaları, davamiyyət və punktuallıq, nizam-intizam, eləcə də tədris prosesinin səmərəli təşkili ilə bağlı mühüm məsələlər müzakirə olunub.

Direktor Əliheydər Əlifli çıxışında məktəb-valideyn əməkdaşlığının şagird uğurundakı rolunu vurğulayıb, sağlam və nizamlı təhsil mühitinin yaradılmasının prioritet olduğunu qeyd edib.

Təlim-tərbiyə işləri üzrə direktor müavini Aynur Ələsgərova isə tədrisin keyfiyyətinin yüksəldilməsi, şagird nailiyyətlərinin artırılması və təhsil nəticələrinin yaxşılaşdırılması istiqamətində vacib məsələlərə toxunub.', 'school205/valideyn-yiginciagi.jpg', 1, NULL, '2026-09-23 20:20:00.206', 'Məktəb həyatı', '', 'Məktəb rəhbərliyi', '[]', '2026-09-25', '[]'),
(10, 'Məktəbə ilk addım – sevgi, anlayış və dəstək!', 'Məktəbimizin psixoloqu Aytən Məmmədova I sinif şagirdlərinin valideyn iclasında iştirak edərək psixoprofilaktik söhbət aparıb.

Şagirdlərin məktəbə uğurlu adaptasiyasını dəstəkləmək məqsədilə valideynlərə tövsiyələr verilib: uşağa qarşı səbirli və anlayışlı olmaq, məktəb və müəllim haqqında pozitiv fikir formalaşdırmaq, uşağı digər şagirdlərlə müqayisə etməmək, onun narahatlıqlarını dinləmək, dərs-istirahət rejiminə diqqət yetirmək və kiçik uğurlarını belə təqdir etmək.', 'school205/ilk-zeng-1.jpg', 1, NULL, '2026-09-22 20:20:00.206', 'Məktəb həyatı', '', 'Məktəb rəhbərliyi', '[]', '2026-09-25', '[]'),
(11, 'Məktəbin uğurlu nəticələri', '2025/2026-cı tədris ilində 139 məzunumuz qəbul imtahanında iştirak edib. Onlardan 63 nəfəri ali təhsil müəssisələrinə qəbul olub. 4 məzunumuz 600-dən yüksək bal toplayıb! Ümumi qəbul göstəricisi — 45,3%.

Məzunlarımızı və müəllimlərimizi bu uğur münasibətilə təbrik edirik!', 'school205/qebul-hesabati.jpg', 1, NULL, '2026-09-20 20:20:00.206', 'Məktəb həyatı', '', 'Məktəb rəhbərliyi', '[]', '2026-09-25', '[]'),
(12, 'Paytaxt təhsil işçilərinin sentyabr konfransına start verilib', 'Bakı şəhərindəki ümumi təhsil və məktəbdənkənar təhsil müəssisələri rəhbərlərinin iştirakı ilə keçirilən konfrans Dövlət Himninin səsləndirilməsi və şəhidlərimizin xatirəsinin bir dəqiqəlik sükutla yad edilməsi ilə başlayıb.

Konfransda yeni tədris ilində ümumi təhsilin keyfiyyətinin yüksəldilməsi, qabaqcıl pedaqoji təcrübələrin yayılması, rəqəmsal və innovativ yanaşmaların tətbiqinin genişləndirilməsi, istedadlı şagirdlərin dəstəklənməsi və məktəb-valideyn əməkdaşlığının möhkəmləndirilməsi əsas prioritetlər kimi vurğulanıb.', 'school205/muellim-konfransi.jpg', 1, NULL, '2026-09-15 20:20:00.206', 'Məktəb həyatı', '', 'Məktəb rəhbərliyi', '[]', '2026-09-25', '[]'),
(13, 'IX sinif buraxılış imtahanı nəticələrinin təhlili', 'IX sinif buraxılış imtahanının nəticələri təhlil olunub. Son üç ilin müqayisəsi göstərir ki, məktəbimiz 2024-cü illə müqayisədə irəliləyiş əldə etsə də, 2025-ci ilin nəticələri ilə müqayisədə geriləmə müşahidə olunub. Növbəti tədris ilində təkmilləşdirilmiş iş prinsipi və komanda əməkdaşlığı ilə nəticələrimizi daha da yaxşılaşdırmaq üçün əzmlə çalışacağıq.', 'school205/mutda-hesabat.jpg', 1, NULL, '2026-09-11 20:20:00.206', 'Məktəb həyatı', '', 'Məktəb rəhbərliyi', '[]', '2026-09-25', '[]'),
(14, '2025/2026-cı tədris ilinin təlim nəticələrinin illik hesabatı təqdim olundu', '2025/2026-cı tədris ili üzrə 2A–11D siniflərinin təlim nəticələrinin geniş təhlili başa çatdırılmışdır. Hesabatda məktəb üzrə müvəffəqiyyət və keyfiyyət göstəriciləri, fənlər üzrə orta bal nəticələri, əla/yaxşı/kafi/qeyri-kafi qiymətlərin sayı əks olunub.

Təhlil göstərir ki, buraxılış fənləri arasında ən yüksək nəticə Azərbaycan dili, ən aşağı nəticə isə riyaziyyat fənni üzrə qeydə alınmışdır. 2026/2027-ci tədris ili üzrə Fəaliyyət Planı hazırlanacaq.', 'school205/hesabat-2025-2026.jpg', 1, NULL, '2026-09-09 20:20:00.206', 'Məktəb həyatı', '', 'Məktəb rəhbərliyi', '[]', '2026-09-25', '[]'),
(15, 'Əməyə verilən yüksək qiymət!', 'Məktəbimizin bir qrup kişi müəllimi və əməkdaşı 26 İyun – Azərbaycan Respublikasının Silahlı Qüvvələri Günü münasibətilə, digər bir qrup müəllimi isə "50 illik yubiley"ləri münasibətilə Elm və Təhsil İşçiləri Həmkarlar İttifaqı Binəqədi Rayon Komitəsi tərəfindən təltif olunublar.

Təltif olunan bütün əməkdaşlarımızı ürəkdən təbrik edir, onlara gələcək fəaliyyətlərində yeni-yeni uğurlar arzulayırıq!', 'school205/teltif-merasimi-a.jpg', 1, NULL, '2026-09-05 20:20:00.206', 'Məktəb həyatı', '', 'Məktəb rəhbərliyi', '[]', '2026-09-25', '[]'),
(16, 'Aprel Şəhidlərinin Xatirəsinə həsr olunmuş görüş', 'Məktəbin tarix müəllimi Billurə Əliyeva və "Kiçik Akademiya" üzvlərinin birgə təşkilatçılığı ilə "Aprel faciəsi" mövzusuna həsr olunmuş görüş keçirilib. Görüşdə Dövlət Himni səsləndirilib, şəhidlərimizin əziz xatirəsi bir dəqiqəlik sükutla yad edilib, şagirdlərin hazırladığı videoçarxlar nümayiş olunub.', 'school205/tarix-ders-aprel.jpg', 1, NULL, '2026-08-31 20:20:00.206', 'Məktəb həyatı', '', 'Məktəb rəhbərliyi', '[]', '2026-09-25', '[]')
ON DUPLICATE KEY UPDATE `title`=VALUES(`title`), `body`=VALUES(`body`), `image_url`=VALUES(`image_url`), `published`=VALUES(`published`), `created_by`=VALUES(`created_by`), `created_at`=VALUES(`created_at`), `category`=VALUES(`category`), `section`=VALUES(`section`), `author`=VALUES(`author`), `keywords`=VALUES(`keywords`), `published_at`=VALUES(`published_at`), `gallery`=VALUES(`gallery`);

INSERT INTO `school_teachers` (`id`, `full_name`, `subject`, `photo_url`, `bio`, `sort_order`, `created_by`, `created_at`) VALUES
(1, 'Əliheydər Əlifli Elman', 'Direktor', 'school205/direktor-cixisi.jpg', 'Məktəb-valideyn əməkdaşlığının şagird uğurundakı rolunu daim vurğulayır; sağlam və nizamlı təhsil mühitinin yaradılmasını prioritet sayır.', 1, NULL, '2026-09-25 20:20:00.183'),
(2, 'Aynur Ələsgərova Cavid', 'Təlim-tərbiyə işləri üzrə direktor müavini', '', 'Tədrisin keyfiyyətinin yüksəldilməsi, şagird nailiyyətlərinin artırılması və təhsil nəticələrinin yaxşılaşdırılması istiqamətində işləri əlaqələndirir.', 2, NULL, '2026-09-25 20:20:00.183'),
(3, 'Vüsalə Rəcəbova Fərhad', 'Məktəbdənkənar və sinifdənxaric tərbiyə işi üzrə təşkilatçı', '', '', 3, NULL, '2026-09-25 20:20:00.183'),
(4, 'Zilfi Zilfiyev Baxış', 'Direktorun təsərrüfat işləri üzrə müavini (təsərrüfat müdiri)', '', '', 4, NULL, '2026-09-25 20:20:00.183'),
(5, 'Emin Əliyev Telman', 'Çağırışaqədərki hazırlıq rəhbəri', '', '', 5, NULL, '2026-09-25 20:20:00.183'),
(6, 'Zülfiyyə Məsimova Qənbər', 'Məktəb psixoloqu', '', '', 6, NULL, '2026-09-25 20:20:00.183'),
(7, 'Aytən Məmmədova Səadət', 'Məktəb psixoloqu', '', 'I sinif şagirdlərinin məktəbə uğurlu adaptasiyası üzrə valideynlərlə psixoprofilaktik söhbətlər aparır.', 7, NULL, '2026-09-25 20:20:00.183'),
(8, 'İlahə Babayeva Səadətdin', 'Kitabxana müdiri', '', '', 8, NULL, '2026-09-25 20:20:00.183'),
(9, 'Rüxsarə Qocayeva Qahir', 'Uşaq birliyi rəhbəri', '', '', 9, NULL, '2026-09-25 20:20:00.183'),
(10, 'Əliheydər Əlifli Elman', 'Direktor', '', '', 1, NULL, '2026-09-25 20:20:00.202'),
(11, 'Aynur Ələsgərova Cavid', 'Təlim-tərbiyə işləri üzrə direktor müavini', '', '', 2, NULL, '2026-09-25 20:20:00.202'),
(12, 'Vüsalə Rəcəbova Fərhad', 'Məktəbdənkənar və sinifdənxaric tərbiyə işi üzrə təşkilatçı', '', '', 3, NULL, '2026-09-25 20:20:00.202'),
(13, 'Zilfi Zilfiyev Baxış', 'Direktorun təsərrüfat işləri üzrə müavini', '', '', 4, NULL, '2026-09-25 20:20:00.202'),
(14, 'Emin Əliyev Telman', 'Çağırışaqədərki hazırlıq rəhbəri', '', '', 5, NULL, '2026-09-25 20:20:00.202'),
(15, 'Zülfiyyə Məsimova Qənbər', 'Məktəb psixoloqu', '', '', 6, NULL, '2026-09-25 20:20:00.202'),
(16, 'Aytən Məmmədova Səadət', 'Məktəb psixoloqu', '', '', 7, NULL, '2026-09-25 20:20:00.202'),
(17, 'İlahə Babayeva Səadətdin', 'Kitabxana müdiri', '', '', 8, NULL, '2026-09-25 20:20:00.202'),
(18, 'Rüxsarə Qocayeva Qahir', 'Uşaq birliyi rəhbəri', '', '', 9, NULL, '2026-09-25 20:20:00.202'),
(19, 'Billurə Əliyeva', 'Tarix müəllimi', '', '', 10, NULL, '2026-09-25 20:20:00.202'),
(20, 'Səbinə Əkbərova', 'Rus dili müəllimi', '', '', 11, NULL, '2026-09-25 20:20:00.202'),
(21, 'Aydan Məlikova', 'İngilis dili müəllimi', '', '', 12, NULL, '2026-09-25 20:20:00.202')
ON DUPLICATE KEY UPDATE `full_name`=VALUES(`full_name`), `subject`=VALUES(`subject`), `photo_url`=VALUES(`photo_url`), `bio`=VALUES(`bio`), `sort_order`=VALUES(`sort_order`), `created_by`=VALUES(`created_by`), `created_at`=VALUES(`created_at`);

INSERT INTO `ss_challenges` (`id`, `scope`, `title`, `slug`, `category`, `icon`, `summary`, `problem`, `why`, `research`, `approaches`, `difficulty`, `points`, `deadline`, `status`, `created_by`, `created_at`) VALUES
(1, 'world', 'Climate Challenge', 'climate-challenge', 'İqlim', '🌡️', 'Məktəbinin karbon izini ölç və azaltmaq üçün real plan təklif et.', 'Məktəblər gündəlik fəaliyyətində nəzərə alınmayan miqdarda enerji və resurs sərf edir.', 'İqlim dəyişikliyi bu nəslin ən böyük problemidir; dəyişiklik kiçik mühitlərdən başlayır.', '', '', 'orta', 60, NULL, 'open', '', '2026-09-25 20:20:00.575'),
(2, 'world', 'Future Education Challenge', 'future-education', 'Təhsil', '📚', '2035-ci ilin dərs otağını layihələndir.', 'Dərs formatı 100 ildir demək olar ki, dəyişməyib, halbuki dünya dəyişib.', 'Təhsilin forması gələcək peşələri müəyyən edir.', '', '', 'orta', 60, NULL, 'open', '', '2026-09-25 20:20:00.575'),
(3, 'world', 'AI for Good', 'ai-for-good', 'Texnologiya', '🤖', 'Süni intellektdən cəmiyyətə fayda verən bir həll qur.', 'AI çox vaxt əyləncə üçün işlənir, sosial problemlər üçün isə az.', 'Texnologiyanın istiqamətini onu quranlar seçir.', '', '', 'çətin', 80, NULL, 'open', '', '2026-09-25 20:20:00.575'),
(4, 'world', 'Water Challenge', 'water-challenge', 'Su', '💧', 'Təmiz suya çıxışı artıran və ya su israfını azaldan həll təklif et.', 'Dünyada hər 4 nəfərdən biri təhlükəsiz içməli su ilə tam təmin olunmur.', 'Su olmadan nə sağlamlıq, nə təhsil, nə də iqtisadiyyat mümkündür.', '', '', 'orta', 70, NULL, 'open', '', '2026-09-25 20:20:00.575'),
(5, 'world', 'Smart City Challenge', 'smart-city', 'Şəhər', '🏙', 'Bakının bir məhəlləsini daha ağıllı və rahat edən ideya qur.', 'Şəhər infrastrukturu çox vaxt insanın gündəlik marşrutunu nəzərə almır.', 'Şəhəri yaxşılaşdırmaq onu hər gün yaşayanların işidir.', '', '', 'orta', 65, NULL, 'open', '', '2026-09-25 20:20:00.575'),
(6, 'world', 'Sustainable Future Challenge', 'sustainable-future', 'Dayanıqlılıq', '🌱', 'Məktəbdə tullantını azaldan davamlı sistem qur.', 'Tullantıların böyük hissəsi düzgün ayrılmadığı üçün təkrar emala getmir.', 'Dayanıqlılıq vərdişi məktəbdə formalaşır.', '', '', 'asan', 50, NULL, 'open', '', '2026-09-25 20:20:00.575'),
(7, 'humanity', 'İqlim və Enerji', 'h-climate', 'Climate', '🌍', 'Qlobal istiləşməni azaldan yerli həllər.', 'Karbon emissiyası artmaqda davam edir.', 'Bugünkü qərarlar 50 il sonranı müəyyən edir.', '', '', 'çətin', 90, NULL, 'open', '', '2026-09-25 20:20:00.582'),
(8, 'humanity', 'Təmiz Su', 'h-water', 'Clean Water', '💧', 'Su çatışmazlığı və çirklənməsi ilə mübarizə.', '2 milyard insan təhlükəsiz su xidmətindən məhrumdur.', 'Su əsas insan hüququdur.', '', '', 'çətin', 90, NULL, 'open', '', '2026-09-25 20:20:00.582'),
(9, 'humanity', 'Hamı üçün Təhsil', 'h-education', 'Education', '📚', 'Təhsilə çıxışı olmayan uşaqlar üçün həllər.', 'Dünyada 250 milyondan çox uşaq məktəbdən kənardadır.', 'Təhsil yoxsulluqdan çıxışın ən qısa yoludur.', '', '', 'orta', 80, NULL, 'open', '', '2026-09-25 20:20:00.582'),
(10, 'humanity', 'Əlçatanlıq', 'h-accessibility', 'Accessibility', '♿', 'Məhdud imkanlı insanlar üçün maneələri aradan qaldır.', 'İctimai məkanların çoxu hərəkət məhdudiyyəti olanlar üçün nəzərdə tutulmayıb.', 'Əlçatanlıq bir azlığın deyil, hamının rahatlığıdır.', '', '', 'orta', 80, NULL, 'open', '', '2026-09-25 20:20:00.582'),
(11, 'humanity', 'Ətraf Mühit', 'h-environment', 'Environment', '🌱', 'Biomüxtəlifliyin qorunması və tullantının azaldılması.', 'Növlərin yox olma sürəti təbii fondan yüzlərlə dəfə yüksəkdir.', 'Ekosistem pozulanda ilk zərbəni insan alır.', '', '', 'orta', 75, NULL, 'open', '', '2026-09-25 20:20:00.582'),
(12, 'humanity', 'Ağıllı Şəhərlər', 'h-cities', 'Smart Cities', '🏙', 'Şəhər həyatını daha səmərəli və insani etmək.', 'Şəhərlərdə əhalinin yarısından çoxu yaşayır və bu rəqəm artır.', 'Yaxşı şəhər dizaynı milyonların gününü dəyişir.', '', '', 'orta', 75, NULL, 'open', '', '2026-09-25 20:20:00.582'),
(13, 'humanity', 'Qida Təhlükəsizliyi', 'h-food', 'Food', '🍎', 'Qida israfı və çatışmazlığı problemləri.', 'İstehsal olunan qidanın təxminən üçdə biri israf olunur.', 'İsrafı azaltmaq aclığı azaltmağın ən sürətli yoludur.', '', '', 'orta', 75, NULL, 'open', '', '2026-09-25 20:20:00.582'),
(14, 'humanity', 'Təmiz Enerji', 'h-energy', 'Clean Energy', '🔋', 'Bərpa olunan enerji həlləri.', 'Enerjinin böyük hissəsi hələ də qazma yanacaqlardan gəlir.', 'Enerji keçidi iqlim məsələsinin mərkəzidir.', '', '', 'çətin', 85, NULL, 'open', '', '2026-09-25 20:20:00.582'),
(15, 'humanity', 'Sosial Birlik', 'h-inclusion', 'Social Inclusion', '🤝', 'Cəmiyyətdə təcridin və ayrı-seçkiliyin azaldılması.', 'Bir çox qrup ictimai həyatdan kənarda qalır.', 'Birlik olmayan cəmiyyət inkişaf edə bilmir.', '', '', 'orta', 75, NULL, 'open', '', '2026-09-25 20:20:00.582')
ON DUPLICATE KEY UPDATE `scope`=VALUES(`scope`), `title`=VALUES(`title`), `slug`=VALUES(`slug`), `category`=VALUES(`category`), `icon`=VALUES(`icon`), `summary`=VALUES(`summary`), `problem`=VALUES(`problem`), `why`=VALUES(`why`), `research`=VALUES(`research`), `approaches`=VALUES(`approaches`), `difficulty`=VALUES(`difficulty`), `points`=VALUES(`points`), `deadline`=VALUES(`deadline`), `status`=VALUES(`status`), `created_by`=VALUES(`created_by`), `created_at`=VALUES(`created_at`);

INSERT INTO `ss_olympics_events` (`id`, `season`, `category`, `icon`, `stage`, `status`, `starts_at`, `duration_min`, `question_count`, `description`, `created_by`, `created_at`) VALUES
(1, '205 OLYMPICS 2026', 'Məntiq', '🧠', 'qualification', 'upcoming', NULL, 15, 12, 'Məntiqi ardıcıllıq və problem həlli.', '', '2026-09-25 20:20:00.594'),
(2, '205 OLYMPICS 2026', 'Söz ehtiyatı', '📚', 'qualification', 'upcoming', NULL, 15, 15, 'SözLab lüğəti üzrə yarış.', '', '2026-09-25 20:20:00.594'),
(3, '205 OLYMPICS 2026', 'Kodlaşdırma', '💻', 'qualification', 'upcoming', NULL, 15, 10, 'Alqoritm və məntiq tapşırıqları.', '', '2026-09-25 20:20:00.594'),
(4, '205 OLYMPICS 2026', 'Elm', '🔬', 'qualification', 'upcoming', NULL, 15, 12, 'Fizika, kimya, biologiya.', '', '2026-09-25 20:20:00.594'),
(5, '205 OLYMPICS 2026', 'Coğrafiya', '🗺️', 'qualification', 'upcoming', NULL, 15, 12, 'Dünya və Azərbaycan coğrafiyası.', '', '2026-09-25 20:20:00.594'),
(6, '205 OLYMPICS 2026', 'Dizayn', '🎨', 'qualification', 'upcoming', NULL, 15, 8, 'Vizual həll və kompozisiya.', '', '2026-09-25 20:20:00.594'),
(7, '205 OLYMPICS 2026', 'Natiqlik', '🎤', 'class', 'upcoming', NULL, 15, 5, 'Çıxış və arqumentasiya.', '', '2026-09-25 20:20:00.594'),
(8, '205 OLYMPICS 2026', 'Yaradıcı yazı', '✍️', 'class', 'upcoming', NULL, 15, 5, 'Mətn yaratma bacarığı.', '', '2026-09-25 20:20:00.594'),
(9, '205 OLYMPICS 2026', 'Texnologiya', '⚙️', 'qualification', 'upcoming', NULL, 15, 12, 'Rəqəmsal savadlılıq.', '', '2026-09-25 20:20:00.594'),
(10, '205 OLYMPICS 2026', 'Məktəb fəaliyyəti', '🏃', 'class', 'upcoming', NULL, 15, 6, 'Komanda və fiziki fəaliyyət.', '', '2026-09-25 20:20:00.594')
ON DUPLICATE KEY UPDATE `season`=VALUES(`season`), `category`=VALUES(`category`), `icon`=VALUES(`icon`), `stage`=VALUES(`stage`), `status`=VALUES(`status`), `starts_at`=VALUES(`starts_at`), `duration_min`=VALUES(`duration_min`), `question_count`=VALUES(`question_count`), `description`=VALUES(`description`), `created_by`=VALUES(`created_by`), `created_at`=VALUES(`created_at`);

INSERT INTO `ss_problems` (`id`, `title`, `body`, `category`, `difficulty`, `status`, `points`, `created_by`, `deadline`, `solved_by`, `solved_at`, `created_at`) VALUES
(1, 'Kitabxanada kitab tapmaq necə asanlaşdırıla bilər?', 'Şagirdlər kitabxanada axtardıqları kitabı tapmaqda çətinlik çəkir: kataloq kağız üzərindədir, rəflərdə naviqasiya işarəsi azdır. Məqsəd — şagirdin 2 dəqiqə ərzində kitabı tapmasını təmin edən həll.', 'Təhsil', 'orta', 'open', 75, '', NULL, '[]', NULL, '2026-09-25 20:20:00.586'),
(2, 'Məktəbdə enerji sərfiyyatını necə azalda bilərik?', 'Dərsdən sonra bəzi otaqlarda işıq və avadanlıq açıq qalır. Məqsəd — davranış və ya texniki həll ilə aylıq elektrik sərfini ölçülə bilən şəkildə azaltmaq.', 'Ekologiya', 'orta', 'open', 85, '', NULL, '[]', NULL, '2026-09-25 20:20:00.586'),
(3, 'Məktəbdə təkrar emalı necə yaxşılaşdıra bilərik?', 'Tullantı qabları var, amma ayrılma düzgün getmir. Məqsəd — şagirdlərin düzgün ayırmasını təbii hala gətirən sistem.', 'Ekologiya', 'asan', 'open', 60, '', NULL, '[]', NULL, '2026-09-25 20:20:00.586'),
(4, 'Şagirdlər vaxtlarını necə daha yaxşı idarə edə bilər?', 'Sınaqlar və tapşırıqlar üst-üstə düşəndə şagirdlər planlaşdıra bilmir. Məqsəd — sadə, istifadəsi asan planlaşdırma həlli.', 'Məktəb həyatı', 'orta', 'open', 70, '', NULL, '[]', NULL, '2026-09-25 20:20:00.586'),
(5, 'Məktəb tədbirlərini hamı üçün necə əlçatan edə bilərik?', 'Tədbirlər haqqında məlumat hamıya çatmır; bəzi şagirdlər üçün fiziki çıxış da çətindir. Məqsəd — məlumat və məkan baxımından əlçatanlığı artırmaq.', 'Əlçatanlıq', 'orta', 'open', 80, '', NULL, '[]', NULL, '2026-09-25 20:20:00.586')
ON DUPLICATE KEY UPDATE `title`=VALUES(`title`), `body`=VALUES(`body`), `category`=VALUES(`category`), `difficulty`=VALUES(`difficulty`), `status`=VALUES(`status`), `points`=VALUES(`points`), `created_by`=VALUES(`created_by`), `deadline`=VALUES(`deadline`), `solved_by`=VALUES(`solved_by`), `solved_at`=VALUES(`solved_at`), `created_at`=VALUES(`created_at`);

INSERT INTO `ss_rewards` (`id`, `code`, `name`, `description`, `icon`, `cost`, `kind`, `stock`, `active`, `sort_order`) VALUES
(1, 'badge_innovator', 'İnnovator nişanı', 'Profilində görünən xüsusi nişan.', '🎖️', 150, 'badge', NULL, 1, 1),
(2, 'theme_aurora', 'Aurora teması', 'Profil üçün xüsusi rəng teması.', '🎨', 250, 'theme', NULL, 1, 2),
(3, 'booster_xp', 'XP Booster (7 gün)', 'Bir həftə ərzində oyunlardan 1.5× XP.', '⚡', 300, 'booster', NULL, 1, 3),
(4, 'rank_pioneer', 'Pioner rütbəsi', 'Liderbordda xüsusi rütbə adı.', '🏅', 400, 'rank', NULL, 1, 4),
(5, 'pass_challenge', 'Challenge Pass', 'Növbəti beynəlxalq çağırışa prioritet qeydiyyat.', '🎫', 350, 'pass', NULL, 1, 5),
(6, 'badge_founder', 'Founder nişanı', 'Startap quranlar üçün xüsusi nişan.', '🚀', 500, 'badge', NULL, 1, 6),
(7, 'frame_exclusive', 'Eksklüziv avatar çərçivəsi', 'Profil şəklinə xüsusi çərçivə.', '🖼️', 600, 'frame', NULL, 1, 7)
ON DUPLICATE KEY UPDATE `code`=VALUES(`code`), `name`=VALUES(`name`), `description`=VALUES(`description`), `icon`=VALUES(`icon`), `cost`=VALUES(`cost`), `kind`=VALUES(`kind`), `stock`=VALUES(`stock`), `active`=VALUES(`active`), `sort_order`=VALUES(`sort_order`);

INSERT INTO `ss_schools` (`id`, `name`, `country`, `country_code`, `city`, `lat`, `lng`, `student_count`, `status`, `website`, `note`, `is_home`, `created_at`) VALUES
(1, 'R. İmanov adına 205 nömrəli tam orta məktəb', 'Azərbaycan', 'AZ', 'Bakı, Binəqədi', 40.43, 49.826, 780, 'connected', '', 'Ekosistemin mərkəzi', 1, '2026-09-25 20:20:00.574'),
(2, 'Ankara Fen Lisesi', 'Türkiyə', 'TR', 'Ankara', 39.933, 32.859, 640, 'connected', '', 'STEM yönümlü lisey', 0, '2026-09-25 20:20:00.574'),
(3, 'Tbilisi Public School №1', 'Gürcüstan', 'GE', 'Tbilisi', 41.716, 44.783, 520, 'connected', '', 'Regional tərəfdaş', 0, '2026-09-25 20:20:00.574'),
(4, 'Astana IT Lyceum', 'Qazaxıstan', 'KZ', 'Astana', 51.169, 71.449, 700, 'pending', '', 'Kodlaşdırma çağırışları', 0, '2026-09-25 20:20:00.574'),
(5, 'Tallinn Innovation School', 'Estoniya', 'EE', 'Tallinn', 59.437, 24.754, 430, 'pending', '', 'Rəqəmsal təhsil təcrübəsi', 0, '2026-09-25 20:20:00.574'),
(6, 'Kyoto Global Academy', 'Yaponiya', 'JP', 'Kyoto', 35.011, 135.768, 610, 'invited', '', 'Mədəni mübadilə', 0, '2026-09-25 20:20:00.574'),
(7, 'Nairobi STEM Academy', 'Keniya', 'KE', 'Nairobi', -1.286, 36.817, 480, 'invited', '', 'Təmiz su layihəsi', 0, '2026-09-25 20:20:00.574'),
(8, 'Lisboa Escola Futuro', 'Portuqaliya', 'PT', 'Lissabon', 38.722, -9.139, 550, 'invited', '', 'Dayanıqlılıq çağırışı', 0, '2026-09-25 20:20:00.574')
ON DUPLICATE KEY UPDATE `name`=VALUES(`name`), `country`=VALUES(`country`), `country_code`=VALUES(`country_code`), `city`=VALUES(`city`), `lat`=VALUES(`lat`), `lng`=VALUES(`lng`), `student_count`=VALUES(`student_count`), `status`=VALUES(`status`), `website`=VALUES(`website`), `note`=VALUES(`note`), `is_home`=VALUES(`is_home`), `created_at`=VALUES(`created_at`);

SET FOREIGN_KEY_CHECKS = 1;
