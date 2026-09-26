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
