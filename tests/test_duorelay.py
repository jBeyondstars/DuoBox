"""Run with python -m unittest discover -s tests (Windows only: runs DuoRelay.ps1 -SelfTest).

The self-test checks the config, click detection (click / drag / camera turn / long press),
the message format, sender filtering and a loopback exchange on 127.0.0.1. It never presses a key.
"""
from pathlib import Path
import shutil
import subprocess
import sys
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "DuoRelay" / "DuoRelay.ps1"


@unittest.skipUnless(sys.platform == "win32" and shutil.which("powershell.exe"), "needs Windows PowerShell 5.1")
class DuoRelaySelfTest(unittest.TestCase):
    def test_selftest(self):
        result = subprocess.run(
            ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(SCRIPT), "-SelfTest"],
            capture_output=True, text=True, timeout=120)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Self-test OK.", result.stdout)
        self.assertNotIn("FAIL", result.stdout)


if __name__ == "__main__":
    unittest.main()
