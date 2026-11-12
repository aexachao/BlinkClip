#!/usr/bin/env python3
"""Test the signed update-feed contract without building or accessing GitHub."""
import base64
import importlib.util
import json
import os
# Accept canonical names while keeping existing CI configuration compatible.
for _blinkclip_key, _blinkclip_value in list(os.environ.items()):
    if _blinkclip_key.startswith("BLINKCLIP_"):
        os.environ["BLINKCLIP_" + _blinkclip_key[9:]] = _blinkclip_value
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

spec = importlib.util.spec_from_file_location("update_feed", Path(__file__).with_name("create-update-feed.py"))
feed = importlib.util.module_from_spec(spec)
spec.loader.exec_module(feed)


class UpdateFeedTests(unittest.TestCase):
    def test_stable_universal_archive_and_system_requirement(self):
        signature = base64.b64encode(bytes(64)).decode()
        result = feed.make_feed("1.0.6", signature, 1234)
        item = result.find("channel/item")
        self.assertEqual(item.find("{" + feed.SPARKLE + "}version").text, "1.0.6")
        self.assertEqual(item.find("{" + feed.SPARKLE + "}minimumSystemVersion").text, "14.0")
        enclosure = item.find("enclosure")
        self.assertEqual(enclosure.get("url"),
            "https://github.com/aexachao/BlinkClip/releases/download/v1.0.6/BlinkClip-1.0.6-macos-universal.dmg")
        self.assertEqual(enclosure.get("{" + feed.SPARKLE + "}edSignature"), signature)
        self.assertEqual(enclosure.get("length"), "1234")
        ET.fromstring(ET.tostring(result.getroot()))

    def test_invalid_versions_and_signatures(self):
        valid = base64.b64encode(bytes(64)).decode()
        for version in ["1.0", "1.0.6-dev.1", "v1.0.6", "1.0.6/evil", "1.0.6\n"]:
            with self.subTest(version=version), self.assertRaises(ValueError):
                feed.make_feed(version, valid, 1234)
        for signature, size in [("invalid", 1234), ("", 1234), (valid, 0), (valid, -1)]:
            with self.subTest(signature=signature, size=size), self.assertRaises(ValueError):
                feed.make_feed("1.0.6", signature, size)

    def test_missing_private_key_fails_before_signing(self):
        with patch.dict(feed.os.environ, {}, clear=True), patch.object(feed.subprocess, "run") as run:
            with self.assertRaises(ValueError):
                feed.create_feed(Path("missing.dmg"), "1.0.6", Path("sign_update"))
            run.assert_not_called()

    def test_private_key_uses_stdin_and_feed_is_signed_and_verified(self):
        secret = base64.b64encode(bytes(range(32))).decode()
        signature = base64.b64encode(bytes(64)).decode()
        with tempfile.TemporaryDirectory() as temporary:
            archive = Path(temporary) / "BlinkClip-1.0.6-macos-universal.dmg"
            archive.write_bytes(b"fixture")
            with patch.dict(feed.os.environ, {"BLINKCLIP_UPDATE_PRIVATE_KEY": secret}), \
                    patch.object(feed.subprocess, "run") as run:
                run.return_value.stdout = signature
                result = feed.create_feed(archive, "1.0.6", Path("sign_update"))
                self.assertEqual(result.name, "appcast.xml")
                self.assertEqual(len(run.call_args_list), 4)
                for call in run.call_args_list:
                    self.assertNotIn(secret, " ".join(map(str, call.args[0])))
                    self.assertNotIn("BLINKCLIP_UPDATE_PRIVATE_KEY", call.kwargs["env"])
                self.assertEqual(run.call_args_list[0].kwargs["input"], secret + "\n")
                self.assertIn("verify-update-signature.swift", run.call_args_list[1].args[0][1])
                self.assertEqual(run.call_args_list[2].args[0][-1], str(result))
                self.assertIn("--verify", run.call_args_list[3].args[0])


class SparkleToolPathTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="sparkle-paths-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.replica = self.root / "fixture-repo/replica"
        scripts = self.replica / "scripts"
        scripts.mkdir(parents=True)
        self.script = scripts / "prepare-sparkle-tools.sh"
        shutil.copyfile(Path(__file__).with_name(self.script.name), self.script)
        commands = self.root / "commands"
        commands.mkdir()
        self.trace = self.root / "commands.jsonl"
        # Execute the production shell script. Only the external download,
        # checksum and unpack commands are replaced by controlled fixtures.
        driver = """import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['FIXTURE_TRACE'], 'a') as trace:
    trace.write(json.dumps({'command': name, 'arguments': args}) + '\\n')
if name == 'curl':
    assert args[:7] == ['--fail', '--location', '--silent', '--show-error', '--proto', '=https', '--proto-redir']
    assert 'https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-2.10.1.tar.xz' in args
    pathlib.Path(args[args.index('-o') + 1]).write_bytes(b'fixture archive')
elif name == 'shasum':
    assert args == ['-a', '256', '--check']
    checksum, archive = sys.stdin.read().strip().split('  ', 1)
    assert checksum == '1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27'
    assert pathlib.Path(archive).read_bytes() == b'fixture archive'
    sys.exit(int(os.environ.get('FIXTURE_HASH_FAIL', '0')))
elif name == 'tar':
    assert args[0] == '-xf' and args[2] == '-C' and args[4] == 'bin/sign_update'
    assert pathlib.Path(args[1]).is_file()
    binary = pathlib.Path(args[3]) / 'bin/sign_update'
    binary.parent.mkdir()
    binary.write_text('#!/bin/sh\\nexit 0\\n')
    binary.chmod(0o755)
"""
        for name in ("curl", "shasum", "tar"):
            command = commands / name
            command.write_text("#!" + sys.executable + "\n" + driver)
            command.chmod(0o755)
        self.environment = {key: value for key, value in os.environ.items()
                            if key not in {"ARTIFACT_TASK_DIR", "BLINKCLIP_BUILD_ROOT"}}
        self.environment.update(PATH=str(commands) + os.pathsep + os.environ["PATH"],
                                FIXTURE_TRACE=str(self.trace))

    def prepare(self, overrides):
        environment = {**self.environment, **overrides}
        return subprocess.run(["bash", str(self.script)], env=environment,
                              text=True, capture_output=True)

    def assert_installed(self, result, scratch):
        self.assertEqual(result.returncode, 0, result.stderr)
        expected = scratch / "sparkle-tools/2.10.1/bin/sign_update"
        self.assertEqual(Path(result.stdout.strip()), expected)
        self.assertTrue(os.access(expected, os.X_OK))
        calls = [json.loads(line) for line in self.trace.read_text().splitlines()]
        self.assertEqual([call["command"] for call in calls], ["curl", "shasum", "tar"])
        self.assertTrue(Path(calls[0]["arguments"][-1]).is_relative_to(scratch))
        self.assertTrue(Path(calls[2]["arguments"][3]).is_relative_to(scratch))
        self.assertEqual(list((scratch / "sparkle-tools").glob(".download.*")), [])
        return expected

    def test_managed_task_keeps_download_unpack_and_tool_outside_repository(self):
        task = self.root / "managed task"
        self.assert_installed(self.prepare({"ARTIFACT_TASK_DIR": str(task)}), task / "build/swiftpm")
        self.assertFalse((self.replica / ".build").exists())

    def test_explicit_build_root_overrides_managed_default(self):
        task = self.root / "managed"
        scratch = self.root / "explicit scratch"
        self.assert_installed(self.prepare({"ARTIFACT_TASK_DIR": str(task),
                                           "BLINKCLIP_BUILD_ROOT": str(scratch)}), scratch)
        self.assertFalse((task / "build").exists())
        self.assertFalse((self.replica / ".build").exists())

    def test_cached_tool_skips_download_checksum_and_unpack(self):
        scratch = self.root / "cache"
        overrides = {"BLINKCLIP_BUILD_ROOT": str(scratch)}
        expected = self.assert_installed(self.prepare(overrides), scratch)
        before = self.trace.read_bytes()
        result = self.prepare(overrides)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(Path(result.stdout.strip()), expected)
        self.assertEqual(self.trace.read_bytes(), before)

    def test_unmanaged_ci_keeps_legacy_cache_layout(self):
        self.assert_installed(self.prepare({}), self.replica / ".build")

    def test_checksum_failure_does_not_install_and_removes_download(self):
        scratch = self.root / "invalid"
        result = self.prepare({"BLINKCLIP_BUILD_ROOT": str(scratch), "FIXTURE_HASH_FAIL": "1"})
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((scratch / "sparkle-tools/2.10.1/bin/sign_update").exists())
        self.assertEqual(list((scratch / "sparkle-tools").glob(".download.*")), [])
        calls = [json.loads(line)["command"] for line in self.trace.read_text().splitlines()]
        self.assertEqual(calls, ["curl", "shasum"])


if __name__ == "__main__":
    unittest.main()
