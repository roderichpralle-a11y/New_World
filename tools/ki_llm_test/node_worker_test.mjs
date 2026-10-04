// Testet web/ki_llm.js workerMain in Node mit den winzigen Testmodellen
import fs from 'fs';
const src = fs.readFileSync('/home/claude/new_world/web/ki_llm.js', 'utf8');
const m = src.match(/function workerMain\(\) \{[\s\S]*?\n\t\}\n\n\t\/\/ -{10}/);
const body = m[0].replace(/\n\n\t\/\/ -+$/, '');
const msgs = [];
globalThis.self = { postMessage: (x) => { msgs.push(x); if (x.type !== 'progress') console.log('<-', JSON.stringify(x).slice(0, 300)); } };
globalThis.performance = performance;
eval('(' + body + ')()');
const cfg = { lib_urls: ['file:///tmp/claude-0/tinyllm/node_modules/@huggingface/transformers/dist/transformers.node.mjs'],
  models: { rat: ['gibtsnicht', 'tiny-llama'], siedler: ['tiny-smol'] }, dtypes: { wasm: ['q4', 'fp32'] }, device: 'cpu', local_path: '/tmp/claude-0/tinyllm/models/' };
await self.onmessage({ data: { type: 'init', cfg } });
const ask = [{ role: 'system', content: 'Du bist ein Rat.' }, { role: 'user', content: 'Was tun?\n1) Essen\n2) Holz\n3) Stein\nAntworte nur mit der Nummer.' }];
self.onmessage({ data: { type: 'job', job: { id: 1, model: 'rat', mode: 'choose', messages: ask, n: 3 } } });
self.onmessage({ data: { type: 'job', job: { id: 2, model: 'siedler', mode: 'choose', messages: ask, n: 3 } } });
self.onmessage({ data: { type: 'job', job: { id: 3, model: 'rat', mode: 'generate', messages: ask, max_new_tokens: 10, temperature: 0.3 } } });
self.onmessage({ data: { type: 'job', job: { id: 4, model: 'siedler', mode: 'generate', messages: ask, max_new_tokens: 10, temperature: 0 } } });
const t0 = Date.now();
while (msgs.filter((x) => x.type === 'result').length < 4 && Date.now() - t0 < 60000) await new Promise((r) => setTimeout(r, 50));
console.log('fertig', msgs.filter((x) => x.type === 'result').length);
