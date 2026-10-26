"""
tests/test_hsm_keys.py — Automated SoftHSMv2, PKCS#11 Signing & Zero Key Audit Verification
"""

import os
import subprocess
import tempfile
import unittest

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
KEYS_HSM_DIR = os.path.join(REPO_ROOT, "keys_hsm")
CERTS_DIR = os.path.join(KEYS_HSM_DIR, "certs")


class TestPhase4TokenAndCertificates(unittest.TestCase):
    """Verifies SoftHSMv2 token initialization, key objects, and public cert exports."""

    def test_setup_softhsm_script_presence(self):
        script = os.path.join(KEYS_HSM_DIR, "setup_softhsm.sh")
        self.assertTrue(os.path.isfile(script), f"Missing script: {script}")
        self.assertTrue(os.access(script, os.X_OK), f"Script not executable: {script}")

    def test_exported_public_keys_present(self):
        expected_keys = [
            "KernelModuleSigningKey_pub.pem",
            "DmVeritySigningKey_pub.pem",
            "ImaSigningKey_pub.pem",
            "DeviceEnrollmentCaKey_pub.pem",
            "HumanoidDeviceIdentityKey_pub.pem",
        ]
        for key in expected_keys:
            p = os.path.join(CERTS_DIR, key)
            self.assertTrue(os.path.isfile(p), f"Missing exported public key: {p}")
            self.assertGreater(os.path.getsize(p), 50, f"Public key file is empty/invalid: {p}")
            with open(p, "r", encoding="utf-8") as f:
                content = f.read()
            self.assertIn("BEGIN PUBLIC KEY", content)
            self.assertNotIn("PRIVATE KEY", content)

    def test_token_contains_all_signing_keys(self):
        script = os.path.join(KEYS_HSM_DIR, "sign_helper.sh")
        result = subprocess.run([script, "status"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, f"sign_helper.sh status failed: {result.stderr}")

        required_labels = [
            "KernelModuleSigningKey",
            "DmVeritySigningKey",
            "ImaSigningKey",
            "DeviceEnrollmentCaKey",
            "HumanoidDeviceIdentityKey",
        ]
        for lbl in required_labels:
            self.assertIn(lbl, result.stdout, f"Missing key in token: {lbl}")


class TestPhase4SigningPipeline(unittest.TestCase):
    """Verifies in-HSM signature generation and verification for kmod, verity, and ima."""

    def setUp(self):
        self.script = os.path.join(KEYS_HSM_DIR, "sign_helper.sh")

    def test_sign_and_verify_dm_verity(self):
        test_roothash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        with tempfile.TemporaryDirectory() as tmpdir:
            sig_file = os.path.join(tmpdir, "test_verity.sig")
            hash_file = os.path.join(tmpdir, "test_hash.txt")
            with open(hash_file, "w", encoding="utf-8") as f:
                f.write(test_roothash)

            # Sign
            sign_res = subprocess.run(
                [self.script, "verity", "--hash", test_roothash, "--out", sig_file],
                capture_output=True,
                text=True,
            )
            self.assertEqual(sign_res.returncode, 0, f"verity signing failed: {sign_res.stderr}")
            self.assertTrue(os.path.isfile(sig_file))

            # Verify
            ver_res = subprocess.run(
                [self.script, "verify", "--in", hash_file, "--sig", sig_file, "--type", "verity"],
                capture_output=True,
                text=True,
            )
            self.assertEqual(ver_res.returncode, 0, f"verity verification failed: {ver_res.stderr}")

    def test_sign_and_verify_ima(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            payload_file = os.path.join(tmpdir, "test_binary.bin")
            sig_file = os.path.join(tmpdir, "test_binary.bin.ima.sig")
            with open(payload_file, "wb") as f:
                f.write(b"Antigravity IMA measurement payload test data 2026")

            # Sign
            sign_res = subprocess.run(
                [self.script, "ima", "--in", payload_file, "--out", sig_file],
                capture_output=True,
                text=True,
            )
            self.assertEqual(sign_res.returncode, 0, f"ima signing failed: {sign_res.stderr}")
            self.assertTrue(os.path.isfile(sig_file))

            # Verify
            ver_res = subprocess.run(
                [self.script, "verify", "--in", payload_file, "--sig", sig_file, "--type", "ima"],
                capture_output=True,
                text=True,
            )
            self.assertEqual(ver_res.returncode, 0, f"ima verification failed: {ver_res.stderr}")

    def test_sign_and_verify_kernel_module(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            dummy_ko = os.path.join(tmpdir, "dummy_driver.ko")
            sig_file = os.path.join(tmpdir, "dummy_driver.ko.sig")
            with open(dummy_ko, "wb") as f:
                f.write(b"\x7fELF\x02\x01\x01\x00Dummy Linux Kernel Module Content for Testing")

            # Sign
            sign_res = subprocess.run(
                [self.script, "kmod", "--in", dummy_ko],
                capture_output=True,
                text=True,
            )
            self.assertEqual(sign_res.returncode, 0, f"kmod signing failed: {sign_res.stderr}")
            self.assertTrue(os.path.isfile(sig_file))

            # Verify
            ver_res = subprocess.run(
                [self.script, "verify", "--in", dummy_ko, "--sig", sig_file, "--type", "kmod"],
                capture_output=True,
                text=True,
            )
            self.assertEqual(ver_res.returncode, 0, f"kmod verification failed: {ver_res.stderr}")


class TestPhase4ZeroPlaintextPolicy(unittest.TestCase):
    """Verifies that Zero Plaintext Key Audit passes with 0 private keys in repo."""

    def test_audit_zero_keys_passes(self):
        audit_script = os.path.join(KEYS_HSM_DIR, "audit_zero_keys.sh")
        self.assertTrue(os.path.isfile(audit_script))
        result = subprocess.run([audit_script], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, f"Zero Plaintext Audit failed: {result.stdout}\n{result.stderr}")
        self.assertIn("Zero Plaintext Key Policy: PASSED", result.stdout)


if __name__ == "__main__":
    unittest.main()
