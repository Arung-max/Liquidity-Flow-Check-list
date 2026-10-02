# Menyalakan bridge.mjs (kalau belum jalan) + serve.mjs (kalau belum jalan), lalu membuka
# liquidity-flow-checklist.html lewat http://localhost:8850 (BUKAN file://) supaya auto-reload aktif.
# Aman dijalankan berkali-kali: kalau port sudah dipakai, bagian itu dilewati.

# --- UBAH DI SINI kalau folder bridge dipindah ---
$bridgeDir  = "C:\Users\admin\OneDrive\Documents\Order Flow Bridge FIle"
$bridgePort = 8787
$servePort  = 8850
# --------------------------------------------------

$root = Split-Path -Parent $MyInvocation.MyCommand.Path

function Test-Port($port) {
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $c.Connect("127.0.0.1", $port)
        $c.Close()
        return $true
    } catch {
        return $false
    }
}

# 1) Bridge cTrader (log ditulis ke bridge.log di folder bridge, jendela disembunyikan)
if (-not (Test-Port $bridgePort)) {
    if (Test-Path (Join-Path $bridgeDir "bridge.mjs")) {
        Start-Process -FilePath "cmd.exe" `
            -ArgumentList "/c node bridge.mjs >> bridge.log 2>&1" `
            -WorkingDirectory $bridgeDir -WindowStyle Hidden
        # Tunggu bridge siap (maks ~8 detik) supaya koneksi pertama dashboard langsung berhasil
        for ($i = 0; $i -lt 16; $i++) {
            Start-Sleep -Milliseconds 500
            if (Test-Port $bridgePort) { break }
        }
    }
}

# 2) Server preview (serve.mjs keluar sendiri kalau port sudah dipakai)
if (-not (Test-Port $servePort)) {
    Start-Process -FilePath "node" -ArgumentList "serve.mjs" -WorkingDirectory $root -WindowStyle Hidden
    Start-Sleep -Milliseconds 600
}

# 3) Buka dashboard
Start-Process "http://localhost:$servePort/liquidity-flow-checklist.html"
