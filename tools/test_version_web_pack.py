"""Focused export-rewrite checks; run with python -m unittest discover -s tools -p 'test_version_web_pack.py'."""
import json
from pathlib import Path
import re
import tempfile
import unittest

if __package__:
    from .version_web_pack import WebPackError, version_web_pack
else:
    from version_web_pack import WebPackError, version_web_pack


class VersionWebPackTests(unittest.TestCase):
    PACK = b"GDPC\x00\xff\x10pack contents\n"

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.build = Path(self.temporary.name)
        self.config = {
            "executable": "index",
            "args": [],
            "fileSizes": {"index.pck": len(self.PACK), "index.wasm": 1234},
            "serviceWorker": "index.service.worker.js",
        }
        self.write_config(self.config)
        (self.build / "index.pck").write_bytes(self.PACK)
        (self.build / "index.service.worker.js").write_text(
            'const CACHED_FILES = ["index.html", "index.js"];\n'
            "const CACHEABLE_FILES = ['index.pck', 'index.wasm'];\n"
            'const ALSO = ["index.pck", "index.js"];\n', encoding="utf-8"
        )
        (self.build / "index.js").write_bytes(b"unchanged engine loader")
        (self.build / "index.wasm").write_bytes(b"unchanged wasm")

    def write_config(self, config):
        (self.build / "index.html").write_text(
            '<html><script src="index.js"></script><script>\n'
            "const GODOT_CONFIG = " + json.dumps(config) + ";\n"
            "engine.startGame();</script></html>\n", encoding="utf-8"
        )

    def snapshot(self):
        return {path.name: path.read_bytes() for path in self.build.iterdir()}

    def read_config(self):
        html = (self.build / "index.html").read_text(encoding="utf-8")
        return json.loads(re.search(r"const GODOT_CONFIG = (.*);", html)[1])

    def test_versions_pack_and_both_entry_points_without_changing_engine(self):
        pack = version_web_pack(self.build, "b365b38", "gang-2.html")
        self.assertEqual(pack.name, "index-b365b38.pck")
        self.assertEqual(pack.read_bytes(), self.PACK)
        self.assertFalse((self.build / "index.pck").exists())
        config = self.read_config()
        self.assertEqual(config["mainPack"], pack.name)
        self.assertEqual(config["fileSizes"], {pack.name: len(self.PACK), "index.wasm": 1234})
        self.assertEqual(config["executable"], "index")
        self.assertEqual(config["serviceWorker"], "index.service.worker.js")
        worker = (self.build / "index.service.worker.js").read_text(encoding="utf-8")
        self.assertIn("'index-b365b38.pck'", worker)
        self.assertIn('"index-b365b38.pck"', worker)
        self.assertNotIn("'index.pck'", worker)
        self.assertNotIn('"index.pck"', worker)
        cached_files = json.loads(re.search(r"const CACHED_FILES = (.*);", worker)[1])
        self.assertEqual(cached_files, ["index.html", "index.js", "gang-2.html"])
        self.assertEqual((self.build / "gang-2.html").read_bytes(), (self.build / "index.html").read_bytes())
        self.assertEqual((self.build / "index.js").read_bytes(), b"unchanged engine loader")
        self.assertEqual((self.build / "index.wasm").read_bytes(), b"unchanged wasm")

    def test_entry_is_optional(self):
        version_web_pack(self.build, "gang_2")
        self.assertEqual(sorted(path.name for path in self.build.glob("*.html")), ["index.html"])

    def test_unsafe_revisions_and_entries_leave_export_unchanged(self):
        before = self.snapshot()
        for revision in ("", "../bad", "a/b", "a b", "a'bad", ".", "x" * 81):
            with self.subTest(revision=revision), self.assertRaises(WebPackError):
                version_web_pack(self.build, revision, "gang-2.html")
            self.assertEqual(self.snapshot(), before)
        for entry in ("../gang.html", "nested/gang.html", "gang.js", "index.html", "x.html?bad"):
            with self.subTest(entry=entry), self.assertRaises(WebPackError):
                version_web_pack(self.build, "good", entry)
            self.assertEqual(self.snapshot(), before)

    def test_each_missing_required_file_fails_before_any_write(self):
        original = self.snapshot()
        for name in ("index.html", "index.service.worker.js", "index.pck"):
            (self.build / name).unlink()
            before = self.snapshot()
            with self.subTest(missing=name), self.assertRaises(WebPackError):
                version_web_pack(self.build, "good", "gang-2.html")
            self.assertEqual(self.snapshot(), before)
            (self.build / name).write_bytes(original[name])

    def test_missing_worker_token_fails_before_pack_rename(self):
        (self.build / "index.service.worker.js").write_text("const CACHEABLE_FILES = [];", encoding="utf-8")
        before = self.snapshot()
        with self.assertRaises(WebPackError):
            version_web_pack(self.build, "good", "gang-2.html")
        self.assertEqual(self.snapshot(), before)

    def test_checkpoint_requires_valid_original_cached_files_before_any_write(self):
        worker_path = self.build / "index.service.worker.js"
        for cached in ("", "const CACHED_FILES = [];\n", 'const CACHED_FILES = ["wrong.html"];\n'):
            worker_path.write_text(cached + 'const CACHEABLE_FILES = ["index.pck"];\n', encoding="utf-8")
            before = self.snapshot()
            with self.subTest(cached=cached), self.assertRaises(WebPackError):
                version_web_pack(self.build, "good", "gang-2.html")
            self.assertEqual(self.snapshot(), before)

    def test_invalid_or_already_versioned_config_fails_before_any_write(self):
        invalid_configs = [
            dict(self.config, mainPack="index-old.pck"),
            dict(self.config, fileSizes={"index-old.pck": len(self.PACK)}),
            dict(self.config, fileSizes={"index.pck": len(self.PACK) + 1}),
            dict(self.config, executable="other"),
        ]
        for config in invalid_configs:
            self.write_config(config)
            before = self.snapshot()
            with self.subTest(config=config), self.assertRaises(WebPackError):
                version_web_pack(self.build, "good", "gang-2.html")
            self.assertEqual(self.snapshot(), before)

    def test_existing_destination_is_not_overwritten(self):
        (self.build / "gang-2.html").write_bytes(b"existing checkpoint")
        before = self.snapshot()
        with self.assertRaises(WebPackError):
            version_web_pack(self.build, "good", "gang-2.html")
        self.assertEqual(self.snapshot(), before)


if __name__ == "__main__":
    unittest.main()
