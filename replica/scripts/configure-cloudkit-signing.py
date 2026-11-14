#!/usr/bin/env python3
"""Configure only a user's own, matching Apple provisioning profile. Never edits a profile."""
import argparse
import datetime
import hashlib
import plistlib
import re
import shutil
import subprocess
from pathlib import Path


def validate_signing_identity(profile, identity, identities):
    matches = [(fingerprint, name) for fingerprint, name in
               re.findall(r'\) ([A-Fa-f0-9]{40}) "([^"]+)"', identities)
               if identity.upper() == fingerprint.upper() or identity == name]
    if len(matches) != 1:
        raise ValueError('需要唯一且有效的本机 Apple 签名身份。')
    fingerprint = matches[0][0].upper()
    authorized = {hashlib.sha1(cert).hexdigest().upper() for cert in profile.get('DeveloperCertificates', [])}
    if fingerprint not in authorized:
        raise ValueError('签名证书不在描述文件的 DeveloperCertificates 中，请重新生成匹配的描述文件。')


def validate_profile(profile, bundle_id, container, environment):
    entitlements = profile.get('Entitlements', {})
    teams = profile.get('TeamIdentifier', [])
    if len(teams) != 1 or teams[0] == '4788TTJ39Y':
        raise ValueError('需要 BlinkClip 自有开发者团队，不能使用原版厂商团队。')
    team = teams[0]
    if not container.startswith('iCloud.') or 'wiheads' in container.lower():
        raise ValueError('需要 BlinkClip 自有的 iCloud 容器。')
    app_id = f'{team}.{bundle_id}'
    if entitlements.get('com.apple.application-identifier') != app_id:
        raise ValueError('描述文件的应用标识与当前 Bundle ID 不匹配。')
    if container not in entitlements.get('com.apple.developer.icloud-container-identifiers', []):
        raise ValueError('描述文件未授权此 CloudKit 容器。')
    services = entitlements.get('com.apple.developer.icloud-services', [])
    if isinstance(services, str):
        services = [services]
    if not {'CloudKit', '*'}.intersection(services):
        raise ValueError('描述文件未启用 CloudKit。')
    allowed = entitlements.get('com.apple.developer.icloud-container-environment', [])
    if isinstance(allowed, str):
        allowed = [allowed]
    if environment not in allowed:
        raise ValueError('描述文件未授权此 CloudKit 环境。')
    if profile.get('ExpirationDate', datetime.datetime.min) <= datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None):
        raise ValueError('描述文件已过期。')
    result = {
        'com.apple.application-identifier': app_id,
        'com.apple.developer.team-identifier': team,
        'com.apple.developer.icloud-container-identifiers': [container],
        'com.apple.developer.icloud-services': ['CloudKit'],
        'com.apple.developer.icloud-container-environment': environment,
    }
    # A profile is an allowlist; Apple can authorize TEAM.* here even for an
    # explicit App ID. The signature must contain a concrete, permitted value
    # (TN2415), while an already concrete/legacy KV identifier stays unchanged.
    kvstore = entitlements.get('com.apple.developer.ubiquity-kvstore-identifier')
    if isinstance(kvstore, str) and kvstore:
        if '*' in kvstore:
            if kvstore.count('*') != 1 or not kvstore.endswith('.*') or not app_id.startswith(kvstore[:-1]):
                raise ValueError('描述文件的 KV 存储通配授权与当前应用不匹配。')
            kvstore = app_id
        result['com.apple.developer.ubiquity-kvstore-identifier'] = kvstore
    for key in ('com.apple.developer.aps-environment', 'aps-environment'):
        if key in entitlements:
            result[key] = entitlements[key]
    # get-task-allow 只影响调试器挂载，却会随签名进入分发版；sign-app.py 已把它
    # 从嵌套可执行文件里剔除，主程序必须同样剔除，所以这里显式丢弃而不是复制。
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', type=Path, required=True)
    parser.add_argument('--bundle', type=Path, required=True)
    parser.add_argument('--container', required=True)
    parser.add_argument('--environment', choices=['Development', 'Production'], default='Development')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--identity', required=True)
    args = parser.parse_args()
    decoded = subprocess.run(['/usr/bin/security', 'cms', '-D', '-i', str(args.profile)], check=True, capture_output=True)
    profile = plistlib.loads(decoded.stdout)
    info_path = args.bundle / 'Contents/Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    entitlements = validate_profile(profile, info['CFBundleIdentifier'], args.container, args.environment)
    identities = subprocess.run(['/usr/bin/security', 'find-identity', '-v', '-p', 'codesigning'],
                                check=True, capture_output=True, text=True).stdout
    validate_signing_identity(profile, args.identity, identities)
    args.output.write_bytes(plistlib.dumps(entitlements))
    info['BlinkClipCloudKitContainerIdentifier'] = args.container
    info_path.write_bytes(plistlib.dumps(info))
    shutil.copyfile(args.profile, args.bundle / 'Contents/embedded.provisionprofile')


if __name__ == '__main__':
    main()
