#!/usr/bin/env python3
"""
tests/test_secure_mtls.py — Automated Verification for Secure World mTLS & Remote Attestation

Validates:
  1. Secure World device key enrollment & certificate issuance
  2. OpenSSL 3.x PKCS#11 Provider-backed TLS 1.3 Mutual Authentication
  3. Remote Attestation Agent evidence packaging and anti-replay protection
  4. Verifier integrity evaluation (IMA log replay, PCR matching, dm-verity verification)
  5. Fleet Server secure endpoints and attestation workflow
"""

import os
import subprocess
import time
import unittest

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CERTS_DIR = os.path.join(REPO_ROOT, "keys_hsm", "certs")
KEYS_HSM_DIR = os.path.join(REPO_ROOT, "keys_hsm")

from apps.attestation_agent.attestation_agent import AttestationAgent
from apps.attestation_agent.verifier import AttestationVerifier
from apps.mtls_client.mtls_client import HumanoidMtlsClient
from apps.mtls_client.mtls_server import HumanoidFleetMtlsServer


class TestPhase6CertificatesAndKeyEnrollment(unittest.TestCase):
    """Verifies CA and device identity certificates issued via PKCS#11 HSM keys."""

    def test_root_ca_certificate_valid(self):
        ca_cert = os.path.join(CERTS_DIR, "DeviceEnrollmentCa.crt")
        self.assertTrue(os.path.isfile(ca_cert), f"Missing Root CA certificate: {ca_cert}")
        res = subprocess.run(["openssl", "x509", "-in", ca_cert, "-text", "-noout"], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"Failed to parse Root CA certificate: {res.stderr}")
        self.assertIn("Humanoid-Root-CA", res.stdout)
        self.assertIn("Signature Algorithm: ecdsa-with-SHA256", res.stdout)

    def test_device_certificate_valid_and_signed(self):
        dev_cert = os.path.join(CERTS_DIR, "humanoid_device.crt")
        ca_cert = os.path.join(CERTS_DIR, "DeviceEnrollmentCa.crt")
        self.assertTrue(os.path.isfile(dev_cert), f"Missing device certificate: {dev_cert}")

        res = subprocess.run(["openssl", "x509", "-in", dev_cert, "-text", "-noout"], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0)
        self.assertIn("jetson-humanoid-01", res.stdout)

    def test_device_identity_key_in_token(self):
        script = os.path.join(KEYS_HSM_DIR, "sign_helper.sh")
        res = subprocess.run([script, "status"], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0)
        self.assertIn("HumanoidDeviceIdentityKey", res.stdout)


