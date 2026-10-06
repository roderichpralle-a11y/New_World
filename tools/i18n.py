"""Uebersetzungen pflegen (Quelltext deutsch, data/i18n/en.json = Deutsch -> Englisch).

  python3 tools/i18n.py wrap     deutsche Texte im Code in tr()/Loc.t() einpacken (wiederholbar)
  python3 tools/i18n.py missing  Texte ohne englische Uebersetzung nach data/i18n/missing.json
  python3 tools/i18n.py check    Platzhalter (%s, %d, ...) in en.json pruefen

Texte, die nicht uebersetzt werden duerfen (Bus-Namen, Siedlernamen), stehen in SKIP.
"""
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EN = os.path.join(ROOT, "data", "i18n", "en.json")
SKIP_FILES = {"scripts/ui/ui_theme.gd", "scripts/autoload/loc.gd", "scripts/autoload/sound.gd"}
SKIP = {"Lena", "Jonas", "Kim", "Insel%d", "Sprache / Language", "Deutsch", "English"}
TEXT_KEYS = {"name", "desc", "text", "hint", "verb", "sow_verb", "harvest_verb", "names", "_tiers",
             "comfort_stages", "low", "high", "plural", "plural_dat", "by", "food_name", "deadly"}
LIT = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
GERMAN = re.compile(r"[A-ZÄÖÜ][a-zäöüß]|[äöüßÄÖÜ]|\s[a-zäöü]{2}")
SKIP_LINE = re.compile(r"^\s*(#|@|class_name|extends|signal|enum)|create_from_string\(|JavaScriptBridge\.eval\(|print\(|printerr\(|push_error\(|push_warning\(|preload\(|\bload\(")


def unescape(s):
    return s.encode("utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8")


# Kleingeschriebene Einzelwoerter sehen aus wie IDs; diese hier sind Anzeigetext.
WORDS = {"angehalten", "bezahlt", "durchschnittlich", "jetzt", "erreicht", "keine", "klein", "mittel",
         "krank", "krank: %s", "nichts", "niemand", "unzufrieden", "verzweifelt", "zufrieden", "verhungert"}


def is_text(t):
    if not t or t in SKIP or t.startswith(("res://", "user://", "#")):
        return False
    return t in WORDS or bool(GERMAN.search(t))


def gd_files():
    for f in sorted(glob.glob(os.path.join(ROOT, "scripts", "**", "*.gd"), recursive=True)):
        rel = os.path.relpath(f, ROOT)
        if rel not in SKIP_FILES:
            yield f, rel


def iter_code(lines):
    """Liefert (zeilennr, zeile, statisch, ueberspringen) und merkt sich const-Bloecke und \"\"\"-Texte."""
    static = False
    depth = 0
    in_triple = False
    for i, line in enumerate(lines):
        st = line.strip()
        if in_triple:
            if '"""' in line:
                in_triple = False
            yield i, line, static, True
            continue
        if line.count('"""') == 1:
            in_triple = True
            yield i, line, static, True
            continue
        if re.match(r"^(static )?func ", line):
            static = line.startswith("static func")
        if depth > 0 or st.startswith("const ") or re.match(r"^\s*(static\s+)?func ", line):
            depth += line.count("[") + line.count("{") + line.count("(") - line.count("]") - line.count("}") - line.count(")")
            if not re.match(r"^\s*(static\s+)?func ", line) or depth < 0:
                pass
            depth = max(depth, 0) if (st.startswith("const ") or depth > 0) else 0
            yield i, line, static, True
            continue
        yield i, line, static, bool(SKIP_LINE.search(line))


def wrap():
    changed = 0
    for f, rel in gd_files():
        lines = open(f, encoding="utf-8").read().split("\n")
        out = list(lines)
        for i, line, static, skip in iter_code(lines):
            if skip:
                continue
            new = []
            pos = 0
            for m in LIT.finditer(line):
                t = m.group(1)
                before = line[:m.start()]
                if not is_text(unescape(t)) or re.search(r"(\btr|Loc\.t|Loc\.name_of|tr_n)\(\s*$", before):
                    continue
                if line[m.end():].lstrip().startswith(":") and not line[m.end():].lstrip().startswith(":="):
                    continue  # Schluessel in einem Dictionary
                fn = "Loc.t" if static else "tr"
                new.append(line[pos:m.start()] + "%s(%s)" % (fn, m.group(0)))
                pos = m.end()
            if new:
                out[i] = "".join(new) + line[pos:]
                changed += 1
        if out != lines:
            open(f, "w", encoding="utf-8").write("\n".join(out))
    print("Zeilen geaendert:", changed)


def collect():
    keys = {}
    for f, rel in gd_files():
        lines = open(f, encoding="utf-8").read().split("\n")
        text = "\n".join(lines)
        # tr("...") / Loc.t("...") ueberall, auch in Konstanten
        for m in re.finditer(r'(?:\btr|Loc\.t|Loc\.name_of)\(\s*"((?:[^"\\\n]|\\.)*)"', text):
            keys.setdefault(unescape(m.group(1)), rel)
        # Texte in Konstanten und """-Bloecken, die zur Laufzeit uebersetzt werden
        for m in re.finditer(r'"""(.*?)"""', text, re.S):
            if re.search(r"eval\(\s*$", text[:m.start()]):
                continue  # JavaScript fuer den Browser, kein Text
            keys.setdefault(m.group(1), rel)
        for i, line, static, skip in iter_code(lines):
            if skip and not SKIP_LINE.search(line) and not re.match(r"^\s*(static\s+)?func ", line):
                for m in LIT.finditer(line):
                    if is_text(unescape(m.group(1))):
                        keys.setdefault(unescape(m.group(1)), rel)
    for f in sorted(glob.glob(os.path.join(ROOT, "data", "*.json"))):
        if f.endswith("names.json"):
            continue
        rel = os.path.relpath(f, ROOT)

        def walk(o, key=""):
            if isinstance(o, dict):
                for k, v in o.items():
                    walk(v, k if k in TEXT_KEYS else "")
            elif isinstance(o, list):
                for v in o:
                    walk(v, key)
            elif isinstance(o, str) and key and o.strip():
                keys.setdefault(o, rel)
        walk(json.load(open(f, encoding="utf-8")))
    return keys


def missing():
    en = json.load(open(EN, encoding="utf-8"))
    keys = collect()
    miss = {k: v for k, v in keys.items() if not en.get(k)}
    path = os.path.join(ROOT, "data", "i18n", "missing.json")
    json.dump(miss, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("Texte gesamt: %d, ohne Uebersetzung: %d (siehe data/i18n/missing.json)" % (len(keys), len(miss)))
    return miss


def check():
    en = json.load(open(EN, encoding="utf-8"))
    ph = re.compile(r"%[-0-9.]*[sdf%]")
    bad = 0
    for k, v in en.items():
        if v and sorted(ph.findall(k)) != sorted(ph.findall(v)):
            print("Platzhalter passen nicht:", repr(k), "->", repr(v))
            bad += 1
    print("Pruefung:", "ok" if bad == 0 else "%d Fehler" % bad)
    return bad


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "missing"
    {"wrap": wrap, "missing": missing, "check": check}[cmd]()
