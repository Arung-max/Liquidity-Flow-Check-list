# Liquidity Flow Checklist — Blueprint V1.4

> V1.0 adalah konsep & mockup ASCII. V1.1 ini mengisi setiap celah yang membuat
> V1.0 tidak bisa langsung dikodekan: ambang angka, urutan gate yang tidak
> bisa dilompati, aturan invalidasi, dan cara menyambung ke data live lewat
> `bridge.mjs`. Implementasi V1.1 ada di `liquidity-flow-checklist.html` (folder
> yang sama dengan file ini).

## 0. Apa yang diperbaiki dari V1.0

| Masalah di V1.0 | Perbaikan di V1.1 |
|---|---|
| Checklist berupa kotak centang tanpa aturan kapan boleh dicentang | Setiap centang punya rumus numerik (§4) — tidak ada yang "menurut mata" |
| Fase bisa terasa loncat (langsung ke Displacement tanpa Second Sweep) | State machine bergerbang: fase N+1 tidak bisa TRUE selama fase N belum VALID (§3) |
| "Satu candle tidak boleh menentukan keputusan" hanya jadi prinsip penutup | Dibangun ke definisi *displacement* & *sweep* itu sendiri: butuh breach **+** reclaim/kontinuasi yang tervalidasi lintas beberapa candle, bukan satu tick (§4.3, §4.7) |
| Sweep dianggap otomatis reversal | Sweep punya jalur gagal eksplisit: FAILED jika harga melanjutkan tanpa reclaim → hipotesis dibuang, dicari level baru (§4.3) |
| Tidak ada definisi "compression", "equal highs/lows", "range valid" | Dirumuskan dari lebar range & toleransi tick (§4.5) |
| Tidak jelas apa yang terjadi di aset tanpa tape volume nyata (forex/emas/indeks) | Seluruh mesin dibangun dari **struktur harga (candle)**, bukan volume asli — jadi valid di semua 12 pair; status `hasTape` hanya memengaruhi label peringatan, bukan logika (§2, §6) |
| Hanya contoh XAUUSD, pair lain tidak disebut | Roadmap pair dikunci ke daftar yang sama dengan aplikasi Order Flow Roadmap yang sudah berjalan (§1) |
| SL/TP cuma placeholder "—" | SL = di luar wick invalidasi sweep; TP = liquidity pool lawan terdekat; R:R dihitung otomatis (§4.8) |
| Tidak ada spesifikasi koneksi live | §6 — protokol persis, alamat, dan cara `bridge.mjs` dipakai tanpa diubah |

---

## 1. Roadmap Pair (dikunci ke Order Flow Roadmap yang sudah berjalan)

| Kelas | Pair | Sumber via bridge.mjs |
|---|---|---|
| Kripto | BTCUSDT, ETHUSDT, SOLUSDT | Binance (`source=binance`, tape nyata) |
| Metal | XAUUSD, XAGUSD | cTrader (`source=ctrader`, tape disimpulkan) |
| Forex | EURUSD, GBPUSD, USDJPY | cTrader (tape disimpulkan) |
| Indeks | US30, US100, US500, DAX40 | cTrader (tape disimpulkan) |

Dashboard V1.1 memantau **semua 12 pair sekaligus** dalam satu grid pemindai
(scanner), dan bisa dibuka penuh per pair untuk melihat checklist lengkap.
Menambah pair baru = menambah satu baris di `ASSETS` pada kode — tidak ada
logika lain yang perlu diubah, karena mesinnya generik per simbol.

---

## 2. Batasan data yang wajib disadari (bukan bug, sifat pasar)

- **Kripto (Binance)**: order book asli 20 level + tape transaksi asli. Semua
  perhitungan valid 100%.
- **Metal/Forex/Indeks (cTrader)**: order book Level II dari satu broker
  (bukan book pasar terpusat), **tanpa tape transaksi**. Arah "trade" di sini
  disimpulkan dari pergerakan tick (`inferred:true`). Karena mesin V1.1
  **tidak memakai volume/tape sama sekali** — hanya struktur OHLC dari harga
  — batasan ini tidak menurunkan validitas Liquidity Flow Checklist. Yang
  terdampak hanya fitur *di luar* checklist ini (bubble agresi, CVD di app
  Order Flow Roadmap yang sudah ada).
- Setiap pair menampilkan badge sumber (`LIVE cTrader:NamaBroker` /
  `LIVE Binance` / `SIMULASI`) sesuai pesan `meta`/`status` dari bridge.

---

## 3. Mesin: Gerbang Berurutan (Sequential Gate State Machine)

Setiap pair punya satu instance mesin dengan status tepat satu dari:

```
OBSERVE → DEVELOPING → WAIT → CONFIRMED
              ↓            ↓
           INVALID ←───────┘  (dari mana pun, kapan pun hipotesis gagal)
```

Gerbang (tidak bisa dilompati — fase N+1 hanya dievaluasi jika fase N berstatus VALID):

1. **Market Context** siap (bias & regime terhitung) — prasyarat, bukan gate skor.
2. **External Liquidity** teridentifikasi → kalau tidak ada, status tetap `OBSERVE`.
3. **Liquidity Approach** → `DEVELOPING`.
4. **First Sweep** = `VALID` (breach + reclaim) → lanjut. Kalau `FAILED` → cari
   level baru, kembali ke langkah 2 (tetap `DEVELOPING`, tidak `INVALID`,
   karena belum ada hipotesis entry yang dibentuk).
5. **Post-Sweep State** terklasifikasi (Ranging paling disukai) → `WAIT`.
6. **Range + Internal Liquidity** terbentuk.
7. **Second Sweep** = `CONFIRMED` (breach + reclaim + rejection wick pada
   liquidity internal).
8. **Displacement** valid.
9. **MSS/CHOCH** valid (ditembus oleh candle displacement yang sama/berturutan,
   bukan wick saja).
10. **FVG** terbentuk dan masih terbuka (belum terisi >50%).
11. **Retest** menyentuh zona MSS/FVG lalu menolak → **`CONFIRMED`**.

Kapan pun setelah langkah 4, jika harga menembus **SL invalidasi** (§4.8)
sebelum retest tercapai, mesin pindah ke `INVALID`, event dicatat di timeline,
dan pencarian level baru dimulai lagi dari langkah 2.

---

## 4. Definisi numerik setiap fase (mengisi celah V1.0)

Semua ambang di bawah dapat diubah lewat panel Pengaturan; nilai default
dipilih agar noise minor tidak lolos jadi "sinyal".

