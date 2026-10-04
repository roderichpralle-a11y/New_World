// KI-Variante: Sprachmodelle im Browser (transformers.js in einem Web Worker).
// Godot lädt diese Datei mit JavaScriptBridge.eval und spricht nur über window.KiLlm:
//   KiLlm.init(cfgJson)   Modelle laden (Rat: Llama-3.2-1B, Siedler: SmolLM-135M)
//   KiLlm.submit(jobJson) Anfrage einreihen, Antwort kommt über poll()
//   KiLlm.poll()          JSON {status, results: [...]} seit dem letzten Aufruf
//   KiLlm.probe()         was das Gerät kann (WebGPU, Speicher, Handy?)
// Das Spiel läuft weiter, während der Worker rechnet. Ohne Netz oder bei Fehlern meldet
// der Status "fehler" und das Spiel nimmt die Regel-KI.
(function () {
	if (window.KiLlm) return;

	// ------------------------------------------------------------------ Worker
	function workerMain() {
		let T = null;            // transformers.js
		const M = {};            // rat / siedler -> {tok, model, id, dtype, device, digits}
		const queue = [];
		let busy = false;
		let cfg = null;
		let device = 'wasm';

		const post = (m) => self.postMessage(m);
		const status = (extra) => post(Object.assign({ type: 'status' }, extra));

		async function importLib() {
			let last = null;
			for (const url of cfg.lib_urls) {
				try {
					T = await import(url);
					if (T && T.AutoTokenizer) return url;
				} catch (e) { last = e; }
			}
			throw new Error('Bibliothek nicht geladen: ' + (last && last.message));
		}

		async function pickDevice() {
			if (cfg.device && cfg.device !== 'auto') return cfg.device;
			try {
				if (self.navigator && navigator.gpu) {
					const ad = await navigator.gpu.requestAdapter();
					if (ad) return ad.features && ad.features.has('shader-f16') ? 'webgpu-f16' : 'webgpu';
				}
			} catch (e) { }
			return 'wasm';
		}

		// Ziffern-Token je Option (mit und ohne Leerzeichen davor)
		function digitIds(tok) {
			const out = [];
			for (let d = 1; d <= 9; d++) {
				const ids = new Set();
				for (const s of ['' + d, ' ' + d]) {
					try {
						const e = tok.encode(s, { add_special_tokens: false });
						if (e.length === 1) ids.add(Number(e[0]));
						else if (e.length === 2 && s[0] === ' ') ids.add(Number(e[1]));
					} catch (err) { }
				}
				out.push([...ids]);
			}
			return out;
		}

		// Welche Modelle probieren? Der Rat hat ein großes (Llama) und kleine für Handys. Modelle, bei
		// denen das Gerät früher abgestürzt ist (cfg.skip), kommen nicht mehr dran.
		function candidates(role) {
			let ids = cfg.models[role] || [];
			if (role === 'rat') {
				const small = cfg.models.rat_small || [];
				ids = cfg.small_first ? [...small, ...ids] : [...ids, ...small];
			}
			return ids.filter((id) => !(cfg.skip || []).includes(role + ':' + id));
		}

		let goResolve = null;

		async function loadOne(role) {
			const ids = candidates(role);
			if (!ids.length && role === 'rat' && M.siedler) {
				shareSettlerModel();
				return;
			}
			const dev = device.startsWith('webgpu') ? 'webgpu' : (device === 'cpu' ? 'cpu' : 'wasm');
			const dtypes = device === 'webgpu-f16' ? cfg.dtypes.webgpu_f16 : (dev === 'webgpu' ? cfg.dtypes.webgpu : cfg.dtypes.wasm);
			let last = null;
			for (const id of ids) {
				for (const dtype of dtypes) {
					try {
						status({ state: 'laden', role, note: id + ' (' + dtype + ')' });
						// Erst weiter, wenn die Seite sich sicher gemerkt hat, was jetzt geladen wird
						await new Promise((res) => { goResolve = res; post({ type: 'trying', role, id }); setTimeout(res, 3000); });
						const progress_callback = (p) => {
							if (p && p.status === 'progress' && p.total) {
								post({ type: 'progress', role, file: p.file, loaded: p.loaded, total: p.total });
							}
						};
						const tok = await T.AutoTokenizer.from_pretrained(id, { progress_callback });
						const model = await T.AutoModelForCausalLM.from_pretrained(id, { dtype, device: dev, progress_callback });
						M[role] = { tok, model, id, dtype, device: dev, digits: digitIds(tok) };
						post({ type: 'loaded', role, id, dtype, device: dev });
						return;
					} catch (e) {
						last = e;
						post({ type: 'log', text: role + ': ' + id + ' ' + dtype + ' geht nicht: ' + (e && e.message) });
					}
				}
			}
			if (role === 'rat' && M.siedler) {
				shareSettlerModel();
				return;
			}
			throw new Error(role + ': kein Modell ladbar (' + (last && last.message) + ')');
		}

		// Notlösung: Der Rat denkt mit dem Siedlermodell (braucht keinen zusätzlichen Speicher)
		function shareSettlerModel() {
			M.rat = M.siedler;
			post({ type: 'loaded', role: 'rat', id: M.siedler.id, dtype: M.siedler.dtype, device: M.siedler.device, shared: true });
			post({ type: 'ok', role: 'rat', id: M.siedler.id });
		}

		function render(m, job) {
			let text;
			try {
				text = m.tok.apply_chat_template(job.messages, { tokenize: false, add_generation_prompt: true });
			} catch (e) {
				// Ohne Chat-Vorlage: einfach zusammensetzen
				text = job.messages.map((x) => x.role + ': ' + x.content).join('\n') + '\nassistant: ';
			}
			return text + (job.prefix || '');
		}

		function logsumexp(arr) {
			let mx = -Infinity;
			for (const v of arr) mx = Math.max(mx, v);
			if (mx === -Infinity) return -Infinity;
			let s = 0;
			for (const v of arr) s += Math.exp(v - mx);
			return mx + Math.log(s);
		}

		// Lange Anfragen stückweise einlesen: Ohne das berechnet das Modell für jedes Wort der Anfrage
		// eine Wahrscheinlichkeit für jedes Wort seines Wortschatzes (bei Llama mit 2000 Wörtern
		// Anfrage über 1 GB auf einmal). In Stücken von `chunk` Wörtern bleibt es klein; das Gelesene
		// steht im Zwischenspeicher (past_key_values), generate() macht danach mit dem Rest weiter.
		async function runGen(m, enc, opts) {
			const L = enc.input_ids.dims.at(-1);
			const CH = cfg.chunk || 64;
			let cache = null;
			try {
				for (let s = 0; s + CH < L; s += CH) {
					const out = await m.model.forward({
						input_ids: enc.input_ids.slice(null, [s, s + CH]), attention_mask: T.ones([1, s + CH]), past_key_values: cache,
					});
					const pkv = {};
					for (const k in out) if (k.startsWith('present')) pkv[k.replace('present', 'past_key_values')] = out[k];
					if (cache) cache.update(pkv); else cache = new T.DynamicCache(pkv);
					if (out.logits && out.logits.location === 'gpu-buffer') out.logits.dispose();
				}
				return await m.model.generate({
					...opts, input_ids: enc.input_ids, attention_mask: T.ones([1, L]), ...(cache ? { past_key_values: cache } : {}),
				});
			} finally {
				if (cache) await cache.dispose();
			}
		}

		// Auswahl: Wahrscheinlichkeit jeder Nummer 1..n als nächstes Wort der Antwort
		async function choose(m, job) {
			const text = render(m, job);
			const enc = m.tok(text, { add_special_tokens: false });
			let captured = null;
			class Capture extends T.LogitsProcessor {
				_call(input_ids, logits) {
					if (!captured) captured = Float32Array.from(logits.data.subarray(0, logits.dims.at(-1)));
					return logits;
				}
			}
			await runGen(m, enc, { max_new_tokens: 1, do_sample: false, logits_processor: [new Capture()] });
			const n = Math.max(1, Math.min(9, job.n));
			const raw = [];
			for (let i = 0; i < n; i++) {
				const ids = m.digits[i];
				raw.push(ids.length ? logsumexp(ids.map((id) => captured[id])) : -Infinity);
			}
			// Anteil der Nummern an allem, was das Modell sagen wollte
			const all = logsumexp(captured);
			const opt = logsumexp(raw);
			let top = 0;
			for (let i = 1; i < captured.length; i++) if (captured[i] > captured[top]) top = i;
			const probs = raw.map((v) => Math.exp(v - opt));
			return { probs, mass: Math.exp(opt - all), top: m.tok.decode([top], { skip_special_tokens: false }), tokens: enc.input_ids.dims.at(-1) };
		}

		async function generate(m, job) {
			const text = render(m, job);
			const enc = m.tok(text, { add_special_tokens: false });
			const t = job.temperature || 0;
			const out = await runGen(m, enc, {
				max_new_tokens: job.max_new_tokens || 48, do_sample: t > 0, temperature: t > 0 ? t : 1.0, repetition_penalty: 1.15,
			});
			const len = enc.input_ids.dims.at(-1);
			const seq = out.tolist()[0].slice(len).map(Number);
			return { text: m.tok.decode(seq, { skip_special_tokens: true }), tokens: len };
		}

		async function pump() {
			if (busy) return;
			busy = true;
			while (queue.length) {
				const job = queue.shift();
				const t0 = performance.now();
				try {
					const m = M[job.model];
					if (!m) throw new Error('Modell ' + job.model + ' nicht geladen');
					const r = job.mode === 'generate' ? await generate(m, job) : await choose(m, job);
					post({ type: 'result', id: job.id, ok: true, ms: performance.now() - t0, ...r });
					if (!m.proven) {
						// Erste Antwort geschafft: das Gerät verkraftet dieses Modell
						m.proven = true;
						post({ type: 'ok', role: job.model, id: m.id });
					}
				} catch (e) {
					post({ type: 'result', id: job.id, ok: false, ms: performance.now() - t0, error: String(e && e.message || e) });
				}
			}
			busy = false;
		}

		self.onmessage = async (ev) => {
			const msg = ev.data;
			if (msg.type === 'init') {
				cfg = msg.cfg;
				try {
					status({ state: 'laden', note: 'Bibliothek' });
					const url = await importLib();
					T.env.allowLocalModels = false;
					T.env.useBrowserCache = true;
					if (cfg.wasm_paths && T.env.backends && T.env.backends.onnx && T.env.backends.onnx.wasm) {
						T.env.backends.onnx.wasm.wasmPaths = cfg.wasm_paths;
					}
					if (cfg.remote_host) {
						// Nur für Tests ohne Internet: eigener Server statt huggingface.co
						T.env.remoteHost = cfg.remote_host;
						T.env.useBrowserCache = false;
					}
					if (cfg.local_path) {
						// Nur für Tests ohne Internet: Modelle aus einem Ordner
						T.env.localModelPath = cfg.local_path;
						T.env.allowLocalModels = true;
						T.env.allowRemoteModels = false;
						T.env.useBrowserCache = false;
					}
					device = await pickDevice();
					status({ state: 'laden', device, note: url });
					// Erst das kleine Siedlermodell, dann den Rat
					await loadOne('siedler');
					await loadOne('rat');
					status({ state: 'bereit', device });
				} catch (e) {
					status({ state: 'fehler', device, error: String(e && e.message || e) });
				}
			} else if (msg.type === 'go') {
				if (goResolve) { const r = goResolve; goResolve = null; r(); }
			} else if (msg.type === 'job') {
				queue.push(msg.job);
				pump();
			}
		};
	}

	// ------------------------------------------------------------------ Seite
	const K = {
		worker: null,
		st: { state: 'aus', device: '', error: '', note: '', models: {}, progress: {}, log: [] },
		results: [],
	};

	K.probe = function () {
		const nav = window.navigator || {};
		const mobile = /Android|iPhone|iPad|iPod|Mobile/i.test(nav.userAgent || '');
		return JSON.stringify({ webgpu: !!nav.gpu, memory: nav.deviceMemory || 0, mobile, cores: nav.hardwareConcurrency || 0 });
	};

	// Absturzschutz: Stürzt die Seite beim Laden oder bei der ersten Antwort eines Modells ab (zu wenig
	// Speicher, z. B. auf dem iPhone), steht das Modell beim nächsten Start in kiLlmTooBig und wird übersprungen.
	function lsGet(k, d) {
		try { const v = localStorage.getItem(k); return v ? JSON.parse(v) : d; } catch (e) { return d; }
	}
	function lsSet(k, v) {
		try { if (v === null) localStorage.removeItem(k); else localStorage.setItem(k, JSON.stringify(v)); } catch (e) { }
	}
	// IndexedDB schreibt verlässlich auf die Platte (localStorage kann bei einem Absturz verloren gehen)
	function idb() {
		return new Promise((res) => {
			try {
				const r = indexedDB.open('kiLlm', 1);
				r.onupgradeneeded = () => r.result.createObjectStore('kv');
				r.onsuccess = () => res(r.result);
				r.onerror = () => res(null);
			} catch (e) { res(null); }
		});
	}
	async function idbGet(k, d) {
		const db = await idb();
		if (!db) return d;
		return new Promise((res) => {
			try {
				const q = db.transaction('kv', 'readonly').objectStore('kv').get(k);
				q.onsuccess = () => res(q.result === undefined ? d : JSON.parse(q.result));
				q.onerror = () => res(d);
			} catch (e) { res(d); }
		});
	}
	async function idbSet(k, v) {
		const db = await idb();
		if (!db) return;
		return new Promise((res) => {
			try {
				const tx = db.transaction('kv', 'readwrite', { durability: 'strict' });
				if (v === null) tx.objectStore('kv').delete(k); else tx.objectStore('kv').put(JSON.stringify(v), k);
				tx.oncomplete = () => res();
				tx.onerror = () => res();
				tx.onabort = () => res();
			} catch (e) { res(); }
		});
	}
	async function store(k, v) {
		lsSet(k, v);
		await idbSet(k, v);
	}

	K.tooBig = function () {
		return JSON.stringify(lsGet('kiLlmTooBig', []));
	};
	K.resetTooBig = function () {
		store('kiLlmTooBig', null);
		store('kiLlmPending', null);
		return 'ok';
	};

	K.init = function (cfgJson) {
		if (K.worker) return 'schon';
		const cfg = JSON.parse(cfgJson);
		K.st.models = {};
		K.st.progress = {};
		K.st.error = '';
		try { if (navigator.storage && navigator.storage.persist) navigator.storage.persist(); } catch (e) { }
		try {
			const src = '(' + workerMain.toString() + ')()';
			const url = URL.createObjectURL(new Blob([src], { type: 'text/javascript' }));
			K.worker = new Worker(url, { type: 'module' });
		} catch (e) {
			K.st.state = 'fehler';
			K.st.error = 'Kein Worker: ' + e.message;
			return 'fehler';
		}
		K.st.state = 'laden';
		K.worker.onmessage = (ev) => {
			const m = ev.data;
			if (m.type === 'status') {
				for (const k of ['state', 'device', 'error', 'note']) if (m[k] !== undefined) K.st[k] = m[k];
			} else if (m.type === 'progress') {
				const p = K.st.progress[m.role] || (K.st.progress[m.role] = {});
				p[m.file] = [m.loaded, m.total];
			} else if (m.type === 'trying') {
				store('kiLlmPending', { role: m.role, id: m.id }).then(() => K.worker && K.worker.postMessage({ type: 'go' }));
			} else if (m.type === 'ok') {
				const p = lsGet('kiLlmPending', null);
				if (!p || p.id === m.id) store('kiLlmPending', null);
			} else if (m.type === 'loaded') {
				K.st.models[m.role] = { id: m.id, dtype: m.dtype, device: m.device, shared: !!m.shared };
			} else if (m.type === 'log') {
				K.st.log.push(m.text);
				if (K.st.log.length > 12) K.st.log.shift();
			} else if (m.type === 'result') {
				K.results.push(m);
			}
		};
		K.worker.onerror = (e) => {
			K.st.state = 'fehler';
			K.st.error = 'Worker: ' + (e.message || 'Fehler');
		};
		// Abgestürzte Modelle aus beiden Speichern lesen, dann erst laden
		(async () => {
			const pend = [lsGet('kiLlmPending', null), await idbGet('kiLlmPending', null)];
			const big = [...new Set([...lsGet('kiLlmTooBig', []), ...(await idbGet('kiLlmTooBig', []))])];
			for (const p of pend) {
				const key = p && p.id ? p.role + ':' + p.id : '';
				if (key && !big.includes(key)) {
					big.push(key);
					K.st.log.push('Beim letzten Mal abgestürzt: ' + p.id + ' wird übersprungen.');
				}
			}
			await store('kiLlmTooBig', big);
			await store('kiLlmPending', null);
			cfg.skip = big;
			K.st.skipped = big;
			if (K.worker) K.worker.postMessage({ type: 'init', cfg });
		})();
		return 'ok';
	};

	K.submit = function (jobJson) {
		if (!K.worker) return 'aus';
		K.worker.postMessage({ type: 'job', job: JSON.parse(jobJson) });
		return 'ok';
	};

	K.poll = function () {
		// Ladefortschritt je Modell zusammenfassen
		const prog = {};
		for (const role in K.st.progress) {
			let a = 0, b = 0;
			for (const f in K.st.progress[role]) { a += K.st.progress[role][f][0]; b += K.st.progress[role][f][1]; }
			prog[role] = [a, b];
		}
		const out = JSON.stringify({ status: Object.assign({}, K.st, { progress: prog }), results: K.results });
		K.results = [];
		return out;
	};

	window.KiLlm = K;
})();
