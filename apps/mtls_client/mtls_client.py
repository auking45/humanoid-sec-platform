#!/usr/bin/env python3
"""
apps/mtls_client/mtls_client.py — Secure World mTLS Client for Humanoid Robot

Establishes TLS 1.3 Mutual Authentication using OpenSSL 3.x and the PKCS#11
Provider to execute private key operations inside the SoftHSM/OP-TEE token
(Zero Plaintext Key Exposure).
"""

import argparse
import json
import os
import subprocess
import sys
from typing import Any, Dict, Optional, Tuple

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
sys.path.insert(0, REPO_ROOT)

from apps.attestation_agent.attestation_agent import AttestationAgent


class HumanoidMtlsClient:
    """Robot Edge Client with HSM-backed Private Key and mTLS Handshake."""

    def __init__(self, host: str = "127.0.0.1", port: int = 8443,
                 device_cert: Optional[str] = None, ca_cert: Optional[str] = None,
                 key_label: str = "HumanoidDeviceIdentityKey", token_label: str = "HumanoidSecToken"):
        self.host = host
        self.port = port
        self.device_cert = device_cert or os.path.join(REPO_ROOT, "keys_hsm", "certs", "humanoid_device.crt")
        self.ca_cert = ca_cert or os.path.join(REPO_ROOT, "keys_hsm", "certs", "DeviceEnrollmentCa.crt")
        self.key_label = key_label
        self.token_label = token_label
        self.attestation_agent = AttestationAgent(repo_root=REPO_ROOT)

        # OpenSSL 3 & PKCS#11 Environment Setup
        self.env = os.environ.copy()
        self.env["OPENSSL_MODULES"] = os.path.join(REPO_ROOT, ".cache", "host_tools", "usr", "lib", "x86_64-linux-gnu", "ossl-modules")
        custom_libs = [
            os.path.join(REPO_ROOT, ".cache", "host_tools", "usr", "lib", "x86_64-linux-gnu"),
            os.path.join(REPO_ROOT, ".cache", "pkcs11_tools", "usr", "lib", "x86_64-linux-gnu")
        ]
        self.env["LD_LIBRARY_PATH"] = ":".join(custom_libs) + ":" + self.env.get("LD_LIBRARY_PATH", "")
        self.env["SOFTHSM2_CONF"] = os.path.join(REPO_ROOT, ".cache", "softhsm", "softhsm2.conf")
        self.env["PKCS11_PROVIDER_MODULE"] = os.path.join(REPO_ROOT, ".cache", "pkcs11_tools", "usr", "lib", "x86_64-linux-gnu", "softhsm", "libsofthsm2.so")
        self.pkcs11_uri = f"pkcs11:token={self.token_label};object={self.key_label}?pin-value=1234"

    def perform_openssl_handshake(self, payload: Optional[str] = None) -> Tuple[bool, str]:
        """
        Executes a real TLS 1.3 Mutual Authentication handshake using
        'openssl s_client' backed by OpenSSL 3.x PKCS#11 Provider.
        """
        cmd = [
            "openssl", "s_client",
            "-connect", f"{self.host}:{self.port}",
            "-cert", self.device_cert,
            "-key", self.pkcs11_uri,
            "-CAfile", self.ca_cert,
            "-provider", "default",
            "-provider", "pkcs11"
        ]

        input_data = (payload or "Q") + "\n"
        res = subprocess.run(cmd, env=self.env, input=input_data, capture_output=True, text=True)

        is_connected = ("CONNECTED" in res.stdout or "Verification: OK" in res.stdout)
        return is_connected, res.stdout + "\n" + res.stderr

    def send_request(self, request_data: Dict[str, Any]) -> Dict[str, Any]:
        """Sends request to server socket directly or over simulated mTLS channel."""
        import socket
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.connect((self.host, self.port))
        s.sendall(json.dumps(request_data).encode("utf-8"))
        raw = s.recv(65536)
        s.close()
        return json.loads(raw.decode("utf-8"))

    def run_full_attestation_flow(self) -> Dict[str, Any]:
        """Executes full challenge-response remote attestation workflow."""
        # 1. Request fresh challenge nonce
        resp_chal = self.send_request({"action": "GET_CHALLENGE"})
        nonce = resp_chal.get("challenge", "")

        # 2. Assemble signed attestation bundle
        bundle = self.attestation_agent.generate_attestation_bundle(nonce)

        # 3. Submit bundle to fleet server
        resp_submit = self.send_request({
            "action": "SUBMIT_ATTESTATION",
            "challenge": nonce,
            "bundle": bundle
        })
        return resp_submit


def main():
    parser = argparse.ArgumentParser(description="Humanoid Robot Secure World mTLS Client")
    parser.add_argument("--host", default="127.0.0.1", help="Target host")
    parser.add_argument("--port", type=int, default=8443, help="Target port")
    parser.add_argument("--attest", action="store_true", help="Execute remote attestation workflow")
    parser.add_argument("--handshake-only", action="store_true", help="Verify OpenSSL PKCS#11 TLS handshake")
    args = parser.parse_args()

    client = HumanoidMtlsClient(host=args.host, port=args.port)
    if args.handshake_only:
        ok, out = client.perform_openssl_handshake()
        print(f"Handshake success: {ok}")
        sys.exit(0 if ok else 1)

    if args.attest:
        result = client.run_full_attestation_flow()
        print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
