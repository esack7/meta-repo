#!/usr/bin/env python3
"""Packed npm artifacts tested against a consumer without enabling delivery tracking."""
import functools
import http.server
import json
import shutil
import sys
import threading
import unittest
from pathlib import Path
import importlib.util

spec = importlib.util.spec_from_file_location("delivery_tests", Path(__file__).with_name("test-delivery.py"))
delivery_tests = importlib.util.module_from_spec(spec)
spec.loader.exec_module(delivery_tests)

PACKAGE = Path(__file__).resolve().parents[1] / ".claude/skills/verify-packages/scripts/verify-packages.py"


class PackageTests(delivery_tests.WorkflowFixture):
    def setUp(self):
        super().setUp()
        self.state_path.unlink()
        self.env["npm_config_cache"] = str(self.base / "npm-cache")

    @unittest.skipUnless(shutil.which("npm"), "npm unavailable")
    def test_package_artifact_and_failed_check_reports(self):
        producer, consumer = self.seeds["a"], self.seeds["b"]
        (producer / "package.json").write_text(
            json.dumps(
                {
                    "name": "fixture-producer",
                    "version": "1.0.0",
                    "main": "dist.js",
                    "files": ["dist.js"],
                    "scripts": {"compile": "node build.js"},
                }
            )
        )
        (producer / "build.js").write_text(
            "require('fs').writeFileSync('dist.js', 'module.exports = 42;');"
        )
        self.call(
            "npm",
            "install",
            "--package-lock-only",
            "--ignore-scripts",
            "--no-audit",
            cwd=producer,
        )
        # The baseline uses a locally packed old release so this fixture needs no registry.
        (producer / "dist.js").write_text("module.exports = 7;")
        packed = json.loads(
            self.call("npm", "pack", "--json", "--ignore-scripts", cwd=producer)
        )
        tarball = producer / packed[0]["filename"]
        (consumer / "package.json").write_text(
            json.dumps(
                {
                    "name": "fixture-consumer",
                    "version": "1.0.0",
                    "dependencies": {"fixture-producer": "file:" + str(tarball)},
                    "scripts": {
                        "prepare": "node prepare.js",
                        "test": "node test.js",
                        "fail": 'node -e "process.exit(1)"',
                        "baseline": "node -e \"require('assert').strictEqual(require('fixture-producer'), 7)\"",
                    },
                }
            )
        )
        self.env["EXPECTED_VALUE"] = "42"
        (consumer / "prepare.js").write_text(
            "require('assert').strictEqual(require('fixture-producer'), Number(process.env.EXPECTED_VALUE));"
        )
        (consumer / "test.js").write_text(
            "require('assert').strictEqual(require('fixture-producer'), 42);"
        )
        self.call(
            "npm",
            "install",
            "--package-lock-only",
            "--ignore-scripts",
            "--no-audit",
            cwd=consumer,
        )

        class QuietHandler(http.server.SimpleHTTPRequestHandler):
            def log_message(self, *args):
                pass

        server = http.server.ThreadingHTTPServer(
            ("127.0.0.1", 0), functools.partial(QuietHandler, directory=str(producer))
        )
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        app = json.loads((consumer / "package.json").read_text())
        app["dependencies"]["fixture-producer"] = "1.0.0"
        (consumer / "package.json").write_text(json.dumps(app))
        lock = json.loads((consumer / "package-lock.json").read_text())
        lock["packages"][""]["dependencies"]["fixture-producer"] = "1.0.0"
        lock["packages"]["node_modules/fixture-producer"]["resolved"] = (
            f"http://127.0.0.1:{server.server_port}/{tarball.name}"
        )
        (consumer / "package-lock.json").write_text(json.dumps(lock))
        shas = []
        for repo, name in [(producer, "a"), (consumer, "b")]:
            self.git(repo, "add", "package.json", "package-lock.json")
            self.git(repo, "add", "build.js" if name == "a" else "test.js")
            if name == "b":
                self.git(repo, "add", "prepare.js")
            self.git(repo, "commit", "-m", "npm fixture")
            self.git(repo, "push", "origin", "main")
            self.git(self.ref(name), "fetch", "origin")
            shas.append(self.git(repo, "rev-parse", "HEAD"))
        before = self.git(self.ref("b"), "status", "--porcelain")
        report = self.base / "candidate.json"
        args = [
            sys.executable,
            PACKAGE,
            self.map,
            "example",
            "a",
            "b",
            "--producer-commit",
            shas[0],
            "--consumer-commit",
            shas[1],
            "--producer-build-script",
            "compile",
            "--check",
            "test",
            "--report",
            report,
        ]
        self.call(*args)
        result = json.loads(report.read_text())
        self.assertTrue(result["passed"])
        self.assertEqual(len(result["artifact_sha256"]), 64)
        self.assertEqual(before, self.git(self.ref("b"), "status", "--porcelain"))
        self.call(*args, ok=False)  # Never overwrite an existing report.
        args[-1] = self.base / "failed.json"
        self.call(*args, "--check", "fail", ok=False)
        self.assertFalse(json.loads(args[-1].read_text())["passed"])
        self.env["EXPECTED_VALUE"] = "7"
        args[-1] = self.base / "published.json"
        self.call(
            *args, "--mode", "published", ok=False
        )  # Baseline exports 7, candidate exports 42.
        args[-1] = self.base / "published-pass.json"
        args[args.index("--check") + 1] = "baseline"
        self.call(*args, "--mode", "published")
        self.assertTrue(json.loads(args[-1].read_text())["passed"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
