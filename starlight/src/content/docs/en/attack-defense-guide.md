---
title: "Attack Scenarios & Defense-in-Depth Verification Guide"
description: "Technical analysis of 10 attack vectors, vulnerable baselines, and hardened platform defense mechanisms (ATK-01~10)"
---

> **Purpose**: Proves the architectural necessity and technical defense mechanisms of the platform's 10 core security controls against physical, network, and runtime threats in humanoid robot autonomous environments.  
> **Verification Harness**: `tests/test_attack_scenarios.py` (Red/Blue Team Attack Simulation Suite)  
> **Core Principles**: Defense-in-Depth, Least Privilege, Fail-Secure Enforcement  

---

## 1. End-to-End Attack & Defense Matrix (ATK-01 through ATK-10)

| Attack ID | Phase | Scenario Description | STRIDE Category | Vulnerable Baseline | Hardened Platform Security Control | Security Outcome |
| :---: | :---: | :--- | :---: | :--- | :--- | :--- |
| **ATK-01** | Phase 2 | Kernel Ciphertext Tampering & Rogue Signing Key Bypass | **Tampering / Elevation** | Unverified boot loads corrupted or backdoored kernel payload | **NVIDIA Tegra PKC + SoC eFuse + SBKPKC 8KB BCH Container** | Immediate boot abort (`Exit 2`) on eFuse mismatch or AES-GCM tag failure |
| **ATK-02** | Phase 2/4 | Unsigned Rootkit Kernel Module (`.ko`) Injection | **Tampering / Elevation** | Arbitrary `.ko` loads into ring 0 via `insmod` without signature verification | **`CONFIG_MODULE_SIG_FORCE=y` + SoftHSMv2 RSA-3072 Signature** | Unsigned or tampered module rejected with `EKEYREJECTED` |
| **ATK-03** | Phase 5 | Offline Chip-off Flash Storage Tampering | **Tampering** | Modifications to rootfs persist silently across reboots | **EROFS Read-Only Image + dm-verity Merkle Tree + HSM Root Hash Signature** | Real-time I/O error (`EIO`) on corrupted 4KB block; forged Merkle root rejected |
| **ATK-04** | Phase 3/6 | Stealth Malware Execution & Attestation Quote Replay | **Tampering / Repudiation** | Static telemetry or replayed valid quote hides compromised state | **fTPM PCR 10 Hash Chaining + Fresh Nonce Remote Attestation** | Replay blocked; PCR 10 mismatch triggers `UNTRUSTED` verdict |
| **ATK-05** | Phase 4/6 | Filesystem Private Key Exfiltration & Rogue Robot mTLS | **Information Disclosure / Spoofing** | Plaintext private keys on disk dumped to clone robot identity | **Zero Plaintext Key Policy + PKCS#11 Non-extractable Token Isolation** | Zero key files on disk; rogue self-signed certificate rejected at TLS handshake |
| **ATK-06** | Phase 0/2 | Stage 2 UEFI db Signature Forgery & AuthVar Tamper | **Tampering / Elevation** | Attacker bypasses bootloader auth or tampers with UEFI security variables | **Stage 2 UEFI db (RSA-3072) + EKB Tag 4 UEFI AuthVar Key Binding** | Boot halted immediately if Stage 2 signature or EKB AuthVar is tampered |
| **ATK-07** | Phase 2 | Kernel Runtime Attack Surface Exploitation & Physical RAM Snooping | **Elevation / Information Disclosure** | `/dev/mem` access and unprivileged eBPF allow reading/writing kernel memory | **KSPP Hardening (`STRICT_DEVMEM`, `BPF_UNPRIV_DEFAULT_OFF`, etc.)** | Direct physical memory mapping blocked; unprivileged eBPF rejected |
| **ATK-08** | Phase 3 | Normal World TrustZone Memory Intrusion & Storage Rollback | **Tampering / Elevation** | Compromised kernel accesses TZDRAM or replays stale fTPM state | **ARM TrustZone Hardware Bus Firewall + RPMB Write Counter Auth** | Hardware bus error on secure RAM access; rollback rejected with `TEE_ERROR_SECURITY` |
| **ATK-09** | Phase 5 | Runtime Executable Tampering & Stripped IMA xattr | **Tampering** | Unverified executable runs without integrity appraisal | **IMA Appraisal (`ima_policy=tcb`) + HSM ECDSA Signature Enforcement** | Missing or invalid `security.ima` signature triggers `EACCES` execution failure |
| **ATK-10** | Phase 6 | Network MITM & Rogue Motion Command Injection | **Spoofing / Tampering** | Unauthenticated or one-way TLS allows forged control packets | **TLS 1.3 Mutual TLS (mTLS) + Perfect Forward Secrecy (PFS)** | Handshake aborted for untrusted server; session traffic secure against eavesdropping |

