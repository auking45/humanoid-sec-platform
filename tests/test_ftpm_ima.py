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


class TestPhase5StorageAndVerity(unittest.TestCase):
    """Verifies EROFS immutable filesystem, dm-verity Merkle tree, and HSM signature."""

    def setUp(self):
        self.images_dir = os.path.join(REPO_ROOT, "build", "images")
        self.erofs_path = os.path.join(self.images_dir, "rootfs.erofs")
        self.verity_path = os.path.join(self.images_dir, "rootfs.verity")
        self.roothash_path = os.path.join(self.images_dir, "verity.roothash")
        self.sig_path = os.path.join(self.images_dir, "verity.roothash.sig")
        self.params_path = os.path.join(self.images_dir, "verity_params.env")

        # Resolve veritysetup
        host_verity = os.path.join(REPO_ROOT, ".cache", "host_tools", "sbin", "veritysetup")
        if os.path.isfile(host_verity):
            self.veritysetup_bin = host_verity
        else:
            self.veritysetup_bin = "veritysetup"

        self.custom_env = os.environ.copy()
        lib_path = os.path.join(REPO_ROOT, ".cache", "host_tools", "usr", "lib", "x86_64-linux-gnu")
        if os.path.isdir(lib_path):
            self.custom_env["LD_LIBRARY_PATH"] = f"{lib_path}:{self.custom_env.get('LD_LIBRARY_PATH', '')}"

    def test_erofs_image_presence_and_magic(self):
        self.assertTrue(os.path.isfile(self.erofs_path), f"Missing EROFS image: {self.erofs_path}")
        self.assertGreater(os.path.getsize(self.erofs_path), 4096)
        with open(self.erofs_path, "rb") as f:
            f.seek(1024)
            magic = f.read(4)
        # EROFS magic: 0xE0F5E1E2 (LE: \xe2\xe1\xf5\xe0)
        self.assertEqual(magic, b"\xe2\xe1\xf5\xe0", "Invalid EROFS filesystem magic")

    def test_dm_verity_hash_tree_presence_and_magic(self):
        self.assertTrue(os.path.isfile(self.verity_path), f"Missing verity image: {self.verity_path}")
        self.assertGreater(os.path.getsize(self.verity_path), 4096)
        with open(self.verity_path, "rb") as f:
            magic = f.read(8)
        self.assertEqual(magic, b"verity\x00\x00", "Invalid dm-verity superblock magic")

    def test_roothash_format_and_params(self):
        self.assertTrue(os.path.isfile(self.roothash_path))
        with open(self.roothash_path, "r", encoding="utf-8") as f:
            roothash = f.read().strip()
        self.assertEqual(len(roothash), 64, "Root hash must be 64-char hex SHA256")
        self.assertTrue(all(c in "0123456789abcdefABCDEF" for c in roothash))

        self.assertTrue(os.path.isfile(self.params_path))
        with open(self.params_path, "r", encoding="utf-8") as f:
            params = f.read()
        self.assertIn("VERITY_ROOTHASH=", params)
        self.assertIn("VERITY_DATA_BLOCK_SIZE=\"4096\"", params)
        self.assertIn("VERITY_HASH_ALGO=\"sha256\"", params)

    def test_roothash_cryptographic_signature_valid(self):
        self.assertTrue(os.path.isfile(self.sig_path), f"Missing root hash signature: {self.sig_path}")
        self.assertGreater(os.path.getsize(self.sig_path), 128)

        sign_helper = os.path.join(REPO_ROOT, "keys_hsm", "sign_helper.sh")
        cmd = [
            "bash", sign_helper, "verify",
            "--in", self.roothash_path,
            "--sig", self.sig_path,
            "--type", "verity"
        ]
        res = subprocess.run(cmd, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"Root hash HSM signature verification failed: {res.stderr}")
        self.assertIn("SUCCESSFUL", res.stdout)

    def test_dm_verity_integrity_verification_pass(self):
        with open(self.roothash_path, "r", encoding="utf-8") as f:
            roothash = f.read().strip()

        cmd = [self.veritysetup_bin, "verify", self.erofs_path, self.verity_path, roothash]
        res = subprocess.run(cmd, env=self.custom_env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"veritysetup verify failed: {res.stderr}")

    def test_dm_verity_tamper_detection(self):
        with open(self.roothash_path, "r", encoding="utf-8") as f:
            roothash = f.read().strip()

        tampered_img = os.path.join(self.images_dir, "test_tamper.tmp")
        try:
            # Copy valid image
            with open(self.erofs_path, "rb") as f_in, open(tampered_img, "wb") as f_out:
                f_out.write(f_in.read())

            # Flip single byte at offset 2048
            with open(tampered_img, "r+b") as f:
                f.seek(2048)
                current = f.read(1)
                f.seek(2048)
                f.write(bytes([ord(current) ^ 0xFF]))

            cmd = [self.veritysetup_bin, "verify", tampered_img, self.verity_path, roothash]
            res = subprocess.run(cmd, env=self.custom_env, capture_output=True, text=True)
            self.assertNotEqual(res.returncode, 0, "dm-verity MUST fail when image data is tampered")
        finally:
            if os.path.isfile(tampered_img):
                os.remove(tampered_img)


class TestPhase5ImaHardening(unittest.TestCase):
    """Verifies IMA kernel configurations and HSM-backed IMA signing."""

    def test_ima_kernel_symbols(self):
        if not os.path.isfile(KERNEL_CONFIG):
            self.skipTest(f"Kernel config not found at {KERNEL_CONFIG}")

        with open(KERNEL_CONFIG, "r", encoding="utf-8") as f:
            content = f.read()

        required = [
            "CONFIG_IMA=y",
            "CONFIG_IMA_MEASURE_PCR_IDX=10",
            "CONFIG_IMA_DEFAULT_HASH_SHA256=y",
            "CONFIG_IMA_DEFAULT_HASH=\"sha256\"",
            "CONFIG_DM_VERITY=y",
            "CONFIG_DM_VERITY_VERIFY_ROOTHASH_SIG=y",
        ]
        for sym in required:
            self.assertIn(sym, content, f"Missing IMA config symbol: {sym}")

    def test_ima_file_signing_via_hsm(self):
        sign_helper = os.path.join(REPO_ROOT, "keys_hsm", "sign_helper.sh")
        test_file = os.path.join(REPO_ROOT, "build", "images", "test_binary.bin")
        test_sig = test_file + ".sig"

        try:
            with open(test_file, "wb") as f:
                f.write(b"#!/bin/sh\necho 'Humanoid Secure Payload Execution'\n")

            # Sign using ImaSigningKey (ECDSA P-384)
            cmd_sign = ["bash", sign_helper, "ima", "--in", test_file, "--out", test_sig]
            res_sign = subprocess.run(cmd_sign, capture_output=True, text=True)
            self.assertEqual(res_sign.returncode, 0, f"IMA signing failed: {res_sign.stderr}")

            # Verify using ImaSigningKey
            cmd_verify = [
                "bash", sign_helper, "verify",
                "--in", test_file,
                "--sig", test_sig,
                "--type", "ima"
            ]
            res_verify = subprocess.run(cmd_verify, capture_output=True, text=True)
            self.assertEqual(res_verify.returncode, 0, f"IMA verification failed: {res_verify.stderr}")
            self.assertIn("SUCCESSFUL", res_verify.stdout)
        finally:
            for p in [test_file, test_sig]:
                if os.path.isfile(p):
                    os.remove(p)


if __name__ == "__main__":
    unittest.main()
