#!/usr/bin/env python3
"""Select a versioned release without building or publishing anything."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys

VERSION = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+(?:-dev\.[0-9]+)?")


def note(message):
    """Print a fallback reason on stderr so the CI log states why it happened."""
    print("release-plan: " + message, file=sys.stderr)


def git(*arguments):
    return subprocess.run(["git", *arguments], capture_output=True, text=True)


def crash_commit(revision):
    """The commit `revision` names, or None when it is not resolvable in this clone."""
    resolved = git("rev-parse", "--verify", "--quiet", revision + "^{commit}")
    return resolved.stdout.strip() if resolved.returncode == 0 else None


def version_at(revision):
    """package.json version stored at `revision`, or None when it is unreadable."""
    shown = git("show", revision + ":package.json")
    if shown.returncode != 0:
        return None
    return json.loads(shown.stdout)["version"]


def previous_version(before, version):
    """Version the pushed-from commit claims, or `version` when that is unknowable.

    A force-push, an amended/rewritten root commit, or a ref's first push leaves
    `before` missing, all zeros, or unreachable in CI's shallow clone. None of that
    is evidence of a version bump, so this falls back in this order:

    1. `before` names a readable commit → use its package.json version.
    2. `before` is unusable → compare with the parent commit (`HEAD^`) when this
       clone has it, and print why.
    3. No usable reference at all → report the version as unchanged, so an
       unreachable `before` can never be mistaken for a new release.

    The fallback never returns None, because `version != None` would select a
    release for every force-pushed run.
    """
    if not before:
        note("push event carries no usable `before` sha; comparing with the parent commit instead")
    elif not before.strip("0"):
        note("push event `before` is all zeros (first push of a ref); comparing with the parent commit instead")
    else:
        commit = crash_commit(before)
        if commit is not None:
            known = version_at(commit)
            if known is not None:
                return known
            note("push event `before` " + before + " has no readable package.json; "
                 "comparing with the parent commit instead")
        else:
            note("push event `before` " + before + " is not reachable in this clone "
                 "(git cat-file -e failed; likely a force-push or rewritten history); "
                 "comparing with the parent commit instead")
    parent = crash_commit("HEAD^")
    if parent is None:
        note("parent commit is not present in this clone (shallow or root commit); "
             "treating the version as unchanged")
        return version
    inherited = version_at(parent)
    if inherited is None:
        note("parent commit " + parent + " has no readable package.json; treating the version as unchanged")
        return version
    note("parent commit " + parent + " records version " + inherited + "; using it as the previous version")
    return inherited


def select_plan(event, ref, version, previous_version=None):
    if not VERSION.fullmatch(version):
        raise ValueError("Unsupported package.json version: " + version)
    tag = "v" + version
    if ref.startswith("refs/tags/"):
        if ref != "refs/tags/" + tag:
            raise ValueError("Tag does not match package.json version")
        selected = event in {"push", "workflow_dispatch"}
    elif event == "workflow_dispatch":
        selected = True
    else:
        selected = event == "push" and ref == "refs/heads/main" and version != previous_version
    return {"release": str(selected).lower(), "version": version, "tag": tag}


def main():
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
    version = json.loads(Path("package.json").read_text())["version"]
    previous = None
    if os.environ.get("GITHUB_EVENT_NAME") == "push" and os.environ.get("GITHUB_REF") == "refs/heads/main":
        previous = previous_version(str(event.get("before") or ""), version)
    result = select_plan(os.environ.get("GITHUB_EVENT_NAME"), os.environ.get("GITHUB_REF"), version, previous)
    # Source pushes and version tags validate contracts only. Publication is opt-in.
    if os.environ.get("BLINKCLIP_PUBLISH") != "true":
        result["release"] = "false"
    result["commit"] = subprocess.run(["git", "rev-parse", "HEAD"],
                                      capture_output=True, check=True, text=True).stdout.strip()
    with Path(os.environ["GITHUB_OUTPUT"]).open("a") as output:
        for key, value in result.items():
            output.write(key + "=" + value + "\n")
    print(json.dumps(result))


if __name__ == "__main__":
    main()
