"""发布的 CloudKit 闸门：正式包缺描述文件或缺 CloudKit 授权时必须中止，而不是静默降级。

用例不真签名：用 fixture entitlements 覆盖 `app_entitlements()`，描述文件用空的
`Contents/embedded.provisionprofile` 占位。脚本级用例只跑「变量缺失」的早退路径，
不会触发编译。
"""
import importlib.util
import os
import plistlib
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("release_ci_cloudkit",
                                              ROOT / "replica/scripts/release-ci.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)

BUILD_NOTARIZED = ROOT / "replica/scripts/build-notarized.sh"
CLOUDKIT_VARIABLES = ("BLINKCLIP_CLOUDKIT_PROFILE", "BLINKCLIP_CLOUDKIT_CONTAINER",
                      "BLINKCLIP_CLOUDKIT_ENVIRONMENT")


def signed_entitlements(environment="Production"):
    """1.0.33/1.0.34 真机产物的 7 个键（见 evidence/release/r25b-build-report.md §4）。"""
    return {
        "com.apple.application-identifier": "4NJM425J3B.com.chrisli.blinkclip",
        "com.apple.developer.icloud-container-environment": environment,
        "com.apple.developer.icloud-container-identifiers": ["iCloud.com.chrisli.blinkclip"],
        "com.apple.developer.icloud-services": ["CloudKit"],
        "com.apple.developer.team-identifier": "4NJM425J3B",
        "com.apple.developer.ubiquity-kvstore-identifier": "4NJM425J3B.com.chrisli.blinkclip",
        "com.apple.security.automation.apple-events": True,
    }


class CloudKitReleaseGateTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.app = Path(self.directory.name) / "BlinkClip.app"
        (self.app / "Contents").mkdir(parents=True)

    def write_profile(self, size=13355):
        (self.app / "Contents/embedded.provisionprofile").write_bytes(b"fixture"[:size].ljust(size, b"\0"))

    def test_missing_embedded_provisionprofile_fails(self):
        with patch.object(release, "app_entitlements", return_value=signed_entitlements()):
            with self.assertRaisesRegex(ValueError, "embedded\\.provisionprofile"):
                release.verify_cloudkit(self.app, environment="Production")

    def test_empty_embedded_provisionprofile_fails(self):
        self.write_profile(size=0)
        with patch.object(release, "app_entitlements", return_value=signed_entitlements()):
            with self.assertRaisesRegex(ValueError, "描述文件为空"):
                release.verify_cloudkit(self.app, environment="Production")

    def test_entitlements_without_cloudkit_keys_fail(self):
        self.write_profile()
        bare = {"com.apple.security.automation.apple-events": True}
        problems = release.cloudkit_entitlement_problems(bare, environment="Production")
        self.assertEqual(len(problems), 3)
        self.assertTrue(any("com.apple.developer.icloud-services" in problem for problem in problems))
        self.assertTrue(any("icloud-container-identifiers" in problem for problem in problems))
        self.assertTrue(any("icloud-container-environment" in problem for problem in problems))
        with patch.object(release, "app_entitlements", return_value=bare):
            with self.assertRaisesRegex(ValueError, "com\\.apple\\.developer\\.icloud-services"):
                release.verify_cloudkit(self.app, environment="Production")

    def test_get_task_allow_fails(self):
        self.write_profile()
        debugging = signed_entitlements()
        debugging["com.apple.security.get-task-allow"] = True
        problems = release.cloudkit_entitlement_problems(debugging, environment="Production")
        self.assertEqual(len(problems), 1)
        self.assertIn("get-task-allow", problems[0])
        with patch.object(release, "app_entitlements", return_value=debugging):
            with self.assertRaisesRegex(ValueError, "get-task-allow"):
                release.verify_cloudkit(self.app, environment="Production")

    def test_complete_seven_keys_pass(self):
        self.write_profile()
        entitlements = signed_entitlements()
        self.assertEqual(len(entitlements), 7)
        self.assertEqual(release.cloudkit_entitlement_problems(entitlements, environment="Production"), [])
        with patch.object(release, "app_entitlements", return_value=entitlements):
            self.assertEqual(release.verify_cloudkit(self.app, environment="Production"), entitlements)

    def test_services_list_may_carry_more_than_cloudkit(self):
        entitlements = signed_entitlements()
        entitlements["com.apple.developer.icloud-services"] = ["CloudKit", "CloudDocuments"]
        self.assertEqual(release.cloudkit_entitlement_problems(entitlements, environment="Production"), [])

    def test_environment_must_match_expectation(self):
        self.write_profile()
        development = signed_entitlements(environment="Development")
        # 未显式给期望值时按 Production 处理，Apple 下发的 Development 描述文件必须被拦住。
        with patch.dict(os.environ, {}, clear=True):
            problems = release.cloudkit_entitlement_problems(development)
        self.assertEqual(len(problems), 1)
        self.assertIn("Production", problems[0])
        with patch.dict(os.environ, {"BLINKCLIP_CLOUDKIT_ENVIRONMENT": "Production"}):
            with patch.object(release, "app_entitlements", return_value=development):
                with self.assertRaisesRegex(ValueError, "icloud-container-environment"):
                    release.verify_cloudkit(self.app)
        self.assertEqual(release.cloudkit_entitlement_problems(development, environment="Development"), [])

    def test_unexpected_environment_value_is_rejected(self):
        with self.assertRaises(ValueError):
            release.cloudkit_entitlement_problems(signed_entitlements(), environment="Staging")

    def test_verify_app_runs_the_cloudkit_gate(self):
        """verify_app 不能只校验版本与签名：CloudKit 闸门必须在打包校验里被调用。"""
        (self.app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleExecutable": "BlinkClip", "CFBundleDisplayName": "BlinkClip",
            "CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "1.0.0",
            "BlinkClipSourceVersion": "1.0.0", "LSMinimumSystemVersion": "14.0",
            "SUFeedURL": "https://github.com/aexachao/BlinkClip/releases/latest/download/appcast.xml",
            "SUPublicEDKey": (ROOT / "replica/Assets/UpdatePublicKey.txt").read_text().strip(),
            "SURequireSignedFeed": True, "SUVerifyUpdateBeforeExtraction": True,
            "SUEnableAutomaticChecks": False, "SUAutomaticallyUpdate": False, "SUSendProfileInfo": False}))
        with patch.object(release, "run", return_value=SimpleNamespace(stdout="arm64 x86_64")), \
                patch.object(release, "verify_cloudkit", side_effect=ValueError("缺 CloudKit 授权")) as gate:
            with self.assertRaisesRegex(ValueError, "缺 CloudKit 授权"):
                release.verify_app(self.app, "1.0.0", ["arm64", "x86_64"])
        gate.assert_called_once_with(self.app)


