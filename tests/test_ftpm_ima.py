"""
tests/test_ftpm_ima.py — Automated fTPM, OP-TEE PKCS#11, and Storage/IMA Integrity Verification
"""

import os
import subprocess
import unittest

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FIRMWARE_DIR = os.path.join(REPO_ROOT, "build", "firmware")
KERNEL_CONFIG = os.path.join(REPO_ROOT, "build", "kernel", ".config")
SCRIPTS_DIR = os.path.join(REPO_ROOT, "scripts")

FTPM_TA_UUID = "bc50d971-d4c9-42c4-82cb-343fb7f37896"
PKCS11_TA_UUID = "fd02c9da-306c-48c7-a49c-bbd827ae86ee"


class TestPhase3FirmwareArtifacts(unittest.TestCase):
    """Verifies generated TF-A, OP-TEE Core, and Trusted Application binaries."""

    def test_tfa_and_fip_artifacts_present(self):
        required_bins = ["bl1.bin", "bl2.bin", "bl31.bin", "fip.bin"]
        for b in required_bins:
            p = os.path.join(FIRMWARE_DIR, b)
            self.assertTrue(os.path.isfile(p), f"Missing TF-A firmware artifact: {p}")
            self.assertGreater(os.path.getsize(p), 1024, f"Firmware file {p} is suspiciously small")

    def test_optee_pager_and_early_ftpm(self):
        pager = os.path.join(FIRMWARE_DIR, "tee-pager_v2.bin")
        self.assertTrue(os.path.isfile(pager), f"Missing OP-TEE pager: {pager}")
        # tee-pager_v2.bin contains embedded early TA fTPM (> 500KB)
        self.assertGreater(os.path.getsize(pager), 300 * 1024, "tee-pager_v2.bin does not contain embedded early TA")

    def test_ftpm_ta_standalone_artifact(self):
        ftpm_ta = os.path.join(FIRMWARE_DIR, "ta", f"{FTPM_TA_UUID}.ta")
        self.assertTrue(os.path.isfile(ftpm_ta), f"Missing fTPM TA artifact: {ftpm_ta}")
        self.assertGreater(os.path.getsize(ftpm_ta), 100 * 1024)
        with open(ftpm_ta, "rb") as f:
            header_magic = f.read(4)
        # OP-TEE SHDR_MAGIC: 0x4f545348 ('OTSH' in LE byte order: b"HSTO")
        self.assertEqual(header_magic, b"HSTO", "Invalid OP-TEE Signed Header magic in fTPM TA")

    def test_pkcs11_ta_standalone_artifact(self):
        pkcs11_ta = os.path.join(FIRMWARE_DIR, "ta", f"{PKCS11_TA_UUID}.ta")
        self.assertTrue(os.path.isfile(pkcs11_ta), f"Missing PKCS#11 TA artifact: {pkcs11_ta}")
        self.assertGreater(os.path.getsize(pkcs11_ta), 100 * 1024)
        with open(pkcs11_ta, "rb") as f:
            header_magic = f.read(4)
        self.assertEqual(header_magic, b"HSTO", "Invalid OP-TEE Signed Header magic in PKCS#11 TA")

    def test_optee_client_and_supplicant(self):
        client_lib = os.path.join(FIRMWARE_DIR, "client", "lib", "libteec.so")
        pkcs11_lib = os.path.join(FIRMWARE_DIR, "client", "lib", "libckteec.so")
        supplicant = os.path.join(FIRMWARE_DIR, "client", "sbin", "tee-supplicant")

        for p in [client_lib, pkcs11_lib, supplicant]:
            self.assertTrue(os.path.exists(p), f"Missing OP-TEE client binary: {p}")


class TestPhase3KernelIntegration(unittest.TestCase):
    """Verifies that the compiled/configured Linux kernel includes TEE, fTPM, and IMA drivers."""

    def test_kernel_config_symbols(self):
        if not os.path.isfile(KERNEL_CONFIG):
            self.skipTest(f"Kernel config not found at {KERNEL_CONFIG}")

        with open(KERNEL_CONFIG, "r", encoding="utf-8") as f:
            content = f.read()

        required_symbols = [
            "CONFIG_TEE=y",
            "CONFIG_OPTEE=y",
            "CONFIG_TCG_FTPM_TEE=y",
            "CONFIG_TCG_TPM=y",
            "CONFIG_HW_RANDOM_TPM=y",
            "CONFIG_EROFS_FS=y",
            "CONFIG_IMA=y",
            "CONFIG_SECURITY_NETWORK=y",
        ]
        for sym in required_symbols:
            self.assertIn(sym, content, f"Missing kernel symbol: {sym}")


class TestPhase3QemuInvocation(unittest.TestCase):
    """Verifies QEMU run script dry-run output with OP-TEE and security parameters."""

    def test_run_qemu_dry_run_includes_optee(self):
        script = os.path.join(SCRIPTS_DIR, "run_qemu.sh")
        result = subprocess.run([script, "--dry-run"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        self.assertIn("virt,secure=on", result.stdout)
        self.assertIn("tee-pager_v2.bin", result.stdout)
        self.assertIn("addr=0x0e100000", result.stdout)


if __name__ == "__main__":
    unittest.main()
