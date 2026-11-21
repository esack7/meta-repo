#!/usr/bin/env python3
"""Tracked delivery state and guarded slice operations. Python standard library only."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

SHARED = Path(__file__).resolve().parent
STATES = {"planned", "implementing", "review", "blocked", "merged", "verified"}
SLUG = r"[a-z0-9][a-z0-9-]*"


def run(*args, cwd=None):
    p = subprocess.run([str(a) for a in args], cwd=cwd, text=True, capture_output=True)
    if p.returncode:
        raise ValueError(
            p.stderr.strip() or p.stdout.strip() or f"command failed: {args[0]}"
        )
    return p.stdout.strip()


def git(path, *args):
    return run("git", "-C", path, *args)


def atomic_json(path, value):
    fd, tmp = tempfile.mkstemp(prefix=".delivery-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(value, f, indent=2)
            f.write("\n")
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


class Delivery:
    def __init__(self, project_map, spec):
        if not re.fullmatch(SLUG, spec):
            raise ValueError("invalid spec name")
        self.project_map = Path(project_map).resolve(strict=True)
        self.root = self.project_map.parent
        expected = self.root / "specs" / spec
        self.directory = expected.resolve(strict=True)
        if self.directory != expected:
            raise ValueError("spec directory must not be a symlink")
        self.path = self.directory / "delivery.json"
        if self.path.is_symlink():
            raise ValueError("delivery.json must not be a symlink")
        self.spec = spec
        names = run(
            "sh",
            SHARED / "parse-repos-txt.sh",
            self.directory / "repos.txt",
            "--validate-map",
            self.project_map,
        ).splitlines()
        self.repos = {}
        for name in names:
            record = run(
                "sh", SHARED / "extract-project-map.sh", self.project_map, "--get", name
            ).split("\t")
            self.repos[name] = {"url": record[1], "default": record[2]}

    def load(self):
        if not self.path.exists():
            raise ValueError(
                "delivery tracking is disabled: initialize delivery.json with spec-status ... init, then record its slices and evidence"
            )
        data = json.loads(self.path.read_text())
        self.validate(data)
        return data

    def validate(self, data):
        if not isinstance(data, dict):
            raise ValueError("delivery record must be an object")
        if data.get("version") != 1 or data.get("spec") != self.spec:
            raise ValueError("unsupported delivery version or mismatched spec")
        if not isinstance(data.get("criteria"), dict) or not isinstance(
            data.get("slices"), list
        ):
            raise ValueError("criteria must be an object and slices an array")
        for key, description in data["criteria"].items():
            if (
                not re.fullmatch(SLUG, key)
                or not isinstance(description, str)
                or not description.strip()
            ):
                raise ValueError("criteria need slug IDs and nonempty descriptions")
        seen, branches, start_orders = set(), set(), set()
        for s in data["slices"]:
            if not isinstance(s, dict):
                raise ValueError("each slice must be an object")
            sid = s["id"]
            if not re.fullmatch(SLUG, sid) or sid in seen:
                raise ValueError("invalid or duplicate slice ID")
            # Ordered dependencies eliminate cycles and make next-action selection stable.
            if not isinstance(s["depends_on"], list) or any(
                d not in seen for d in s["depends_on"]
            ):
                raise ValueError(f"{sid}: dependencies must reference earlier slices")
            seen.add(sid)
            if s["repo"] not in self.repos or s["status"] not in STATES:
                raise ValueError(f"{sid}: invalid repo or status")
            if (
                not isinstance(s["criteria"], list)
                or not s["criteria"]
                or any(c not in data["criteria"] for c in s["criteria"])
            ):
                raise ValueError(f"{sid}: assign known acceptance criteria")
            if s.get("pr") is not None and (type(s["pr"]) is not int or s["pr"] <= 0):
                raise ValueError(
                    "PR must be a positive number in the selected repository"
                )
            start_order = s.get("start_order")
            if start_order is not None:
                if (
                    type(start_order) is not int
                    or start_order <= 0
                    or start_order in start_orders
                    or not s.get("branch")
                ):
                    raise ValueError(
                        f"{sid}: start_order must be a unique positive integer on a started slice"
                    )
                start_orders.add(start_order)
            branch = s.get("branch")
            if branch:
                run("git", "check-ref-format", "--branch", branch)
                if (
                    branch == self.repos[s["repo"]]["default"]
                    or (s["repo"], branch) in branches
                ):
                    raise ValueError(
                        "slice branches must be unique and cannot be the default branch"
                    )
                branches.add((s["repo"], branch))
            if (
                s["status"] in {"implementing", "review", "merged", "verified"}
                and not branch
            ):
                raise ValueError(f"{sid}: status requires a registered branch")
            evidence = s.get("evidence", {})
            if not isinstance(evidence, dict):
                raise ValueError("evidence must be an object")
            for criterion, item in evidence.items():
                if (
                    criterion not in s["criteria"]
                    or not re.fullmatch(r"[0-9a-f]{40}", item["commit"])
                    or not item["check"].strip()
                ):
                    raise ValueError(
                        f"{sid}: invalid evidence; use a full commit and concrete check"
                    )
            if s["status"] == "verified" and set(evidence) != set(s["criteria"]):
                raise ValueError(
                    f"{sid}: verified requires evidence for every assigned criterion"
                )
            if s["status"] == "blocked" and not s.get("note", "").strip():
                raise ValueError(f"{sid}: blocked requires a reason and next action")
        if not isinstance(data.get("working_agreement"), str):
            raise ValueError("working_agreement must record the user-authorized scope")

    def paths(self, name):
        ref = self.root / "repos" / name
        wt = self.directory / "repos" / name
        for path in (ref, wt):
            if path.resolve() != path:
                raise ValueError(f"unsafe repository path: {path}")
        if git(ref, "remote", "get-url", "origin") != self.repos[name]["url"]:
            raise ValueError(f"origin mismatch: {name}")
        return ref, wt

    def registered_worktree(self, name):
        ref, wt = self.paths(name)
        if f"worktree {wt}\n" not in git(ref, "worktree", "list", "--porcelain") + "\n":
            raise ValueError(
                f"{name}: expected registered worktree at {wt}; run prepare-spec"
            )
        return ref, wt

    def evidence_errors(self, data):
        errors = []
        for s in data["slices"]:
            if s["status"] != "verified":
                continue
            try:
                ref, _ = self.paths(s["repo"])
                head = git(ref, "rev-parse", "refs/heads/" + s["branch"])
                for e in s["evidence"].values():
                    if e["commit"] != head:
                        raise ValueError(
                            "evidence is stale for the current branch head"
                        )
                    git(ref, "cat-file", "-e", e["commit"] + "^{commit}")
                    git(
                        ref,
                        "merge-base",
                        "--is-ancestor",
                        e["commit"],
                        "refs/heads/" + s["branch"],
                    )
            except ValueError as exc:
                errors.append(
                    f"{s['id']}: evidence is missing or no longer on its branch: {exc}"
                )
        return errors

    def completion_errors(self, data):
        errors = self.evidence_errors(data)
        if not data["criteria"] or not data["slices"]:
            errors.append(
                "acceptance criteria and delivery slices have not been planned"
            )
        for s in data["slices"]:
            if s["status"] != "verified":
                errors.append(
                    f"{s['id']}: {s['status']} (needs merged work and verified evidence)"
                )
        covered = {
            c
            for s in data["slices"]
            if s["status"] == "verified"
            for c in s["criteria"]
        }
        errors.extend(
            f"{c}: no verified slice" for c in data["criteria"] if c not in covered
        )
        return errors

    def pr_state(self, s):
        if not s.get("pr"):
            raise ValueError(f"{s['id']}: no PR recorded")
        ref, _ = self.paths(s["repo"])
        p = json.loads(
            run(
                "gh",
                "pr",
                "view",
                str(s["pr"]),
                "--json",
                "state,headRefName,headRefOid,baseRefName,mergeCommit,url",
                cwd=ref,
            )
        )
        if (
            p["headRefName"] != s["branch"]
            or p["baseRefName"] != self.repos[s["repo"]]["default"]
        ):
            raise ValueError(f"{s['id']}: PR branch/base mismatch")
        head = git(ref, "rev-parse", "refs/heads/" + s["branch"])
        if p["headRefOid"] != head:
            raise ValueError(f"{s['id']}: PR head differs from retained local branch")
        return p

    def merged(self, s):
        ref, _ = self.paths(s["repo"])
        base = "refs/remotes/origin/" + self.repos[s["repo"]]["default"]
        head = git(ref, "rev-parse", "refs/heads/" + s["branch"])
        try:
            git(ref, "merge-base", "--is-ancestor", head, base)
        except ValueError:
            p = self.pr_state(s)
            if p["state"] != "MERGED" or not p.get("mergeCommit"):
                raise ValueError(f"{s['id']}: PR is not merged")
            git(ref, "merge-base", "--is-ancestor", p["mergeCommit"]["oid"], base)


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("project_map")
    p.add_argument("spec")
    sub = p.add_subparsers(dest="command", required=True)
    sub.add_parser("init")
    status = sub.add_parser("status")
    status.add_argument(
        "--remote",
        action="store_true",
        help="query GitHub; never fetch or mutate state",
    )
    status.add_argument("--json", action="store_true")
    start = sub.add_parser("start")
    start.add_argument("slice")
    start.add_argument("--branch-prefix", default="codex", help="branch namespace, default codex")
    close = sub.add_parser("check-close")
    close.add_argument("--offline", action="store_true")
    close.add_argument("--worktrees-only", action="store_true")
    active = sub.add_parser("active-branch")
    active.add_argument("repo")
    branch = sub.add_parser("branch")
    branch.add_argument("repo")
    branch.add_argument("branch")
    safe = sub.add_parser("merged-branch")
    safe.add_argument("repo")
    safe.add_argument("branch")
    return p


def execute(args):
    d = Delivery(args.project_map, args.spec)
    if args.command == "init":
        if d.path.exists():
            raise ValueError("delivery.json already exists; left unchanged")
        atomic_json(
            d.path,
            {
                "version": 1,
                "spec": args.spec,
                "working_agreement": "",
                "criteria": {},
                "slices": [],
            },
        )
        print(f"initialized {d.path}; plan criteria and slices before implementation")
        return
    data = d.load()
    if args.command == "active-branch":
        if args.repo not in d.repos:
            raise ValueError("repository not selected")
        started = [
            s for s in data["slices"] if s["repo"] == args.repo and s.get("branch")
        ]
        active = [
            s for s in started if s["status"] in {"implementing", "review", "blocked"}
        ]
        if len(active) > 1:
            raise ValueError(
                f"{args.repo}: multiple active slices; reconcile their statuses before reopening"
            )
        if active:
            chosen = active[0]
        elif len(started) <= 1:
            chosen = started[0] if started else None
        elif any(s.get("start_order") is None for s in started):
            raise ValueError(
                f"{args.repo}: start order is unknown; add start_order to older registered slices before reopening"
            )
        else:
            chosen = max(started, key=lambda s: s["start_order"])
        print(chosen["branch"] if chosen else f"feature/{d.spec}")
        return
    if args.command in {"branch", "merged-branch"}:
        s = next(
            (
                s
                for s in data["slices"]
                if s["repo"] == args.repo and s.get("branch") == args.branch
            ),
            None,
        )
        if not s:
            raise ValueError("branch is not registered in delivery.json")
        if args.command == "merged-branch":
            d.merged(s)
        return
    if args.command == "check-close":
        errors = [] if args.worktrees_only else d.completion_errors(data)
        if not args.worktrees_only:
            for s in data["slices"]:
                if s.get("branch"):
                    if args.offline:
                        errors.append(
                            "cannot establish current merge evidence offline; use explicit --worktrees-only for cleanup"
                        )
                        break
                    try:
                        d.merged(s)
                    except ValueError as exc:
                        errors.append(f"{s['id']}: {exc}")
        if errors:
            raise ValueError("\n".join(errors))
        return
    if args.command == "start":
        s = next((s for s in data["slices"] if s["id"] == args.slice), None)
        if not s or s["status"] != "planned" or s.get("branch"):
            raise ValueError(
                "start requires a planned slice with branch=null; register existing branches explicitly in delivery.json"
            )
        if any(
            x["status"] not in {"merged", "verified"}
            for x in data["slices"]
            if x["id"] in s["depends_on"]
        ):
            raise ValueError("slice dependencies are not merged")
        ref, wt = d.registered_worktree(s["repo"])
        if git(wt, "status", "--porcelain", "--untracked-files=all"):
            raise ValueError("slice worktree is dirty")
        old = git(wt, "symbolic-ref", "--short", "HEAD")
        previous = next(
            (
                x
                for x in data["slices"]
                if x["repo"] == s["repo"] and x.get("branch") == old
            ),
            None,
        )
        if old != f"feature/{d.spec}" and previous is None:
            raise ValueError("current worktree branch is not registered")
        git(ref, "fetch", "origin", "--prune")
        base = "refs/remotes/origin/" + d.repos[s["repo"]]["default"]
        if previous:
            if previous["status"] not in {"merged", "verified"}:
                raise ValueError("current slice has not merged")
            d.merged(previous)
        else:
            git(ref, "merge-base", "--is-ancestor", git(wt, "rev-parse", "HEAD"), base)
        # Validate cross-repository dependencies against freshly fetched refs too.
        for dep in data["slices"]:
            if dep["id"] in s["depends_on"]:
                dep_ref, _ = d.paths(dep["repo"])
                if dep_ref != ref:
                    git(dep_ref, "fetch", "origin", "--prune")
                d.merged(dep)
        branch = f"{args.branch_prefix}/{d.spec}-{s['id']}"
        run("git", "check-ref-format", "--branch", branch)
        refs = git(
            ref,
            "for-each-ref",
            "--format=%(refname)",
            "refs/heads/" + branch,
            "refs/remotes/origin/" + branch,
        )
        if refs:
            raise ValueError(f"branch collision: {branch}")
        baseline = git(ref, "rev-parse", base)
        git(wt, "checkout", "--no-track", "-b", branch, baseline)
        try:
            next_order = (
                max((x.get("start_order") or 0 for x in data["slices"]), default=0) + 1
            )
            s.update(branch=branch, status="implementing", start_order=next_order)
            d.validate(data)
            atomic_json(d.path, data)
        except Exception:
            # Roll back only the branch created here, before any implementation edits.
            git(wt, "checkout", old)
            git(ref, "branch", "-D", branch)
            raise
        print(f"started {s['id']} in {wt} on {branch} at {baseline}")
        return
    errors = d.completion_errors(data)
    report = {
        "spec": d.spec,
        "completion": "incomplete"
        if errors
        else "locally verified; merge state needs checking",
        "acceptance_gaps": errors,
        "repositories": [],
        "slices": [],
        "next_action": None,
        "freshness": "GitHub queried; local refs not fetched"
        if args.remote
        else "local only; remote state unverified",
    }
    for name in d.repos:
        row = {"repo": name}
        try:
            ref, wt = d.paths(name)
            row["worktree"] = "present" if wt.exists() else "removed or not prepared"
            if wt.exists():
                d.registered_worktree(name)
                row["branch"] = git(wt, "symbolic-ref", "--short", "HEAD")
                row["dirty"] = bool(git(wt, "status", "--porcelain"))
                known = row["branch"] == f"feature/{d.spec}" or any(
                    s.get("branch") == row["branch"] and s["repo"] == name
                    for s in data["slices"]
                )
                if not known:
                    row["warning"] = "unregistered branch"
        except ValueError as exc:
            row["warning"] = str(exc)
        report["repositories"].append(row)
    for s in data["slices"]:
        row = {
            k: s.get(k)
            for k in ("id", "repo", "status", "branch", "start_order", "pr", "note")
        }
        if args.remote and s.get("pr"):
            try:
                p = d.pr_state(s)
                row["remote"] = p["state"]
                row["url"] = p["url"]
                if (s["status"] in {"merged", "verified"}) != (p["state"] == "MERGED"):
                    row["warning"] = (
                        "recorded status differs from GitHub; reconcile delivery.json"
                    )
            except ValueError as exc:
                row["warning"] = str(exc)
        report["slices"].append(row)
    pending = [s for s in data["slices"] if s["status"] != "verified"]
    report["next_action"] = (
        f"{pending[0]['id']}: {pending[0].get('note') or pending[0]['status']}"
        if pending
        else "fill acceptance gaps"
        if errors
        else "check current merges, then close worktrees when authorized"
    )
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print(f"{d.spec}: {report['completion']} ({report['freshness']})")
        for row in report["repositories"] + report["slices"]:
            print(" | ".join(f"{k}: {v}" for k, v in row.items() if v is not None))
        for error in errors:
            print("gap: " + error)
        print("next: " + report["next_action"])


def main():
    args = parser().parse_args()
    # Serializes helper mutations; direct edits should be made while helpers are idle.
    lock = None
    try:
        if args.command in {"init", "start"}:
            if not re.fullmatch(SLUG, args.spec):
                raise ValueError("invalid spec name")
            directory = Delivery(args.project_map, args.spec).directory
            candidate = directory / ".delivery.lock"
            candidate.mkdir()
            lock = candidate
        execute(args)
    except (ValueError, KeyError, TypeError, AttributeError, OSError) as exc:
        print(f"delivery: {exc}", file=sys.stderr)
        return 1
    finally:
        if lock is not None:
            lock.rmdir()
    return 0


if __name__ == "__main__":
    sys.exit(main())
