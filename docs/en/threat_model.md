# Threat Modeling & Security Controls Mapping (STRIDE)

> **Methodology**: STRIDE (Spoofing, Tampering, Repudiation, Information Disclosure, Denial of Service, Elevation of Privilege)  
> **Target System**: NVIDIA Jetson Humanoid Robot Autonomous Platform  
> **Status**: Approved / Baseline

---

## 1. Threat Environment & Humanoid Safety Context

- **Physical Safety Hazards**: Humanoids operate autonomously within human work environments. Exploitation leads not only to data leaks, but to **physical damage, human injury, and hazardous actuator motion**.
- **Physical Access Surface**: Unlike datacenter servers, robots are physically accessible to attackers, requiring defense against direct memory dumping and hardware probing.

---

## 2. Attack Surface Analysis

[![STRIDE Threat Model](../diagrams/threat_model_stride.svg)](../diagrams/threat_model_stride.html)
> 💡 *Click to open the [Archify Interactive Diagram](../diagrams/threat_model_stride.html) mapping attack surfaces to STRIDE threats and countermeasures.*

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

## 3. STRIDE Threat Analysis Matrix

| Threat Category (STRIDE) | Scenario | Risk | Impact | Implemented Security Control |
| :--- | :--- | :---: | :--- | :--- |
| **Spoofing** | Attacker impersonates legitimate robot to cloud, or injects fake teleoperation commands | **High** | Malicious motion commands, false telemetry | **TLS 1.3 mTLS** via OP-TEE PKCS#11 TA, fTPM Remote Attestation |
| **Tampering** | Direct flash memory modification inserting rootkit into bootloader or kernel | **Critical** | Robot malfunction, physical collision | **Root of Trust Secure Boot**, **EROFS + dm-verity**, Forced Module Signing |
| **Repudiation** | Unauthorized actions executed on compromised robot followed by log deletion | **Medium** | Denied forensic investigation, loss of liability trail | **IMA Runtime Measurement -> fTPM PCR 10 Chaining**, Immutable audit logs |
| **Information Disclosure** | Memory sniffing or storage dump extracting robot private keys or proprietary AI models | **Critical** | Device cloning, intellectual property theft | **Zero Plaintext Key Policy**, Private key isolated in Secure World / RPMB |
| **Denial of Service** | DoS attack disrupting control loops causing stability loss and fall | **High** | Balance failure, human injury, robot damage | **Watchdog Fail-Safe**, Safe stop fallback upon cryptographic verification failure |
| **Elevation of Privilege** | App exploit hijacking kernel ring 0 to compromise TrustZone | **Critical** | Total system compromise, TEE bypass attempt | **KSPP Kernel Hardening**, ARM TrustZone hardware isolation (EL3 / S-EL1) |

---

## 4. Security Controls Mapping Table

Technical countermeasure alignment with identified STRIDE threats and SRD requirements:

```text
 STRIDE Threats               Technical Security Controls            Security Requirements (SRD)
 ─────────────────            ───────────────────────────            ───────────────────────────
 Device Cloning / Spoofing ──> OP-TEE PKCS#11 TA + fTPM ───────────> SRD-COMM / SRD-MEAS
 Flash Storage Tampering   ──> EROFS + dm-verity Block Integrity ──> SRD-STOR / SRD-BOOT
 Plaintext Key Leakage     ──> SoftHSMv2 PKCS#11 URI Pipeline ────> SRD-HSM Policy
 Rootkit / Kernel Exploit  ──> KSPP Hardening + Forced Mod Sign ──> SRD-KERN
```

---

## 5. Residual Risk & Production Guidelines

1. **Hardware Glitch & Fault Injection**:
   - This verification platform focuses on software and architecture security layers. Physical production boards must integrate electromagnetic shielding and power glitch detection.
2. **Transitioning to Enterprise Hardware HSM**:
   - SoftHSMv2 is utilized in development and CI environments. Production deployment requires switching `PKCS11_MODULE_PATH` to FIPS 140-2/3 Level 3 certified hardware HSMs.
