import copy
import datetime
import importlib.util
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / 'scripts/configure-cloudkit-signing.py'
spec = importlib.util.spec_from_file_location('cloudkit_signing', SCRIPT)
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)


class CloudKitSigningTests(unittest.TestCase):
    def setUp(self):
        self.profile = {
            'TeamIdentifier': ['TESTTEAM01'],
            'ExpirationDate': datetime.datetime.now() + datetime.timedelta(days=1),
            'Entitlements': {
                'com.apple.application-identifier': 'TESTTEAM01.local.blinkclip.tests',
                'com.apple.developer.icloud-container-identifiers': ['iCloud.local.blinkclip.tests'],
                'com.apple.developer.icloud-services': ['CloudKit'],
                'com.apple.developer.icloud-container-environment': ['Development'],
                'com.apple.developer.aps-environment': 'development',
            },
        }

    def validate(self, profile=None, **options):
        return signing.validate_profile(profile or self.profile, options.get('bundle', 'local.blinkclip.tests'),
                                        options.get('container', 'iCloud.local.blinkclip.tests'), options.get('environment', 'Development'))

    def test_valid_profile_and_no_mutation(self):
        before = copy.deepcopy(self.profile)
        result = self.validate()
        self.assertEqual(result['com.apple.developer.icloud-services'], ['CloudKit'])
        self.assertEqual(result['com.apple.developer.aps-environment'], 'development')
        self.assertEqual(before, self.profile)

    def test_expired(self):
        self.profile['ExpirationDate'] = datetime.datetime(2020, 1, 1)
        with self.assertRaises(ValueError): self.validate()

    def test_wrong_app(self):
        with self.assertRaises(ValueError): self.validate(bundle='local.other.app')

    def test_wrong_container(self):
        with self.assertRaises(ValueError): self.validate(container='iCloud.local.other')

    def test_original_vendor_rejected(self):
        self.profile['TeamIdentifier'] = ['4788TTJ39Y']
        with self.assertRaises(ValueError): self.validate()

    def test_wrong_environment(self):
        with self.assertRaises(ValueError): self.validate(environment='Production')

    def test_no_cloudkit_service(self):
        self.profile['Entitlements']['com.apple.developer.icloud-services'] = ['CloudDocuments']
        with self.assertRaises(ValueError): self.validate()

    def test_kvstore_identifier_copied_verbatim(self):
        self.profile['Entitlements']['com.apple.developer.ubiquity-kvstore-identifier'] = 'TESTTEAM01.local.blinkclip.tests'
        self.assertEqual(self.validate()['com.apple.developer.ubiquity-kvstore-identifier'], 'TESTTEAM01.local.blinkclip.tests')

    def test_kvstore_identifier_omitted_when_profile_lacks_it(self):
        self.assertNotIn('com.apple.developer.ubiquity-kvstore-identifier', self.validate())

    def test_debugger_attachments_never_signed(self):
        # 开发描述文件会带 get-task-allow；发布签名里出现它等于允许调试器挂载，
        # 与 Assets/BlinkClip.entitlements 的取舍冲突，因此必须显式丢弃。
        self.profile['Entitlements'].update({'get-task-allow': True, 'com.apple.security.get-task-allow': True})
        result = self.validate()
        self.assertNotIn('get-task-allow', result)
        self.assertNotIn('com.apple.security.get-task-allow', result)


if __name__ == '__main__':
    unittest.main()
