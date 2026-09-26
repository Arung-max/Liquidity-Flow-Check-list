# Liquidity Flow Checklist

Dashboard live untuk membaca struktur likuiditas (liquidity sweep, MSS/CHOCH, FVG, retest)
di 12 pair — kripto, emas/perak, forex, dan indeks — berdasarkan checklist V1.1 di
[`liquidity-flow-checklist-blueprint.md`](./liquidity-flow-checklist-blueprint.md).

Ini alat bantu baca struktur pasar, **bukan** sinyal beli/jual otomatis dan bukan
nasihat investasi.

## Isi repo ini

- **`liquidity-flow-checklist.html`** — aplikasi live-nya. Satu file HTML mandiri
  (tanpa bundler, tanpa dependency npm), langsung dibuka di browser.
- **`liquidity-flow-checklist-blueprint.md`** — spesifikasi lengkap: definisi numerik
  setiap fase checklist, aturan gerbang berurutan, protokol data live, dan roadmap pair.

## Menjalankan

Aplikasi ini butuh sumber data live yang berjalan terpisah:

1. **Kripto (BTCUSDT, ETHUSDT, SOLUSDT)** — connect langsung ke Binance dari browser,
   tidak butuh apa pun tambahan.
2. **Emas/Perak/Forex/Indeks** (XAUUSD, XAGUSD, EURUSD, GBPUSD, USDJPY, US30, US100,
   US500, DAX40) — butuh jembatan `bridge.mjs` (proyek terpisah, tidak ada di repo ini)
   yang menghubungkan ke cTrader Open API, berjalan di `ws://localhost:8787`.

Kalau bridge belum aktif, pair-pair itu otomatis jatuh ke status SIM/ERROR tanpa
mengganggu pair kripto yang lain.

Begitu tersambung, kripto & pair lewat bridge sama-sama langsung menarik histori
candle (bukan mulai dari nol) — kripto lewat REST Binance, pair lainnya lewat
histori trendbar cTrader yang diteruskan bridge. Fitur bridge ini butuh
`bridge.mjs` versi yang sudah mendukung `GET_TRENDBARS_REQ`/`RES`; lihat
blueprint §6.1–6.2 untuk detail protokolnya.

Buka `liquidity-flow-checklist.html` langsung di browser (dobel klik, atau lewat
`file://`) — tidak perlu server statis.

## Live preview dengan auto-reload (opsional, buat yang lagi ikut kembangkan)

Kalau lagi memantau pembaruan (mis. lewat Claude Code) dan ingin browser Anda
otomatis me-refresh sendiri setiap ada perubahan di file — tanpa perlu dibuka
ulang manual tiap kali:

1. Dobel-klik **`Buka Live Preview.vbs`** (sekali saja). Ini menyalakan
   `serve.mjs` (server statis kecil, `http://localhost:8850`) dan membuka
   `liquidity-flow-checklist.html` lewat alamat itu — **bukan** `file://`.
2. Biarkan tab itu tetap terbuka. Halaman mengecek tiap 2 detik apakah file-nya
   berubah di disk (lewat header `Last-Modified`); begitu berubah, tab
   refresh sendiri.
3. Server-nya jalan di latar belakang (hidden) sampai komputer dimatikan atau
   prosesnya dihentikan manual. Dobel-klik lagi kapan pun aman — kalau server
   sudah jalan, percobaan kedua langsung keluar sendiri tanpa bentrok
   (lihat `serve.mjs`), cuma browser-nya yang dibuka ulang.

Auto-reload ini **cuma aktif kalau dibuka lewat `http://localhost:8850`**;
membuka file ini langsung lewat `file://` (dobel klik biasa dari Explorer)
tetap berfungsi normal seperti biasa, tanpa auto-reload.