---

## 2. In-Depth Technical Attack & Defense Analysis

### [ATK-01] Kernel Ciphertext Tampering & Rogue Signing Key Bypass (Secure Boot)
- **Attack Vector**: Attacker with physical flash access modifies kernel binary to inject rootkit/backdoor hooks, signs with an unauthorized private RSA key, and boots.
- **Vulnerable Baseline**: Without hardware-rooted Secure Boot, the system blindly executes the modified kernel, granting rootkit control over the robot.
- **Hardened Defense**:
  - Matches the Stage 1 PKC public key against SoC eFuse `FUSE_PKC_HASH`.
  - Validates AES-256-GCM authentication tag in the 8KB NVDA BCH container; any 1-bit alteration causes cryptographic decryption failure (`SECURE_BOOT_VIOLATION`, Exit code 2).
- **Automated Test**: `test_atk01_secureboot_rogue_key_and_kernel_tamper`

---

### [ATK-02] Unsigned Rootkit Kernel Module (`.ko`) Injection (Kernel Module Signing)
- **Attack Vector**: Attacker with root privileges loads an untrusted kernel module disguised as an actuator driver to manipulate motor controls.
- **Vulnerable Baseline**: Kernels without `CONFIG_MODULE_SIG_FORCE` load unsigned modules, compromising kernel space.
- **Hardened Defense**:
  - Forces `CONFIG_MODULE_SIG_FORCE=y` in kernel configuration.
  - Requires valid cryptographic signature from SoftHSMv2 `KernelModuleSigningKey` (RSA-3072); unsigned or modified `.ko` returns `EKEYREJECTED`.
- **Automated Test**: `test_atk02_unsigned_and_tampered_kernel_module`

---

### [ATK-03] Offline Chip-off Flash Storage Tampering (EROFS + dm-verity)
- **Attack Vector**: Attacker de-solders eMMC, modifies `/bin/bash` or motion control binaries on disk, and re-attaches the flash.
- **Vulnerable Baseline**: Standard read-write ext4 partitions persist modifications silently.
- **Hardened Defense**:
  - Read-only EROFS partition protected by dm-verity Merkle tree.
  - Reads verify 4KB blocks dynamically against cryptographic hashes; corrupted blocks raise `EIO`.
  - Recomputed Merkle trees are rejected because `verity.roothash.sig` requires SoftHSM `DmVeritySigningKey` verification.
- **Automated Test**: `test_atk03_dm_verity_offline_corruption_and_ro_enforcement`

---

### [ATK-04] Stealth Malware Execution & Attestation Quote Replay (fTPM + IMA)
- **Attack Vector**: Attacker executes in-memory malware and replays a captured valid TPM quote to spoof compliance to Fleet Management.
- **Vulnerable Baseline**: Static status checks accept replayed credentials.
- **Hardened Defense**:
  - Fleet Verifier issues unique cryptographic `Nonce` challenges bound to the fTPM quote signature.
  - Runtime execution extends fTPM PCR 10 via IMA; discrepancies between IMA logs and PCR 10 composite result in `UNTRUSTED` verdict.
- **Automated Test**: `test_atk04_runtime_ima_tamper_and_attestation_replay`

---

### [ATK-05] Filesystem Private Key Exfiltration & Rogue Robot mTLS (Zero Plaintext Key)
- **Attack Vector**: Attacker dumps filesystem to steal plaintext mTLS private keys, impersonating the robot on fleet networks.
- **Vulnerable Baseline**: Plaintext keys on disk permit device identity cloning.
- **Hardened Defense**:
  - Strict Zero Plaintext Key policy guarantees no private key files on disk (`audit_zero_keys.sh`).
  - Device identity keys generated inside OP-TEE PKCS#11 TA with `CKA_EXTRACTABLE=FALSE`.
  - Fleet server rejects self-signed certificates during TLS 1.3 mTLS handshake.
