// Vergleicht stückweises Einlesen mit dem Einlesen am Stück (gleiches Ergebnis erwartet)
import fs from 'fs';
const src = fs.readFileSync('/home/claude/new_world/web/ki_llm.js', 'utf8');
const body = src.match(/function workerMain\(\) \{[\s\S]*?\n\t\}\n\n\t\/\/ -{10}/)[0].replace(/\n\n\t\/\/ -+$/, '');
async function run(chunk) {
  const res = [];
  globalThis.self = { postMessage: (x) => { if (x.type === 'result') res.push(x); if (x.type === 'trying') setTimeout(() => self.onmessage({ data: { type: 'go' } }), 0); } };
  eval('(' + body + ')()');
  const cfg = { lib_urls: ['file:///tmp/claude-0/tinyllm/node_modules/@huggingface/transformers/dist/transformers.node.mjs'],
    models: { rat: ['tiny-llama'], siedler: ['tiny-smol'] }, dtypes: { wasm: ['fp32'] }, device: 'cpu', local_path: '/tmp/claude-0/tinyllm/models/', chunk };
  await self.onmessage({ data: { type: 'init', cfg } });
  const long = 'Lage der Insel: ' + 'Holz Stein Essen Siedler Fischer Sammler '.repeat(40);
  const ask = [{ role: 'system', content: 'Du bist ein Rat.' }, { role: 'user', content: long + '\n1) Essen\n2) Holz\n3) Stein\nAntworte nur mit der Nummer.' }];
  for (const [id, model] of [[1, 'rat'], [2, 'siedler']]) self.onmessage({ data: { type: 'job', job: { id, model, mode: 'choose', messages: ask, n: 3 } } });
  self.onmessage({ data: { type: 'job', job: { id: 3, model: 'rat', mode: 'generate', messages: ask, max_new_tokens: 8, temperature: 0 } } });
  const t0 = Date.now();
  while (res.length < 3 && Date.now() - t0 < 60000) await new Promise((r) => setTimeout(r, 20));
  return res.map((r) => r.ok ? (r.probs ? r.probs.map((p) => p.toFixed(5)).join(',') + ' n=' + r.tokens : JSON.stringify(r.text)) : 'FEHLER ' + r.error);
}
console.log('am Stück  ', await run(100000));
console.log('Stücke 64 ', await run(64));
console.log('Stücke 7  ', await run(7));
