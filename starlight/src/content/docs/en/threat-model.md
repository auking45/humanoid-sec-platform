---
title: "Humanoid Robot Threat Model (STRIDE)"
description: "Robot-specific attack surfaces, STRIDE threat analysis matrix, and defense control mapping"
---

> **Methodology**: STRIDE (Spoofing, Tampering, Repudiation, Information Disclosure, Denial of Service, Elevation of Privilege)
> **Target System**: NVIDIA Jetson Humanoid Robot Autonomous Platform
> **Status**: Approved / Baseline

---

## 1. Threat Environment & Humanoid Safety Context

- **Physical Safety Hazards**: Humanoids operate autonomously within human work environments. Exploitation leads not only to data leaks, but to **physical damage, human injury, and hazardous actuator motion**.
- **Physical Access Surface**: Unlike datacenter servers, robots are physically accessible to attackers, requiring defense against direct memory dumping and hardware probing.

---

## 2. Attack Surface Analysis

[![STRIDE Threat Model](/humanoid-sec-platform/diagrams/threat_model_stride.svg)](/humanoid-sec-platform/diagrams/threat_model_stride.html)
> 💡 *Click to open the [Archify Interactive Diagram](/humanoid-sec-platform/diagrams/threat_model_stride.html) mapping attack surfaces to STRIDE threats and countermeasures.*

1. **Physical & Hardware Interface**:
   - Chip-off attacks on eMMC/UFS storage for offline rootfs tampering and key extraction.
   - Bootloader hijacking via debug headers (UART, JTAG).
   - Packet spoofing on internal CAN FD and Ethernet sensor/actuator buses.
2. **Network & Wireless Teleoperation**:
   - Man-in-the-Middle (MITM) attacks spoofing cloud fleet management servers.
   - Malicious firmware or poisoned AI model weights distributed via OTA.
3. **Software & Runtime Interfaces**:
   - Memory corruption vulnerabilities in ROS 2 / Isaac middleware nodes.
   - Privilege escalation and unauthorized rootkit installation via kernel modules.

---

## 3. STRIDE Threat Analysis Matrix & 10 Attack Scenarios

> 💡 *For comprehensive technical specifications and automated attack verification code, refer to the [Attack Scenarios & Defense-in-Depth Guide](./attack_defense_guide.md).*

| Threat Category (STRIDE) | Attack Scenario ID & Title | Risk | Impact | Implemented Security Control |
| :---: | :--- | :---: | :--- | :--- |
| **Spoofing** | **ATK-05**: Filesystem Key Exfiltration & Rogue Robot mTLS<br>**ATK-10**: Network MITM & Rogue Motion Command Injection | **Critical** | Unauthorized fleet access, device cloning, motion tampering | **Zero Plaintext Key Policy**, OP-TEE PKCS#11 TA isolation, **TLS 1.3 mTLS + PFS** |
| **Tampering** | **ATK-01**: Bootloader/Kernel Ciphertext Tamper & Rogue PKC<br>**ATK-03**: Offline Chip-off Flash Storage Tampering<br>**ATK-06**: Stage 2 UEFI db Signature Forgery & AuthVar Tamper<br>**ATK-09**: Runtime Executable Tampering & Stripped IMA xattr | **Critical** | Backdoor kernel launch, binary tampering, unauthorized processes | **Root of Trust Secure Boot (PKC + eFuse + SBKPKC)**, **EROFS + dm-verity**, **Stage 2 UEFI db RSA-3072**, **IMA Appraisal (`ima_policy=tcb`)** |
| **Repudiation** | **ATK-04**: Stealth Malware Execution & Quote Replay | **Medium** | Concealed compromise, falsified telemetry, denied forensics | **IMA Runtime Measurement -> fTPM PCR 10 Chaining**, Fresh Nonce Remote Attestation |
| **Information Disclosure** | **ATK-05**: Storage Dump Extracting Private Keys & AI Weights<br>**ATK-07**: Physical Memory (`/dev/mem`) Snooping | **Critical** | Intellectual property theft, credential compromise | **Zero Plaintext Key (`CKA_EXTRACTABLE=FALSE`)**, **KSPP Hardening (`CONFIG_STRICT_DEVMEM=y`)** |
| **Denial of Service** | DoS attack disrupting control loops causing stability loss and fall | **High** | Balance failure, human injury, robot damage | **Watchdog Fail-Safe**, Safe stop fallback upon cryptographic verification failure |
| **Elevation of Privilege** | **ATK-02**: Unsigned Rootkit Kernel Module (`.ko`) Injection<br>**ATK-07**: Kernel Runtime Exploitation (eBPF, Heap Corruption)<br>**ATK-08**: Normal World TrustZone Memory Intrusion & Storage Rollback | **Critical** | Ring 0 compromise, TrustZone TZDRAM intrusion, state rollback | **`CONFIG_MODULE_SIG_FORCE=y`**, **KSPP Kernel Hardening**, **ARM TrustZone Hardware Firewall**, **RPMB Write Counter Auth** |

---

## 4. Security Controls Mapping Table

Technical countermeasure alignment with identified STRIDE threats and automated verification test cases:

```text
 STRIDE Threats               Technical Security Controls            Verification Tests (tests/)
 ─────────────────            ───────────────────────────            ───────────────────────────
 Device Cloning / Spoofing ──> OP-TEE PKCS#11 TA + fTPM ───────────> test_atk05, test_atk10
 Flash Storage Tampering   ──> EROFS + dm-verity Block Integrity ──> test_atk03
 Plaintext Key Leakage     ──> SoftHSMv2 PKCS#11 URI Pipeline ────> test_atk05
 Rootkit / Kernel Exploit  ──> KSPP Hardening + Forced Mod Sign ──> test_atk02, test_atk07
 Secure Boot Bypass        ──> NVIDIA PKC + Stage 2 UEFI db + EKB ─> test_atk01, test_atk06
 TrustZone / Rollback      ──> ARM TrustZone + RPMB Counter ───────> test_atk08
 Runtime Binary Tamper     ──> IMA Appraisal (imasig) ────────────> test_atk09
 Stale / Replayed Quote    ──> fTPM PCR 10 + Nonce Challenge ─────> test_atk04
```

---

## 5. Residual Risk & Production Guidelines

1. **Hardware Glitch & Fault Injection**:
   - This verification platform focuses on software and architecture security layers. Physical production boards must integrate electromagnetic shielding and power glitch detection.
2. **Transitioning to Enterprise Hardware HSM**:
   - SoftHSMv2 is utilized in development and CI environments. Production deployment requires switching `PKCS11_MODULE_PATH` to FIPS 140-2/3 Level 3 certified hardware HSMs.