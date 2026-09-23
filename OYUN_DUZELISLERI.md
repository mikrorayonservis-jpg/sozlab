# Oyun düzəlişləri — nə səhv idi, nə edildi

Şikayət olunan 8 oyun: **Mənası Nədir?, Sinonim Tap, Söz Zənciri, Hərf Şorbası,
Hərf Tetrisi, Səhv Avçısı, İmtahan Simulyasiyası, Bilik Yarışı**
(+ eyni datadan işlədiyi üçün **Antonim Tap** və **Boşluğu Doldur** da daxil).

Aşağıdakıların hamısı kodda yoxlanılıb və avtomatik testlə təsdiqlənib:
`.tests/games.mjs` — **43 test, 0 xəta**, `.tests/smoke.mjs` — 12 bölmə + 21 oyun, 0 konsol xətası.

---

## 1. Ən ağır qüsur: oyunlar səhv şeyi öyrədirdi

### Səhv Avçısı real sözləri "səhv" sayırdı

Köhnə siyahıda bu cütlər var idi:

| "Düzgün" | "Səhv" sayılan | Həqiqət |
|---|---|---|
| od | **ot** | *ot* — bitki. Tamamilə düzgün sözdür. |
| bağ | **bax** | *bax* — feilin əmr forması. |
| baş | **bas** | *bas* — feilin əmr forması. |
| saat | **sait** | *sait* — dilçilik termini. |
| arı | **ari** | *ari* — lüğətdə var. |
| at | **ot** | eyni "ot" ikinci dəfə. |

Şagird "ot" sözünü səhv sayıb klikləyirdi və oyun ona **"düzgün!"** deyirdi.

**İndi:** bütün 107 cüt 81.932 sözlük orfoqrafiya siyahısı ilə yoxlanılıb —
heç bir "səhv" forma real söz deyil. Siyahı 56 → 107 cütə çıxarılıb və
7 orfoqrafiya qaydası üzrə qruplaşdırılıb (ə/e, söz sonunda q→x, karlaşma,
qoşa samit, sait səhvləri, danışıq dili, alınma sözlər).

### Səhv Avçısında cavab rənglə verilirdi

Səhv yazılmış söz **qırmızı fonda** göstərilirdi. Yəni sözü oxumağa ehtiyac
yox idi — rəngə baxıb klikləmək kifayət idi. İndi bütün sözlər eyni görünür.

### Hərf Şorbasında olmayan sözlər "düzgün" idi

Əl ilə yazılmış siyahıda bunlar var idi: `alam, taş, lər, güls, niz, məş,
əba, ray, luz, azu, sözdük, lük, çiçəkb, bəki, sane, inas, nəsi, vətn, nəst`.
Bunların çoxu Azərbaycan dilində mövcud deyil.

**İndi:** əl siyahısı tamamilə ləğv edilib. Düzgün sözlər oyun başlayanda
real lüğətdən hesablanır (`word_pool.json` + `CHAIN_WORDS` + SözLab lüğəti
= 75.000+ söz). Uydurma söz qəbul etmək artıq mümkün deyil.

### Sinonim/Antonim datası səhv idi

`kəlan` (böyük), `uzunluqlu`/`dartımlı` (uzun), `gecikmə` (gec — başqa nitq
hissəsi), `sevecən` (türkcə), `novator` (adam bildirir), `həmkar` (dost yox,
iş yoldaşı), `sessiz` (orfoqrafiya səhvi — `səssiz` olmalıdır).
Hamısı düzəldilib, siyahı **20 → 48 sözə** genişləndirilib.

---

## 2. Cavabsız suallar

### İki variantın mənası eyni olurdu

**Mənası Nədir?** yanlış variantları `shuffle(WORDS).slice(0,3)` ilə seçirdi.
Lüğətdə 3.636 söz var və çoxu yaxın mənalıdır, ona görə "Gücsüz, zəif" və
"Zəif, bacarıqsız" eyni sualda görünə bilirdi.

**İndi:** variantlar məna səviyyəsində süzülür — iki variant 4 hərfdən uzun
heç bir ortaq söz daşıya bilməz.

### Sinonim sualında yanlış variant da düzgün ola bilirdi

Yanlış variantlar AZ_WORDS-un başlıq sözlərindən götürülürdü. Nəticədə
"şirin" sözünün sinonimi soruşulanda variantlar arasına "gözəl" düşürdü.

**İndi:** hər söz üçün "toxunulmaz dairə" (söz + bütün sinonimləri +
bütün antonimləri) hesablanır; yanlış variantlar yalnız bu dairə ilə
kəsişməyən qeydlərdən götürülür.

### Boşluğu Doldur suallarına birdən çox cavab uyğun gəlirdi

"Ağacdan bir _____ düşdü" sualında "quş" variantı da tam düzgün idi,
çünki yanlış variantlar digər sualların sözlərindən gəlirdi.

**İndi:** hər sualın öz yanlış variantları var — qrammatik cəhətdən oturur,
məna cəhətdən mümkün deyil.

### Bilik Yarışında cavab özünü ələ verirdi

```
S: "Vasim Məmmədəliyev hansı tarixdə anadan olub?"
C: "Vasim Məmmədəliyev 27 avqust 1942-ci ildə anadan olub."
Yanlış variantlar: "Portuqal dili…", "Kurqanların tarixi…"
```

Sualdakı adı təkrarlayan variant həmişə düzgün cavab idi — oxumağa ehtiyac yox.

**İndi iki mexanizm işləyir:**

