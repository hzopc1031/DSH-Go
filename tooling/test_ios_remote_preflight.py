"""Integrity and archive safety checks for the public-artifact preflight."""
import base64
import hashlib
import io
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ios_remote_preflight as preflight


class ArtifactIntegrityTest(unittest.TestCase):
    def test_modified_archive_is_rejected(self):
        original = b"published artifact"
        digest = "sha512-" + base64.b64encode(hashlib.sha512(original).digest()).decode()
        preflight.verify_integrity(original, digest)
        with self.assertRaisesRegex(ValueError, "integrity mismatch"):
            preflight.verify_integrity(original + b"tampered", digest)

    def test_archive_members_are_read_without_extraction(self):
        data = io.BytesIO()
        with tarfile.open(fileobj=data, mode="w:gz") as archive:
            item = tarfile.TarInfo("../../outside.json")
            payload = b'{"version":"test"}'
            item.size = len(payload)
            archive.addfile(item, io.BytesIO(payload))
        self.assertEqual(preflight.archive_texts(data.getvalue())["../../outside.json"], payload.decode())

    def test_missing_offline_cache_fails_instead_of_reporting_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(FileNotFoundError):
                preflight.inspect(Path(directory), offline=True)

    def test_markers_report_location_without_executing_code(self):
        self.assertEqual(preflight.markers({"host.js": "throw Error();\nharness.remote.v3"},
                                          ["harness.remote.v3", "absent"]),
                         {"harness.remote.v3": [{"file": "host.js", "line": 2}], "absent": []})


if __name__ == "__main__":
    unittest.main()
