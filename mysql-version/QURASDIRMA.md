# SözLab — MySQL + Node.js versiyası: cPanel-də quraşdırma

Bu qovluq SözLab-ın **öz hostinqinizdə** (cPanel) işləyən versiyasıdır. Supabase lazım deyil:
məlumatlar hostinqin MySQL bazasında saxlanılır, sayt və server eyni ünvandadır.

Hazırkı Supabase versiyası (sozlab205.vercel.app) **toxunulmadan** işləməyə davam edir.
Hər iki versiya eyni `index.html`-dən qurulur.

```
mysql-version/
├── sozlab-server.zip      ← hostinqə YÜKLƏNƏN budur (server + sayt faylları)
├── sozlab-server/         ← zip-in açılmış halı (baxmaq/dəyişmək üçün)
│   ├── app.js             ← başlanğıc faylı
│   ├── lib/               ← giriş, təhlükəsizlik qaydaları, sorğular, server funksiyaları
│   ├── public/            ← saytın özü (index.html, şəkillər, data)
│   ├── package.json
│   └── .env.example       ← ayar nümunəsi
├── database/
│   ├── 01_schema.sql      ← cədvəllər (əvvəl bu)
│   └── 02_seed.sql        ← başlanğıc məzmun (sonra bu)
├── client/, build_public.py   ← sayt dəyişəndə MySQL versiyasını yenidən qurmaq üçün
└── QURASDIRMA.md          ← bu fayl
```

---

## 1. Hostinq tələbləri

- cPanel-də **"Setup Node.js App"** bölməsi olmalıdır (CloudLinux Node.js Selector). Node **18 və ya yeni**.
- **MySQL 8.0+** və ya **MariaDB 10.5+** (phpMyAdmin-də "Server version" yazır).
- Saxlanan funksiya, trigger, view yoxdur — SUPER hüququ lazım deyil, adi paylaşımlı hostinq kifayətdir.

## 2. Verilənlər bazasını yaradın (MySQL Database Wizard)

1. cPanel → **MySQL Database Wizard**.
2. **Step 1:** bazanın adı, məs. `sozlab` → cPanel onu `hesabadi_sozlab` edəcək. Tam adı yazın.
3. **Step 2:** istifadəçi, məs. `sozuser` → `hesabadi_sozuser`. **Password Generator** ilə güclü şifrə yaradın və yadda saxlayın.
4. **Step 3:** **ALL PRIVILEGES** işarələyin → Next.

## 3. Cədvəlləri import edin (phpMyAdmin)

1. cPanel → **phpMyAdmin** → soldan `hesabadi_sozlab` bazasını seçin.
2. **Import** → `database/01_schema.sql` → **Go**. 43 cədvəl yaranmalıdır.
3. Yenə **Import** → `database/02_seed.sql` → **Go** (məktəb məlumatları, müəllimlər, xəbərlər, 205 ekosistemi, mükafatlar).

> Sıra vacibdir: əvvəl 01, sonra 02. Xəta çıxsa, bazanı boşaldıb (Operations → Drop) yenidən başlayın.

## 4. Server fayllarını yükləyin

1. cPanel → **File Manager** → ev qovluğunuzda (`/home/hesabadi/`) — **public_html-in İÇİNDƏ YOX** — yeni qovluq: `sozlab-server`.
2. Həmin qovluğa `sozlab-server.zip` yükləyin → sağ klik → **Extract**.
   İçində `app.js`, `lib/`, `public/`, `package.json` görünməlidir (əlavə alt qovluq olmamalıdır).

## 5. Node.js tətbiqini yaradın (Setup Node.js App)

1. cPanel → **Setup Node.js App** → **Create Application**.
2. Doldurun:
   - **Node.js version:** 18 və ya ən yeni
   - **Application mode:** Production
   - **Application root:** `sozlab-server`
   - **Application URL:** saytınızın domeni (məs. `sozlab.az`)
   - **Application startup file:** `app.js`
3. **Environment variables** bölməsinə əlavə edin (**Add Variable**):

   | Ad | Dəyər |
   |---|---|
   | `DB_HOST` | `localhost` |
   | `DB_NAME` | `hesabadi_sozlab` |
   | `DB_USER` | `hesabadi_sozuser` |
   | `DB_PASSWORD` | 2-ci addımdakı şifrə |
   | `EMAIL_CONFIRM` | `off` |

4. **Create** → sonra səhifədə **Run NPM Install** düyməsi → bitəndə **Restart**.

## 6. Yoxlayın

- `https://domeniniz/api/health` açın → `{"ok":true,"db":"connected"}` görünməlidir.
  - `Cədvəllər yoxdur` → 3-cü addım edilməyib.
  - `Bazaya qoşulmaq alınmadı (ER_ACCESS_DENIED_ERROR)` → DB_USER / DB_PASSWORD səhvdir və ya 2-ci addımda hüquq verilməyib.
- `https://domeniniz/` → sayt açılır. **Qeydiyyat** edin — dərhal daxil olursunuz.

## 7. Özünüzü admin edin

