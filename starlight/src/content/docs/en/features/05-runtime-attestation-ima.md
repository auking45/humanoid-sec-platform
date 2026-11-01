---
title: "05. Linux IMA Measurement, fTPM PCR 10 & Remote Attestation Deep-Dive"
description: "Runtime binary hash chaining into PCR 10, nonce challenges, and 4-stage fleet verification"
---

> **Purpose**: Defines the Zero-Trust remote attestation architecture hash-chaining all executed binaries into hardware TPM registers and evaluating robot compliance via cryptographic challenge-response before granting fleet access.  
> **Target Standard**: TCG TPM 2.0 Attestation Architecture, Linux Integrity Measurement Architecture (IMA)  
> **Status**: Approved / Production Baseline  

---

## 1. Architectural Overview & Remote Attestation Flow

Static health telemetry can be easily spoofed or replayed by stealth rootkits. Remote Attestation combines hardware-signed TPM quotes with single-use server nonce challenges to guarantee authentic verification.

[![Remote Attestation Flow](../../diagrams/remote_attestation_flow.svg)](../../diagrams/remote_attestation_flow.html)
> 💡 *Click to open the [Archify Interactive Viewer](../../diagrams/remote_attestation_flow.html) for challenge-response timeline animation.*

---

## 2. Linux IMA Subsystem & PCR 10 Hash Chaining

- **Kernel Boot Arguments**:
  - `ima_policy=tcb ima_hash=sha256`: Enforces cryptographic measurement over all executed ELF binaries and dynamic shared libraries.
- **PCR 10 Extend Formula**:
  $$\text{PCR}_{10}^{\text{new}} = \text{SHA256}\left(\text{PCR}_{10}^{\text{old}} \parallel \text{SHA256}(\text{Binary\_Content})\right)$$
  - Because SHA-256 is a one-way collision-resistant function, it is mathematically impossible to conceal execution of unauthorized malware.

---

## 3. Attestation Evidence Bundle Structure

Transmitted from `apps/attestation_agent/` to the Cloud Fleet Verifier:

```json
{
  "nonce": "32-byte single-use cryptographic challenge",
  "quote": {
    "attest_data": "fTPM 2.0 TPMS_ATTEST struct (binds Nonce + PCR 10 composite)",
    "signature": "ECDSA P-256 signature from fTPM Attestation Key (AK)",
    "pcr_composite": { "10": "Current PCR 10 hardware digest" }
  },
  "ima_log": [
    { "pcr": 10, "template_hash": "...", "file_hash": "...", "file_path": "/usr/bin/ros2" }
  ],
  "storage": {
    "roothash": "Active dm-verity Merkle root hash",
    "signature_file": "verity.roothash.sig"
  }
}
```

---

## 4. Cloud Fleet Verifier 4-Stage Engine

Implementation in `apps/attestation_agent/verifier.py`:

1. **Nonce Freshness**: Confirms single-use nonce match (defeats replay attacks, ATK-04A).
2. **AK Hardware Signature**: Authenticates quote signature against `DeviceEnrollmentCa.crt`.
3. **IMA Log Replay**: Reconstructs the synthetic PCR 10 hash by replaying log entries sequentially; compares with the quote's hardware PCR (detects stealth malware, ATK-04B).
4. **dm-verity Integrity**: Validates root hash signature with `DmVeritySigningKey` (detects rootfs forgery, ATK-04C).

---

## 5. Automated Attack Defense Proof (ATK-04 & ATK-09)

Verified via `test_atk04_runtime_ima_tamper_and_attestation_replay` and `test_atk09_ima_appraisal_bypass_and_stripped_xattr` in `tests/test_attack_scenarios.py`.