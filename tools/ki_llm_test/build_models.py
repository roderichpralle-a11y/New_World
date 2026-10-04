"""Build two tiny random Llama models with local BPE tokenizers and chat templates."""
import json, os, shutil, subprocess, sys
import torch
from tokenizers import Tokenizer, models, trainers, pre_tokenizers, decoders, normalizers
from transformers import LlamaConfig, LlamaForCausalLM, PreTrainedTokenizerFast, GenerationConfig

ROOT = "/tmp/claude-0/tinyllm"
OUT = f"{ROOT}/models"

TEXT = """
Du bist ein hilfreicher Assistent. Wähle 1 oder 2. Die Antwort ist 1. Die Antwort ist 2.
Guten Morgen! Wie geht es dir heute? Mir geht es gut, danke. Das Wetter ist schön.
Ich möchte einen Kaffee bestellen. Der Hund läuft über die Straße. Die Kinder spielen im Garten.
Bitte antworte kurz und präzise. Welche Option ist besser? Option A oder Option B?
Hello! How are you today? I am fine, thank you. The weather is nice.
You are a helpful assistant. Choose 1 or 2. The answer is 1. The answer is 2.
Please answer briefly and precisely. Which option is better? Option A or option B?
The quick brown fox jumps over the lazy dog. Zwölf Boxkämpfer jagen Viktor quer über den großen Sylter Deich.
Ärger, Öl, Übel, Straße, Füße, schön, hören, Mädchen, Größe. Zahlen: 0 1 2 3 4 5 6 7 8 9 10 42 100 2024.
system user assistant Test Frage Antwort question answer true false ja nein yes no.
""" * 20

COMMON_SPECIALS = ["<unk>", "<pad>"]

TEMPLATES = {
    "tiny-llama": dict(
        bos="<|begin_of_text|>", eos="<|eot_id|>",
        specials=["<|begin_of_text|>", "<|end_of_text|>", "<|start_header_id|>", "<|end_header_id|>", "<|eot_id|>"],
        eos_ids_names=["<|eot_id|>", "<|end_of_text|>"],
        chat_template=(
            "{{ bos_token }}"
            "{% for message in messages %}"
            "{{ '<|start_header_id|>' + message['role'] + '<|end_header_id|>\n\n' + message['content'] | trim + '<|eot_id|>' }}"
            "{% endfor %}"
            "{% if add_generation_prompt %}{{ '<|start_header_id|>assistant<|end_header_id|>\n\n' }}{% endif %}"
        ),
    ),
    "tiny-smol": dict(
        bos="<|im_start|>", eos="<|im_end|>",
        specials=["<|endoftext|>", "<|im_start|>", "<|im_end|>"],
        eos_ids_names=["<|im_end|>"],
        chat_template=(
            "{% for message in messages %}"
            "{{ '<|im_start|>' + message['role'] + '\n' + message['content'] + '<|im_end|>' + '\n' }}"
            "{% endfor %}"
            "{% if add_generation_prompt %}{{ '<|im_start|>assistant\n' }}{% endif %}"
        ),
    ),
}


def build_tokenizer(specials):
    tok = Tokenizer(models.BPE(unk_token=None, byte_fallback=False))
    tok.normalizer = normalizers.NFC()
    # digits split individually, then byte-level
    tok.pre_tokenizer = pre_tokenizers.Sequence([
        pre_tokenizers.Digits(individual_digits=True),
        pre_tokenizers.ByteLevel(add_prefix_space=False, use_regex=True),
    ])
    tok.decoder = decoders.ByteLevel()
    trainer = trainers.BpeTrainer(
        vocab_size=1024,
        special_tokens=COMMON_SPECIALS + specials,
        initial_alphabet=pre_tokenizers.ByteLevel.alphabet(),
        show_progress=False,
    )
    tok.train_from_iterator([TEXT], trainer)
    return tok


def build(name, spec):
    d = f"{OUT}/{name}"
    hfdir = f"{ROOT}/work/{name}-hf"
    shutil.rmtree(d, ignore_errors=True); shutil.rmtree(hfdir, ignore_errors=True)
    os.makedirs(hfdir)

    raw = build_tokenizer(spec["specials"])
    tok = PreTrainedTokenizerFast(
        tokenizer_object=raw, bos_token=spec["bos"], eos_token=spec["eos"],
        unk_token="<unk>", pad_token="<pad>",
        additional_special_tokens=[s for s in spec["specials"] if s not in (spec["bos"], spec["eos"])],
        clean_up_tokenization_spaces=False,
    )
    tok.chat_template = spec["chat_template"]
    # digits single tokens?
    for dgt in "0123456789":
        assert tok.convert_tokens_to_ids(dgt) != tok.unk_token_id, dgt
    assert tok("2024")["input_ids"] == [tok.convert_tokens_to_ids(c) for c in "2024"]

    eos_ids = [tok.convert_tokens_to_ids(t) for t in spec["eos_ids_names"]]
    cfg = LlamaConfig(
        vocab_size=len(tok), hidden_size=64, intermediate_size=128, num_hidden_layers=2,
        num_attention_heads=4, num_key_value_heads=4, max_position_embeddings=512,
        bos_token_id=tok.bos_token_id, eos_token_id=eos_ids if len(eos_ids) > 1 else eos_ids[0],
        pad_token_id=tok.pad_token_id, tie_word_embeddings=True, rope_theta=10000.0,
    )
    torch.manual_seed(0)
    model = LlamaForCausalLM(cfg).eval()
    model.generation_config = GenerationConfig(
        bos_token_id=cfg.bos_token_id, eos_token_id=cfg.eos_token_id, pad_token_id=cfg.pad_token_id,
        do_sample=False, max_new_tokens=32,
    )
    model.save_pretrained(hfdir)
    tok.save_pretrained(hfdir)

    subprocess.run([f"{ROOT}/venv/bin/optimum-cli", "export", "onnx", "--model", hfdir,
                    "--task", "text-generation-with-past", "--opset", "14", f"{ROOT}/work/{name}-onnx"], check=True)

    os.makedirs(f"{d}/onnx")
    src = f"{ROOT}/work/{name}-onnx"
    for f in os.listdir(src):
        if f.endswith(".onnx") or f.endswith(".onnx_data"):
            shutil.copy(f"{src}/{f}", f"{d}/onnx/{f}")
        else:
            shutil.copy(f"{src}/{f}", f"{d}/{f}")
    # ensure chat_template is in tokenizer_config.json (newer transformers may write chat_template.jinja)
    tc_path = f"{d}/tokenizer_config.json"
    tc = json.load(open(tc_path))
    tc["chat_template"] = spec["chat_template"]
    json.dump(tc, open(tc_path, "w"), indent=2, ensure_ascii=False)
    for extra in ("chat_template.jinja",):
        if os.path.exists(f"{d}/{extra}"):
            os.remove(f"{d}/{extra}")
    print(name, "->", d, sorted(os.listdir(d)), sorted(os.listdir(f"{d}/onnx")))


if __name__ == "__main__":
    for n, s in TEMPLATES.items():
        build(n, s)
