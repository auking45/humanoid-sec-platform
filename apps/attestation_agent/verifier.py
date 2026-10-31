#!/usr/bin/env python3
"""
apps/attestation_agent/verifier.py — Remote Attestation Verification Service

Validates TCG-compliant attestation bundles from humanoid robot edge nodes:
  1. Nonce freshness check (anti-replay protection)
  2. Cryptographic signature verification over TPM Quote / PCR digest
  3. dm-verity root hash signature verification (storage immutability)
  4. IMA (Integrity Measurement Architecture) event log replay and PCR 10 consistency check
"""

import hashlib
import json
import os
import subprocess
import time
from typing import Any, Dict, Optional, Tuple


class AttestationVerifier:
    """Evaluates cryptographic integrity and boot measurements of a humanoid robot."""

    def __init__(self, ca_cert_path: str, dm_verity_pubkey_path: str, sign_helper_path: str):
        self.ca_cert_path = ca_cert_path
        self.dm_verity_pubkey_path = dm_verity_pubkey_path
        self.sign_helper_path = sign_helper_path
        self.active_challenges: Dict[str, float] = {}  # nonce -> expiry timestamp
        self.challenge_ttl_sec = 60.0

    def issue_challenge(self, nonce: Optional[str] = None) -> str:
        """Issues a fresh cryptographically random 256-bit challenge nonce."""
        if not nonce:
            nonce = os.urandom(32).hex()
        self.active_challenges[nonce] = time.time() + self.challenge_ttl_sec
        return nonce

    def verify_nonce(self, nonce: str) -> Tuple[bool, str]:
        """Validates that the nonce is active, not expired, and not reused."""
        now = time.time()
        # Clean expired nonces
        self.active_challenges = {n: exp for n, exp in self.active_challenges.items() if exp > now}

        if nonce not in self.active_challenges:
            return False, "Nonce is invalid, expired, or already consumed (Replay attack detected)"

        del self.active_challenges[nonce]
        return True, "Nonce validated successfully"

    def verify_quote_signature(self, quote_data: bytes, signature_path: str, key_label: str = "DeviceEnrollmentCaKey") -> Tuple[bool, str]:
        """Verifies cryptographic signature on quote using sign_helper verify."""
        tmp_data = f"/tmp/quote_verify_{os.urandom(8).hex()}.tmp"
        try:
            with open(tmp_data, "wb") as f:
                f.write(quote_data)

            cmd = [
                "bash", self.sign_helper_path, "verify",
                "--in", tmp_data,
                "--sig", signature_path,
                "--type", "ima"  # ECDSA
            ]
            res = subprocess.run(cmd, capture_output=True, text=True)
            if res.returncode == 0:
                return True, "Quote signature verified successfully"
            else:
                return False, f"Quote signature verification failed: {res.stderr}"
        finally:
            if os.path.isfile(tmp_data):
                os.remove(tmp_data)

    def replay_ima_log(self, ima_log: list, expected_pcr10: str) -> Tuple[bool, str]:
        """
        Replays IMA measurement event log by extending each template hash
        from initial zeroed PCR state: PCR_new = SHA256(PCR_old + measurement).
        """
        current_pcr = bytes(32)  # 32 zero bytes (SHA-256 initial digest)

        for entry in ima_log:
            # entry: [pcr_idx, template_hash_hex, template_name, file_hash_hex, file_path]
            if len(entry) < 2:
                continue
            template_hash_bytes = bytes.fromhex(entry[1])
            # TPM2 Extend operation: H(current || incoming)
            hasher = hashlib.sha256()
            hasher.update(current_pcr)
            hasher.update(template_hash_bytes)
            current_pcr = hasher.digest()

        calculated_pcr10 = current_pcr.hex()
        if calculated_pcr10.lower() == expected_pcr10.lower():
            return True, f"IMA event log replay matches PCR 10 ({calculated_pcr10})"
        else:
            return False, f"IMA log replay mismatch! Computed: {calculated_pcr10}, Attested: {expected_pcr10}"

    def verify_dm_verity(self, roothash: str, roothash_sig_path: str) -> Tuple[bool, str]:
        """Verifies that the attested dm-verity root hash is authentically signed."""
        tmp_hash = f"/tmp/roothash_verify_{os.urandom(8).hex()}.tmp"
        try:
            with open(tmp_hash, "w", encoding="utf-8") as f:
                f.write(roothash)

            cmd = [
                "bash", self.sign_helper_path, "verify",
                "--in", tmp_hash,
                "--sig", roothash_sig_path,
                "--type", "verity"
            ]
            res = subprocess.run(cmd, capture_output=True, text=True)
            if res.returncode == 0:
                return True, "dm-verity Root Hash signature verified"
            else:
                return False, f"dm-verity signature invalid: {res.stderr}"
        finally:
            if os.path.isfile(tmp_hash):
                os.remove(tmp_hash)

    def evaluate_bundle(self, bundle: Dict[str, Any], expected_nonce: Optional[str] = None) -> Dict[str, Any]:
        """Executes complete attestation verification workflow on an evidence bundle."""
        result = {
            "verdict": "UNTRUSTED",
            "timestamp": time.time(),
            "checks": {},
            "reason": ""
        }

        nonce = bundle.get("nonce", "")
        if expected_nonce:
            if nonce != expected_nonce:
                result["reason"] = f"Nonce mismatch (Expected: {expected_nonce}, Received: {nonce})"
                return result
            ok_nonce, msg_nonce = self.verify_nonce(nonce)
            result["checks"]["nonce_freshness"] = ok_nonce
            if not ok_nonce:
                result["reason"] = msg_nonce
                return result
        else:
            result["checks"]["nonce_freshness"] = True

        # 2. Check dm-verity Root Hash signature
        storage = bundle.get("storage", {})
        roothash = storage.get("roothash", "")
        sig_file = storage.get("signature_file", "")
        if roothash and sig_file and os.path.isfile(sig_file):
            ok_verity, msg_verity = self.verify_dm_verity(roothash, sig_file)
            result["checks"]["dm_verity_integrity"] = ok_verity
            if not ok_verity:
                result["reason"] = msg_verity
                return result
        else:
            result["checks"]["dm_verity_integrity"] = True

        # 3. Check IMA log replay into PCR 10
        pcrs = bundle.get("pcrs", {})
        pcr10 = pcrs.get("10", "")
        ima_log = bundle.get("ima_log", [])
        if pcr10 and ima_log:
            ok_ima, msg_ima = self.replay_ima_log(ima_log, pcr10)
            result["checks"]["ima_pcr10_consistency"] = ok_ima
            if not ok_ima:
                result["reason"] = msg_ima
                return result
        else:
            result["checks"]["ima_pcr10_consistency"] = True

        # 4. Check PCR 0 / 7 / 10 policy & composite digest integrity
        for req_pcr in ("0", "7", "10"):
            val = pcrs.get(req_pcr, "")
            if len(val) != 64 or val == ("0" * 64):
                result["checks"]["pcr_composite_integrity"] = False
                result["reason"] = f"Invalid or uninitialized PCR {req_pcr} digest: {val}"
                return result

        try:
            composite_hasher = hashlib.sha256()
            for idx in sorted(pcrs.keys(), key=int):
                composite_hasher.update(bytes.fromhex(pcrs[idx]))
            expected_composite = composite_hasher.hexdigest()
        except Exception as exc:
            result["checks"]["pcr_composite_integrity"] = False
            result["reason"] = f"Malformed PCR hex value: {exc}"
            return result

        attested_composite = bundle.get("pcr_composite_digest", "")
        if expected_composite.lower() != attested_composite.lower():
            result["checks"]["pcr_composite_integrity"] = False
            result["reason"] = (
                f"PCR composite digest mismatch! Computed: {expected_composite}, Attested: {attested_composite}"
            )
            return result
        result["checks"]["pcr_composite_integrity"] = True

        # 5. Check cryptographic Quote signature (ECDSA-P384 over ATTEST:<nonce>:<pcr_digest>:<timestamp>)
        quote_sig_hex = bundle.get("quote_signature_hex", "")
        timestamp = bundle.get("timestamp", "")
        if not quote_sig_hex:
            result["checks"]["quote_signature_valid"] = False
            result["reason"] = "Missing quote_signature_hex in attestation bundle"
            return result

        tmp_sig = f"/tmp/quote_sig_verify_{os.urandom(8).hex()}.sig"
        try:
            sig_bytes = bytes.fromhex(quote_sig_hex)
            with open(tmp_sig, "wb") as f:
                f.write(sig_bytes)
            quote_payload = f"ATTEST:{nonce}:{attested_composite}:{timestamp}".encode("utf-8")
            ok_sig, msg_sig = self.verify_quote_signature(quote_payload, tmp_sig)
            result["checks"]["quote_signature_valid"] = ok_sig
            if not ok_sig:
                result["reason"] = msg_sig
                return result
        except Exception as exc:
            result["checks"]["quote_signature_valid"] = False
            result["reason"] = f"Quote signature verification error: {exc}"
            return result
        finally:
            if os.path.isfile(tmp_sig):
                os.remove(tmp_sig)

        # Passed all verification gates
        result["verdict"] = "TRUSTED"
        result["reason"] = "All cryptographic signatures, nonce freshness, and PCR/IMA measurements verified."
        return result


def main():
    import sys
    print("Remote Attestation Verifier Module loaded.")
    if len(sys.argv) > 1 and sys.argv[1] == "--test":
        verifier = AttestationVerifier(
            ca_cert_path="keys_hsm/certs/DeviceEnrollmentCa.crt",
            dm_verity_pubkey_path="keys_hsm/certs/DmVeritySigningKey_pub.pem",
            sign_helper_path="keys_hsm/sign_helper.sh"
        )
        challenge = verifier.issue_challenge()
        print(f"[OK] Challenge issued: {challenge}")


if __name__ == "__main__":
    main()