phpMyAdmin → bazanı seçin → **SQL** → (istifadəçi adınızı yazın) → **Go**:

```sql
UPDATE profiles SET role = 'admin' WHERE username = 'kamal';
```

Sonra saytda çıxıb yenidən daxil olun — Admin paneli görünəcək.
Direktor üçün `'director'`, müəllim üçün `role = 'teacher', teacher_class = '10B'`.

---

## E-poçt təsdiqi (istəyə bağlı)

Default olaraq **söndürülüb** (`EMAIL_CONFIRM=off`): şagird qeydiyyatdan keçən kimi daxil olur.
Qeydiyyatda e-poçt kodu istəyirsinizsə:

1. cPanel → **Email Accounts** → məs. `noreply@domeniniz` yaradın.
2. Node.js tətbiqinin dəyişənlərinə əlavə edin:
   `EMAIL_CONFIRM=on`, `SMTP_HOST=mail.domeniniz`, `SMTP_PORT=465`, `SMTP_USER=noreply@domeniniz`,
   `SMTP_PASS=(poçt şifrəsi)`, `SMTP_FROM=noreply@domeniniz`
3. **Restart**. Kod 6 rəqəmlidir, 15 dəqiqə etibarlıdır, 5 yanlış cəhddən sonra yenisi istənilir.

SMTP qurulanda **«Şifrəni unutmusan?»** də işləyir: e-poçta 6 rəqəmli bərpa kodu gedir. SMTP yoxdursa, şagirdə bunu sinif rəhbərinə/adminə bildirməsi yazılır.

Hostinqin öz poçtu işlədiyi üçün Supabase-dəki "kod gəlmir / saatda 2 məktub" limiti yoxdur.

## Digər ayarlar

| Dəyişən | Default | Nə edir |
|---|---|---|
| `MAX_UPLOAD_MB` | 8 | Şəkil ölçüsü üst həddi (dərs şəkli 8 MB, məktəb yükləməsi 5 MB) |
| `SESSION_DAYS` | 30 | Neçə gün daxil olmuş qalır |
| `DB_POOL` | 8 | Eyni anda baza bağlantısı sayı |

Yüklənən şəkillər `sozlab-server/uploads/` qovluğunda saxlanılır — ehtiyat nüsxəyə daxil edin.

## Ehtiyat nüsxə

- **Baza:** phpMyAdmin → bazanı seçin → **Export** → Quick → SQL → Go. (və ya cPanel → Backup)
- **Şəkillər:** File Manager → `sozlab-server/uploads` → Compress → yükləyin.
- Admin panelindəki "Ehtiyat nüsxə" düyməsi də işləyir (JSON).

## Saytı yeniləmək

Əsas `index.html` dəyişəndə MySQL versiyası üçün yenidən qurun:

```bash
cd mysql-version
SITE_URL=https://domeniniz python3 build_public.py      # ../index.html-dən qurur
```

Sonra yalnız `sozlab-server/public/` qovluğunu hostinqdə əvəz edin və **Restart** edin.
`SITE_URL` göstərilsə, söz kartlarında və SEO-da sayt ünvanı sizin domen olur.

---

## Təhlükəsizlik — nə dəyişdi

Supabase versiyasındakı bütün qaydalar (kim nəyi görür/dəyişir) serverə köçürülüb və əlavə olaraq:

- Şifrələr **scrypt** ilə, sessiya açarları bazada yalnız **hash** kimi saxlanılır.
- Şagird özünə **205 Points** yaza bilməz (yalnız startap qurmaq və olimpiada nəticəsi — hərəsi bir dəfə); heyət istənilən xalı verir.
- Şagird öz işini "təsdiqlənmiş" göndərə, startapına səs, layihəsinə Humanity Points yaza bilməz.
- Başqasının XP jurnalına yazmaq, başqasının profilini dəyişmək/silmək mümkün deyil.
- Şəkil yükləmədə faylın özünə baxılır: yalnız PNG/JPG/GIF/WEBP (SVG/HTML qəbul edilmir).
- Bir hesaba 10 yanlış şifrədən sonra 10 dəqiqəlik kilid; bütün sinif eyni IP-dən rahat girə bilir.
- `.env`, server kodu və baza faylları brauzerdən açılmır.

## Problemlər

| Əlamət | Səbəb / həll |
|---|---|
| Sayt açılır, amma "Bağlantı problemi" | `/api/health`-ə baxın (6-cı addım) |
| 503 / "Web application could not be started" | Setup Node.js App → **Restart**; Node versiyası ≥ 18; `app.js` startup file-dır |
| Qeydiyyat: "Error sending confirmation email" | `EMAIL_CONFIRM=on`, amma SMTP ayarı səhvdir — ya düzəldin, ya `off` edin |
| Şəkil yüklənmir | `uploads/` qovluğuna yazma icazəsi (File Manager → Permissions 755) |
| Köhnə görünüş qalır | Brauzerdə Ctrl+F5 (service worker yeni versiyanı növbəti açılışda götürür) |
