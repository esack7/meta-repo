#!/usr/bin/env python3
"""Behavioral tests using isolated real repositories and npm package fixtures."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SKILLS = ROOT / ".claude/skills"
ENGINE = SKILLS / "_shared/delivery.py"
spec = importlib.util.spec_from_file_location("delivery", ENGINE)
delivery = importlib.util.module_from_spec(spec)
spec.loader.exec_module(delivery)


class WorkflowFixture(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="delivery tests ")
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()
        self.root = self.base / "meta"
        self.root.mkdir()
        self.env = dict(
            os.environ,
            GIT_AUTHOR_NAME="Fixture",
            GIT_AUTHOR_EMAIL="fixture@example.test",
            GIT_COMMITTER_NAME="Fixture",
            GIT_COMMITTER_EMAIL="fixture@example.test",
            GIT_CONFIG_NOSYSTEM="1",
            GIT_CONFIG_GLOBAL=os.devnull,
        )
        self.map = self.root / "project-repositories.yaml"
        lines = ["version: 1", "repositories:"]
        self.seeds = {}
        for name in ["a", "b"]:
            origin = self.base / (name + ".git")
            seed = self.base / (name + "-seed")
            self.call("git", "init", "--bare", origin)
            self.call("git", "init", "-b", "main", seed)
            (seed / "README.md").write_text(name)
            self.git(seed, "add", ".")
            self.git(seed, "commit", "-m", "initial")
            self.git(seed, "remote", "add", "origin", origin)
            self.git(seed, "push", "origin", "main")
            self.git(origin, "symbolic-ref", "HEAD", "refs/heads/main")
            self.seeds[name] = seed
            lines += [
                f"  - name: {name}",
                "    git:",
                f"      clone_url: {origin}",
                "      default_branch: main",
            ]
        self.map.write_text("\n".join(lines) + "\n")
        self.helper("setup-repositories")
        self.helper("create-spec", "example", "a", "b")
        self.directory = self.root / "specs/example"
        self.state_path = self.directory / "delivery.json"
        self.helper("prepare-spec", "example")
        self.engine("init")
        self.data = json.loads(self.state_path.read_text())
        self.data["criteria"] = {"a1": "observable behavior"}
        self.data["working_agreement"] = "Implement and prepare PRs; no publication."
        self.data["slices"] = [self.slice("first", "a")]
        self.save()

    def call(self, *args, ok=True, cwd=None):
        p = subprocess.run(
            [str(x) for x in args],
            text=True,
            capture_output=True,
            env=self.env,
            cwd=cwd,
        )
        if ok:
            self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        else:
            self.assertNotEqual(p.returncode, 0, p.stdout + p.stderr)
        return p.stdout + p.stderr

    def git(self, cwd, *args):
        return self.call("git", "-C", cwd, *args).strip()

    def helper(self, name, *args, ok=True):
        return self.call(
            "sh", SKILLS / name / "scripts" / (name + ".sh"), self.map, *args, ok=ok
        )

    def engine(self, *args, ok=True):
        return self.call(sys.executable, ENGINE, self.map, "example", *args, ok=ok)

    def slice(self, sid, repo, depends=None):
        return dict(
            id=sid,
            repo=repo,
            depends_on=depends or [],
            criteria=["a1"],
            status="planned",
            branch=None,
            pr=None,
            evidence={},
            note="next action",
        )

    def save(self):
        self.state_path.write_text(json.dumps(self.data))

    def reload(self):
        self.data = json.loads(self.state_path.read_text())

    def wt(self, name="a"):
        return self.directory / "repos" / name

    def ref(self, name="a"):
        return self.root / "repos" / name

    def change(self, name="a"):
        wt = self.wt(name)
        path = wt / "change.txt"
        path.write_text(path.read_text() + "more\n" if path.exists() else "new\n")
        self.git(wt, "add", ".")
        self.git(wt, "commit", "-m", "change")
        return self.git(wt, "rev-parse", "HEAD")

    def start(self):
        self.engine("start", "first")
        self.reload()

    def verified(self):
        s = self.data["slices"][0]
        s["status"] = "verified"
        s["evidence"] = {
            "a1": {
                "commit": self.git(self.wt(), "rev-parse", "HEAD"),
                "check": "fixture assertion passed",
            }
        }
        self.save()

    def fake_gh(self, **overrides):
        s = self.data["slices"][0]
        response = dict(
            state="MERGED",
            headRefName=s["branch"],
            headRefOid=self.git(self.wt(), "rev-parse", "HEAD"),
            baseRefName="main",
            mergeCommit={"oid": self.git(self.ref(), "rev-parse", "origin/main")},
            url="https://example.test/pull/1",
        )
        response.update(overrides)
        bin_dir = self.base / "bin"
        bin_dir.mkdir(exist_ok=True)
        (bin_dir / "gh").write_text('#!/bin/sh\ncat "$GH_FIXTURE"\n')
        (bin_dir / "gh").chmod(0o755)
        fixture = self.base / "gh.json"
        fixture.write_text(json.dumps(response))
        self.env.update(
            PATH=str(bin_dir) + os.pathsep + self.env["PATH"], GH_FIXTURE=str(fixture)
        )
        self.data["slices"][0]["pr"] = 1
        self.save()


class WorkflowTests(WorkflowFixture):
    def test_custom_branch_prefix(self):
        self.engine("start", "first", "--branch-prefix", "team")
        self.assertEqual(self.git(self.wt(), "branch", "--show-current"), "team/example-first")

    def test_tracking_requires_explicit_initialization(self):
        self.helper("create-spec", "plain", "a")
        plain = self.root / "specs/plain"
        self.assertFalse((plain / "delivery.json").exists())
        self.helper("prepare-spec", "plain")
        self.helper("close-spec", "plain")
        self.assertFalse((plain / "repos/a").exists())

    def test_invalid_delivery_entries_block_lifecycle_helpers(self):
        original = self.state_path.read_bytes()
        for entry in ("dangling", "directory", "invalid-json", "invalid-schema"):
            with self.subTest(entry=entry):
                self.state_path.unlink()
                if entry == "dangling":
                    self.state_path.symlink_to(self.base / "missing.json")
                elif entry == "directory":
                    self.state_path.mkdir()
                elif entry == "invalid-json":
                    self.state_path.write_text("{")
                else:
                    self.state_path.write_text('{"slices": []}')
                self.helper("prepare-spec", "example", ok=False)
                self.helper("close-spec", "example", ok=False)
                self.helper("close-spec", "example", "--worktrees-only", ok=False)
                self.assertTrue(self.wt().exists())
                self.assertTrue(self.wt("b").exists())
                if self.state_path.is_dir():
                    self.state_path.rmdir()
                    self.state_path.write_bytes(original)
                else:
                    self.state_path.unlink()
                    self.state_path.write_bytes(original)

    def test_invalid_delivery_blocks_preparation_amendment(self):
        self.helper("create-spec", "unprepared", "a")
        directory = self.root / "specs/unprepared"
        record = directory / "delivery.json"
        selection = (directory / "repos.txt").read_bytes()
        for value in ('{"slices": []}', '{'):
            record.write_text(value)
            self.helper("create-spec", "unprepared", "--amend", "b", ok=False)
            self.assertEqual((directory / "repos.txt").read_bytes(), selection)
        record.unlink()
        record.symlink_to(self.base / "missing.json")
        self.helper("create-spec", "unprepared", "--amend", "b", ok=False)
        self.assertEqual((directory / "repos.txt").read_bytes(), selection)

    def test_status_read_only_and_incomplete_close(self):
        before = self.state_path.read_bytes()
        result = json.loads(self.engine("status", "--json"))
        self.assertEqual(result["completion"], "incomplete")
        self.assertEqual(before, self.state_path.read_bytes())
        self.assertIn(
            "delivery is incomplete", self.helper("close-spec", "example", ok=False)
        )
        self.assertTrue(self.wt().exists())
        self.assertTrue(self.wt("b").exists())

    def test_slice_start_preserves_branch_and_prepare_is_idempotent(self):
        baseline = self.git(self.ref(), "rev-parse", "origin/main")
        self.start()
        self.assertEqual(
            self.git(self.wt(), "branch", "--show-current"), "codex/example-first"
        )
        self.assertEqual(self.git(self.ref(), "rev-parse", "feature/example"), baseline)
        self.helper("prepare-spec", "example")
        self.assertFalse((self.directory / ".delivery.lock").exists())
        self.engine("start", "first", ok=False)

    def test_reopen_prefers_actual_active_slice_over_array_order(self):
        self.data["slices"].append(self.slice("second", "a"))
        self.save()
        self.engine("start", "second")
        self.reload()
        self.change()
        self.git(self.wt(), "push", "origin", "HEAD:main")
        self.data["slices"][1]["status"] = "merged"
        self.save()
        self.engine("start", "first")
        self.reload()
        self.assertEqual(self.data["slices"][0]["start_order"], 2)
        self.assertEqual(self.data["slices"][1]["start_order"], 1)
        self.helper("close-spec", "example", "--worktrees-only")
        self.helper("prepare-spec", "example", "--reuse-branches")
        self.assertEqual(
            self.git(self.wt(), "branch", "--show-current"), "codex/example-first"
        )
        self.data["slices"][0]["status"] = "merged"
        self.save()
        self.helper("close-spec", "example", "--worktrees-only")
        self.helper("prepare-spec", "example", "--reuse-branches")
        self.assertEqual(
            self.git(self.wt(), "branch", "--show-current"), "codex/example-first"
        )

    def test_unpushed_error_names_checked_out_slice_branch(self):
        self.start()
        self.change()
        output = self.helper("close-spec", "example", "--worktrees-only", ok=False)
        self.assertIn("has unpushed commits on codex/example-first", output)
        self.assertNotIn("has unpushed commits on feature/example", output)

    def test_dirty_and_lock_refusals_preserve_state(self):
        before = self.state_path.read_bytes()
        (self.wt() / "untracked").write_text("keep")
        self.engine("start", "first", ok=False)
        self.assertEqual(before, self.state_path.read_bytes())
        lock = self.directory / ".delivery.lock"
        lock.mkdir()
        self.engine("start", "first", ok=False)
        self.assertTrue(lock.exists())

    def test_dependencies_and_unregistered_branch_refused(self):
        self.data["slices"].append(self.slice("second", "b", ["first"]))
        self.save()
        self.engine("start", "second", ok=False)
        self.git(self.wt(), "checkout", "-b", "unrelated")
        self.engine("start", "first", ok=False)
        self.helper("close-spec", "example", "--worktrees-only", ok=False)
        self.assertTrue(self.wt("b").exists())

    def test_invalid_evidence_and_cycles_refused(self):
        self.data["slices"][0]["depends_on"] = ["first"]
        self.save()
        self.engine("status", ok=False)
        self.data["slices"][0]["depends_on"] = []
        self.save()
        self.start()
        self.verified()
        self.data["slices"][0]["evidence"]["a1"]["commit"] = "0" * 40
        self.save()
        self.assertIn("evidence is missing", self.engine("status"))
        self.helper("close-spec", "example", ok=False)

    def test_verified_merge_close_and_reopen(self):
        self.start()
        head = self.change()
        self.git(self.wt(), "push", "origin", "HEAD:main")
        self.verified()
        self.helper("close-spec", "example")
        self.assertFalse(self.wt().exists())
        self.assertEqual(head, self.git(self.ref(), "rev-parse", "codex/example-first"))
        self.helper("prepare-spec", "example", ok=False)
        output = self.helper("prepare-spec", "example", "--reuse-branches")
        self.assertTrue(self.wt().exists(), output)
        self.assertEqual(
            self.git(self.wt(), "branch", "--show-current"), "codex/example-first"
        )

    def squash(self):
        self.start()
        self.change()
        self.change()
        self.git(self.ref(), "merge", "--squash", "codex/example-first")
        self.git(self.ref(), "commit", "-m", "squash")
        self.git(self.ref(), "push", "origin", "main")
        self.verified()
        self.fake_gh()

    def test_squash_merge_exact_head_allows_cleanup(self):
        self.squash()
        self.helper("close-spec", "example")
        self.assertFalse(self.wt().exists())

    def test_extra_local_commit_and_wrong_pr_base_block_cleanup(self):
        self.squash()
        self.change()
        self.helper("close-spec", "example", ok=False)
        self.fake_gh(baseRefName="other")
        self.helper("close-spec", "example", ok=False)
        self.assertTrue(self.wt("b").exists())

    def test_later_commits_invalidate_acceptance_evidence(self):
        self.start()
        self.verified()
        self.change()
        self.assertIn("evidence is stale", self.engine("status"))
        self.helper("close-spec", "example", ok=False)

    def test_remote_drift_is_reported_without_rewriting_state(self):
        self.start()
        self.data["slices"][0]["status"] = "review"
        self.fake_gh()
        before = self.state_path.read_bytes()
        result = json.loads(self.engine("status", "--remote", "--json"))
        self.assertIn("differs from GitHub", result["slices"][0]["warning"])
        self.assertEqual(before, self.state_path.read_bytes())

    def test_next_slice_requires_actual_merge(self):
        self.start()
        self.change()
        self.data["slices"][0]["status"] = "merged"
        self.data["slices"].append(self.slice("second", "a", ["first"]))
        self.save()
        self.engine("start", "second", ok=False)
        self.git(self.wt(), "push", "origin", "HEAD:main")
        self.engine("start", "second")
        self.assertEqual(
            self.git(self.wt(), "branch", "--show-current"), "codex/example-second"
        )

    def test_state_write_failure_rolls_back_new_branch(self):
        args = delivery.parser().parse_args(
            [str(self.map), "example", "start", "first"]
        )
        with patch.object(delivery, "atomic_json", side_effect=OSError("disk full")):
            with self.assertRaises(OSError):
                delivery.execute(args)
        self.assertEqual(
            self.git(self.wt(), "branch", "--show-current"), "feature/example"
        )
        self.assertNotIn(
            "codex/example-first", self.git(self.ref(), "branch", "--list")
        )
        self.assertEqual(
            json.loads(self.state_path.read_text())["slices"][0]["status"], "planned"
        )

    def test_legacy_and_explicit_early_cleanup(self):
        self.helper("close-spec", "example", "--offline", ok=False)
        self.helper("close-spec", "example", "--offline", "--worktrees-only")
        self.assertEqual(
            json.loads(self.state_path.read_text())["slices"][0]["status"], "planned"
        )
        self.state_path.unlink()
        self.helper("prepare-spec", "example", "--reuse-branches")
        self.assertIn("delivery tracking is disabled", self.helper("close-spec", "example"))

    def test_amend_refuses_populated_delivery_and_symlinks(self):
        self.helper("create-spec", "example", "--amend", "a", ok=False)
        external = self.base / "state.json"
        self.state_path.rename(external)
        self.state_path.symlink_to(external)
        self.engine("status", ok=False)



if __name__ == "__main__":
    unittest.main(verbosity=2)
