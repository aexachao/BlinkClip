#!/usr/bin/env python3
"""Sign every nested executable before its containing bundle (never codesign --deep)."""
import argparse
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile

MACHO = {bytes.fromhex(value) for value in (
    "feedface", "cefaedfe", "feedfacf", "cffaedfe", "cafebabe", "bebafeca", "cafebabf", "bfbafeca")}


def signing_targets(app):
    targets = set()
    for path in app.rglob("*"):
        if path.is_symlink():
            continue
        if path.is_dir() and path.suffix in {".app", ".xpc", ".framework"}:
            targets.add(path)
        elif path.is_file():
            with path.open("rb") as stream:
                if stream.read(4) in MACHO:
                    targets.add(path)
    return sorted(targets, key=lambda p: (-len(p.parts), str(p))) + [app]


def sign_app(app, identity, entitlements=None):
    app = app.resolve(strict=True)
    if app.suffix != ".app" or not (app / "Contents/Info.plist").is_file():
        raise ValueError("Expected a built application bundle")
    if not identity or identity == "-":
        raise ValueError("A real code signing identity is required")
    task = os.environ.get("ARTIFACT_TASK_DIR")
    temporary_root = Path(task) / "build/signing" if task else None
    if temporary_root:
        temporary_root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="blinkclip-sign-", dir=temporary_root) as temporary:
        preserved = Path(temporary) / "entitlements.plist"
        for target in signing_targets(app):
            command = ["codesign", "--force", "--sign", identity, "--options", "runtime", "--timestamp"]
            if target == app and entitlements:
                command += ["--entitlements", str(entitlements)]
            else:
                result = subprocess.run(["codesign", "--display", "--entitlements", ":-", str(target)],
                                        capture_output=True, check=False)
                if result.stdout.strip():
                    values = plistlib.loads(result.stdout)
                    values.pop("com.apple.security.get-task-allow", None)
                    if values:
                        preserved.write_bytes(plistlib.dumps(values))
                        command += ["--entitlements", str(preserved)]
            subprocess.run([*command, str(target)], check=True)
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--identity", default=os.environ.get("BLINKCLIP_SIGNING_IDENTITY"))
    parser.add_argument("--entitlements", type=Path)
    arguments = parser.parse_args()
    sign_app(arguments.app, arguments.identity, arguments.entitlements)


if __name__ == "__main__":
    main()
