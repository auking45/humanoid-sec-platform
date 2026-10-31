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
        cls.fuses_xml = os.path.join(CONFIGS_DIR, "secureboot", "fuse_config.xml")
        cls.ekb_t234 = os.path.join(BUILD_DIR, "images", "eks_t234.img")
        cls.ekb_t264 = os.path.join(BUILD_DIR, "images", "eks_t264.img")
        cls.pubkey_pem = os.path.join(CERTS_DIR, "SecureBootKey_pub.pem")

    def test_01_secureboot_script_executable(self):
        self.assertTrue(os.path.isfile(self.sign_script), f"Missing {self.sign_script}")
        self.assertTrue(os.access(self.sign_script, os.X_OK), "sign_jetson_secureboot.sh is not executable")

    def test_02_burn_efuses_and_ekb_generation(self):
        res = subprocess.run(
            [self.sign_script, "burn-fuses", "--out", self.fuses_file, "--xml", self.fuses_xml],
            capture_output=True,
            text=True,
        )
        self.assertEqual(res.returncode, 0, f"burn-fuses failed: {res.stderr}")
        self.assertTrue(os.path.isfile(self.fuses_file), f"Missing {self.fuses_file}")
        self.assertTrue(os.path.isfile(self.fuses_xml), f"Missing {self.fuses_xml}")

        with open(self.fuses_xml, "r", encoding="utf-8") as fx:
            xml_content = fx.read()
        self.assertIn('<genericfuse MagicId="0x45535546" version="1.0.0">', xml_content)
        self.assertIn('name="PublicKeyHash"', xml_content)
        self.assertIn('name="SecureBootKey"', xml_content)
        self.assertIn('name="OemK1"', xml_content)
        self.assertIn('name="OemKdk0"', xml_content)
        self.assertIn('name="BootSecurityInfo" size="4" value="0x00000209"', xml_content)

        with open(self.fuses_file, "r", encoding="utf-8") as f:
            data = json.load(f)

        self.assertEqual(data.get("security_mode"), "1")
        fuses = data.get("fuses", {})
        self.assertIn("FUSE_PKC_HASH", fuses)
        self.assertEqual(len(fuses["FUSE_PKC_HASH"]), 64)
        self.assertIn("FUSE_SBK", fuses)
        self.assertIn("FUSE_OEM_K1", fuses)
        self.assertEqual(fuses.get("FUSE_BOOT_SECURITY_INFO"), "0x00000209")

        # Verify R39.2.1 EKB images (eks_t234.img & eks_t264.img)
        self.assertTrue(os.path.isfile(self.ekb_t234), "Missing eks_t234.img")
        self.assertTrue(os.path.isfile(self.ekb_t264), "Missing eks_t264.img")
        res_ekb234 = subprocess.run(
            [self.sign_script, "verify-ekb", "--in", self.ekb_t234, "--chip", "t234", "--fuses", self.fuses_xml],
            capture_output=True,
            text=True,
        )
        self.assertEqual(res_ekb234.returncode, 0, f"T234 EKB verify failed: {res_ekb234.stdout}")
        self.assertIn("PASS: EKB v2.1 (t234) authenticated", res_ekb234.stdout)

        res_ekb264 = subprocess.run(
            [self.sign_script, "verify-ekb", "--in", self.ekb_t264, "--chip", "t264", "--fuses", self.fuses_xml],
            capture_output=True,
            text=True,
        )
        self.assertEqual(res_ekb264.returncode, 0, f"T264 EKB verify failed: {res_ekb264.stdout}")
        self.assertIn("PASS: EKB v2.1 (t264) authenticated", res_ekb264.stdout)

    def test_03_tamper_resistance_verification(self):
        res = subprocess.run([self.sign_script, "tamper-test"], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"tamper-test failed:\n{res.stdout}\n{res.stderr}")
        self.assertIn("Test 1 PASSED", res.stdout)
        self.assertIn("Test 2 PASSED", res.stdout)
        self.assertIn("Test 3 PASSED", res.stdout)
        self.assertIn("Test 4 PASSED", res.stdout)
        self.assertIn("Test 5 PASSED", res.stdout)

    def test_04_kernel_container_signing_and_verification(self):
        kernel_img = os.path.join(BUILD_DIR, "kernel", "arch", "arm64", "boot", "Image")
        signed_container = os.path.join(BUILD_DIR, "images", "kernel.signed")

        if os.path.isfile(kernel_img):
            res_sign = subprocess.run([self.sign_script, "sign", "--in", kernel_img, "--out", signed_container], capture_output=True, text=True)
            self.assertEqual(res_sign.returncode, 0, f"Signing kernel failed: {res_sign.stderr}")
            self.assertTrue(os.path.isfile(signed_container))

            with open(signed_container, "rb") as sf:
                hdr = sf.read(8192)
            self.assertEqual(hdr[:4], b"NVDA")
            self.assertEqual(hdr[5120:5124], b"BCRT")

            res_verify = subprocess.run([self.sign_script, "verify", "--in", signed_container, "--fuses", self.fuses_xml], capture_output=True, text=True)
            self.assertEqual(res_verify.returncode, 0, f"Verification failed: {res_verify.stderr}")
            self.assertIn("PASS: R39.2.1 NVDA BCH + SBKPKC + EKB + UEFI db verified & decrypted", res_verify.stdout)


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

        # Dual-Profile Ubuntu 24.04 EROFS + dm-verity + OverlayFS dry run
        res_ubuntu = subprocess.run([self.run_qemu_script, "--ubuntu", "--secureboot", "--optee-chain", "--dry-run"], capture_output=True, text=True)
        self.assertEqual(res_ubuntu.returncode, 0)
        self.assertIn("Profile:        ubuntu", res_ubuntu.stdout)
        self.assertIn("ubuntu_rootfs.erofs", res_ubuntu.stdout)
        self.assertIn("ubuntu_rootfs.verity", res_ubuntu.stdout)
        self.assertIn("initramfs_ubuntu.cpio.gz", res_ubuntu.stdout)

    def test_03_qemu_boot_verification_log_inspection(self):
        run_console_log = os.path.join(REPO_ROOT, ".cache", "run", "console.log")
        console_log = run_console_log if os.path.isfile(run_console_log) else os.path.join(REPO_ROOT, ".cache", "logs", "console.log")

        # If previous verified boot ran, assert presence of devices
        if os.path.isfile(console_log):
            with open(console_log, "r", encoding="utf-8", errors="ignore") as f:
                content = f.read()
            self.assertIn("/dev/tee0", content, "OP-TEE Primary Device not found in boot log")
            self.assertIn("/dev/teepriv0", content, "OP-TEE Privileged Device not found in boot log")
            self.assertIn("/dev/tpmrm0", content, "OP-TEE fTPM Resource Manager not found in boot log")
            if "Ubuntu 24.04 LTS Boot Node" in content:
                self.assertIn("dm-verity activated: /dev/mapper/dm-root", content)
                self.assertIn("OverlayFS union mounted rw at /mnt/sysroot", content)
                self.assertIn("Ubuntu 24.04", content)

    def test_04_dual_profile_ubuntu_artifacts_when_built(self):
        ubuntu_erofs = os.path.join(BUILD_DIR, "images", "ubuntu_rootfs.erofs")
        ubuntu_verity = os.path.join(BUILD_DIR, "images", "ubuntu_rootfs.verity")
        ubuntu_sig = os.path.join(BUILD_DIR, "images", "ubuntu_verity.roothash.sig")
        ubuntu_env = os.path.join(BUILD_DIR, "images", "ubuntu_verity_params.env")

        if not os.path.isfile(ubuntu_erofs):
            self.skipTest("Ubuntu EROFS profile not built in this environment; skipping artifact size check")

        self.assertGreater(os.path.getsize(ubuntu_erofs), 100 * 1024 * 1024)
        self.assertTrue(os.path.isfile(ubuntu_verity))
        self.assertTrue(os.path.isfile(ubuntu_sig))
        self.assertTrue(os.path.isfile(ubuntu_env))


if __name__ == "__main__":
    unittest.main()