### 4.1 Timeframe & candle
- Candle dibangun **di sisi klien** dari tick harga mid `(bid+ask)/2` yang
  dikirim bridge (event `trade`), bukan dari OHLC API broker (cTrader/Binance
  lewat bridge ini tidak mengirim candle jadi).
- Dua timeframe: **M5** untuk *Market Context* (bias, regime), **M1** untuk
  mekanika liquidity/sweep/struktur (fase 2–11).

### 4.2 Market Context
- **ATR(14)** dihitung standar (true range candle M1, rata-rata 14 periode).
- **Volatilitas**: `ATR / rata-rata ATR 50 periode` → `<0.7` = RENDAH,
  `0.7–1.3` = NORMAL, `>1.3` = TINGGI.
- **Market Regime** (Efficiency Ratio Kaufman, M5, 20 periode):
  `ER = |close_sekarang − close_20_candle_lalu| / Σ|close_i − close_i-1|`.
  `ER > 0.4` → TRENDING, selain itu → RANGING.
- **M5 Bias**: dari swing point M5 (lihat §4.3) — higher-high & higher-low
  berturutan → BULLISH; lower-high & lower-low → BEARISH; campur → RANGING.
- **VWAP Sesi** (konteks tambahan, bukan gate): rata-rata harga tertimbang volume
  sejak sesi (hari) berjalan, reset tiap 24 jam, dengan pita ±1/±2 deviasi
  standar — definisi & tampilan sama persis dengan app Order Flow Roadmap.
  Ditampilkan sebagai kurva di chart plus metrik "Jarak dari VWAP" (%) berwarna
  hijau/merah tergantung harga di atas/bawah VWAP. Tidak memengaruhi status
  checklist di §3 — murni informasi tambahan untuk pembaca.