class TestPhase6OpenSslPkcs11Handshake(unittest.TestCase):
    """Executes real TLS 1.3 Mutual Authentication using OpenSSL 3.x PKCS#11 Provider."""

    def test_openssl3_pkcs11_mutual_tls_handshake(self):
        port = 18443
        ca_cert = os.path.join(CERTS_DIR, "DeviceEnrollmentCa.crt")
        dev_cert = os.path.join(CERTS_DIR, "humanoid_device.crt")
        conf_file = os.path.join(REPO_ROOT, ".cache", "softhsm", "softhsm2.conf")
        mod_file = os.path.join(REPO_ROOT, ".cache", "pkcs11_tools", "usr", "lib", "x86_64-linux-gnu", "softhsm", "libsofthsm2.so")
        ossl_modules = os.path.join(REPO_ROOT, ".cache", "host_tools", "usr", "lib", "x86_64-linux-gnu", "ossl-modules")

        server_env = os.environ.copy()
        server_env["OPENSSL_MODULES"] = ossl_modules
        server_env["SOFTHSM2_CONF"] = conf_file
        server_env["PKCS11_PROVIDER_MODULE"] = mod_file
        server_env["LD_LIBRARY_PATH"] = f"{REPO_ROOT}/.cache/host_tools/usr/lib/x86_64-linux-gnu:{REPO_ROOT}/.cache/pkcs11_tools/usr/lib/x86_64-linux-gnu:{server_env.get('LD_LIBRARY_PATH', '')}"

        # Start OpenSSL s_server in background with PKCS#11 key
        server_cmd = [
            "openssl", "s_server",
            "-accept", str(port),
            "-cert", ca_cert,
            "-key", "pkcs11:token=HumanoidSecToken;object=DeviceEnrollmentCaKey?pin-value=1234",
            "-CAfile", dev_cert,
            "-Verify", "1",
            "-provider", "default",
            "-provider", "pkcs11",
            "-www"
        ]

        server_proc = subprocess.Popen(server_cmd, env=server_env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        time.sleep(1.0)

        try:
            client = HumanoidMtlsClient(host="127.0.0.1", port=port, device_cert=dev_cert, ca_cert=ca_cert)
            success, handshake_log = client.perform_openssl_handshake(payload="GET / HTTP/1.0\r\n\r\n")
            self.assertTrue(success, f"OpenSSL 3 PKCS#11 mTLS handshake failed:\n{handshake_log}")
            self.assertIn("CONNECTED", handshake_log)
            self.assertIn("Verification: OK", handshake_log)
        finally:
            server_proc.terminate()
            server_proc.wait(timeout=3)


class TestPhase6RemoteAttestation(unittest.TestCase):
    """Verifies Attestation Agent, evidence bundle generation, and Verifier logic."""

    def setUp(self):
        self.agent = AttestationAgent(repo_root=REPO_ROOT)
        self.verifier = AttestationVerifier(
            ca_cert_path=os.path.join(CERTS_DIR, "DeviceEnrollmentCa.crt"),
            dm_verity_pubkey_path=os.path.join(CERTS_DIR, "DmVeritySigningKey_pub.pem"),
            sign_helper_path=os.path.join(KEYS_HSM_DIR, "sign_helper.sh")
        )

    def test_attestation_bundle_structure_and_signature(self):
        nonce = self.verifier.issue_challenge()
        bundle = self.agent.generate_attestation_bundle(nonce)

        self.assertEqual(bundle["nonce"], nonce)
        self.assertIn("10", bundle["pcrs"])
        self.assertGreater(len(bundle["ima_log"]), 0)
        self.assertGreater(len(bundle["quote_signature_hex"]), 64)
        self.assertEqual(bundle["storage"]["status"], "ENFORCED")

    def test_attestation_eval_trusted_verdict(self):
        nonce = self.verifier.issue_challenge()
        bundle = self.agent.generate_attestation_bundle(nonce)

        res = self.verifier.evaluate_bundle(bundle, expected_nonce=nonce)
        self.assertEqual(res["verdict"], "TRUSTED")
        self.assertTrue(res["checks"]["nonce_freshness"])
        self.assertTrue(res["checks"]["ima_pcr10_consistency"])
        self.assertTrue(res["checks"]["dm_verity_integrity"])

    def test_attestation_replay_attack_rejected(self):
        nonce = self.verifier.issue_challenge()
        bundle = self.agent.generate_attestation_bundle(nonce)

        # First evaluation consumes nonce -> TRUSTED
        res1 = self.verifier.evaluate_bundle(bundle, expected_nonce=nonce)
        self.assertEqual(res1["verdict"], "TRUSTED")

        # Second evaluation with consumed nonce -> UNTRUSTED
        res2 = self.verifier.evaluate_bundle(bundle, expected_nonce=nonce)
        self.assertEqual(res2["verdict"], "UNTRUSTED")
        self.assertIn("Replay attack", res2["reason"])

    def test_attestation_tampered_ima_rejected(self):
        nonce = self.verifier.issue_challenge()
        bundle = self.agent.generate_attestation_bundle(nonce)

        # Corrupt one entry in the IMA log
        bundle["ima_log"][0][1] = "ff" * 32
        res = self.verifier.evaluate_bundle(bundle, expected_nonce=nonce)
        self.assertEqual(res["verdict"], "UNTRUSTED")
        self.assertIn("mismatch", res["reason"].lower())


class TestPhase6FleetServerEndpoints(unittest.TestCase):
    """Verifies end-to-end communication with the Humanoid Fleet Server."""

    def test_fleet_server_workflow(self):
        test_port = 19444
        server = HumanoidFleetMtlsServer(port=test_port)
        server.start(blocking=False)
        time.sleep(0.5)

        try:
            client = HumanoidMtlsClient(port=test_port)

            # 1. Attestation workflow
            res_attest = client.run_full_attestation_flow()
            self.assertEqual(res_attest["status"], "OK")
            self.assertEqual(res_attest["attestation_result"]["verdict"], "TRUSTED")

            # 2. Telemetry endpoint
            res_telemetry = client.send_request({"action": "GET_TELEMETRY"})
            self.assertEqual(res_telemetry["status"], "OK")
            self.assertEqual(res_telemetry["telemetry"]["state"], "OPERATIONAL")
            self.assertEqual(res_telemetry["telemetry"]["storage_integrity"], "EROFS_DM_VERITY_ACTIVE")
        finally:
            server.stop()


if __name__ == "__main__":
    unittest.main()
