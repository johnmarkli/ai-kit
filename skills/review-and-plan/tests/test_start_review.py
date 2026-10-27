"""Launcher contract tests; no live panes or model calls."""

import json
import os
import shlex
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/start-review.sh"


class StartReviewTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="review-and-plan-tests-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.log = self.root / "calls.jsonl"
        self.session = self.root / "parent session.jsonl"
        self.session.write_text('{"type":"session","id":"parent"}\n')
        self.prompt = self.root / "review prompt.md"
        self.prompt.write_text("Review both passes, don't implement.\n")
        self.context = self.root / "runtime context.md"
        self.context.write_text("Preserve the parent's runtime rules.\n")
        self.env = dict(
            os.environ,
            PATH=f"{self.bin}:{os.environ['PATH']}",
            HERDR_ENV="1",
            HERDR_PANE_ID="w1:p1",
            PI_SESSION_FILE=str(self.session),
            CALL_LOG=str(self.log),
        )
        fake = """#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
name = Path(sys.argv[0]).name
with open(os.environ['CALL_LOG'], 'a') as f:
    f.write(json.dumps([name, *args]) + '\\n')
if name == 'pi':
    print('provider model context')
    if not os.environ.get('NO_MODEL'):
        print('openai gpt-6.1-sol 272K')
elif args[:2] == ['pane', 'split']:
    print(json.dumps({'result': {'pane': {'pane_id': 'w1:p2'}}}))
elif args[:2] == ['pane', 'run'] and os.environ.get('FAIL_START'):
    sys.exit(1)
else:
    print('{}')
"""
        for name in ("pi", "herdr", "run-agent"):
            path = self.bin / name
            path.write_text(fake)
            path.chmod(0o755)

    def run_script(self, *extra):
        result = subprocess.run(
            [
                "bash",
                str(SCRIPT),
                "--prompt-file",
                str(self.prompt),
                "--context-file",
                str(self.context),
                *extra,
            ],
            env=self.env,
            cwd=self.root,
            text=True,
            capture_output=True,
            check=False,
        )
        # Snapshots deliberately survive the launcher; remove only our test run.
        if result.returncode == 0:
            self.addCleanup(shutil.rmtree, json.loads(result.stdout)["run_dir"])
        return result

    def calls(self):
        return (
            [json.loads(line) for line in self.log.read_text().splitlines()]
            if self.log.exists()
            else []
        )

    def test_launches_exact_fork_on_left_without_focus_change(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        calls = self.calls()
        split = next(c for c in calls if c[:3] == ["herdr", "pane", "split"])
        self.assertIn("--no-focus", split)
        self.assertEqual(split[split.index("--pane") + 1], "w1:p1")
        self.assertEqual(split[split.index("--cwd") + 1], str(self.root))
        swap = next(c for c in calls if c[:3] == ["herdr", "pane", "swap"])
        self.assertEqual(swap[3:], ["--source-pane", "w1:p1", "--target-pane", "w1:p2"])
        launch = next(c for c in calls if c[:3] == ["herdr", "pane", "run"])
        self.assertEqual(launch[3], "w1:p2")
        command = shlex.split(launch[4])
        self.assertEqual(command[:3], ["run-agent", "--profile", "indigo"])
        self.assertIn("--no-update", command)
        self.assertEqual(command[command.index("--agent") + 1], "pi")
        self.assertEqual(command[command.index("--") + 1], "")
        native = command[command.index("--") + 3 :]
        self.assertFalse(any(c[:3] == ["herdr", "agent", "start"] for c in calls))
        self.assertEqual(data["profile"], "indigo")
        self.assertEqual(data["launch_status"], "queued")
        self.assertEqual(native[native.index("--model") + 1], "openai/gpt-6.1-sol")
        snapshot = Path(native[native.index("--fork") + 1])
        self.assertNotEqual(snapshot, self.session)
        self.assertEqual(snapshot.read_bytes(), self.session.read_bytes())
        self.assertNotIn("--continue", native)
        self.assertNotIn("--session", native)
        context = Path(native[native.index("--append-system-prompt") + 1])
        self.assertEqual(context.read_text(), self.context.read_text())
        self.assertEqual(data["pane_id"], "w1:p2")
        self.assertEqual(data["parent_pane_id"], "w1:p1")
        self.assertEqual(Path(data["prompt_file"]).read_text(), self.prompt.read_text())
        self.assertEqual(Path(data["run_dir"]).stat().st_mode & 0o777, 0o700)
        # Submission/wait is a separate agent step, never hidden in the launcher.
        self.assertFalse(any(c[:3] == ["herdr", "agent", "prompt"] for c in calls))

    def test_refuses_outside_herdr(self):
        self.env["HERDR_ENV"] = "0"
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not running inside herdr", result.stderr)
        self.assertEqual(self.calls(), [])

    def test_refuses_missing_exact_session(self):
        self.env.pop("PI_SESSION_FILE")
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("PI_SESSION_FILE", result.stderr)
        self.assertEqual(self.calls(), [])

    def test_refuses_missing_parent_pane(self):
        self.env.pop("HERDR_PANE_ID")
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("HERDR_PANE_ID", result.stderr)
        self.assertEqual(self.calls(), [])

    def test_refuses_unavailable_model_before_splitting(self):
        self.env["NO_MODEL"] = "1"
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no fallback model", result.stderr)
        self.assertFalse(any(c[0] == "herdr" for c in self.calls()))

    def test_refuses_missing_prompt(self):
        self.prompt.unlink()
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--prompt-file", result.stderr)
        self.assertEqual(self.calls(), [])

    def test_refuses_missing_context(self):
        self.context.unlink()
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--context-file", result.stderr)
        self.assertEqual(self.calls(), [])

    def test_start_failure_reports_pane_without_closing_or_retrying(self):
        self.env["FAIL_START"] = "1"
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("w1:p2", result.stderr)
        calls = self.calls()
        self.assertEqual(sum(c[:3] == ["herdr", "pane", "run"] for c in calls), 1)
        self.assertFalse(any("close" in c for c in calls))
        # The diagnostic names the retained run directory for manual recovery.
        for line in result.stderr.splitlines():
            if line.startswith("run_dir="):
                shutil.rmtree(line.removeprefix("run_dir="))

    def test_rejects_unknown_arguments(self):
        result = self.run_script("--bogus")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unknown argument", result.stderr)
        self.assertEqual(self.calls(), [])


if __name__ == "__main__":
    unittest.main()
