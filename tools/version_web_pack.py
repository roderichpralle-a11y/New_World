#!/usr/bin/env python3
"""Give a Godot Web pack a build-specific URL without changing engine URLs."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import tempfile


class WebPackError(ValueError):
    """The export cannot safely be rewritten."""


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise WebPackError(f"Duplicate GODOT_CONFIG key: {key}")
        result[key] = value
    return result


def _read_config(html: str):
    matches = list(re.finditer(r"\bconst\s+GODOT_CONFIG\s*=\s*", html))
    if len(matches) != 1:
        raise WebPackError("Expected exactly one const GODOT_CONFIG assignment")
    start = matches[0].end()
    try:
        config, length = json.JSONDecoder(object_pairs_hook=_unique_object).raw_decode(html[start:])
    except json.JSONDecodeError as error:
        raise WebPackError(f"GODOT_CONFIG is not valid JSON: {error}") from error
    end = start + length
    if not isinstance(config, dict) or not re.match(r"\s*;", html[end:]):
        raise WebPackError("Expected a JSON object followed by a semicolon")
    return config, start, end


def version_web_pack(build_dir: Path, revision: str, entry: str | None = None) -> Path:
    """Validate the complete export first, then rename its pack and rewrite URLs.

    This operates on a fresh Godot export only. Re-running it on an already
    versioned or incomplete export fails before changing any output files.
    """
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,79}", revision):
        raise WebPackError("Revision must be 1–80 letters, digits, underscores or hyphens")
    if entry is not None and (
        not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*\.html", entry)
        or entry == "index.html"
    ):
        raise WebPackError("Entry must be a new simple .html filename, such as gang-2.html")

    build_dir = Path(build_dir)
    html_path = build_dir / "index.html"
    worker_path = build_dir / "index.service.worker.js"
    pack_path = build_dir / "index.pck"
    for path in (html_path, worker_path, pack_path):
        if not path.is_file():
            raise WebPackError(f"Missing exported file: {path}")
    pack_name = f"index-{revision}.pck"
    versioned_pack = build_dir / pack_name
    if versioned_pack.exists():
        raise WebPackError(f"Versioned pack already exists: {versioned_pack}")
    if entry is not None and (build_dir / entry).exists():
        raise WebPackError(f"Checkpoint entry already exists: {build_dir / entry}")

    html = html_path.read_text(encoding="utf-8")
    worker = worker_path.read_text(encoding="utf-8")
    config, start, end = _read_config(html)
    if config.get("executable") != "index":
        raise WebPackError("Expected the unchanged Godot executable name 'index'")
    if "mainPack" in config and config["mainPack"] != "index.pck":
        raise WebPackError("GODOT_CONFIG already points at a different mainPack")
    sizes = config.get("fileSizes")
    if not isinstance(sizes, dict) or "index.pck" not in sizes or pack_name in sizes:
        raise WebPackError("Expected an unversioned index.pck fileSizes entry")
    pack_size = sizes["index.pck"]
    if type(pack_size) is not int or pack_size != pack_path.stat().st_size:
        raise WebPackError("The declared pack size does not match index.pck")

    config["mainPack"] = pack_name
    config["fileSizes"] = {
        pack_name if key == "index.pck" else key: value
        for key, value in sizes.items()
    }
    rewritten_html = html[:start] + json.dumps(config, separators=(",", ":")) + html[end:]
    rewritten_worker, replacements = re.subn(
        r"(['\"])index\.pck\1",
        lambda match: match[1] + pack_name + match[1],
        worker,
    )
    if replacements == 0:
        raise WebPackError("Service worker has no quoted index.pck cache entry")
    if entry is not None:
        cached_matches = list(re.finditer(r"\bconst\s+CACHED_FILES\s*=\s*", rewritten_worker))
        if len(cached_matches) != 1:
            raise WebPackError("Expected exactly one service-worker CACHED_FILES array")
        cached_start = cached_matches[0].end()
        try:
            cached_files, cached_length = json.JSONDecoder().raw_decode(rewritten_worker[cached_start:])
        except json.JSONDecodeError as error:
            raise WebPackError("Service-worker CACHED_FILES is not a JSON array") from error
        cached_end = cached_start + cached_length
        if (
            not isinstance(cached_files, list)
            or not cached_files
            or cached_files[0] != "index.html"
            or not all(isinstance(name, str) for name in cached_files)
            or not re.match(r"\s*;", rewritten_worker[cached_end:])
            or entry in cached_files
        ):
            raise WebPackError("Expected the original CACHED_FILES array beginning with index.html")
        # Keep index.html first: the generated worker uses CACHED_FILES[0].
        cached_files.append(entry)
        rewritten_worker = (
            rewritten_worker[:cached_start]
            + json.dumps(cached_files, separators=(",", ":"))
            + rewritten_worker[cached_end:]
        )

    # Stage all small rewritten files before making any destructive changes.
    outputs = {html_path: rewritten_html, worker_path: rewritten_worker}
    if entry is not None:
        outputs[build_dir / entry] = rewritten_html
    staged = []
    try:
        for destination, content in outputs.items():
            with tempfile.NamedTemporaryFile(
                mode="w", encoding="utf-8", dir=build_dir, prefix=".version-pack-", delete=False
            ) as handle:
                handle.write(content)
                staged.append((Path(handle.name), destination))
        pack_path.rename(versioned_pack)
        for temporary, destination in staged:
            temporary.replace(destination)
    finally:
        for temporary, _ in staged:
            temporary.unlink(missing_ok=True)
    return versioned_pack


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("build_dir", type=Path)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--entry", help="Also write a fresh checkpoint HTML entry")
    args = parser.parse_args()
    try:
        output = version_web_pack(args.build_dir, args.revision, args.entry)
    except (WebPackError, OSError, UnicodeError) as error:
        parser.error(str(error))
    print(f"Versioned Godot pack: {output.name}")


if __name__ == "__main__":
    main()
