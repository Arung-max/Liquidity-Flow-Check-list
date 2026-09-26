/* ===========================================================================
   Server statis kecil khusus utk liquidity-flow-checklist.html -- gunanya
   supaya file ini bisa dibuka lewat http:// (bukan file://) sehingga fitur
   auto-reload di dalam HTML-nya bisa aktif: begitu file di-update (misal
   lewat "git pull" atau ditulis ulang), tab yang sedang terbuka refresh
   sendiri dalam 1-2 detik, tanpa perlu dibuka ulang manual.

   Jalankan:  node serve.mjs        (mendengar di http://localhost:8850)
   Atau dobel-klik "Buka Live Preview.vbs" di folder yang sama.
   ========================================================================= */

import { createServer } from 'http';
import { readFile, stat } from 'fs/promises';
import { join, extname, normalize } from 'path';

const ROOT = process.cwd();
const PORT = Number(process.env.PORT || 8850);
const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.md': 'text/plain; charset=utf-8',
};

const server = createServer(async (req, res) => {
  let p = decodeURIComponent((req.url || '/').split('?')[0]);
  if (p === '/') p = '/liquidity-flow-checklist.html';
  const fp = normalize(join(ROOT, p));
  // Jaga-jaga sederhana: jangan layani file di luar folder proyek ini.
  if (!fp.startsWith(ROOT)) { res.writeHead(403); res.end('Forbidden'); return; }
  try {
    const st = await stat(fp);
    const body = await readFile(fp);
    const headers = {
      'Content-Type': MIME[extname(fp)] || 'application/octet-stream',
      'Last-Modified': st.mtime.toUTCString(),
      'Cache-Control': 'no-cache',
    };
    res.writeHead(200, headers);
    if (req.method !== 'HEAD') res.end(body); else res.end();
  } catch {
    res.writeHead(404); res.end('Not found: ' + p);
  }
});

server.on('error', (e) => {
  if (e.code === 'EADDRINUSE') {
    console.log(`Sudah ada server di port ${PORT} (kemungkinan sesi sebelumnya masih jalan) -- tidak apa, biarkan itu yang melayani.`);
    process.exit(0);
  }
  console.error('Server error:', e.message);
  process.exit(1);
});

server.listen(PORT, () => {
  console.log(`Liquidity Flow Checklist (live-reload): http://localhost:${PORT}/`);
});
