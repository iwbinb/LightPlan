#!/usr/bin/env python3
"""Project-generator fixtures: validate output consistency without invoking Xcode."""
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1]


class GeneratorTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        for folder in ('scripts', 'appstore', 'ios', 'licenses'):
            shutil.copytree(SOURCE / folder, self.root / folder, ignore=shutil.ignore_patterns('__pycache__', 'Local.xcconfig'))
        self.config = json.loads((self.root/'appstore/release_config.json').read_text())

    def generate(self):
        (self.root/'appstore/release_config.json').write_text(json.dumps(self.config))
        return subprocess.run(['python3', str(self.root/'scripts/generate_project.py')], capture_output=True, text=True)

    def test_current_settings_preserve_entire_checked_in_project(self):
        self.assertEqual(self.generate().returncode, 0)
        for path in (SOURCE/'LightPlan.xcodeproj').rglob('*'):
            if path.is_file():
                self.assertEqual(path.read_bytes(), (self.root/path.relative_to(SOURCE)).read_bytes())

    def test_config_controls_both_targets_and_generation_is_repeatable(self):
        self.config.update(candidate_name='Synthetic App', candidate_bundle_id='org.synthetic.photo',
                           candidate_app_group_id='group.org.synthetic.photo', marketing_version='1.2.3',
                           build_number='7', minimum_runtime_ios='18.0')
        self.assertEqual(self.generate().returncode, 0)
        for target in ('LightPlan', 'LightPlanWidget'):
            info=plistlib.loads((self.root/f'ios/{target}/Info.plist').read_bytes())
            self.assertEqual(info['CFBundleDisplayName'], 'Synthetic App')
            self.assertEqual(info['CFBundleVersion'], '$(CURRENT_PROJECT_VERSION)')
        config=(self.root/'ios/Config/Project.xcconfig').read_text()
        self.assertIn('APP_BUNDLE_ID = org.synthetic.photo', config)
        self.assertIn('APP_GROUP_ID = group.org.synthetic.photo', config)
        pbx=self.root/'LightPlan.xcodeproj/project.pbxproj';before=pbx.read_bytes()
        for value in ('"MARKETING_VERSION" = "1.2.3"', '"CURRENT_PROJECT_VERSION" = "7"', '"IPHONEOS_DEPLOYMENT_TARGET" = "18.0"'):
            self.assertIn(value, before.decode())
        self.assertEqual(self.generate().returncode, 0);self.assertEqual(before, pbx.read_bytes())

    def test_bad_settings_fail_before_overwriting_generated_files(self):
        self.assertEqual(self.generate().returncode, 0)
        pbx=self.root/'LightPlan.xcodeproj/project.pbxproj';before=pbx.read_bytes()
        self.config['candidate_bundle_id']='foo\n#include "unapproved"'
        self.assertNotEqual(self.generate().returncode, 0)
        self.assertEqual(before, pbx.read_bytes())

    def test_local_signing_overrides_are_preserved(self):
        path=self.root/'ios/Config/Local.xcconfig';path.write_text('// SYNTHETIC_LOCAL_SIGNING')
        self.assertEqual(self.generate().returncode, 0)
        self.assertEqual(path.read_text(), '// SYNTHETIC_LOCAL_SIGNING')


if __name__ == '__main__': unittest.main()
