# Menyalakan serve.mjs (kalau belum jalan) lalu membuka liquidity-flow-checklist.html
# lewat http://localhost:8850 -- BUKAN file:// -- supaya auto-reload di halamannya aktif.
# Aman dijalankan berkali-kali: kalau server sudah jalan (port dipakai), serve.mjs keluar
# sendiri dengan pesan ramah (lihat server.on('error') di dalamnya), tidak menumpuk proses.

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$port = 8850

Start-Process -FilePath "node" -ArgumentList "serve.mjs" -WorkingDirectory $root -WindowStyle Hidden
Start-Sleep -Milliseconds 600
Start-Process "http://localhost:$port/liquidity-flow-checklist.html"
