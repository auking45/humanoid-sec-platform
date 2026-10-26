"""
tests/test_secureboot_chain.py — NVIDIA Secure Boot (PKC + eFuse) & TrustZone Cold Boot Test Suite
"""

import json
import os
import subprocess
import unittest

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SCRIPTS_DIR = os.path.join(REPO_ROOT, "scripts")
BUILD_DIR = os.path.join(REPO_ROOT, "build")
CONFIGS_DIR = os.path.join(REPO_ROOT, "configs")
CERTS_DIR = os.path.join(REPO_ROOT, "keys_hsm", "certs")


class TestNvidiaSecureBootPKC(unittest.TestCase):
    """Verifies NVIDIA Jetson PKC Secure Boot signing, eFuses, and tamper resistance."""

    @classmethod
    def setUpClass(cls):
        cls.sign_script = os.path.join(SCRIPTS_DIR, "sign_jetson_secureboot.sh")
        cls.fuses_file = os.path.join(CONFIGS_DIR, "secureboot", "tegra_fuses.json")
        cls.pubkey_pem = os.path.join(CERTS_DIR, "SecureBootKey_pub.pem")

    def test_01_secureboot_script_executable(self):
        self.assertTrue(os.path.isfile(self.sign_script), f"Missing {self.sign_script}")
        self.assertTrue(os.access(self.sign_script, os.X_OK), "sign_jetson_secureboot.sh is not executable")

    def test_02_burn_efuses_generation(self):
        res = subprocess.run([self.sign_script, "burn-fuses", "--out", self.fuses_file], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"burn-fuses failed: {res.stderr}")
        self.assertTrue(os.path.isfile(self.fuses_file), f"Missing {self.fuses_file}")

        with open(self.fuses_file, "r", encoding="utf-8") as f:
            data = json.load(f)

        self.assertEqual(data.get("security_mode"), "1")
        fuses = data.get("fuses", {})
        self.assertIn("FUSE_PKC_HASH", fuses)
        self.assertEqual(len(fuses["FUSE_PKC_HASH"]), 64)

    def test_03_tamper_resistance_verification(self):
        res = subprocess.run([self.sign_script, "tamper-test"], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"tamper-test failed:\n{res.stdout}\n{res.stderr}")
        self.assertIn("Test 1 PASSED", res.stdout)
        self.assertIn("Test 2 PASSED", res.stdout)
        self.assertIn("Test 3 PASSED", res.stdout)

    def test_04_kernel_container_signing_and_verification(self):
        kernel_img = os.path.join(BUILD_DIR, "kernel", "arch", "arm64", "boot", "Image")
        signed_container = os.path.join(BUILD_DIR, "images", "kernel.signed")

        if os.path.isfile(kernel_img):
            res_sign = subprocess.run([self.sign_script, "sign", "--in", kernel_img, "--out", signed_container], capture_output=True, text=True)
            self.assertEqual(res_sign.returncode, 0, f"Signing kernel failed: {res_sign.stderr}")
            self.assertTrue(os.path.isfile(signed_container))

            res_verify = subprocess.run([self.sign_script, "verify", "--in", signed_container, "--fuses", self.fuses_file], capture_output=True, text=True)
            self.assertEqual(res_verify.returncode, 0, f"Verification failed: {res_verify.stderr}")
            self.assertIn("PASS: Container authenticated successfully", res_verify.stdout)


class TestTrustZoneBootChain(unittest.TestCase):
    """Verifies that TF-A, OP-TEE, Kernel, and Userspace link properly in QEMU."""

    @classmethod
    def setUpClass(cls):
        cls.run_qemu_script = os.path.join(SCRIPTS_DIR, "run_qemu.sh")
        cls.flash0_bin = os.path.join(BUILD_DIR, "firmware", "flash0.bin")
        cls.kernel_img = os.path.join(BUILD_DIR, "kernel", "arch", "arm64", "boot", "Image")

    def test_01_flash0_firmware_integrity(self):
        if not os.path.isfile(self.flash0_bin):
            self.skipTest(f"flash0.bin not built yet ({self.flash0_bin}); skipping firmware size check in clean environment")
        # flash0.bin must be at least 64MB for QEMU PFLASH
        self.assertEqual(os.path.getsize(self.flash0_bin), 64 * 1024 * 1024)

    def test_02_run_qemu_dry_run_modes(self):
        # Direct dry run
        res_direct = subprocess.run([self.run_qemu_script, "--direct", "--dry-run"], capture_output=True, text=True)
        self.assertEqual(res_direct.returncode, 0)
        self.assertIn("Direct Boot", res_direct.stdout)

        # TrustZone cold boot dry run with Secure Boot
        res_sec = subprocess.run([self.run_qemu_script, "--secureboot", "--optee-chain", "--dry-run"], capture_output=True, text=True)
        self.assertEqual(res_sec.returncode, 0)
        self.assertIn("TrustZone Boot Chain (TF-A + OP-TEE)", res_sec.stdout)
        self.assertIn("Secure Boot:    ENFORCED", res_sec.stdout)

    def test_03_qemu_boot_verification_log_inspection(self):
        console_log = os.path.join(REPO_ROOT, ".cache", "logs", "console.log")
        optee_log = os.path.join(REPO_ROOT, ".cache", "logs", "optee.log")

        # If previous verified boot ran, assert presence of devices
        if os.path.isfile(console_log):
            with open(console_log, "r", encoding="utf-8", errors="ignore") as f:
                content = f.read()
            self.assertIn("/dev/tee0", content, "OP-TEE Primary Device not found in boot log")
            self.assertIn("/dev/teepriv0", content, "OP-TEE Privileged Device not found in boot log")
            self.assertIn("/dev/tpmrm0", content, "OP-TEE fTPM Resource Manager not found in boot log")


if __name__ == "__main__":
    unittest.main()
