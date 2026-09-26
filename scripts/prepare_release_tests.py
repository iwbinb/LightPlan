#!/usr/bin/env python3
"""Isolated Git fixtures; not release approvals."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import prepare_release as prep


class PreparationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name); self.output = self.root / 'tests/reports/local/candidate'
        source = Path(__file__).resolve().parents[1]
        for folder in ('appstore', 'codex', 'docs'):
            shutil.copytree(source / folder, self.root / folder)
        for target in ('LightPlan', 'LightPlanWidget'):
            dest = self.root / 'ios' / target; dest.mkdir(parents=True)
            for name in ('Info.plist', 'PrivacyInfo.xcprivacy'):
                shutil.copyfile(source / 'ios' / target / name, dest / name)
        (self.root / '.gitignore').write_text('/tests/reports/local/\n')
        self.git('init', '-q'); self.git('config', 'user.name', 'Synthetic Fixture')
        self.git('config', 'user.email', 'fixture@localhost'); self.commit()

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.root, text=True, stderr=subprocess.DEVNULL).strip()

    def commit(self):
        self.git('add', '-A'); self.git('commit', '-qm', 'Synthetic fixture')

    def test_prepared_is_not_approved_and_history_is_untouched(self):
        before = (self.root / 'codex/release_gates.json').read_bytes()
        result = prep.prepare(self.root, self.output)
        self.assertTrue(result['prepared']); self.assertFalse(result['ready_for_submission'])
        self.assertGreater(result['submission_blockers'], 0)
        self.assertEqual(before, (self.root / 'codex/release_gates.json').read_bytes())
        gates = json.loads((self.output / 'release_gates.json').read_text())['gates']
        self.assertEqual(len(gates), 20)
        self.assertTrue(all(x['status'] == 'pending' and not x['evidence'] and x['reviewer'] is None for x in gates))
        self.assertEqual(self.git('status', '--porcelain'), '')

    def test_never_overwrites_existing_owner_evidence(self):
        self.output.mkdir(parents=True); (self.output / 'owner.txt').write_text('preserve')
        with self.assertRaisesRegex(prep.PreparationError, 'already exists'):
            prep.prepare(self.root, self.output)
        self.assertEqual((self.output / 'owner.txt').read_text(), 'preserve')

    def test_dirty_worktree_is_rejected(self):
        (self.root / 'change.txt').write_text('unsaved')
        with self.assertRaisesRegex(prep.PreparationError, 'clean Git'):
            prep.prepare(self.root, self.output)

    def test_outside_unignored_and_symlink_outputs_are_rejected(self):
        for path in (self.root / 'public-package', self.root.parent / 'escape'):
            with self.assertRaises(prep.PreparationError): prep.prepare(self.root, path)
        (self.root / '.gitignore').write_text(''); self.commit()
        with self.assertRaisesRegex(prep.PreparationError, 'not Git-ignored'):
            prep.prepare(self.root, self.output)

    def test_parent_symlink_cannot_redirect_private_evidence(self):
        (self.root / 'tests/reports').mkdir(parents=True)
        (self.root / 'elsewhere').mkdir()
        (self.root / 'tests/reports/local').symlink_to(self.root / 'elsewhere', target_is_directory=True)
        with self.assertRaisesRegex(prep.PreparationError, 'symbolic link'):
            prep.prepare(self.root, self.output)

    def test_gate_removal_or_waiver_is_rejected(self):
        path = self.root / 'codex/release_gates.json'
        data = json.loads(path.read_text()); data['gates'][0]['required'] = False
        path.write_text(json.dumps(data)); self.commit()
        with self.assertRaisesRegex(prep.PreparationError, 'G01'):
            prep.prepare(self.root, self.output)

    def test_missing_locale_is_rejected(self):
        (self.root / 'appstore/metadata/th.json').unlink(); self.commit()
        with self.assertRaisesRegex(prep.PreparationError, 'nine'):
            prep.prepare(self.root, self.output)

    def test_no_account_or_signing_files_are_copied(self):
        private = self.root / 'tests/reports/local'; private.mkdir(parents=True)
        (private / 'identity.p12').write_text('do not copy')
        result = prep.prepare(self.root, self.output)
        self.assertTrue(result['prepared'])
        self.assertFalse(list(self.output.rglob('*.p12')))
        manifest = json.loads((self.output / 'submission_manifest.json').read_text())
        self.assertTrue(all(x['status'] == 'pending' for x in manifest['account_checks'].values()))
        self.assertEqual(manifest['screenshots'], [])

    def test_concurrent_source_change_is_rejected_atomically(self):
        head = self.git('rev-parse', 'HEAD')
        with patch.object(prep, 'git_state', side_effect=[(head, False), (head, True)]):
            with self.assertRaisesRegex(prep.PreparationError, 'changed during'):
                prep.prepare(self.root, self.output)
        self.assertFalse(self.output.exists())

    def test_missing_public_handoff_is_not_silently_omitted(self):
        (self.root / 'docs/M6B_LOCAL_HANDOFF.md').unlink(); self.commit()
        with self.assertRaisesRegex(prep.PreparationError, 'handoff'):
            prep.prepare(self.root, self.output)


if __name__ == '__main__': unittest.main()
