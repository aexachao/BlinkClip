#!/usr/bin/env python3
"""Create a Developer ID signed, notarized Universal DMG without publishing it.

Requires storage-guard, BLINKCLIP_SIGNING_IDENTITY and a notarytool keychain profile.
Credentials stay in Keychain. Sparkle feeds must be generated after this finishes.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def run(arguments, **kwargs):
    return subprocess.run([str(value) for value in arguments], check=True, cwd=ROOT, **kwargs)


def digest(path):
    checksum = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            checksum.update(block)
    return checksum.hexdigest()


def verify_distribution(app, team):
    spec = importlib.util.spec_from_file_location("blinkclip_signing", Path(__file__).with_name("sign-app.py"))
    signing = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(signing)
    run(["codesign", "--verify", "--deep", "--strict", app])
    for target in signing.signing_targets(app):
        details = run(["codesign", "--display", "--verbose=4", target], capture_output=True, text=True).stderr
        if ("Authority=Developer ID Application:" not in details or f"TeamIdentifier={team}\n" not in details
                or "(runtime)" not in details or "Timestamp=" not in details):
            raise ValueError(f"Missing Developer ID, team, Hardened Runtime or timestamp: {target}")
        result = run(["codesign", "--display", "--entitlements", ":-", target], capture_output=True)
        if result.stdout.strip() and plistlib.loads(result.stdout).get("com.apple.security.get-task-allow"):
            raise ValueError(f"Debug entitlement is forbidden in distribution: {target}")


def notarize(archive, staple_target, profile, evidence):
    """Persist the submission before waiting so a timeout can safely be resumed."""
    evidence.mkdir(parents=True, exist_ok=True)
    receipt = evidence / "submission.json"
    archive_hash = digest(archive)
    if receipt.exists():
        submission = json.loads(receipt.read_text())
        if submission["sha256"] != archive_hash:
            raise ValueError(f"Submission is for different bytes; use a new output directory: {receipt}")
    else:
        result = run(["xcrun", "notarytool", "submit", archive, "--keychain-profile", profile,
                      "--output-format", "json"], capture_output=True, text=True)
        submission = json.loads(result.stdout)
        if not submission.get("id"):
            raise ValueError("Apple did not return a notarization submission ID")
        submission["sha256"] = archive_hash
        receipt.write_text(json.dumps(submission, indent=2) + "\n")
    identifier = submission["id"]
    print(f"Apple notarization submission: {identifier}", flush=True)
    result = subprocess.run(["xcrun", "notarytool", "wait", identifier, "--keychain-profile", profile,
                             "--timeout", "20m", "--output-format", "json"],
                            cwd=ROOT, capture_output=True, text=True)
    (evidence / "wait.json").write_text(result.stdout)
    (evidence / "wait.stderr.txt").write_text(result.stderr)
    if result.returncode:
        raise RuntimeError(f"Notarization is unfinished; resume with the same archive and profile. ID: {identifier}")
    status = json.loads(result.stdout)
    run(["xcrun", "notarytool", "log", identifier, "--keychain-profile", profile, evidence / "apple-log.json"])
    if status.get("status") != "Accepted":
        raise ValueError(f"Apple notarization rejected the upload; inspect {evidence / 'apple-log.json'}")
    run(["xcrun", "stapler", "staple", staple_target])
    run(["xcrun", "stapler", "validate", staple_target])
    return identifier


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", default=os.environ.get("BLINKCLIP_NOTARY_PROFILE"))
    parser.add_argument("--team", default="4NJM425J3B")
    parser.add_argument("--app", type=Path)
    parser.add_argument("--output", type=Path)
    arguments = parser.parse_args()
    task_value = os.environ.get("ARTIFACT_TASK_DIR")
    if not task_value or not arguments.profile:
        parser.error("Run via storage-guard and provide --profile (a notarytool Keychain profile)")
    task = Path(task_value).resolve(strict=True)
    app = (arguments.app or task / "out/BlinkClip.app").resolve(strict=True)
    output = (arguments.output or task / "out/release").resolve()
    if not app.is_relative_to(task) or not output.is_relative_to(task / "out"):
        parser.error("App and output must belong to the current storage-guard task")
    output.mkdir(parents=True, exist_ok=True)
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    version = info["BlinkClipSourceVersion"]
    if info.get("CFBundleIdentifier") != "com.chrisli.blinkclip":
        raise ValueError("Unexpected application identifier")
    verify_distribution(app, arguments.team)
    # Verify architectures, metadata and Sparkle configuration using the release contract.
    spec = importlib.util.spec_from_file_location("blinkclip_release", Path(__file__).with_name("release-ci.py"))
    release = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(release)
    release.verify_app(app, version, ["arm64", "x86_64"])
    evidence = output / "evidence"
    app_ticket = subprocess.run(["xcrun", "stapler", "validate", str(app)], capture_output=True)
    if app_ticket.returncode:
        # Preserve exactly the uploaded bytes across storage-guard teardown/timeouts.
        archive = evidence / "app/BlinkClip.zip"
        archive.parent.mkdir(parents=True, exist_ok=True)
        if not archive.exists():
            run(["ditto", "-c", "-k", "--keepParent", app, archive])
        notarize(archive, app, arguments.profile, evidence / "app")
    run(["spctl", "--assess", "--type", "execute", "--verbose=4", app])
    dmg = output / f"BlinkClip-{version}-macos-universal.dmg"
    if not dmg.exists():
        run(["bash", "replica/scripts/build-dmg.sh", app, dmg, "universal"])
        identity = os.environ.get("BLINKCLIP_SIGNING_IDENTITY")
        if not identity or identity == "-":
            raise ValueError("BLINKCLIP_SIGNING_IDENTITY is required to sign the DMG")
        run(["codesign", "--force", "--sign", identity, "--timestamp", dmg])
    if subprocess.run(["xcrun", "stapler", "validate", str(dmg)], capture_output=True).returncode:
        notarize(dmg, dmg, arguments.profile, evidence / "dmg")
    run(["codesign", "--verify", "--strict", dmg])
    run(["spctl", "--assess", "--type", "open", "--context", "context:primary-signature", "--verbose=4", dmg])
    release.verify_dmg(dmg, version, ["arm64", "x86_64"])
    manifest = {"version": version, "bundle_id": info["CFBundleIdentifier"], "team_id": arguments.team,
                "archive": dmg.name, "sha256": digest(dmg), "architectures": ["arm64", "x86_64"],
                "codesign_verified": True, "notarized": True, "stapled": True, "gatekeeper_accepted": True,
                "functional_tests_executed": False, "sparkle_feed_generated": False}
    (output / "signing-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (output / "SHA256SUMS.txt").write_text(digest(dmg) + "  " + dmg.name + "\n")
    print(f"Signed and notarized installer: {dmg}", flush=True)


if __name__ == "__main__":
    main()
