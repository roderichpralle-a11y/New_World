# Test der Sprachmodell-Anbindung ohne Internet

`web/ki_llm.js` lässt sich ohne huggingface.co prüfen, mit winzigen Zufallsmodellen im Llama-Format:

1. `build_models.py` baut `tiny-llama` (Llama-3-Chatvorlage) und `tiny-smol` (ChatML) mit ONNX-Export
   (braucht torch, transformers, tokenizers, optimum-onnx in einer venv).
2. `npm i @huggingface/transformers@4.3.0 playwright` (mit `ONNXRUNTIME_NODE_INSTALL=skip`).
3. `node_worker_test.mjs` lädt den Worker-Code in Node (`local_path`), `browser_test.mjs` startet einen
   kleinen Server, Chromium und `index.html` (Worker als Blob-Modul, WASM, `remote_host` statt huggingface.co).

Die Pfade in den Skripten zeigen auf `/tmp/claude-0/tinyllm`; anpassen, wo nötig.
