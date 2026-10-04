import { chromium } from 'playwright';
import http from 'http'; import fs from 'fs'; import path from 'path';
const root = '/tmp/claude-0/tinyllm/www';
const srv = http.createServer((q, r) => { const f = path.join(root, decodeURIComponent(q.url.split('?')[0])); fs.readFile(f, (e, d) => { if (e) { r.writeHead(404); r.end(); return; } r.writeHead(200, { 'Content-Type': f.endsWith('.html') ? 'text/html' : (f.endsWith('.wasm') ? 'application/wasm' : (f.match(/\.m?js$/) ? 'text/javascript' : 'application/octet-stream')) }); r.end(d); }); }).listen(8766);
const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
const p = await b.newPage();
const url = 'http://localhost:8766/index.html';
await p.goto(url);
// "Absturz": sobald der Rat (tiny-llama) geladen wird, Seite neu laden
for (let i = 0; i < 200; i++) { const v = await p.evaluate(() => localStorage.getItem('kiLlmPending')); if (v && v.includes('tiny-llama')) { console.log('Absturz simuliert bei', v); break; } await p.waitForTimeout(20); }
await p.reload();
for (let i = 0; i < 60; i++) { await p.waitForTimeout(500); const r = await p.evaluate(() => ({ out: window.out, st: window.st, ls: [localStorage.getItem('kiLlmTooBig'), localStorage.getItem('kiLlmPending')] })); if (r.out && r.out.length >= 2) { console.log('Lauf 2:', JSON.stringify(r.st.models), r.ls, r.out.map(o => o.ok)); break; } }
// Dritter Lauf: auch tiny-smol als Rat "zu groß" -> Rat teilt das Siedlermodell
await p.evaluate(() => localStorage.setItem('kiLlmTooBig', JSON.stringify(['rat:tiny-llama'])));
await p.evaluate(() => localStorage.setItem('kiLlmPending', JSON.stringify({ role: 'rat', id: 'tiny-smol' })));
await p.reload();
for (let i = 0; i < 60; i++) { await p.waitForTimeout(500); const r = await p.evaluate(() => ({ out: window.out, st: window.st, ls: [localStorage.getItem('kiLlmTooBig'), localStorage.getItem('kiLlmPending')] })); if ((r.out && r.out.length >= 2) || (r.st && r.st.state === 'fehler')) { console.log('Lauf 3:', r.st.state, r.st.error, JSON.stringify(r.st.models), r.ls, (r.out || []).map(o => o.ok)); break; } }
await b.close(); srv.close();
