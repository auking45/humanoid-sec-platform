#!/usr/bin/env python3
"""
tests/test_attack_scenarios.py — Red/Blue Team Attack Simulation & Defense Verification Suite (ATK-01 ~ ATK-05)

Compares:
  - Vulnerable Baseline (when a security control is absent or bypassed -> COMPROMISED)
  - Hardened Platform (when Humanoid Security Platform controls are active -> BLOCKED / DETECTED)
"""

import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import time
import unittest

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SCRIPTS_DIR = os.path.join(REPO_ROOT, "scripts")
KEYS_HSM_DIR = os.path.join(REPO_ROOT, "keys_hsm")
CERTS_DIR = os.path.join(KEYS_HSM_DIR, "certs")
CONFIGS_DIR = os.path.join(REPO_ROOT, "configs")
BUILD_DIR = os.path.join(REPO_ROOT, "build")
IMAGES_DIR = os.path.join(BUILD_DIR, "images")

from apps.attestation_agent.attestation_agent import AttestationAgent
from apps.attestation_agent.verifier import AttestationVerifier


def _resolve_veritysetup() -> str:
    path_bin = shutil.which("veritysetup")
    if path_bin:
        return path_bin
    cached = os.path.join(REPO_ROOT, ".cache", "host_tools", "sbin", "veritysetup")
    if os.path.isfile(cached):
        return cached
    return "veritysetup"


def _build_env() -> dict:
    env = os.environ.copy()
    host_lib = os.path.join(REPO_ROOT, ".cache", "host_tools", "usr", "lib", "x86_64-linux-gnu")
    host_lib2 = os.path.join(REPO_ROOT, ".cache", "host_tools", "lib", "x86_64-linux-gnu")
    pkcs11_lib = os.path.join(REPO_ROOT, ".cache", "pkcs11_tools", "usr", "lib", "x86_64-linux-gnu")
    ld_paths = [p for p in [host_lib, host_lib2, pkcs11_lib, env.get("LD_LIBRARY_PATH", "")] if p]
    env["LD_LIBRARY_PATH"] = ":".join(ld_paths)
    return env


