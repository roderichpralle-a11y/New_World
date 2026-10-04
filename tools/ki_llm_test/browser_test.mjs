import { chromium } from 'playwright';
import http from 'http'; import fs from 'fs'; import path from 'path';
const root = '/tmp/claude-0/tinyllm/www';
const types = { '.js': 'text/javascript', '.mjs': 'text/javascript', '.html': 'text/html', '.json': 'application/json', '.wasm': 'application/wasm', '.onnx': 'application/octet-stream' };
const srv = http.createServer((q, r) => { const f = path.join(root, decodeURIComponent(q.url.split('?')[0])); fs.readFile(f, (e, d) => { if (e) { console.log('404', q.url); r.writeHead(404); r.end(); return; } r.writeHead(200, { 'Content-Type': types[path.extname(f)] || 'application/octet-stream' }); r.end(d); }); }).listen(8765);
const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
const p = await b.newPage();
p.on('console', (m) => console.log('console:', m.text().slice(0, 200)));
p.on('request', (q) => console.log('req', q.url().slice(0,120)));
p.on('worker', (wk) => wk.on('console', (m) => console.log('wconsole:', m.text().slice(0, 300))));
p.on('pageerror', (e) => console.log('pageerror:', e.message));
await p.goto('http://localhost:8765/index.html');
for (let i = 0; i < 30; i++) { await p.waitForTimeout(500); const r = await p.evaluate(() => ({ out: window.out, st: window.st })); if (r.out && r.out.length >= 3) { console.log(JSON.stringify(r, null, 0).slice(0, 1500)); break; } if (i % 10 == 9) console.log('warte', JSON.stringify(r.st).slice(0, 400)); }
await b.close(); srv.close();
