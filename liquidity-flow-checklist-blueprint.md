# Liquidity Flow Checklist — Blueprint V1.1

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
- **Reclaim**: dalam `≤ 3 candle M1` setelah breach, ada **close** yang balik
  ke sisi dalam `L` → status `VALID`.
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
- **Range valid**: `≥ 6 candle M1` dengan high/low tertampung dalam pita
  `≤ 1.2 × ATR`.
- **Compression**: lebar pita rolling-5-candle menurun `≥ 3` candle berturutan.
- **Equal highs/lows**: `≥ 2` swing point M1 dalam toleransi `≤ 0.15 × ATR`
  (atau `≤ 3 tick`, mana yang lebih besar) satu sama lain. Jumlah titik yang
  berkumpul = **Liquidity Density** (2 titik = LOW, 3 = MEDIUM, ≥4 = HIGH),
  persis visual di V1.0 §5.

### 4.6 Second Sweep
Level target = klaster equal-high/low dengan density tertinggi di dalam
range aktif. Rumus breach/reclaim/rejection identik §4.4.
**SECOND SWEEP CONFIRMED** hanya jika ketiganya (breach + reclaim + rejection
wick) terpenuhi — ini gate wajib sebelum §4.7 dievaluasi sama sekali.

### 4.7 Displacement & MSS/CHOCH
- **Displacement valid**:
  `|close−open| ≥ 1.5 × ATR` **dan** close berada di 25% terluar range candle
  (searah pergerakan) **dan** body-nya lebih besar dari 2 candle sebelumnya.
  Ini mencegah satu wick liar dibaca sebagai displacement (prinsip "satu
  candle tidak menentukan").
- **MSS/CHOCH valid**: **close** (bukan wick) dari candle displacement yang
  sama menembus swing point M1 tervalidasi (fractal L=2) yang paling relevan
  ke arah hipotesis, dan gate §4.6 sudah `CONFIRMED` sebelum ini dievaluasi.

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

**Sudah diuji** end-to-end lewat `mock-ctrader.mjs` (server broker tiruan
juga diperluas untuk membalas trendbar sintetis) — protokol klien↔bridge↔mock
terbukti nyambung. **Belum diuji** terhadap server cTrader sungguhan (nama
field & format enum `period` diambil dari dokumentasi/memori, bukan hasil
observasi langsung) — kemungkinan perlu penyesuaian kecil begitu dicoba saat
market buka dengan akun broker asli. Kalau ada `ERROR_RES` utk histori, cek
log bridge (`Histori M1 gagal -> ...`) untuk detail errorCode/description
dari broker.

---

## 7. Yang sengaja belum dikerjakan di V1.1

- Multi-timeframe confluence di luar M1/M5 (H1 bias, dst.) — bisa ditambah
  sebagai filter tambahan, tidak mengubah gate inti.
- Liquidity Density dari order book L2 (bukan hanya swing point harga) —
  akan menambah akurasi untuk kripto (yang punya book asli), tapi bukan
  syarat karena mesin ini dirancang generik lintas 12 pair.
- Alert suara/notifikasi push saat status naik ke WAIT/CONFIRMED.