class NotarizedScriptGateTests(unittest.TestCase):
    """build-notarized.sh 必须在使用前就拦住缺失的 CloudKit 配置。"""

    def run_script(self, environment):
        return subprocess.run(["bash", str(BUILD_NOTARIZED)], cwd=ROOT, capture_output=True, text=True,
                              env=environment)

    def isolated_environment(self, **overrides):
        environment = {key: value for key, value in os.environ.items() if key not in CLOUDKIT_VARIABLES}
        environment.update(overrides)
        return environment

    def test_script_parses(self):
        self.assertEqual(subprocess.run(["bash", "-n", str(BUILD_NOTARIZED)], capture_output=True).returncode, 0)

    def test_missing_cloudkit_variables_exit_two_before_building(self):
        with tempfile.TemporaryDirectory() as directory:
            task = Path(directory) / "never-created"
            profile = Path(directory) / "fixture.provisionprofile"
            profile.write_bytes(b"fixture")
            environment = self.isolated_environment(ARTIFACT_TASK_DIR=str(task))
            for missing in (CLOUDKIT_VARIABLES, CLOUDKIT_VARIABLES[:1], CLOUDKIT_VARIABLES[1:]):
                with self.subTest(missing=missing):
                    provided = {name: value for name, value in (
                        ("BLINKCLIP_CLOUDKIT_PROFILE", str(profile)),
                        ("BLINKCLIP_CLOUDKIT_CONTAINER", "iCloud.com.chrisli.blinkclip"),
                        ("BLINKCLIP_CLOUDKIT_ENVIRONMENT", "Production")) if name not in missing}
                    result = self.run_script({**environment, **provided})
                    self.assertEqual(result.returncode, 2, result.stderr)
                    for name in missing:
                        self.assertIn(name, result.stderr)
                    self.assertFalse(task.exists(), "缺变量时不应创建任何构建输出")

    def test_invalid_environment_exits_two(self):
        with tempfile.TemporaryDirectory() as directory:
            task = Path(directory) / "never-created"
            profile = Path(directory) / "fixture.provisionprofile"
            profile.write_bytes(b"fixture")
            result = self.run_script(self.isolated_environment(
                ARTIFACT_TASK_DIR=str(task), BLINKCLIP_CLOUDKIT_PROFILE=str(profile),
                BLINKCLIP_CLOUDKIT_CONTAINER="iCloud.com.chrisli.blinkclip",
                BLINKCLIP_CLOUDKIT_ENVIRONMENT="Staging"))
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertIn("Development 或 Production", result.stderr)
            self.assertFalse(task.exists())

    def test_unreadable_profile_exits_two(self):
        with tempfile.TemporaryDirectory() as directory:
            task = Path(directory) / "never-created"
            result = self.run_script(self.isolated_environment(
                ARTIFACT_TASK_DIR=str(task), BLINKCLIP_CLOUDKIT_PROFILE=str(Path(directory) / "absent.provisionprofile"),
                BLINKCLIP_CLOUDKIT_CONTAINER="iCloud.com.chrisli.blinkclip",
                BLINKCLIP_CLOUDKIT_ENVIRONMENT="Production"))
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertIn("不存在或不可读", result.stderr)
            self.assertFalse(task.exists())


if __name__ == "__main__":
    unittest.main()