- **Zona Liquidity** (lapisan visual tambahan, bukan gate): kotak di atas/bawah
  setiap pivot high/low M1 (trailing 15-bar, deteksi terpisah dari fractal
  §4.3 — ini niru definisi pivot dari indikator Pine "Liquidity Location
  Detector [BigBeluga]" apa adanya). Tinggi kotak = setengah range candle
  pivot-nya; warna & intensitas mengikuti kekuatan volume relatif (persentil
  ke-99 dari 1000 candle terakhir) — pink pekat = sell-side liquidity (di atas
  swing high) bervolume besar, teal pekat = buy-side liquidity (di bawah
  swing low). Kotak melebar terus sampai harga menyapunya, lalu berhenti di
  situ secara permanen. Untuk pair tanpa tape asli, "volume" candle = jumlah
  tick per candle (proksi, sama seperti keterbatasan §2). Ini berbeda dari
  Liquidity Map inti di §3/§4.3 (yang jadi bagian gerbang checklist) — zona
  ini murni peta kepadatan liquidity di seluruh candle yang terlihat, tidak
  memengaruhi status akhir.

### 4.3 Swing point & External Liquidity (fractal)
- Candle `i` adalah **swing high** jika high-nya lebih tinggi dari 2 candle
  sebelum **dan** 2 candle sesudah (fractal L=2). Swing low simetris.
- **External liquidity** = swing point M5 paling ekstrem yang belum pernah
  disapu (belum ada sweep VALID di level itu) dalam lookback 50 candle M5.
  Mesin melacak **dua** level sekaligus: liquidity di atas (untuk skenario
  turun dulu baru naik dianulir) dan di bawah — mana pun yang didekati harga
  duluan yang dievaluasi.
- **Liquidity Approach**: harga bergerak ke arah level dalam jarak
  `≤ 1.5 × ATR`, dengan momentum (3 candle M1 terakhir searah level).

### 4.4 Sweep (First & Second — rumus yang sama, level berbeda)
Diberi level target `L` (external di fase pertama, internal equal-high/low di
fase kedua):
- **Breach**: high/low candle menembus `L` sejauh `≥ max(2 tick, 0.05×ATR)`.
- **Reclaim**: dalam `N candle M1` setelah breach (default `3`, **kalibratable**
  1–4 lewat panel — §8 "Reclaim"), ada **close** yang balik ke sisi dalam `L`
  → dicek dulu terhadap Sweep Depth (di bawah) sebelum jadi `VALID`.
- **Sweep Depth** *(V1.2, baru)*: kedalaman TERJAUH yang pernah dicapai sejak
  breach (bukan cuma titik breach pertama — harga bisa terus menembus lebih
  jauh sebelum akhirnya reclaim) harus berada dalam rentang
  `[min, max]` — default `0.5×ATR – 2.0×ATR`, atau mode poin harga langsung
  `1.0 – 15 poin` (kalibratable, §8). Di bawah minimum → dianggap breach
  terlalu dangkal (noise, bukan sapuan sungguhan), sapuan dianulir. Di atas
  maksimum → dianggap sudah jadi breakout (bukan sweep lagi), langsung
  `FAILED` walau belum sempat reclaim.
- **Rejection wick** (disyaratkan khusus di Second Sweep, karena ini satu-
  satunya konfirmasi yang sahih tanpa tape nyata): candle breach punya wick ke
  arah breach `≥ 50%` dari total range candle itu.
- **FAILED**: dalam jendela yang sama, harga **melanjutkan** menembus lebih
  jauh (`≥ 1×ATR` tambahan) tanpa reclaim → bukan sweep, ini breakout asli.
  Hipotesis dibuang, level target diganti ke arah breakout (kembali ke §4.3).
- **WAITING/PARTIAL**: belum breach / sudah breach tapi jendela reclaim
  belum habis.

### 4.5 Post-Sweep, Range, Compression, Internal Liquidity
- **Post-Sweep State** dievaluasi 5–8 candle M1 setelah reclaim:
  - *Ranging* (disukai): rasio overlap high/low antar candle berturutan
    `≥ 70%` selama jendela itu.
  - *Immediate Reversal*: candle displacement (§4.7) muncul langsung tanpa
    ranging dulu — jalur dipercepat, tapi retest (§4.9) tetap wajib, tidak
    ada gate yang dilompati.
  - *Continuation* → berarti sweep sebenarnya FAILED, lihat §4.4.
  - *Unclear* → tunggu, timeout 15 candle M1 tanpa kejelasan = kembali ke
    `DEVELOPING` dan cari setup baru.
- **Range valid**: dicari dengan menyisir lebar jendela `Maks..Min candle M1`
  (default `24..6`, **kalibratable** lewat panel — §8 "Range") dari yang
  **TERBESAR ke TERKECIL** (bukan kaku satu ukuran) — begitu ketemu jendela
  dengan high/low tertampung dalam pita `≤ 2.0 × ATR` (kalibratable), itu dipakai
  (jendela terbesar yang masih sah, memberi paling banyak kandidat titik
  swing utk §"Equal highs/lows" di bawah — lebar range monoton melebar
  seiring jendela membesar, jadi kalau jendela kecil sudah tidak muat,
  jendela lebih besar pasti juga tidak muat; sebaliknya tidak berlaku).
  *(V1.1.1: nilai asli 1.2×ATR dgn jendela kaku 8-candle terbukti lewat
  simulasi random-walk cuma punya ~0,3% peluang terpenuhi per langkah —
  praktis mustahil pada gerak harga sungguhan. Versi pertama perbaikan
  (2.0×ATR, cari dari jendela TERKECIL) menaikkan peluang range itu sendiri
  ke ~30%, tapi jendela kecil yang kepilih nyaris tidak pernah punya cukup
  titik swing utk "Equal highs/lows" (lihat catatan di situ) — makanya
  Second Sweep dst. tetap 0% sampai arah pencarian dibalik ke TERBESAR.)*
- **Compression** *(V1.2: sebelumnya cuma disebut di V1.0, sekarang benar-benar
  diimplementasikan)*: ATR saat ini `< X%` dari ATR pada saat fase pencarian
  range ini pertama dimulai (jangkar diambil sekali, bukan bergerak tiap
  langkah) — default `X=70` (kalibratable, bisa dimatikan, §8 "Compression").
  **Bukan gerbang wajib** — cuma tanda tambahan di checklist ("Compression
  (ATR menyempit)") yang menunjukkan tekanan menyempit sebelum ekspansi;
  tidak memblokir progres ke Second Sweep kalau tidak terpenuhi.
- **Equal highs/lows**: `≥ 2` swing point M1 dalam toleransi `≤ 0.3 × ATR`
  (atau `≤ 3 tick`, mana yang lebih besar) satu sama lain, dicari di dalam
  jendela range §4.5 di atas. Jumlah titik yang berkumpul = **Liquidity
  Density** (2 titik = LOW, 3 = MEDIUM, ≥4 = HIGH), persis visual di V1.0 §5.
  *(V1.1.1: toleransi asli 0.15×ATR, dan jendela range dulu diambil dari yg
  TERSEMPIT/paling baru yg muat di bawah ambang lebar. Kombinasi keduanya
  nyaris mustahil terpenuhi — jendela sempit (6-8 candle) rata-rata cuma
  punya <1 titik swing per tipe, jauh dari cukup utk syarat "≥2 saling
  berdekatan". Sekarang jendela range diambil dari yg TERBESAR yg masih muat
  (lihat §4.5) — memberi lebih banyak kandidat swing tanpa melonggarkan arti
  "range yang sempit" itu sendiri — plus toleransi yang dua kali lebih
  longgar.)*

### 4.6 Second Sweep
Level target = klaster equal-high/low dengan density tertinggi di dalam
range aktif. Rumus breach/reclaim/rejection identik §4.4.
**SECOND SWEEP CONFIRMED** hanya jika ketiganya (breach + reclaim + rejection
wick) terpenuhi — ini gate wajib sebelum §4.7 dievaluasi sama sekali. Kalau
breach+reclaim VALID tapi wick rejection-nya tipis, hipotesis sapuan ini
**direset** (bukan sekadar ditunda) — dicari lagi sapuan baru pada level yang
sama, bukan diam-diam lanjut ke §4.7 tanpa rejection yang sah.
*(V1.1.1: sebelumnya kode punya celah — wick tipis cuma memblokir SATU
langkah, lalu langkah berikutnya keliru melewatkan gate ini sepenuhnya krn
kondisi pemeriksaannya sendiri sudah tidak terpenuhi lagi setelah state
sempat jadi VALID. Ditemukan lewat simulasi Monte Carlo: angka "Displacement
terdeteksi" ternyata lebih tinggi dari "Second Sweep CONFIRMED" -- artinya
sebagian kasus lolos ke Displacement tanpa rejection wick yang sah. Sesudah
diperbaiki, kedua angka itu identik.)*

### 4.7 Displacement & MSS/CHOCH
- **Displacement valid** — dua mode (**kalibratable**, §8 "Displacement"):
  - Mode **Relatif ATR** (default): `|close−open| ≥ 1.5 × ATR` **dan** body-nya
    lebih besar dari candle sebelumnya.
  - Mode **Relatif median body**: `|close−open| ≥ 1.2 × median body` dari 10
    candle terakhir sebelum candle ini — berguna di sesi low-volatility di
    mana ATR global belum "sadar" sebuah gerakan sudah relatif besar.
  - Kedua mode tetap mensyaratkan close berada di 25% terluar range candle
    (searah pergerakan) — mencegah satu wick liar dibaca sebagai displacement
    (prinsip "satu candle tidak menentukan").
- **MSS/CHOCH valid** — dua mode (**kalibratable**, §8 "MSS/CHOCH"):
  - **Wajib close tembus struktur** (default, direkomendasikan): **close**
    (bukan wick) dari candle displacement menembus swing point M1 tervalidasi
    (fractal L=2) yang paling relevan ke arah hipotesis. *Wick Break ≠
    Structure Break* — wick sesaat yang langsung ditarik balik TIDAK dianggap
    tembus struktur, supaya sinyal palsu dari wick sekilas tidak lolos.
  - **Wick cukup** (opsional, lebih cepat tapi lebih rawan sinyal palsu):
    high/low candle displacement menembus swing point, close boleh balik ke
    sisi semula.
  - Gate §4.6 harus `CONFIRMED` sebelum ini dievaluasi. Kalau kandidat
    displacement yang ditemukan **tidak** berhasil menembus struktur (MSS
    gagal), mesin mencoba **kandidat displacement berikutnya** yang muncul
    kemudian — bukan berhenti selamanya di kandidat pertama.
  *(V1.1.1: sebelumnya begitu satu candle displacement "dikunci" ke state,
  MSS dicek SEKALI utk candle itu saja; kalau gagal, `findMSS` dipanggil
  ulang tiap langkah tapi dengan input yang PERSIS SAMA (titik jangkarnya
  tetap), jadi hasilnya juga akan selalu sama -- macet permanen sampai
  seluruh hipotesis di-reset dari SL invalidasi, walau ada displacement
  candle lain yang lebih baru & valid. Diperbaiki dengan kursor pencarian
  yang maju ke kandidat berikutnya tiap kali kandidat sebelumnya gagal MSS.)*

### 4.8 FVG & Risk Map
- **FVG valid**: 3 candle berurutan dengan `high(candle 1) < low(candle 3)`
  (bullish) atau `low(candle 1) > high(candle 3)` (bearish), lebar gap
  `≥ 0.2 × ATR`. FVG "terbuka" selama belum terisi `>50%` oleh harga tanpa
  pembalikan.
- **SL (invalidasi)**: wick paling ekstrem dari sweep yang memulai hipotesis
  aktif, `± buffer (0.1×ATR, min 2 tick)`.
- **TP**: external liquidity pool di sisi berlawanan (dari §4.3) yang paling
  dekat.
- **R:R** = `|TP − harga_acuan| / |harga_acuan − SL|`, harga acuan = harga
  saat retest selesai (atau harga sekarang bila masih berjalan).

### 4.9 Retest → Confirmed
- Harga balik menyentuh zona MSS atau FVG (wick atau close di dalam zona),
  lalu dalam `≤ 3 candle M1` muncul candle rejection ke arah hipotesis
  (wick berlawanan `≥ 40%` range candle).
- Begitu terpenuhi → status **`CONFIRMED`**, event dicatat, R:R final dikunci.

### 4.10 Entry Readiness (%)
Enam kategori (Liquidity, Structure, Displacement, MSS, FVG, Retest), setiap
kategori = jumlah sub-kondisi terpenuhi / total sub-kondisi kategori itu.
Ini **bukan** skor probabilitas profit — murni persentase checklist yang
sudah tercentang, sesuai penegasan V1.0 §8.

---

## 5. Status Akhir (5 status, bukan BUY/SELL)

| Status | Kondisi |
|---|---|
| 🔵 OBSERVE | External liquidity belum teridentifikasi / belum ada approach |
| 🟡 DEVELOPING | Approach berjalan → First Sweep VALID |
| 🟠 WAIT | First Sweep VALID → sebelum Retest selesai (termasuk Second Sweep, Displacement, MSS, FVG yang sudah tercentang tapi Retest belum) |
| 🟢 CONFIRMED | Semua gate §3 langkah 4–11 terpenuhi |
| 🔴 INVALID | SL invalidasi tersentuh, atau sweep FAILED tanpa hipotesis baru, atau timeout — dicatat di timeline lalu mesin reset ke OBSERVE |

Aturan tetap dari V1.0 §13 dipegang ketat: **tidak ada status yang naik dari
satu candle saja** — setiap kenaikan gate mensyaratkan kombinasi breach+reclaim
atau displacement+MSS yang sudah didefinisikan lintas beberapa candle di §4.

---

## 6. Live: langsung ke Binance (kripto) + `bridge.mjs` (selain kripto)

Dua jalur data berbeda, dipilih otomatis dari `asset.cls`:

- **Kripto (BTCUSDT, ETHUSDT, SOLUSDT)** — connect **langsung dari browser** ke
  Binance (`wss://stream.binance.com:9443/stream?streams=...@depth20@100ms/...@aggTrade`),
  **tanpa lewat bridge sama sekali**. Binance publik & ramah WS langsung dari
  browser, jadi tidak butuh perantara — persis seperti app Order Flow Roadmap.
  Menjalankannya lewat bridge cuma menambah hop yang bisa bikin lambat/gagal
  kalau bridge sedang sibuk dengan koneksi lain, padahal tidak perlu.
- **Metal/Forex/Indeks (9 pair sisanya)** — wajib lewat `bridge.mjs` (tidak ada
  perubahan pada file bridge), karena cTrader tidak bisa diakses langsung dari
  browser:
  ```
  ws://localhost:8787?symbol=XAUUSD                (source=auto → cTrader)
  ws://localhost:8787?symbol=XAUUSD&source=mock     (untuk uji coba tanpa akun broker)
  ```
  Pesan yang dikonsumsi (format persis dari `bridge.mjs`):
  ```json
  {"type":"meta","symbol":"XAUUSD","source":"ctrader:NamaBroker","digits":2,"tickSize":0.01,"hasTape":false}
  {"type":"trade","ts":1723459200000,"price":2382.28,"size":1,"side":"buy","inferred":true}
  {"type":"status","state":"live","message":"..."}
  ```

`liquidity-flow-checklist.html` membuka **12 koneksi** (3 langsung ke Binance,
9 lewat bridge), membangun candle M1/M5 dari setiap tick, dan menjalankan satu
instance mesin §3 per pair — semuanya berjalan paralel di scanner grid.

Cara pakai:
1. Jalankan bridge seperti biasa (`node bridge.mjs`, atau lewat
   `bridge-launcher.ps1` di proyek "Order Flow Bridge" — file itu sengaja
   tidak ikut di repo ini, lihat README).
2. Buka `liquidity-flow-checklist.html` di browser — kripto langsung jalan
   walau bridge belum menyala; 9 pair sisanya otomatis mencoba menyambung ke
   `ws://localhost:8787`.
3. Pair yang simbolnya belum ada di broker Anda (lihat catatan alias di
   `bridge.mjs`) akan menunjukkan status error per pair, tanpa mengganggu
   pair lain.

### 6.1 Backfill candle historis (kripto)

Begitu tersambung, kripto langsung menarik **histori candle nyata** lewat REST
publik Binance (`GET /api/v3/klines`, tanpa API key) — ±3 jam M1 dan ±16 jam M5
— dan menyuntikkannya ke aggregator sebelum tick live pertama datang. Efeknya:
ATR, bias, dan liquidity map langsung terisi begitu tersambung, tidak perlu
menunggu candle terbentuk dari nol. Candle historis tidak pernah menimpa candle
yang sudah terbentuk dari tick live (dicek per-timestamp) dan candle terakhir
dari REST (yang belum tentu closed) selalu dibuang, biar tick live yang
melanjutkan candle itu sendiri.

### 6.2 Backfill candle historis (Metal/Forex/Indeks — `bridge.mjs` diperluas)

`bridge.mjs` sekarang juga mengirim histori lewat trendbar cTrader
(`ProtoOAGetTrendbarsReq`/`Res`, payload type 2137/2138). Begitu simbol
resolve, bridge otomatis meminta ±180 bar M1 dan ±200 bar M5 (tanpa diminta
klien — murni tambahan di jalur yang sudah ada, tidak ada pesan baru dari
klien ke bridge) dan meneruskannya sebagai:
```json
{"type":"history","symbol":"XAUUSD","period":"M1","candles":[{"t":..,"o":..,"h":..,"l":..,"c":..,"v":..}]}
```
Trendbar cTrader dikodekan sebagai `low` + delta (`deltaOpen/deltaHigh/deltaClose`,
semua berskala `PRICE_DIV=100000` sama seperti kuotasi spot) dan timestamp
dalam **menit** (`utcTimestampInMinutes`) — bridge yang mengonversi ke bentuk
candle biasa sebelum diteruskan.

Ini fitur pelengkap, sengaja **tanpa** `waitFor`/timeout: kalau broker tidak
menjawab atau format request meleset, jalur live (spot+depth) tetap jalan
normal — `ERROR_RES` hanya dianggap gagal-histori (bukan mematikan status
LIVE) selama masih ada permintaan histori yang menunggu balasan.

Kedua period (M1, M5) diminta **satu per satu** (M5 baru dikirim setelah
balasan M1 diterima/gagal), bukan sekaligus — cTrader terbukti **tidak**
menjamin urutan balasan sama dengan urutan permintaan kalau dua
`GetTrendbarsReq` dikirim beruntun tanpa menunggu (ditemukan lewat pengujian
sungguhan: balasan M5 datang lebih dulu padahal M1 diminta duluan, sehingga
kalau dipasangkan lewat antrean FIFO datanya salah label — M1 dan M5 tertukar).
Dengan cuma satu request "in-flight" per adapter, balasan yang datang dijamin
milik request yang sedang ditunggu, tidak ada lagi ambiguitas.

**Sudah diuji end-to-end dua kali:** lewat `mock-ctrader.mjs` (server broker
tiruan, trendbar sintetis) dan **lewat server cTrader demo sungguhan**
(akun Spotware demo asli) — 8 dari 9 pair (semua kecuali satu kasus timeout
depth-of-market yang tidak terkait histori) berhasil LIVE + menerima histori
M1 180 candle & M5 200 candle dengan benar, nol `ERROR_RES`. Nama field
trendbar (`low`, `deltaOpen/High/Close`, `utcTimestampInMinutes`, `volume`)
dan format `period` sebagai string ("M1"/"M5") terbukti benar sesuai
dokumentasi resmi cTrader.

### 6.3 Interaksi chart: zoom & geser (pan)

Chart tidak lagi terkunci ke "90 candle terakhir" — lebar candle tidak pernah
menumpuk/mengecil tanpa batas karena jendela yang tampak selalu dibatasi
`chartView.count` (default 90), tapi sekarang jendela itu bisa digeser:

- **Scroll** di atas chart = zoom in/out (`chartView.count` mengecil/membesar,
  dibatasi 15–1500 candle atau sebanyak yang tersedia).
- **Klik + tahan + tarik** = geser ke histori lama. Begitu digeser,
  `chartView.follow` jadi `false` dan jendela terkunci pada posisi absolut itu
  — candle baru yang terus masuk lewat tick live TIDAK memaksa geser balik
  (supaya tidak mengganggu saat sedang meninjau histori). Tombol
  **"▶ Kembali ke Live"** muncul otomatis di judul chart selama tidak
  mengikuti live; klik dua kali di chart juga langsung kembali ke live.
- Tiap pair (di `APP[sym].chartView`) punya jendela sendiri-sendiri —
  pindah pair lalu kembali tidak mereset posisi geser/zoom pair sebelumnya.

Catatan implementasi: elemen `<canvas id="chart">` diganti (innerHTML) tiap
render (~1x/detik), jadi listener `mousemove`/`mouseup` untuk drag sengaja
dipasang **sekali** di level `window` saat bootstrap (bukan per-canvas) —
kalau dipasang per-canvas, listener lama menumpuk tiap render karena canvas
lamanya dibuang tapi listeker globalnya tidak pernah lepas.

### 6.4 Replay histori ke mesin checklist — bukan cuma ke chart

Backfill (§6.1/§6.2) awalnya cuma mengisi **candle di chart**; mesin checklist
(§3) sendiri tetap buta terhadap apa yang terjadi sebelum app dibuka, karena
`stepEngine` didesain menganalisis **satu candle BARU** setiap dipanggil —
kalau langsung diberi array 180 candle sekaligus lalu dipanggil sekali, ia
cuma melihat kondisi candle TERAKHIR, seolah 179 candle sebelumnya tidak
pernah terjadi. Akibatnya status selalu mulai dari OBSERVE walau chart-nya
sudah penuh histori — persis pertanyaan "sekarang market di posisi apa"
tidak terjawab, cuma "grafiknya sudah ada" yang terjawab.

Diperbaiki lewat `replayHistory(app)`: begitu histori (kripto maupun
cTrader) selesai di-seed ke aggregator, seluruh candle-nya **diputar ulang
satu per satu** lewat `stepEngine` yang sama persis dipakai candle live —
`engine` dibuang & dibangun ulang dari nol (`newEngineState`), lalu untuk
tiap index candle `i`, `stepEngine` dipanggil dengan potongan array
`m1[0..i]` dan `m5` yang sudah closed sampai waktu itu (bukan cuma
candle terakhir). Hasilnya: begitu backfill selesai, status/checklist/
timeline/SL-TP langsung mencerminkan alur ASLI dari histori sampai
sekarang — termasuk kalau sebuah hipotesis sempat CONFIRMED lalu ter-INVALID
lagi, sweep gagal berkali-kali sebelum akhirnya valid, dst. — bukan cuma
snapshot sesaat.

Biaya komputasi diabaikan (replay ~180-200 candle × 12 pair, tiap langkah
O(panjang-potongan) yang murah — total masih di bawah beberapa milidetik).

**Dibuktikan lewat pengujian**: skenario sintetis yang SAMA (lihat §3)
dipanggil dua cara — sekali dengan array penuh (perilaku lama, hasil:
macet di `DEVELOPING`, sama sekali tidak mendeteksi bahwa CONFIRMED
sebenarnya sudah terjadi) vs. diputar satu-per-satu (perilaku baru, hasil:
`CONFIRMED` dengan timeline lengkap 8 event, SL/TP terisi benar). Juga
diverifikasi langsung ke data live sungguhan: US500 langsung berstatus
`WAIT` (bukan `OBSERVE`) dalam hitungan detik setelah tersambung, dengan
Market Timeline menunjukkan beberapa siklus sweep gagal/invalid sebelum
sweep yang valid — persis riwayat yang sesungguhnya terjadi di histori.

---

## 7. Yang sengaja belum dikerjakan di V1.1

- Multi-timeframe confluence di luar M1/M5 (H1 bias, dst.) — bisa ditambah
  sebagai filter tambahan, tidak mengubah gate inti.
- Liquidity Density dari order book L2 (bukan hanya swing point harga) —
  akan menambah akurasi untuk kripto (yang punya book asli), tapi bukan
  syarat karena mesin ini dirancang generik lintas 12 pair.
- Alert suara/notifikasi push saat status naik ke WAIT/CONFIRMED.

## 8. Panel Kalibrasi (V1.2, baru)

Tombol **"⚙ Kalibrasi"** di topbar membuka panel yang mengubah parameter
mesin **tanpa perlu edit kode**. Ini melengkapi janji di §4 ("Semua ambang di
bawah dapat diubah lewat panel Pengaturan") yang sebelumnya baru berupa
komentar di kode, belum ada UI-nya.

**Enam grup parameter** (nilai default = angka yang dipakai di seluruh §4 di
atas):

| Grup | Field | Default |
|---|---|---|
| Sweep Depth | Mode | Relatif ATR |
| | Minimum / Maksimum (× ATR) | 0.5 / 2.0 |
| | Minimum / Maksimum (poin harga) | 1.0 / 15 |
| Reclaim | Maksimum candle | 3 (pilihan 1–4) |
| Range | Minimum / Maksimum candle | 6 / 24 |
| | Lebar maksimum (× ATR) | 2.0 |
| Compression | Aktifkan | ya |
| | ATR sekarang < X% ATR sebelumnya | 70 |
| Displacement | Mode | Relatif ATR |
| | Badan ≥ (× ATR atau × median body) | 1.5 / 1.2 |
| MSS / CHOCH | Wajib close tembus struktur | ya (Wick Break ≠ Structure Break) |

**Cara kerja**:
- Perubahan di form ditampung di draft terpisah — belum berlaku ke mesin
  sampai **"Terapkan & Hitung Ulang Semua"** ditekan. Menutup panel tanpa
  menekan tombol itu = batal, tidak ada efek.
- Toggle mode (Sweep Depth ATR/Poin, Displacement ATR/Median Body) langsung
  menukar field yang relevan di form (field yang tidak relevan disembunyikan).
- Begitu "Terapkan" ditekan: nilai disimpan ke `localStorage` (bertahan lintas
  buka-tutup browser), lalu **seluruh histori tiap pair yang sudah masuk
  di-replay ulang** dari awal lewat `stepEngine` yang sama persis (mekanisme
  yang sama dengan backfill historis di §6.4) — supaya kalibrasi baru
  langsung tercermin di status/timeline/checklist saat ini, bukan cuma
  berlaku ke candle baru ke depan.
- **"Kembalikan ke Default"** mengisi ulang form ke nilai pabrik (tabel di
  atas); masih perlu "Terapkan" untuk benar-benar berlaku.

**Catatan desain**: Sweep Depth (min & max) diterapkan ke kedua sapuan
(First **dan** Second Sweep — §4.4 pakai rumus yang sama untuk keduanya).
Reclaim, Range, dan Compression secara alami hanya relevan untuk fase
tertentu (First Sweep, pembentukan range, dan indikator pasca-range).

## 9. Perbaikan Bug Kritis V1.2.1

Tinjauan multi-agen (audit kode + backtest 59 hari data M1 Binance vs kontrol
random-walk) menemukan mesin **belum layak jadi acuan scalping** dalam bentuk
V1.2 — sinyal CONFIRMED tidak lebih baik dari kontrol acak, R:R median <0.5.
Bug-bug berikut sudah diperbaiki (cari komentar `V1.2.1` di kode untuk detail
& alasan tiap fix):

- **Arah Second Sweep dibalik ke SISI YANG SAMA dengan first sweep**
  (inducement), bukan sisi berlawanan seperti sebelumnya — ini yang paling
  kritis; logika lama kontradiktif (menuntut rejection kontra-tesis yang
  harus gagal sendiri sebelum tesis bisa lanjut). §4.6 sudah diperbarui.
- **WAITING tidak lagi terkunci selamanya** — dulu bisa macet ribuan candle
  (85-97% waktu di backtest) tanpa kedaluwarsa. Sekarang dibatalkan begitu
  harga >3×ATR menjauh tanpa breach, plus cooldown 30 menit untuk level yang
  baru gagal via breakout (`invalidLevel`, anti pola sama terbaca ulang).
- **Hipotesis (WAIT) kedaluwarsa per-fase** (60 menit/fase, jangkar digeser
  tiap fase maju: internal-liquidity-found → second-sweep-confirmed →
  MSS-confirmed) — dulu tidak ada batas sama sekali.
- **SL diperketat baru saat MSS terkonfirmasi** (bukan langsung saat first
  sweep valid) — dulu R:R median saat CONFIRMED cuma ~0.2-0.5 karena SL
  dijangkar terlalu dini. TP disegarkan dari liquidity eksternal terkini.
- **R:R dihitung terarah** (negatif kalau TP ternyata di sisi salah) + gerbang
  `minRR=1.0` sebelum status boleh CONFIRMED.
- **FVG**: pencarian dibatasi 15 candle dari MSS, retest tidak lagi bisa
  terpicu oleh candle FVG itu sendiri, kursor `fvgSearchFrom` mencegah
  menemukan-ulang gap yang sama tanpa akhir.
- **CONFIRMED tidak lagi membeku selamanya** — dilacak sampai TP/SL/time-stop
  (`tradeMaxAgeMinutes=240`) lalu direset ke OBSERVE (siklus hidup trade).
- **External liquidity** memilih fractal PALING EKSTREM yang belum tersapu
  (`sweptExternal`), bukan cuma fractal terakhir, ditambah syarat momentum
  approach yang disebut §4.3 tapi dulu belum diimplementasikan.
- Bug kecil lain: candle dobel di jalur live, lookahead M5 saat replay,
  off-by-one kursor MSS, ATR-at-candle-time anti-repaint untuk
  displacement/FVG, `wickRatio` second sweep pakai nilai terbesar antara
  breach & reclaim.

**Hasil verifikasi**: WAITING-lock turun dari 85-97% jadi ~5-6% waktu,
pipeline bisa mencapai retest (BTC 7/8 second-sweep-confirmed mencapai MSS,
vs 1/8 sebelum fix), R:R sinyal yang lolos jadi wajar (median dulu ~0.2-0.5,
sekarang mis. 1.09-2.58). Frekuensi sinyal makin RENDAH (disengaja, krn
sekarang lebih ketat) — sampel yang tersedia masih terlalu kecil untuk
mengklaim ada/tidaknya edge; itu di luar cakupan perbaikan ini (bugfix,
bukan pembuktian profitabilitas).

**Yang sengaja belum disentuh** (supaya tetap "bugfix", bukan redesign V2):
`classifyPostSweep` masih longgar (gate post-sweep nyaris no-op), tidak ada
filter sesi/killzone/berita/spread, bias/regime/VWAP masih kosmetik (§4.2),
mode "points" sweep depth masih global per-instrumen, validasi input panel
kalibrasi masih longgar.

## 10. Panel Analisis Pasar & Dukungan Keputusan (V1.3, baru)

Tombol **"📊 Analisis Pasar"** di topbar (sebelah "⚙ Kalibrasi") membuka
modal lebar 4-tab yang menjawab empat kebutuhan yang sebelumnya tidak
terlayani: melihat kondisi pasar lintas pair, menguji hipotesis atas histori
yang sudah ada, melihat DAMPAK kuantitatif dari perubahan kalibrasi (bukan
cuma mengubah ambang tanpa tahu efeknya), dan mempelajari hasil trade dari
waktu ke waktu. Semuanya **murni observasional** — membaca/mensimulasikan
ulang state mesin yang sudah ada tanpa mengubah gerbang/logika inti.

**Prasyarat mesin** (dikerjakan sekali, dipakai ke-4 tab): `stepEngine`
menerima parameter opsional ke-5 `hook` dan ke-6 `settings` (fallback ke
`SETTINGS` aktif kalau tidak dioper — semua call-site lama tidak berubah
perilakunya). Enam titik hook (`hypothesis_started`, `hypothesis_failed`×3
alasan, `confirmed`, `trade_closed`) dipasang di sebelah `pushTimeline` yang
sudah ada, tanpa mengubah kondisi gate apa pun. `replayHistory` direfaktor
jadi wrapper tipis di atas primitif `runReplayLoop` (badan loop identik,
termasuk filter anti-lookahead M5 dari V1.2.1) yang dipakai bersama oleh
`simulateWithSettings(pairSyms, settingsOverride)` — satu-satunya jalur
"jalankan mesin di atas histori" untuk tab Uji Hipotesis & Dampak Kalibrasi.

- **Ringkasan Pasar**: tabel 12 pair (status, bias, regime, ATR, readiness%,
  umur hipotesis/trade relatif terhadap `hypothesisMaxAgeMinutes`/
  `tradeMaxAgeMinutes`, jarak ke liquidity, R:R, event terakhir, cakupan
  histori) — murni render-layer, tanpa simulasi. Klik baris → lompat ke
  detail pair itu. Auto-refresh 1Hz HANYA tab ini (tab lain tidak, supaya
  input form yang sedang diisi tidak kehilangan fokus tiap detik).
- **Uji Hipotesis**: jalankan `simulateWithSettings` untuk 1 atau 12 pair,
  dengan kalibrasi aktif atau parameter alternatif (form yang sama dengan
  panel Kalibrasi, di-reuse via `settingsRowHtml`). Hasil: hipotesis
  terbentuk, CONFIRMED, alasan dibatalkan, outcome TP/SL/timeout, win-rate
  dengan **interval Wilson** (bukan estimasi normal yang bisa keluar [0,1]
  di sampel kecil), avg R:R. Bisa disimpan ke Jurnal ditandai "UJI" (badge
  terpisah dari trade live, tidak pernah tercampur diam-diam).
- **Dampak Kalibrasi**: tombol **"🔍 Pratinjau Dampak"** baru di footer panel
  Kalibrasi menjalankan simulasi Sebelum (kalibrasi aktif) vs Sesudah (draft
  di form) atas 12 pair, TANPA menekan "Terapkan" — supaya efek kalibrasi
  terlihat SEBELUM dikomit. Setiap "Terapkan" mencatat diff + snapshot
  pratinjau (kalau ada) ke riwayat (`lfc.calibrationHistory`, cap 50 entri).
  Banner permanen (tidak bisa ditutup): perbandingan ini in-sample (data
  yang sama dipakai untuk menguji), bukan out-of-sample.
- **Jurnal Hasil**: setiap trade yang benar-benar berjalan sampai TP/SL/
  time-stop di koneksi live dicatat otomatis (`lfc.journal`, cap 1000 entri,
  forward-only — tidak diisi retroaktif dari histori sebelum fitur ini
  dipasang) dengan entry/exit/R realisasi/durasi/snapshot kalibrasi saat
  itu. Statistik agregat (win-rate ± CI, expectancy dalam R, breakdown per
  pair) + ekspor JSON/CSV. Timeout selalu jadi bucket terpisah, tidak pernah
  dipaksa jadi win/loss biner.
- **Data & Privasi**: semua 3 dataset baru (`lfc.journal`,
  `lfc.calibrationHistory`, `lfc.trials`) ada di localStorage browser —
  tidak ada server. Tombol hapus per-dataset (dengan konfirmasi) tersedia
  di tab Jurnal Hasil, independen satu sama lain.

**Disiplin anti-p-hacking**: setiap kali "Jalankan Uji" atau "Pratinjau
Dampak" ditekan, tercatat ke `lfc.trials` (cap 200). Penghitung ini
ditampilkan permanen; makin banyak percobaan dalam satu sesi, makin besar
peringatan yang muncul (>10 kuning, >30 merah) — supaya user sadar bahwa
mengulang-ulang kalibrasi sampai kebetulan hasil bagus bukan bukti edge.
Semua angka statistik (win-rate, dst.) didampingi ukuran sampel dan cakupan
histori (candle + rentang jam/hari) — sampel di bawah 20 dapat peringatan,
di bawah 10 dibulatkan ke persen terdekat (bukan desimal presisi palsu),
di bawah 5 dapat peringatan tegas.

**Di luar cakupan sesi ini**: telemetri level percobaan-sweep individual
(alasan `too_shallow`/`too_deep`/dst. dari `evaluateSweep` sendiri, bukan
cuma siklus hipotesis penuh), `CFG` (konstanta tetap seperti
`hypothesisMaxAgeMinutes`) tetap tidak bisa dikalibrasi lewat UI (batas
CFG/SETTINGS sengaja dijaga), tidak ada sumber histori eksternal baru di
luar buffer in-memory aggregator yang sudah ada (~25 jam M1 untuk kripto,
bergantung durasi koneksi untuk pair lain via `bridge.mjs`).


## 11. Backtest & Simulasi Trading, buffer 3000 candle, timeframe M5 (V1.4, baru)

Tombol **"🧪 Backtest"** di topbar membuka simulator akun trading di atas candle historis. Dua cara
pakai pada simulasi yang sama: (a) **Backtest Otomatis** — mesin Liquidity Flow dijalankan di seluruh
rentang dan setiap sinyal CONFIRMED dieksekusi otomatis; (b) **Replay manual** — candle dimajukan satu
per satu (Play/+1/+10/+100/Sampai Akhir, 1–100 candle/detik) sambil Anda BUY/SELL sendiri.

**Data.** Buffer per timeframe dinaikkan ke **3500 candle** (`AGG_CAP`) = 3000 untuk backtest + ~300
pemanasan. Binance: backfill berhalaman mundur (`fetchBinanceKlinesPaged`, 1000 candle/request,
`endTime` = openTime tertua − 1, halaman lama yang gagal tidak membuang yang sudah didapat) untuk M1
**dan M5** (`BACKFILL_CANDLES = 3300`). `bridge.mjs` (pair non-kripto) meminta 3300 trendbar M1 & M5 —
batas maksimum yang diizinkan broker belum diverifikasi; apa pun yang diterima dipakai. Sumber data
backtest: **Data pasar** (buffer aplikasi) atau **Data demo sintetis** (random-walk berseed + pola setup
Liquidity Flow yang disisipkan agar mesin punya sinyal; BUKAN pasar — ditandai jelas di UI dan laporan).
Mesin (`stepEngine`) tetap hanya melihat jendela terakhir (`ENGINE_WIN_BASE` = 1500 candle, konteks 800)
persis seperti ketika buffer dibatasi 1500/800: ATR SMA-14, swing, range, dan umur hipotesis semuanya
lokal, jadi hasilnya identik tetapi tiap langkah O(1500), bukan O(n). Replay live dibatasi
`LIVE_REPLAY_CANDLES` = 1500 terakhir; pratinjau kalibrasi (§10) juga 1500 — backtest 3000 penuh punya
jalurnya sendiri (1 pair, dipecah per-chunk ~40 ms agar UI tidak membeku; ±1 detik per 3000 candle).

**Timeframe M5.** Backtest bisa berjalan di M1 (konteks M5) atau M5 (konteks M15, hasil resample).
Konstanta berbasis menit (`levelCooldownMinutes`, `hypothesisMaxAgeMinutes`, `tradeMaxAgeMinutes`) dikalikan
`settings.tfMul` (1 untuk M1, 5 untuk M5) supaya batasnya setara dalam JUMLAH CANDLE, bukan 5× lebih
ketat. Chart utama juga punya toggle **M1 | M5** (jendela terpisah per TF; countdown ikut TF; kurva VWAP
hanya ada di M1 karena field vwap hanya diisi pada candle M1).

**Model eksekusi** (bagian 6e di kode — murni & diuji di Node):
- Harga data = MID; spread dimodelkan bid = mid − hs / ask = mid + hs. Order market diisi di CLOSE candle
  terakhir yang terlihat (+ spread/2 + slippage) — tidak mengintip candle berikutnya; SL/TP dievaluasi
  mulai candle berikutnya. Sinyal mesin dieksekusi di close candle sinyal (sama dengan asumsi entry mesin).
- SL = stop order (gap melewati SL → terisi di open yang lebih buruk, + slippage); TP = limit order
  (terisi di TP atau lebih baik, tanpa slippage). SL & TP tersentuh di satu candle: default **pesimis**
  (SL dulu); bisa optimis atau "terdekat dari open".
- Order pending Limit/Stop (terisi saat disentuh candle), SL/TP bisa diedit per posisi, SL→BE, tutup
  satu/semua, batalkan order. Ukuran: lot langsung atau **risiko % ekuitas** (butuh SL). SL/TP bisa
  "× ATR" / "× R" (berlaku untuk BUY maupun SELL) atau harga absolut.
- Biaya: spread (tick), slippage (tick), komisi % notional + per lot — default per instrumen
  (kripto 0,04%; XAU/XAG/forex $3,5/lot; indeks 0). Kontrak per lot: kripto 1, XAU 100, XAG 5000, forex
  100.000, indeks 1; USDJPY P/L dikonversi ke USD (÷ harga).
- Margin = notional/leverage; **stop-out** menutup semua posisi saat margin level < ambang (default 50%).
  Pergerakan sangat cepat bisa menembus stop-out sehingga saldo negatif (tidak ada negative-balance
  protection). Posisi sisa di akhir data ditutup di close terakhir (alasan "AKHIR DATA").
- **Modal**: tambah/tarik modal kapan saja. Setoran/penarikan tidak merusak metrik: peak drawdown
  disesuaikan arus modal dan return TWR dihitung per candle dengan koreksi arus.

**Panel & laporan.** Akun (saldo, ekuitas, P/L mengambang, margin terpakai/bebas/level, setoran, P/L
bersih), Panel Order (BUY/SELL + preview ukuran/risiko/margin), tab **Portofolio** (ringkasan instrumen,
posisi terbuka, order pending), **Riwayat Trade** (kotor, biaya, bersih, R, MAE/MFE, CSV), **Laporan**
(P/L bersih, return terhadap setoran, TWR, buy&hold, profit factor, win rate + interval Wilson,
expectancy $/R, payoff, drawdown maks & terpanjang, recovery factor, eksposur, komisi, per arah, sinyal
mesin), **Kurva Ekuitas** (ekuitas, saldo, setoran/penarikan, drawdown %), dan **Log**. Sharpe/Sortino
dihitung dari return **per jam** dan baru ditampilkan bila ≥ 24 jam data (return per-candle menghasilkan
angka absurd karena sebagian besar candle tanpa posisi) — tetap annualisasi kasar.

**Batasan jujur.** Ini backtest in-sample pada beberapa hari data (3000 candle M1 ≈ 50 jam; M5 ≈ 10 hari),
sinyal mesin jarang (puluhan jam per sinyal), jadi jumlah trade biasanya satu digit — sampel kecil diberi
peringatan bertingkat dan TIDAK boleh dibaca sebagai bukti edge. Satu simulasi = satu pair (portofolio
multi-pair belum ada). Candle antar-gap (pasar tutup) tidak dimodelkan khusus.
