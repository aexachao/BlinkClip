#!/usr/bin/env python3
"""Release-plan tests: version diff, force-push fallbacks, and the publish gate.

The CI plan job used to die with `git show <before>:package.json` returning 128
whenever a force-push (or an amended/rewritten root commit) made the push event's
`before` sha unreachable in the shallow clone. These tests pin the fallback
behaviour and the rule that an unreachable `before` is never a new release.
"""
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).with_name("release-plan.py")

spec = importlib.util.spec_from_file_location("release_plan", SCRIPT)
plan = importlib.util.module_from_spec(spec)
spec.loader.exec_module(plan)

MISSING = "1" * 40
ZERO = "0" * 40


def git_environment():
    environment = {key: value for key, value in os.environ.items()
                   if not key.startswith("GIT_") or key in {"GIT_SSH", "GIT_SSH_COMMAND"}}
    environment.update({
        "GIT_AUTHOR_NAME": "BlinkClip Test", "GIT_AUTHOR_EMAIL": "test@blinkclip.invalid",
        "GIT_COMMITTER_NAME": "BlinkClip Test", "GIT_COMMITTER_EMAIL": "test@blinkclip.invalid",
        "GIT_AUTHOR_DATE": "2026-11-14T00:00:00 +0800", "GIT_COMMITTER_DATE": "2026-11-14T00:00:00 +0800",
        "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_SYSTEM": os.devnull,
        "GIT_TERMINAL_PROMPT": "0",
    })
    return environment


class ReleasePlanTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="blinkclip-release-plan."))
        self.addCleanup(shutil.rmtree, self.root, True)

    # -- fixtures ---------------------------------------------------------
    def repository(self, name="repo", versions=("1.0.11",)):
        path = self.root / name
        path.mkdir(parents=True)
        self.git(path, "init", "-q", "-b", "main")
        for version in versions:
            self.commit(path, version)
        return path

    def git(self, path, *arguments):
        return subprocess.run(["git", *arguments], cwd=path, env=git_environment(),
                              capture_output=True, text=True, check=True).stdout.strip()

    def commit(self, path, version, message=None):
        (path / "package.json").write_text(json.dumps({"name": "blinkclip", "version": version}) + "\n")
        # A unique marker keeps two commits with the same version distinct.
        self.commits = getattr(self, "commits", 0) + 1
        (path / "state.txt").write_text(str(self.commits) + "\n")
        self.git(path, "add", "package.json", "state.txt")
        self.git(path, "commit", "-q", "-m", message or ("package " + version))
        return self.git(path, "rev-parse", "HEAD")

    def shallow_clone(self, source, name="shallow"):
        destination = self.root / name
        subprocess.run(["git", "-c", "protocol.file.allow=always", "clone", "--depth", "1", "-q",
                        source.as_uri(), str(destination)],
                       env=git_environment(), check=True, capture_output=True)
        return destination

    def run_plan(self, path, event, ref="refs/heads/main", name="push", publish=None, extra=None):
        event_path = self.root / "event.json"
        event_path.write_text(json.dumps(event))
        output_path = self.root / "github-output.txt"
        output_path.write_text("")
        environment = {key: value for key, value in os.environ.items()
                       if not key.startswith(("GITHUB_", "BLINKCLIP_"))}
        environment.update({"GITHUB_EVENT_PATH": str(event_path), "GITHUB_EVENT_NAME": name,
                            "GITHUB_REF": ref, "GITHUB_OUTPUT": str(output_path), "PATH": os.environ["PATH"]})
        if publish is not None:
            environment["BLINKCLIP_PUBLISH"] = publish
        environment.update(extra or {})
        result = subprocess.run([sys.executable, str(SCRIPT)], cwd=path, env=environment,
                                capture_output=True, text=True)
        outputs = {}
        for line in output_path.read_text().splitlines():
            key, _, value = line.partition("=")
            outputs[key] = value
        return result, outputs

    def assert_plan(self, result, outputs, release, version="1.0.11"):
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertEqual(outputs["release"], "true" if release else "false", result.stdout + result.stderr)
        self.assertEqual(outputs["version"], version)
        self.assertEqual(outputs["tag"], "v" + version)
        self.assertTrue(re.fullmatch(r"[0-9a-f]{40}", outputs["commit"]), outputs["commit"])

    # -- the three regression inputs --------------------------------------
    def test_before_missing_never_selects_a_release(self):
        """`before` absent from the event: unchanged, exit 0, reason printed."""
        repository = self.repository(versions=("1.0.11", "1.0.11"))
        result, outputs = self.run_plan(repository, {"after": self.git(repository, "rev-parse", "HEAD")},
                                        publish="true")
        self.assert_plan(result, outputs, release=False)
        self.assertIn("no usable `before`", result.stderr)
        self.assertIn("comparing with the parent commit instead", result.stderr)

    def test_before_all_zeros_never_selects_a_release(self):
        """A ref's first push reports an all-zero `before`: unchanged, exit 0."""
        repository = self.repository(versions=("1.0.11", "1.0.11"))
        result, outputs = self.run_plan(repository, {"before": ZERO}, publish="true")
        self.assert_plan(result, outputs, release=False)
        self.assertIn("all zeros", result.stderr)

    def test_before_unreachable_in_shallow_clone_is_not_a_release(self):
        """The CI shape: force-pushed sha, shallow clone, no parent, no traceback."""
        source = self.repository(versions=("1.0.10", "1.0.11"))
        rewritten = self.git(source, "rev-parse", "HEAD^")
        clone = self.shallow_clone(source)
        self.assertEqual(self.git(clone, "rev-parse", "--is-shallow-repository"), "true")
        for before in (rewritten, MISSING):
            with self.subTest(before=before):
                result, outputs = self.run_plan(clone, {"before": before}, publish="true")
                self.assert_plan(result, outputs, release=False)
                self.assertIn(before + " is not reachable in this clone", result.stderr)
                self.assertIn("parent commit is not present in this clone", result.stderr)

    def test_before_unreachable_falls_back_to_the_parent_commit(self):
        """With history present, the parent decides: a real bump still releases."""
        bumped = self.repository("bumped", versions=("1.0.10", "1.0.11"))
        result, outputs = self.run_plan(bumped, {"before": MISSING}, publish="true")
        self.assert_plan(result, outputs, release=True)
        self.assertIn("comparing with the parent commit instead", result.stderr)
        self.assertIn("records version 1.0.10", result.stderr)

        same = self.repository("same", versions=("1.0.11", "1.0.11"))
        result, outputs = self.run_plan(same, {"before": MISSING}, publish="true")
        self.assert_plan(result, outputs, release=False)
        self.assertIn("records version 1.0.11", result.stderr)

    def test_before_unreachable_on_a_root_commit_is_unchanged(self):
        """An amended root commit leaves no parent: unchanged, not a release."""
        repository = self.repository(versions=("1.0.11",))
        result, outputs = self.run_plan(repository, {"before": MISSING}, publish="true")
        self.assert_plan(result, outputs, release=False)
        self.assertIn("parent commit is not present in this clone", result.stderr)

    # -- normal path ------------------------------------------------------
    def test_reachable_before_compares_that_commit(self):
        repository = self.repository(versions=("1.0.10", "1.0.11"))
        first = self.git(repository, "rev-parse", "HEAD^")
        result, outputs = self.run_plan(repository, {"before": first}, publish="true")
        self.assert_plan(result, outputs, release=True)
        self.assertEqual(result.stderr, "")

        current = self.git(repository, "rev-parse", "HEAD")
        result, outputs = self.run_plan(repository, {"before": current}, publish="true")
        self.assert_plan(result, outputs, release=False)
        self.assertEqual(result.stderr, "")

    def test_before_reachable_without_a_readable_package_json(self):
        """A readable `before` with no manifest still ends at "unchanged"."""
        repository = self.root / "manifest-less"
        repository.mkdir()
        self.git(repository, "init", "-q", "-b", "main")
        (repository / "README.md").write_text("first commit, no manifest\n")
        self.git(repository, "add", "README.md")
        self.git(repository, "commit", "-q", "-m", "no manifest")
        first = self.git(repository, "rev-parse", "HEAD")
        self.commit(repository, "1.0.11")
        result, outputs = self.run_plan(repository, {"before": first}, publish="true")
        self.assert_plan(result, outputs, release=False)
        self.assertIn("no readable package.json", result.stderr)

    # -- gates that must not change --------------------------------------
    def test_publication_stays_opt_in(self):
        """A detected bump only releases with workflow_dispatch + publish=true."""
        repository = self.repository(versions=("1.0.10", "1.0.11"))
        first = self.git(repository, "rev-parse", "HEAD^")
        for publish in (None, "false"):
            with self.subTest(publish=publish):
                result, outputs = self.run_plan(repository, {"before": first}, publish=publish)
                self.assert_plan(result, outputs, release=False)

    def test_dispatch_and_tag_selection_are_unchanged(self):
        self.assertEqual(plan.select_plan("workflow_dispatch", "refs/heads/main", "1.0.11", "1.0.11")["release"], "true")
        self.assertEqual(plan.select_plan("push", "refs/heads/main", "1.0.11", "1.0.11")["release"], "false")
        self.assertEqual(plan.select_plan("push", "refs/heads/main", "1.0.11", "1.0.10")["release"], "true")
        self.assertEqual(plan.select_plan("push", "refs/heads/feature", "1.0.11", "1.0.10")["release"], "false")
        self.assertEqual(plan.select_plan("push", "refs/tags/v1.0.11", "1.0.11")["release"], "true")
        with self.assertRaisesRegex(ValueError, "Tag does not match"):
            plan.select_plan("push", "refs/tags/v1.0.10", "1.0.11")
        with self.assertRaisesRegex(ValueError, "Unsupported package.json version"):
            plan.select_plan("push", "refs/heads/main", "1.0")

    def test_workflow_dispatch_never_reads_the_push_event(self):
        repository = self.repository(versions=("1.0.11", "1.0.11"))
        result, outputs = self.run_plan(repository, {"before": MISSING}, name="workflow_dispatch", publish="true")
        self.assert_plan(result, outputs, release=True)
        self.assertEqual(result.stderr, "")


if __name__ == "__main__":
    unittest.main()
