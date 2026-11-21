#!/usr/bin/env python3
"""Verify a packed producer against a consumer in temporary copies at exact commits."""

import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import subprocess
import sys
import tarfile
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "_shared"))
from delivery import Delivery, git, run


def archive(ref, sha, destination):
    if any(
        line.startswith("160000 ")
        for line in git(ref, "ls-tree", "-r", sha).splitlines()
    ):
        raise ValueError("tracked submodules are not supported")
    raw = subprocess.check_output(["git", "-C", str(ref), "archive", sha])
    # Python 3.9 compatible extraction, rejecting symlinks/submodules and traversal.
    # npm package projects requiring tracked symlinks need an explicit alternative.
    with tarfile.open(fileobj=io.BytesIO(raw)) as tar:
        for member in tar.getmembers():
            path = destination / member.name
            if not path.resolve().is_relative_to(destination) or not (
                member.isfile() or member.isdir()
            ):
                raise ValueError(f"unsupported archive entry: {member.name}")
        tar.extractall(destination)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("project_map")
    p.add_argument("spec")
    p.add_argument("producer")
    p.add_argument("consumer")
    p.add_argument("--producer-commit", required=True)
    p.add_argument("--consumer-commit", required=True)
    p.add_argument(
        "--check",
        action="append",
        required=True,
        help="consumer npm script; repeat for build, test, etc.",
    )
    p.add_argument(
        "--producer-build-script", default="build", help="producer npm build script"
    )
    p.add_argument("--mode", choices=["candidate", "published"], default="candidate")
    p.add_argument(
        "--report",
        required=True,
        help="new JSON report path; never overwrites an existing file",
    )
    args = p.parse_args()
    try:
        d = Delivery(args.project_map, args.spec)
        if args.producer == args.consumer or any(
            n not in d.repos for n in (args.producer, args.consumer)
        ):
            raise ValueError("choose two distinct repositories from repos.txt")
        for sha in (args.producer_commit, args.consumer_commit):
            if not re.fullmatch(r"[0-9a-f]{40}", sha):
                raise ValueError("pin both inputs to full commit SHAs")
        refs = [d.paths(n)[0] for n in (args.producer, args.consumer)]
        for ref, sha in zip(refs, (args.producer_commit, args.consumer_commit)):
            git(ref, "cat-file", "-e", sha + "^{commit}")
        report = Path(args.report).resolve()
        if report.exists():
            raise ValueError("report path exists; choose a new path")
        with tempfile.TemporaryDirectory(prefix="meta-package-check-") as tmp:
            root = Path(tmp).resolve()
            producer, consumer = root / "producer", root / "consumer"
            producer.mkdir()
            consumer.mkdir()
            archive(refs[0], args.producer_commit, producer)
            archive(refs[1], args.consumer_commit, consumer)
            package = json.loads((producer / "package.json").read_text())
            app = json.loads((consumer / "package.json").read_text())
            name = package["name"]
            declared = {
                **app.get("dependencies", {}),
                **app.get("devDependencies", {}),
                **app.get("optionalDependencies", {}),
            }
            if name not in declared:
                raise ValueError("consumer does not declare the producer package")
            if any(check not in app.get("scripts", {}) for check in args.check):
                raise ValueError("requested consumer check is not a package script")
            if (
                args.mode == "candidate"
                and args.producer_build_script not in package.get("scripts", {})
            ):
                raise ValueError("producer must define the selected build script")
            result = {
                "mode": args.mode,
                "producer": args.producer,
                "producer_commit": args.producer_commit,
                "consumer": args.consumer,
                "consumer_commit": args.consumer_commit,
                "package": name,
                "node": run("node", "--version"),
                "npm": run("npm", "--version"),
                "checks": args.check,
                "producer_build_script": (
                    args.producer_build_script if args.mode == "candidate" else None
                ),
                "passed": False,
            }
            try:
                run("npm", "ci", "--no-audit", "--no-fund", cwd=consumer)
                if args.mode == "candidate":
                    run("npm", "ci", "--no-audit", "--no-fund", cwd=producer)
                    run("npm", "run", "--", args.producer_build_script, cwd=producer)
                    packed = json.loads(
                        run("npm", "pack", "--json", "--ignore-scripts", cwd=producer)
                    )
                    tarball = producer / packed[0]["filename"]
                    if tarball.parent != producer or not tarball.is_file():
                        raise ValueError("unexpected npm pack output")
                    result["artifact_sha256"] = hashlib.sha256(
                        tarball.read_bytes()
                    ).hexdigest()
                    run(
                        "npm",
                        "install",
                        "--no-save",
                        "--no-audit",
                        "--no-fund",
                        "--package-lock=false",
                        str(tarball),
                        cwd=consumer,
                    )
                else:
                    lock_path = consumer / "npm-shrinkwrap.json"
                    if not lock_path.exists():
                        lock_path = consumer / "package-lock.json"
                    lock = json.loads(lock_path.read_text())
                    locked = lock.get("packages", {}).get("node_modules/" + name, {})
                    if (
                        not re.fullmatch(r"[a-zA-Z0-9*^~<>=| .+_-]+", declared[name])
                        or not locked.get("resolved", "").startswith(
                            ("https://", "http://")
                        )
                        or not locked.get("integrity")
                        or locked.get("link")
                    ):
                        raise ValueError(
                            "published mode requires a registry dependency with URL and integrity in a v2/v3 lockfile"
                        )
                installed = consumer / "node_modules" / name / "package.json"
                installed_package = json.loads(installed.read_text())
                result["installed_version"] = installed_package["version"]
                if (
                    args.mode == "candidate"
                    and installed_package["version"] != package["version"]
                ):
                    raise ValueError(
                        "installed candidate version differs from packed producer"
                    )
                for check in args.check:
                    run("npm", "run", "--", check, cwd=consumer)
                result["passed"] = True
            except (ValueError, OSError) as exc:
                result["error"] = str(exc)
            with report.open("x") as output:
                json.dump(result, output, indent=2)
                output.write("\n")
            print(json.dumps(result, indent=2))
            return 0 if result["passed"] else 1
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as exc:
        print(f"verify-packages: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
