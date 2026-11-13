#!/usr/bin/env python3
"""Check the one-DMG/two-architecture release contract without a macOS build."""
import importlib.util
import json
import os
# Accept canonical names while keeping existing CI configuration compatible.
for _blinkclip_key, _blinkclip_value in list(os.environ.items()):
    if _blinkclip_key.startswith("BLINKCLIP_"):
        os.environ["BLINKCLIP_" + _blinkclip_key[9:]] = _blinkclip_value
from pathlib import Path
import plistlib
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("release_ci", Path(__file__).with_name("release-ci.py"))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


def _resolved(directory):
    """返回与 release-ci 相同形态的规范化路径。

    macOS 上 tempfile 给出的根是 /var/folders/…，而 `Path.resolve()`（release-ci 用它规范化
    ARTIFACT_TASK_DIR / BLINKCLIP_*_OUTPUT_DIR 等环境变量）会解析成 /private/var/folders/…。
    两边字符串不同只是符号链接前缀差异；断言前统一成解析后的形态，才能在不放宽任何逻辑的前提下比较。
    """
    return Path(directory).resolve()


class UniversalReleaseTests(unittest.TestCase):
    def setUp(self):
        # Path-selection tests control their own roots even when this suite is run by storage-guard.
        path_variables = {"ARTIFACT_TASK_DIR", "BLINKCLIP_APP_OUTPUT_DIR", "BLINKCLIP_RELEASE_OUTPUT_DIR", "BLINKCLIP_BUILD_ROOT"}
        environment = {key: value for key, value in os.environ.items() if key not in path_variables}
        isolated = patch.dict(os.environ, environment, clear=True)
        isolated.start()
        self.addCleanup(isolated.stop)

    def test_canonical_environment_wins_with_legacy_fallback(self):
        with tempfile.TemporaryDirectory() as directory:
            root = _resolved(directory)
            with patch.dict(os.environ, {"BLINKCLIP_APP_OUTPUT_DIR": str(root / "old"),
                                         "BLINKCLIP_BUILD_ROOT": str(root / "old-build")}, clear=True):
                self.assertEqual(release.app_output_directory(), root / "old")
                with patch.dict(os.environ, {"BLINKCLIP_APP_OUTPUT_DIR": str(root / "new"),
                                             "BLINKCLIP_BUILD_ROOT": str(root / "new-build")}):
                    self.assertEqual(release.app_output_directory(), root / "new")
                    env = release.app_build_environment()
                    self.assertEqual(env["BLINKCLIP_BUILD_ROOT"], str(root / "new-build"))
                    self.assertEqual(env["BLINKCLIP_APP_OUTPUT_DIR"], str(root / "new"))

    def update_config(self):
        return {
            "SUFeedURL": "https://github.com/aexachao/BlinkClip/releases/latest/download/appcast.xml",
            "SUPublicEDKey": (release.ROOT / "replica/Assets/UpdatePublicKey.txt").read_text().strip(),
            "SURequireSignedFeed": True, "SUVerifyUpdateBeforeExtraction": True,
            "SUEnableAutomaticChecks": False, "SUAutomaticallyUpdate": False, "SUSendProfileInfo": False}

    def test_exactly_one_installer(self):
        self.assertEqual(release.asset_names("1.0.0"), [
            "BlinkClip-1.0.0-macos-universal.dmg", "SHA256SUMS.txt", "release-manifest.json", "appcast.xml"])

    def test_package_is_universal_and_records_both_architectures(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            commands = []

            def run(args, **kwargs):
                commands.append(args)
                if args[1].endswith("build-dmg.sh"):
                    Path(args[3]).write_bytes(b"fixture-dmg")
                if args[1].endswith("create-update-feed.py"):
                    (root / "replica/dist/release/appcast.xml").write_text("fixture-feed")

            with patch.object(release, "ROOT", root), patch.object(release.platform, "system", return_value="Darwin"), \
                    patch.object(release, "run", side_effect=run), \
                    patch.object(release, "verify_app") as app_check, patch.object(release, "verify_dmg") as dmg_check:
                release.package("1.0.0", "v1.0.0", "fixture-commit")
                self.assertEqual(commands[0], ["bash", "replica/scripts/build-app.sh", "release", "universal"])
                self.assertEqual(len(commands), 3)
                self.assertEqual(commands[1][-1], "universal")
                self.assertEqual(app_check.call_args.args[2], ["arm64", "x86_64"])
                self.assertEqual(dmg_check.call_args.args[2], ["arm64", "x86_64"])
            output = root / "replica/dist/release"
            self.assertEqual(len(list(output.glob("*.dmg"))), 1)
            manifest = json.loads((output / "release-manifest.json").read_text())
            self.assertEqual(len(manifest["archives"]), 1)
            self.assertEqual(manifest["archives"][0]["architectures"], ["arm64", "x86_64"])

    def test_managed_package_uses_task_paths_and_passes_them_to_build(self):
        with tempfile.TemporaryDirectory() as directory:
            root = _resolved(directory) / "checkout"
            task = _resolved(directory) / "managed-task"
            output = task / "out/release"
            commands = []

            def run(args, **kwargs):
                commands.append((args, kwargs))
                if args[1].endswith("build-dmg.sh"):
                    Path(args[3]).write_bytes(b"fixture-dmg")
                if args[1].endswith("create-update-feed.py"):
                    (output / "appcast.xml").write_text("fixture-feed")

            with patch.dict(os.environ, {"ARTIFACT_TASK_DIR": str(task)}), \
                    patch.object(release, "ROOT", root), patch.object(release.platform, "system", return_value="Darwin"), \
                    patch.object(release, "run", side_effect=run), \
                    patch.object(release, "verify_app") as app_check, patch.object(release, "verify_dmg") as dmg_check:
                release.package("1.0.0", "v1.0.0", "fixture-commit")
            build_environment = commands[0][1]["env"]
            self.assertEqual(build_environment["BLINKCLIP_APP_OUTPUT_DIR"], str(task / "out"))
            self.assertEqual(build_environment["BLINKCLIP_BUILD_ROOT"], str(task / "build/swiftpm"))
            self.assertEqual(app_check.call_args.args[0], task / "out/BlinkClip.app")
            self.assertEqual(commands[1][0][2], str(task / "out/BlinkClip.app"))
            self.assertEqual(dmg_check.call_args.args[0], output / release.asset_names("1.0.0")[0])
            self.assertFalse((root / "replica/dist").exists())
            self.assertEqual({p.name for p in output.iterdir()}, set(release.asset_names("1.0.0")))

    def test_explicit_app_release_and_scratch_roots_take_precedence(self):
        with tempfile.TemporaryDirectory() as directory:
            root = _resolved(directory)
            app_output = root / "custom-apps"
            release_output = root / "custom-assets"
            scratch = root / "custom-build"
            environment = {"ARTIFACT_TASK_DIR": str(root / "task"),
                           "BLINKCLIP_APP_OUTPUT_DIR": str(app_output),
                           "BLINKCLIP_RELEASE_OUTPUT_DIR": str(release_output),
                           "BLINKCLIP_BUILD_ROOT": str(scratch)}

            def run(args, **kwargs):
                if args[1].endswith("build-app.sh"):
                    self.assertEqual(kwargs["env"]["BLINKCLIP_APP_OUTPUT_DIR"], str(app_output))
                    self.assertEqual(kwargs["env"]["BLINKCLIP_BUILD_ROOT"], str(scratch))
                if args[1].endswith("build-dmg.sh"):
                    self.assertEqual(args[2], str(app_output / "BlinkClip.app"))
                    Path(args[3]).write_bytes(b"fixture-dmg")
                if args[1].endswith("create-update-feed.py"):
                    (release_output / "appcast.xml").write_text("fixture-feed")

            with patch.dict(os.environ, environment), \
                    patch.object(release.platform, "system", return_value="Darwin"), \
                    patch.object(release, "run", side_effect=run), \
                    patch.object(release, "verify_app") as app_check, patch.object(release, "verify_dmg"):
                release.package("1.0.0", "v1.0.0", "fixture-commit")
            self.assertEqual(app_check.call_args.args[0], app_output / "BlinkClip.app")
            self.assertTrue((release_output / "release-manifest.json").is_file())
            self.assertFalse((root / "task").exists())

    def test_intel_verification_uses_same_managed_app_root(self):
        with tempfile.TemporaryDirectory() as directory, \
                patch.dict(os.environ, {"ARTIFACT_TASK_DIR": directory}), \
                patch.object(release.platform, "system", return_value="Darwin"), \
                patch.object(release.platform, "machine", return_value="x86_64"), \
                patch.object(release, "verify_app") as app_check:
            release.verify_intel("1.0.0")
            app_check.assert_called_once_with(_resolved(directory) / "out/BlinkClip.app", "1.0.0", ["x86_64"])

    def test_publish_reads_selected_release_root_and_only_uploads_verified_assets(self):
        with tempfile.TemporaryDirectory() as directory:
            root = _resolved(directory)
            output = root / "verified-assets"
            output.mkdir()
            names = release.asset_names("1.0.0")
            for name in [names[0], "appcast.xml"]:
                (output / name).write_text("fixture-" + name)
            manifest = {"version": "1.0.0", "tag": "v1.0.0", "commit": "fixture-commit", "container": "dmg",
                        "codesign_verified": True, "archives": [{"archive": names[0],
                        "architectures": ["arm64", "x86_64"], "sha256": release.sha(output / names[0])}]}
            (output / "release-manifest.json").write_text(json.dumps(manifest))
            (output / "SHA256SUMS.txt").write_text("".join(
                release.sha(output / name) + "  " + name + "\n" for name in names if name != "SHA256SUMS.txt"))
            commands = []

            def run(args, **kwargs):
                commands.append(args)
                if args[:3] == ["gh", "release", "download"]:
                    download_root = Path(args[args.index("--dir") + 1])
                    for name in names:
                        (download_root / name).write_bytes((output / name).read_bytes())

            with patch.dict(os.environ, {"ARTIFACT_TASK_DIR": str(root / "other-task"),
                                         "BLINKCLIP_RELEASE_OUTPUT_DIR": str(output)}), \
                    patch.object(release, "ROOT", root), \
                    patch.object(release, "check_existing", return_value=({"object": {}}, None)), \
                    patch.object(release, "remote_state"), patch.object(release, "api") as api, \
                    patch.object(release, "changelog_entry", return_value="fixture changes"), \
                    patch.object(release, "verify_dmg") as dmg_check, patch.object(release, "run", side_effect=run):
                release.publish("fixture/blinkclip", "1.0.0", "v1.0.0", "fixture-commit")
                api.assert_not_called()
            dmg_check.assert_called_once_with(output / names[0], "1.0.0", ["arm64", "x86_64"])
            create = next(command for command in commands if command[:3] == ["gh", "release", "create"])
            self.assertEqual(create[4:8], [str(output / name) for name in names])
            self.assertEqual(create[create.index("--notes-file") + 1], str(output / "notes.md"))
            self.assertFalse((root / "replica/dist").exists())

    def test_every_executable_must_include_both_architectures(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "BlinkClip.app"
            (app / "Contents").mkdir(parents=True)
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
                "CFBundleExecutable": "BlinkClip", "CFBundleDisplayName": "BlinkClip",
                "CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "1.0.0", "BlinkClipSourceVersion": "1.0.0",
                "LSMinimumSystemVersion": "14.0", **self.update_config()}))
            for thin_binary in [None, "BlinkClip", "blinkclip-mcp", "BlinkClipHelper", "Sparkle"]:
                with self.subTest(thin_binary=thin_binary):
                    def run(args, **kwargs):
                        if args[0] == "otool":
                            return SimpleNamespace(stdout="cmd LC_BUILD_VERSION\n minos 14.0\n sdk 26.5\n"
                                "path @executable_path/../Frameworks (offset 12)\n"
                                "path @executable_path/../../../../../Frameworks (offset 12)\n")
                        thin = args[0] == "lipo" and Path(args[-1]).name == thin_binary
                        return SimpleNamespace(stdout="arm64" if thin else "arm64 x86_64")
                    with patch.object(release, "run", side_effect=run):
                        if thin_binary is None:
                            release.verify_app(app, "1.0.0", ["arm64", "x86_64"])
                        else:
                            with self.assertRaisesRegex(ValueError, "Unexpected executable architectures"):
                                release.verify_app(app, "1.0.0", ["arm64", "x86_64"])

    def test_system_minimum_and_back_deployment_libraries(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "BlinkClip.app"
            frameworks = app / "Contents/Frameworks"
            frameworks.mkdir(parents=True)
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
                "CFBundleExecutable": "BlinkClip", "CFBundleDisplayName": "BlinkClip",
                "CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "1.0.0", "BlinkClipSourceVersion": "1.0.0",
                "LSMinimumSystemVersion": "14.0", **self.update_config()}))
            library = frameworks / "libswiftCompatibilitySpan.dylib"
            minimum, dependency, library_architectures = "14.0", "", "arm64 x86_64"
            rpaths = ("path @executable_path/../Frameworks (offset 12)\n"
                      "path @executable_path/../../../../../Frameworks (offset 12)")

            def run(args, **kwargs):
                if args[0] == "otool":
                    return SimpleNamespace(stdout=f"cmd LC_BUILD_VERSION\n minos {minimum}\n{dependency}\n{rpaths}\n")
                if args[0] == "lipo" and Path(args[-1]) == library:
                    return SimpleNamespace(stdout=library_architectures)
                return SimpleNamespace(stdout="arm64 x86_64")

            with patch.object(release, "run", side_effect=run):
                release.verify_app(app, "1.0.0", ["arm64", "x86_64"])
                minimum = "26.0"
                with self.assertRaisesRegex(ValueError, "Unexpected minimum macOS version"):
                    release.verify_app(app, "1.0.0", ["arm64", "x86_64"])
                minimum = "14.0"
                saved_rpaths, rpaths = rpaths, ""
                with self.assertRaisesRegex(ValueError, "Missing bundled Frameworks search path"):
                    release.verify_app(app, "1.0.0", ["arm64", "x86_64"])
                rpaths = saved_rpaths
                dependency = "name @rpath/libswiftCompatibilitySpan.dylib (offset 24)"
                with self.assertRaisesRegex(ValueError, "Missing Swift compatibility library"):
                    release.verify_app(app, "1.0.0", ["arm64", "x86_64"])
                library.write_bytes(b"fixture")
                release.verify_app(app, "1.0.0", ["arm64", "x86_64"])
                library_architectures = "arm64"
                with self.assertRaisesRegex(ValueError, "Unexpected library architectures"):
                    release.verify_app(app, "1.0.0", ["arm64", "x86_64"])


if __name__ == "__main__":
    unittest.main()