1. **Cavab nüvəsi** — cavabın əvvəlindəki və sonundakı, sualda onsuz da olan
   sözlər atılır: yuxarıdakı nümunə `27 avqust 1942-ci ildə` şəklinə düşür.
2. **Eyni qəlibdən yanlış variant** — distraktorlar sualın qəlibinə görə
   seçilir (`anadan olub`, `harada yerləşir`, `nə qədərdir` …) və düzgün
   cavabla eyni növdə olmalıdır (hər ikisi rəqəmli və ya hər ikisi mətn),
   uzunluqları da yaxın. Nəticədə dörd variantın dördü də eyni tip faktdır.

Əlavə süzgəclər: konteksdən asılı suallar ("Açıqlamada nə deyilir?"),
vaxta bağlı suallar ("Sabah hava necə olacaq?") və bəli/xeyr sualları
artıq oyuna düşmür. Uyğun sual sayı 13.045 → 12.640 (keyfiyyətə görə).

---

## 3. Söz Zənciri

| Problem | Həll |
|---|---|
| Söz yalnız 884 sözlük `CHAIN_WORDS`-də axtarılırdı, düzgün söz "lüğətdə yoxdur" cavabı alırdı | 75.000+ sözlük real lüğət |
| Bot uyğun söz tapmayanda **istənilən** sözü deyirdi — yəni qaydanı pozurdu və oyunçu haqsız uduzurdu | Bot söz tapmasa, **oyunçu qalib gəlir** |
| 5 saniyə vaxt | 12 saniyədən başlayır, kombo artdıqca 6 saniyəyə enir |
| Uzunluq tələbi yox idi | Minimum 3 hərf; hər 4 komboda bir hərf artır (maks. 6) |
| Bütün sözlərə eyni XP | Uzun sözə çox XP (2/3/5), kombo bonusu |

## 4. Hərf Tetrisi

* Göstəriş **səhv** idi: "düşən hərflərdən söz düzəldin" yazılmışdı, halbuki
  oyun düşən **sözün eynisini** yazmağı tələb edir. Düzəldilib.
* Söz hovuzunda lüğətin **305 çoxsözlü qeydi** var idi ("bazar ertəsi",
  "təşəkkür etmək", "on bir") — onları yazmaq mümkün deyildi, oyunçu nahaq
  can itirirdi. İndi yalnız tək sözlü, 3–9 hərfli, yalnız Azərbaycan
  hərflərindən ibarət sözlər düşür.
* **Azərbaycan hərf düymələri** (ə ı ö ü ç ş ğ + ⌫) əlavə edilib — əks halda
  AZ klaviaturası olmayan kompüterdə oyun praktik olaraq oynanmırdı.
* XP iki dəfə verilirdi (həm hər sözə, həm oyun sonunda ümumi bal). Düzəldilib.
* Çətinlik: səviyyə artdıqca sözlər uzanır (≤5 → 5–7 → ≥7 hərf), sürət artır.

## 5. Çətinləşdirmə (ümumi)

| Oyun | Əvvəl | İndi |
|---|---|---|
| Mənası Nədir? | 5 sual, 4/5 keçid | 10 sual, 7/10, seriya sayğacı |
| Boşluğu Doldur | 5 sual, 20 sadə isim | 8 sual, **48 sual** (10-cu sinif səviyyəsi), ipucu çətinliyə görə azalır |
| Sinonim / Antonim | 5 sual, 3 variant | 8 sual, 4 variant, 6/8 keçid, son 3 sual çətin sözlərdən |
| İmtahan | 19 sual | 24 sual, eyni 6 dəqiqə |
| Səhv Avçısı | 3.0–5.0 s sürət | 2.2–3.8 s, kombo ilə daha sürətli; buraxılan 3 səhv söz bir can aparır |
| Hərf Şorbası | minimum 2 hərf | minimum 3 hərf, hədəf göstəricisi, uzun sözə çox XP, 2 ipucu |

Səhv edəndə indi **izah gəlir**: Səhv Avçısında orfoqrafiya qaydası,
Sinonim/Antonimdə sözün bütün sinonim və antonim sırası,
Bilik Yarışında mənbədəki tam cavab.

---

## 6. Yan tapıntı: taymerlər arxa planda işləməyə davam edirdi

Söz Zənciri, Hərf Tetrisi, Səhv Avçısı və İmtahan oyunçu başqa bölməyə
keçəndən sonra da arxa planda işləyirdi. Bir müddət sonra həmin oyun
"vaxt bitdi" ekranını artıq **tamam başqa məzmun olan** konteynerə yazırdı
(konsolda `Cannot set properties of null`).

Həlli: `gameSession` nişanı. Hər oyun başlayanda say artır; oyun öz nişanını
yadda saxlayır və hər addımda yoxlayır — nişan dəyişibsə sakitcə dayanır.
Bölmə dəyişəndə (`switchView`) və "← Geri"də nişan artırılır.

---

## Testləri işlətmək

```bash
cd sozlab
python3 -m http.server 8777 &
node .tests/data-validate.mjs     # data bütövlüyü (uydurma söz, təkrar, sızma)
node .tests/bilik-quality.mjs     # Bilik Yarışı sual keyfiyyəti
node .tests/games.mjs             # 8 oyunu avtomatik oynayır — 43 test
node .tests/smoke.mjs             # 12 bölmə + 21 oyun açılır, konsol xətası yoxlanır
```

`.testindex.html` və `.teststub/` yalnız test üçündür — sayta yüklənmir.
