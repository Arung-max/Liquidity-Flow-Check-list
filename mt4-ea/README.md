# VWAP Stdev Bands EA (MQL4)

Port dari indikator TradingView Pine Script `VWAP Stdev Bands v2 Mod` menjadi
Expert Advisor MT4 auto-trading. **Terpisah dari `liquidity-flow-checklist.html`**
di root repo ini — alat itu murni untuk membaca struktur pasar secara manual,
bukan auto-trade; EA ini sebaliknya, mengirim order sendiri.

## Isi

- **`VWAP_StdevBands_EA.mq4`** — EA-nya. Hitung VWAP harian (anchored, reset
  tiap sesi baru) + 5 tingkat band deviasi standar berbobot volume, lalu
  trading di atasnya dengan salah satu dari dua mode (dipilih lewat input
  `StrategyMode`):
  - **Mean-Reversion** — fade saat harga menyentuh/menembus band lalu
    candle-nya balik ditutup di dalam band (reversal), target balik ke VWAP
    atau band dalam.
  - **Breakout** — entry searah saat candle close menembus band dengan body
    minimal sekian kali deviasi standar (filter displacement), target tier
    band berikutnya.

## Cara pakai

1. Copy `VWAP_StdevBands_EA.mq4` ke folder `MQL4/Experts/` di data folder
   terminal MT4 kamu, lalu compile di MetaEditor (F7).
2. Attach ke chart simbol & timeframe yang mau dipakai (disarankan M1–M15,
   karena VWAP di-reset harian — di timeframe besar bandnya terlalu kasar).
3. Atur input sesuai kebutuhan (lihat daftar di bawah).
4. **Backtest dulu di Strategy Tester** sebelum dipakai live/demo — EA ini
   belum pernah diuji terhadap data historis riil.

## Input penting

| Input | Fungsi |
|---|---|
| `DevUp1..5` / `DevDn1..5` | Multiplier tiap tingkat band (default sama dengan skrip Pine aslinya: 1.28/2.01/2.51/3.09/4.01). |
| `SessionAnchorShiftHours` | Geser titik reset harian VWAP (jam), relatif waktu server broker — penting kalau mau anchor-nya jam tertentu (mis. midnight NY) bukan midnight server. |
| `StrategyMode` | `MODE_MEAN_REVERSION` atau `MODE_BREAKOUT`. |
| `EntryBandTier` | Tier (1-5) yang jadi pemicu entry di mode mean-reversion. |
| `BreakoutBandTier` | Tier (1-5) yang jadi pemicu entry di mode breakout. |
| `DisplacementFactor` | Filter candle breakout: body minimal = faktor × deviasi standar saat itu. |
| `TPTarget` | Target TP mean-reversion: VWAP atau band tier 1. |
| `SLBufferPoints` / `FixedRR` | Buffer SL & fallback risk:reward kalau tier berikutnya tidak tersedia. |
| `UseRiskPercent` / `RiskPercent` / `FixedLotSize` | Position sizing berbasis risiko % equity, atau lot tetap. |
| `MaxOpenPositions`, `MagicNumber`, `Slippage`, `MaxSpreadPoints` | Kontrol order standar. |
| `UseTradingHoursFilter`, `TradingStartHour/EndHour` | Batasi jam trading (jam server). |
| `CloseAllAtSessionEnd` | Tutup semua posisi EA ini saat sesi/hari berganti. |
| `DrawBandsOnChart`, `ShowTier2..5OnChart` | Visualisasi VWAP & band di chart (garis per-bar, bukan indicator buffer). |

## Catatan & keterbatasan penting

- **Volume di MT4 forex/CFD = tick volume**, bukan volume transaksi asli
  (beda dengan crypto/futures di TradingView). VWAP & band jadi "tick-volume
  weighted", bukan VWAP murni — sadari ini saat membaca levelnya.
- Indikator Pine aslinya **tidak punya logika entry/exit sama sekali** — ini
  murni band visual. Dua mode di atas (`MODE_MEAN_REVERSION` / `MODE_BREAKOUT`)
  adalah aturan trading yang dirancang di atas band tersebut, bukan terjemahan
  literal dari skrip asli.
- Tidak ada trailing stop / breakeven management bawaan — SL/TP dipasang
  sekali saat order dibuka.
- `CalculateVWAP()` menghitung ulang dari awal sesi setiap bar baru (bukan
  menyimpan running sum antar-tick), supaya hasilnya selalu konsisten walau
  EA di-restart — cukup ringan untuk timeframe M1–M15.