- **Automated Test**: `test_atk05_key_exfiltration_and_rogue_mtls_client`

---

### [ATK-06] Stage 2 UEFI db Signature Forgery & AuthVar Tamper (UEFI Security)
- **Attack Vector**: Attacker tampers with Stage 2 UEFI db signatures in the bootloader or modifies UEFI variables to disable secure boot.
- **Vulnerable Baseline**: Single-stage or unauthenticated variable storage permits permanent backdoor persistence.
- **Hardened Defense**:
  - Enforces official 8KB NVDA BCH container with Stage 2 UEFI db RSA-3072 signature at offset `640..1024`.
  - Protects UEFI variables using OP-TEE RPMB authenticated via EKB Tag 4 (`ekb_uefi_var_auth_key`).
- **Automated Test**: `test_atk06_uefi_db_signature_forgery_and_authvar_tamper`

---

### [ATK-07] Kernel Runtime Attack Surface Exploitation (KSPP Hardening)
- **Attack Vector**: Attacker exploits userspace process to open `/dev/mem` or inject unprivileged eBPF programs to snoop kernel secrets.
- **Vulnerable Baseline**: Generic kernels permit physical memory access and speculative execution side-channels.
- **Hardened Defense**:
  - `CONFIG_STRICT_DEVMEM=y` and `CONFIG_IO_STRICT_DEVMEM=y` prevent userspace physical memory mapping.
  - `CONFIG_BPF_UNPRIV_DEFAULT_OFF=y` restricts eBPF to privileged administrative contexts.
  - Active heap freelist hardening and stack protectors prevent control flow hijacking.
- **Automated Test**: `test_atk07_kernel_hardening_kspp_attack_surface`

---

### [ATK-08] Normal World TrustZone Memory Intrusion & Storage Rollback (TrustZone & RPMB)
- **Attack Vector**: Kernel-level attacker attempts direct physical bus read of Secure World RAM (TZDRAM) or restores an older eMMC snapshot to roll back fTPM/PKCS#11 state.
- **Vulnerable Baseline**: Lack of hardware firewall permits secure world extraction; standard flash storage allows rollback attacks.
- **Hardened Defense**:
  - ARM TrustZone TZASC blocks Normal World access to secure memory regions.
  - RPMB write counter guarantees freshness; replayed flash blocks trigger `TEE_ERROR_SECURITY`.
- **Automated Test**: `test_atk08_trustzone_memory_isolation_and_rpmb_rollback`

---

### [ATK-09] Runtime Executable Tampering & Stripped IMA xattr (IMA Appraisal)
- **Attack Vector**: Attacker drops a modified binary into writable storage and strips `security.ima` extended attributes to bypass appraisal.
- **Vulnerable Baseline**: Systems without mandatory appraisal execute unmeasured binaries.
- **Hardened Defense**:
  - IMA policy (`ima_policy=tcb`, `appraise_type=imasig`) enforces signature checks on all executable invocations.
  - Missing or tampered signatures cause immediate `EACCES` execution failure.
- **Automated Test**: `test_atk09_ima_appraisal_bypass_and_stripped_xattr`

---

### [ATK-10] Network MITM & Rogue Motion Command Injection (TLS 1.3 mTLS & PFS)
- **Attack Vector**: Attacker injects a rogue rogue proxy on wireless networks to present false server certificates and issue forged robot control commands.
- **Vulnerable Baseline**: One-way or unverified TLS connections trust spoofed control servers.
- **Hardened Defense**:
  - TLS 1.3 Mutual TLS verifies client and server certificates against platform CA trust root.
  - Perfect Forward Secrecy ensures captured session traffic remains indecipherable even if credentials are later rotated.
- **Automated Test**: `test_atk10_mitm_network_spoofing_and_pfs_defense`

---

## 3. Automated Execution & Verification

Run the entire 10-point test suite locally or within CI:

```bash
python3 -m unittest tests/test_attack_scenarios.py -v
```

Expected output: 10/10 attack scenarios verified (Fail-Secure behavior confirmed across all vectors).