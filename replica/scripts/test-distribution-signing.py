#!/usr/bin/env python3
"""Exercise nested signing order and fail-closed Apple notarization handling."""
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


signing = load("signing", "sign-app.py")
notarization = load("notarization", "notarize-distribution.py")


class SigningTests(unittest.TestCase):
    def test_nested_code_is_signed_inside_out_and_symlinks_are_not_followed(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary) / "BlinkClip.app"
            framework = app / "Contents/Frameworks/Sparkle.framework"
            helper = framework / "Versions/B/XPCServices/Downloader.xpc"
            binary = helper / "Contents/MacOS/Downloader"
            binary.parent.mkdir(parents=True)
            binary.write_bytes(bytes.fromhex("cffaedfe") + b"fixture")
            (framework / "Current").symlink_to("Versions/B", target_is_directory=True)
            targets = signing.signing_targets(app)
            self.assertLess(targets.index(binary), targets.index(helper))
            self.assertLess(targets.index(helper), targets.index(framework))
            self.assertEqual(targets[-1], app)
            self.assertEqual(len(targets), 4)

    def test_debug_entitlement_is_removed_but_sparkle_entitlements_survive(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary) / "BlinkClip.app"
            (app / "Contents").mkdir(parents=True)
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps({}))
            commands, preserved = [], []

            def run(command, **kwargs):
                commands.append(command)
                if "--display" in command:
                    return SimpleNamespace(stdout=plistlib.dumps({"com.apple.security.get-task-allow": True,
                                                                 "com.apple.security.app-sandbox": True}))
                if "--entitlements" in command:
                    preserved.append(plistlib.loads(Path(command[command.index("--entitlements") + 1]).read_bytes()))
                return SimpleNamespace(stdout=b"")

            with patch.object(signing.subprocess, "run", side_effect=run):
                signing.sign_app(app, "fixture-identity")
            self.assertEqual(preserved, [{"com.apple.security.app-sandbox": True}])
            signing_command = next(command for command in commands if "--force" in command)
            self.assertIn("--timestamp", signing_command)
            self.assertIn("runtime", signing_command)
            self.assertNotIn("--deep", signing_command)


class NotarizationTests(unittest.TestCase):
    def test_untrusted_or_incomplete_signatures_never_reach_apple(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary) / "BlinkClip.app"
            app.mkdir()
            valid = ("Authority=Developer ID Application: Fixture\nTeamIdentifier=TEAM\n"
                     "flags=0x10000(runtime)\nTimestamp=Nov 13, 2026\n")
            for details, entitlements in [
                (valid, {}), (valid.replace("TEAM", "OTHER"), {}),
                (valid.replace("Timestamp=", "Signed Time="), {}),
                (valid.replace("(runtime)", ""), {}),
                (valid.replace("Developer ID Application:", "Apple Development:"), {}),
                (valid, {"com.apple.security.get-task-allow": True})]:
                with self.subTest(details=details, entitlements=entitlements):
                    def run(command, **kwargs):
                        return SimpleNamespace(stdout=plistlib.dumps(entitlements) if "--entitlements" in command else b"",
                                               stderr=details)
                    with patch.object(notarization, "run", side_effect=run):
                        if details == valid and not entitlements:
                            notarization.verify_distribution(app, "TEAM")
                        else:
                            with self.assertRaises(ValueError):
                                notarization.verify_distribution(app, "TEAM")

    def run_case(self, temporary, status="Accepted", returncode=0):
        root = Path(temporary)
        archive = root / "BlinkClip.dmg"
        archive.write_bytes(b"fixture-installer")
        commands = []

        def run(command, **kwargs):
            commands.append(command)
            if command[1:3] == ["notarytool", "submit"]:
                return SimpleNamespace(stdout=json.dumps({"id": "fixture-id"}), returncode=0)
            if command[1:3] == ["notarytool", "wait"]:
                return SimpleNamespace(stdout=json.dumps({"status": status}), stderr="", returncode=returncode)
            return SimpleNamespace(stdout="", stderr="", returncode=0)

        return root, archive, commands, run

    def test_ticket_is_stapled_only_after_acceptance(self):
        for status in ["Accepted", "Invalid"]:
            with self.subTest(status=status), tempfile.TemporaryDirectory() as temporary:
                root, archive, commands, run = self.run_case(temporary, status)
                with patch.object(notarization.subprocess, "run", side_effect=run):
                    if status == "Accepted":
                        notarization.notarize(archive, archive, "fixture-profile", root / "evidence")
                    else:
                        with self.assertRaisesRegex(ValueError, "rejected"):
                            notarization.notarize(archive, archive, "fixture-profile", root / "evidence")
                stapled = any(command[1:3] == ["stapler", "staple"] for command in commands)
                self.assertEqual(stapled, status == "Accepted")
                self.assertTrue((root / "evidence/submission.json").exists())

    def test_timeout_resumes_existing_submission_without_uploading_again(self):
        with tempfile.TemporaryDirectory() as temporary:
            root, archive, commands, run = self.run_case(temporary, returncode=1)
            with patch.object(notarization.subprocess, "run", side_effect=run):
                with self.assertRaisesRegex(RuntimeError, "unfinished"):
                    notarization.notarize(archive, archive, "profile", root / "evidence")
            _, _, resumed, run = self.run_case(temporary)
            with patch.object(notarization.subprocess, "run", side_effect=run):
                notarization.notarize(archive, archive, "profile", root / "evidence")
            self.assertFalse(any(command[1:3] == ["notarytool", "submit"] for command in resumed))
            archive.write_bytes(b"changed-installer")
            with patch.object(notarization.subprocess, "run", side_effect=run):
                with self.assertRaisesRegex(ValueError, "different bytes"):
                    notarization.notarize(archive, archive, "profile", root / "evidence")


if __name__ == "__main__":
    unittest.main()
