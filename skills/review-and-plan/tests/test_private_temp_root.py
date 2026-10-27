"""Filesystem tests for the root used by both handoffs and session snapshots."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/private-temp-root.sh"


class PrivateTempRootTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="review-and-plan-root-tests-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "private root"

    def run_script(self):
        return subprocess.run(
            ["bash", str(SCRIPT), str(self.root)],
            capture_output=True,
            text=True,
            check=False,
        )

    def test_creates_private_owned_root(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), str(self.root))
        self.assertEqual(self.root.stat().st_uid, os.geteuid())
        self.assertEqual(self.root.stat().st_mode & 0o7777, 0o700)

    def test_accepts_existing_private_root_without_changing_contents(self):
        self.root.mkdir(mode=0o700)
        marker = self.root / "keep.txt"
        marker.write_text("unchanged")
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(marker.read_text(), "unchanged")

    def test_rejects_insecure_modes_without_repairing_them(self):
        self.root.mkdir()
        for mode in (0o755, 0o777, 0o770, 0o707, 0o1700):
            with self.subTest(mode=oct(mode)):
                self.root.chmod(mode)
                result = self.run_script()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("0700", result.stderr)
                self.assertEqual(result.stdout, "")
                self.assertEqual(self.root.stat().st_mode & 0o7777, mode)
                self.assertEqual(list(self.root.iterdir()), [])

    def test_rejects_symlink_even_to_private_owned_root(self):
        target = Path(self.temp.name) / "target"
        target.mkdir(mode=0o700)
        self.root.symlink_to(target, target_is_directory=True)
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("symlink", result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertEqual(list(target.iterdir()), [])

    def test_rejects_dangling_symlink_without_creating_target(self):
        target = Path(self.temp.name) / "missing"
        self.root.symlink_to(target, target_is_directory=True)
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("symlink", result.stderr)
        self.assertFalse(target.exists())

    def test_rejects_foreign_owned_root_without_changing_it(self):
        # / is a real foreign-owned directory for ordinary non-root test users.
        self.root = Path("/")
        before = self.root.stat()
        if before.st_uid == os.geteuid():
            self.skipTest("requires a foreign-owned directory")
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("owned by", result.stderr)
        self.assertEqual(result.stdout, "")
        after = self.root.stat()
        self.assertEqual(after.st_uid, before.st_uid)
        self.assertEqual(after.st_mode, before.st_mode)

    def test_rejects_regular_file_without_overwriting_it(self):
        self.root.write_text("do not overwrite")
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("directory", result.stderr)
        self.assertEqual(self.root.read_text(), "do not overwrite")


if __name__ == "__main__":
    unittest.main()