class TestRedBlueAttackScenarios(unittest.TestCase):
    """End-to-End Red/Blue Team Attack Simulation Suite (ATK-01 through ATK-05)."""

    def test_atk01_secureboot_rogue_key_and_kernel_tamper(self):
        """
        ATK-01: Malicious Kernel Injection & Rogue Signing Key Bypass
        - Vulnerable Baseline: Unverified boot loads modified kernel payload without error.
        - Hardened Platform: NVIDIA Tegra PKC + SoC eFuse verification blocks both payload
          tampering and rogue key signatures.
        """
        sign_script = os.path.join(SCRIPTS_DIR, "sign_jetson_secureboot.sh")
        fuses_file = os.path.join(CONFIGS_DIR, "secureboot", "tegra_fuses.json")

        with tempfile.TemporaryDirectory() as tmpdir:
            legit_kernel = os.path.join(tmpdir, "Image.legit")
            signed_kernel = os.path.join(tmpdir, "Image.signed")
            with open(legit_kernel, "wb") as f:
                f.write(b"LINUX_ARM64_KERNEL_IMAGE_HEADER_V6_8_NOBLE\x00" * 64)

            # 1. Vulnerable Baseline: without Secure Boot verification, attacker overwrites kernel
            vuln_kernel = os.path.join(tmpdir, "Image.vulnerable")
            shutil.copyfile(legit_kernel, vuln_kernel)
            with open(vuln_kernel, "r+b") as f:
                f.seek(32)
                f.write(b"ROOTKIT_PAYLOAD_INJECTED")
            with open(vuln_kernel, "rb") as f:
                self.assertIn(b"ROOTKIT_PAYLOAD_INJECTED", f.read())

            # 2. Hardened Platform: sign kernel with SoftHSM SecureBootKey
            res_sign = subprocess.run(
                [sign_script, "sign", "--in", legit_kernel, "--out", signed_kernel],
                capture_output=True,
                text=True,
            )
            self.assertEqual(res_sign.returncode, 0, f"Signing failed: {res_sign.stderr}")

            # Attack 1A: 1-byte rootkit injection inside signed kernel payload (offset 600)
            tampered_signed = os.path.join(tmpdir, "Image.tampered.signed")
            shutil.copyfile(signed_kernel, tampered_signed)
            with open(tampered_signed, "r+b") as f:
                f.seek(600)
                orig = f.read(1)
                f.seek(600)
                f.write(bytes([orig[0] ^ 0xFF]))

            res_verify_tamper = subprocess.run(
                [sign_script, "verify", "--in", tampered_signed, "--fuses", fuses_file],
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(res_verify_tamper.returncode, 0, "Hardened Secure Boot must reject tampered kernel!")
            self.assertIn("FAIL", res_verify_tamper.stdout + res_verify_tamper.stderr)

            # Attack 1B: Rogue Key / Mismatched SoC eFuse hash injection
            rogue_fuses = os.path.join(tmpdir, "rogue_fuses.json")
            with open(rogue_fuses, "w", encoding="utf-8") as f:
                json.dump(
                    {
                        "security_mode": "1",
                        "fuses": {"FUSE_PKC_HASH": "deadbeef" * 8},
                    },
                    f,
                )

            res_verify_rogue = subprocess.run(
                [sign_script, "verify", "--in", signed_kernel, "--fuses", rogue_fuses],
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(res_verify_rogue.returncode, 0, "Hardened Secure Boot must reject rogue PKC key hash!")
            self.assertIn("PKC hash mismatch", res_verify_rogue.stdout + res_verify_rogue.stderr)

    def test_atk02_unsigned_and_tampered_kernel_module(self):
        """
        ATK-02: Unsigned or Tampered Rootkit Kernel Module (.ko) Injection
        - Vulnerable Baseline: Kernel without CONFIG_MODULE_SIG_FORCE accepts unsigned .ko.
        - Hardened Platform: Enforces CONFIG_MODULE_SIG_FORCE=y and rejects unsigned or
          post-signature modified .ko binaries via SoftHSM KernelModuleSigningKey.
        """
        hardening_cfg = os.path.join(CONFIGS_DIR, "kernel", "security_hardening.config")
        sign_helper = os.path.join(KEYS_HSM_DIR, "sign_helper.sh")

        with open(hardening_cfg, "r", encoding="utf-8") as f:
            cfg_text = f.read()
        self.assertIn("CONFIG_MODULE_SIG=y", cfg_text)
        self.assertIn("CONFIG_MODULE_SIG_FORCE=y", cfg_text)

        with tempfile.TemporaryDirectory() as tmpdir:
            ko_file = os.path.join(tmpdir, "humanoid_ actuator.ko")
            sig_file = f"{ko_file}.sig"
            with open(ko_file, "wb") as f:
                f.write(b"\x7fELF\x02\x01\x01\x00Legitimate Humanoid Actuator Kernel Module")

            # Sign legitimate module
            res_sign = subprocess.run([sign_helper, "kmod", "--in", ko_file], capture_output=True, text=True)
            self.assertEqual(res_sign.returncode, 0, f"kmod sign failed: {res_sign.stderr}")

            # Attack 2A: Attacker injects hook into .ko after signature generation
            with open(ko_file, "ab") as f:
                f.write(b"\x90\x90MALICIOUS_SYSCALL_HOOK")

            res_verify = subprocess.run(
                [sign_helper, "verify", "--in", ko_file, "--sig", sig_file, "--type", "kmod"],
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(res_verify.returncode, 0, "Hardened kmod verifier must reject modified .ko module!")

            # Attack 2B: Attacker supplies forged signature for unsigned rootkit.ko
            forged_sig = os.path.join(tmpdir, "forged.sig")
            with open(forged_sig, "wb") as f:
                f.write(os.urandom(384))
            res_forged = subprocess.run(
                [sign_helper, "verify", "--in", ko_file, "--sig", forged_sig, "--type", "kmod"],
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(res_forged.returncode, 0, "Hardened kmod verifier must reject forged signature!")

    def test_atk03_dm_verity_offline_corruption_and_ro_enforcement(self):
        """
        ATK-03: Offline Rootfs Binary Tampering & Root Hash Forgery Attack
        - Vulnerable Baseline: Direct modification of an unverified image persists silently.
        - Hardened Platform:
          1) dm-verity Merkle tree immediately rejects 1-byte sector tampering on rootfs.erofs.
          2) Attempting to replace verity.roothash to match the tampered image is blocked by
             SoftHSM DmVeritySigningKey signature verification.
        """
        erofs_img = os.path.join(IMAGES_DIR, "rootfs.erofs")
        verity_img = os.path.join(IMAGES_DIR, "rootfs.verity")
        roothash_file = os.path.join(IMAGES_DIR, "verity.roothash")
        roothash_sig = os.path.join(IMAGES_DIR, "verity.roothash.sig")
        sign_helper = os.path.join(KEYS_HSM_DIR, "sign_helper.sh")
        veritysetup = _resolve_veritysetup()
        env = _build_env()

        self.assertTrue(os.path.isfile(erofs_img), "Missing build/images/rootfs.erofs")
        with open(roothash_file, "r", encoding="utf-8") as f:
            legit_roothash = f.read().strip()

        with tempfile.TemporaryDirectory() as tmpdir:
            tampered_erofs = os.path.join(tmpdir, "rootfs_compromised.erofs")
            shutil.copyfile(erofs_img, tampered_erofs)

            # Attack 3A: Offline attacker flips 1 byte in EROFS data block (offset 1024)
            with open(tampered_erofs, "r+b") as f:
                f.seek(1024)
                b = f.read(1)
                f.seek(1024)
                f.write(bytes([b[0] ^ 0xFF]))

            res_verity = subprocess.run(
                [veritysetup, "verify", tampered_erofs, verity_img, legit_roothash],
                env=env,
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(res_verity.returncode, 0, "dm-verity must block 1-byte corrupted EROFS image!")

            # Attack 3B: Attacker recomputes a forged root hash and tries to pass HSM signature check
            forged_roothash_file = os.path.join(tmpdir, "forged.roothash")
            with open(forged_roothash_file, "w", encoding="utf-8") as f:
                f.write(hashlib.sha256(b"attacker_recomputed_merkle_root").hexdigest())

            res_sig = subprocess.run(
                [sign_helper, "verify", "--in", forged_roothash_file, "--sig", roothash_sig, "--type", "verity"],
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(res_sig.returncode, 0, "DmVeritySigningKey must reject forged root hash!")

    def test_atk04_runtime_ima_tamper_and_attestation_replay(self):
        """
        ATK-04: Stealth Malware Execution, Quote Replay, & IMA Measurement Log Forgery
        - Vulnerable Baseline: Static/unverified telemetry reports 'OK' despite compromises.
        - Hardened Platform: Remote Attestation Verifier detects and blocks:
          1) Replay of a previously captured valid Quote/bundle (Nonce freshness check).
          2) Execution of unauthorized binary modifying PCR 10 without matching IMA log.
          3) Forged dm-verity root hash inside attestation evidence.
        """
        agent = AttestationAgent(repo_root=REPO_ROOT)
        verifier = AttestationVerifier(
            ca_cert_path=os.path.join(CERTS_DIR, "DeviceEnrollmentCa.crt"),
            dm_verity_pubkey_path=os.path.join(CERTS_DIR, "DmVeritySigningKey_pub.pem"),
            sign_helper_path=os.path.join(KEYS_HSM_DIR, "sign_helper.sh"),
        )

        # Legitimate baseline
        nonce = verifier.issue_challenge()
        valid_bundle = agent.generate_attestation_bundle(nonce)
        res_ok = verifier.evaluate_bundle(valid_bundle, expected_nonce=nonce)
        self.assertEqual(res_ok["verdict"], "TRUSTED")

        # Attack 4A: Replay Attack — attacker resends captured valid_bundle
        res_replay = verifier.evaluate_bundle(valid_bundle, expected_nonce=nonce)
        self.assertEqual(res_replay["verdict"], "UNTRUSTED")
        self.assertFalse(res_replay["checks"]["nonce_freshness"])

        # Attack 4B: Stealth Malware Execution — PCR 10 extended by malware, attacker hides IMA log entry
        nonce2 = verifier.issue_challenge()
        tampered_pcr_bundle = agent.generate_attestation_bundle(nonce2)
        tampered_pcr_bundle["pcrs"]["10"] = hashlib.sha256(b"pcr10_after_malware_execution").hexdigest()
        res_pcr = verifier.evaluate_bundle(tampered_pcr_bundle, expected_nonce=nonce2)
        self.assertEqual(res_pcr["verdict"], "UNTRUSTED")
        self.assertFalse(res_pcr["checks"]["ima_pcr10_consistency"])

        # Attack 4C: Attacker spoofs dm-verity roothash in attestation evidence
        nonce3 = verifier.issue_challenge()
        tampered_verity_bundle = agent.generate_attestation_bundle(nonce3)
        tampered_verity_bundle["storage"]["roothash"] = "00" * 32
        res_verity = verifier.evaluate_bundle(tampered_verity_bundle, expected_nonce=nonce3)
        self.assertEqual(res_verity["verdict"], "UNTRUSTED")
        self.assertFalse(res_verity["checks"]["dm_verity_integrity"])

    def test_atk05_key_exfiltration_and_rogue_mtls_client(self):
        """
        ATK-05: Filesystem Private Key Exfiltration & Rogue Certificate mTLS Intrusion
        - Vulnerable Baseline: Plaintext private keys on disk allow identity theft; unauthenticated
          TLS servers accept rogue clients.
        - Hardened Platform:
          1) Zero plaintext keys on disk (audit_zero_keys.sh passes) and PKCS#11 CKA_EXTRACTABLE=FALSE.
          2) TLS 1.3 Mutual Authentication server rejects rogue self-signed client certificate.
        """
        # 1. Verify Zero Plaintext Key Policy blocks filesystem key theft
        audit_script = os.path.join(KEYS_HSM_DIR, "audit_zero_keys.sh")
        res_audit = subprocess.run([audit_script], capture_output=True, text=True)
        self.assertEqual(res_audit.returncode, 0)
        self.assertIn("Zero Plaintext Key Policy: PASSED", res_audit.stdout)

        # 2. Attempt Rogue Client mTLS Intrusion against PKCS#11-backed TLS 1.3 Fleet Server
        port = 18449
        ca_cert = os.path.join(CERTS_DIR, "DeviceEnrollmentCa.crt")
        dev_cert = os.path.join(CERTS_DIR, "humanoid_device.crt")
        conf_file = os.path.join(REPO_ROOT, ".cache", "softhsm", "softhsm2.conf")
        mod_file = os.path.join(
            REPO_ROOT, ".cache", "pkcs11_tools", "usr", "lib", "x86_64-linux-gnu", "softhsm", "libsofthsm2.so"
        )
        ossl_modules = os.path.join(REPO_ROOT, ".cache", "host_tools", "usr", "lib", "x86_64-linux-gnu", "ossl-modules")

        server_env = _build_env()
        server_env["OPENSSL_MODULES"] = ossl_modules
        server_env["SOFTHSM2_CONF"] = conf_file
        server_env["PKCS11_PROVIDER_MODULE"] = mod_file

        server_cmd = [
            "openssl",
            "s_server",
            "-accept",
            str(port),
            "-cert",
            ca_cert,
            "-key",
            "pkcs11:token=HumanoidSecToken;object=DeviceEnrollmentCaKey?pin-value=1234",
            "-CAfile",
            ca_cert,
            "-verify_return_error",
            "-Verify",
            "1",
            "-provider",
            "default",
            "-provider",
            "pkcs11",
            "-www",
        ]

        server_proc = subprocess.Popen(server_cmd, env=server_env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        time.sleep(1.0)

        try:
            with tempfile.TemporaryDirectory() as tmpdir:
                rogue_key = os.path.join(tmpdir, "rogue.key")
                rogue_cert = os.path.join(tmpdir, "rogue.crt")
                subprocess.run(
                    [
                        "openssl",
                        "req",
                        "-x509",
                        "-newkey",
                        "ec",
                        "-pkeyopt",
                        "ec_paramgen_curve:P-256",
                        "-keyout",
                        rogue_key,
                        "-out",
                        rogue_cert,
                        "-days",
                        "1",
                        "-nodes",
                        "-subj",
                        "/CN=rogue-attacker-robot",
                    ],
                    check=True,
                    capture_output=True,
                )

                client_cmd = [
                    "openssl",
                    "s_client",
                    "-connect",
                    f"127.0.0.1:{port}",
                    "-cert",
                    rogue_cert,
                    "-key",
                    rogue_key,
                    "-CAfile",
                    ca_cert,
                    "-tls1_3",
                ]
                res_rogue = subprocess.run(
                    client_cmd,
                    input="GET / HTTP/1.0\r\n\r\n",
                    capture_output=True,
                    text=True,
                    timeout=5,
                )
                combined = res_rogue.stdout + res_rogue.stderr
                # In TLS 1.3, s_server validates the client certificate after ServerFinished and aborts before serving -www HTML
                self.assertNotIn(
                    "<HTML>",
                    combined,
                    f"Fleet mTLS server must NOT serve protected data to rogue certificate! Output:\n{combined}",
                )
        finally:
            server_proc.terminate()
            try:
                srv_out, srv_err = server_proc.communicate(timeout=3)
                srv_combined = (srv_out.decode("utf-8", errors="ignore") + srv_err.decode("utf-8", errors="ignore")).lower()
                self.assertTrue(
                    "verify error" in srv_combined or "self-signed" in srv_combined or "error" in srv_combined,
                    f"Server must log certificate verification error for rogue client! Server log:\n{srv_combined}",
                )
            except subprocess.TimeoutExpired:
                server_proc.kill()


if __name__ == "__main__":
    unittest.main()
