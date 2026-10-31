---
title: "E2E Security Verification & Attack Lab Guide"
description: "Step-by-step E2E verification manual and Red/Blue Team attack scenarios (ATK-01~05)"
---

> **Document ID**: `HSP-VER-001`  
> **Target Platform**: NVIDIA JetPack 7.2.1 (Jetson Linux R39.2.1 / Kernel 6.8 / Ubuntu 24.04 Noble) & QEMU `aarch64` (`virt`, `secure=on`)

---

## 1. Overview & Verification Philosophy

- This document serves as the **End-to-End (E2E) Verification & Attack Lab Manual** for executing and validating all security layers of the **Humanoid Security Platform** (Secure Boot, TrustZone OP-TEE/fTPM, Kernel Hardening, EROFS + `dm-verity` + `OverlayFS`, IMA, SoftHSMv2/PKCS#11 mTLS, and Remote Attestation).
- Beyond happy-path functional checks, this guide establishes a 1:1 comparative verification model contrasting a **Vulnerable Baseline (how an attack succeeds when a security control is absent or disabled)** against the **Hardened Platform (how the exact same attack is immediately blocked or detected)**.
- Every verification step and attack simulation is deterministic and reproducible across both local developer environments (VS Code Dev Container / Linux CLI) and the GitHub Actions CI pipeline.

---

## 2. E2E Verification Architecture & Matrix

| Step | Security Domain | Verification Script / Command | Mapped SRD IDs | Automated Test Suite |
| :---: | :--- | :--- | :---: | :--- |
| **Step 1** | **HSM Key Provisioning & Zero-Key Audit** | `keys_hsm/setup_softhsm.sh`<br>`keys_hsm/audit_zero_keys.sh` | `SRD-HSM-001` ~ `003` | `tests/test_hsm_keys.py` |
| **Step 2** | **NVIDIA Tegra PKC Secure Boot & eFuse** | `scripts/sign_jetson_secureboot.sh` | `SRD-BOOT-001` ~ `003` | `tests/test_secureboot_chain.py` |
| **Step 3** | **Dual-Profile Rootfs (`dm-verity` + `OverlayFS`)** | `scripts/build_rootfs.sh --minimal`<br>`scripts/build_rootfs.sh --ubuntu` | `SRD-STOR-001` ~ `004` | `tests/test_ftpm_ima.py` |
| **Step 4** | **TrustZone Cold Boot & Ubuntu 24.04 Handoff** | `scripts/run_qemu.sh --ubuntu --optee-chain --secureboot` | `SRD-TEE-001` ~ `004` | `tests/test_boot_optee.py`<br>`tests/test_secureboot_chain.py` |
| **Step 5** | **PKCS#11 mTLS 1.3 & Remote Attestation** | `apps/mtls_client/mtls_verify.py`<br>`apps/attestation_agent/verifier.py` | `SRD-COM-001` ~ `002`<br>`SRD-INT-001` ~ `003` | `tests/test_secure_mtls.py` |
| **Step 6** | **Red/Blue Team 5 Attack Scenarios** | `scripts/run_attack_demo.sh` | Cross-Layer Defense | `tests/test_attack_scenarios.py` |

---

## 3. Step-by-Step E2E Verification Procedure

### 3.1. Step 1 — SoftHSMv2 Token Initialization & Zero Plaintext Key Audit
- Provision all offline signing keys (`SecureBootKey`, `KernelModuleSigningKey`, `DmVeritySigningKey`, `ImaSigningKey`, `DeviceEnrollmentCaKey`) and runtime device identity keys (`HumanoidDeviceIdentityKey`) inside the SoftHSMv2 PKCS#11 token with `CKA_EXTRACTABLE=FALSE`, and audit the repository to confirm zero plaintext private keys exist on disk.

```bash
# 1. Initialize SoftHSMv2 token and provision PKCS#11 keypairs
bash keys_hsm/setup_softhsm.sh

# 2. Run full-tree Zero Plaintext Private Key (.pem, .key) audit
bash keys_hsm/audit_zero_keys.sh
```
- **Expected Outcome**:
  - Only public keys and certificates are exported under `keys_hsm/certs/`, while private keys remain strictly non-extractable inside the PKCS#11 token.
  - Output confirms `Zero Plaintext Key Policy: PASSED (0 plaintext private keys)`.

### 3.2. Step 2 — NVIDIA Jetson Tegra PKC Secure Boot Signing & eFuse Verification
- Provision the SHA-256 digest of `SecureBootKey` (`FUSE_PKC_HASH`) into the simulated SoC eFuse configuration (`configs/secureboot/tegra_fuses.json`), sign the Linux kernel image into an `NVD1` authenticated container (`build/images/kernel.signed`), and verify cryptographic authenticity.

```bash
# 1. Provision SoC eFuses (burn FUSE_PKC_HASH and enable ODM security mode)
bash scripts/sign_jetson_secureboot.sh burn-fuses --out configs/secureboot/tegra_fuses.json

# 2. Sign kernel image and verify against SoC eFuses
bash scripts/sign_jetson_secureboot.sh sign --in build/kernel/arch/arm64/boot/Image --out build/images/kernel.signed
bash scripts/sign_jetson_secureboot.sh verify --in build/images/kernel.signed

# 3. Run built-in 1-byte tamper and rogue key rejection self-test
bash scripts/sign_jetson_secureboot.sh tamper-test
```
- **Expected Outcome**:
  - Authentic container outputs `PASS: Container authenticated successfully`.
  - Any 1-byte payload modification, signature corruption, or mismatched eFuse hash immediately returns `FAIL` and halts boot.

### 3.3. Step 3 — Dual-Profile Immutable Rootfs (`EROFS` + `dm-verity`) Build
- Package either the lightweight verification profile (`--minimal`) or the official NVIDIA JetPack 7.2.1 Ubuntu 24.04 LTS Sample Rootfs (`--ubuntu`) into a read-only EROFS image paired with a SHA-256 `dm-verity` Merkle hash tree signed by SoftHSMv2.

```bash
# Profile 1: Build fast minimal EROFS + dm-verity image for CI and rapid checks
bash scripts/build_rootfs.sh --minimal

# Profile 2: Build full L4T R39.2.1 Ubuntu 24.04 LTS EROFS + dm-verity image
bash scripts/build_rootfs.sh --ubuntu
```
- **Expected Outcome**:
  - Generates `build/images/ubuntu_rootfs.erofs` (data image), `build/images/ubuntu_rootfs.verity` (Merkle hash tree), and `build/images/ubuntu_verity.roothash.sig` (SoftHSMv2 PKCS#11 signature).
  - Automatically passes `veritysetup verify` and 1-byte data block tamper rejection (`Tamper-resistance verification: PASSED`).

### 3.4. Step 4 — TrustZone Cold Boot & Ubuntu 24.04 `OverlayFS` Runtime Verification
- Boot the complete TrustZone cold boot chain: `TF-A (BL1 -> BL2 -> BL31)` -> `OP-TEE (BL32 + Early fTPM TA + PKCS#11 TA)` -> `Linux Kernel 6.8` -> `Initramfs (dm-verity verified mount + OverlayFS union)` -> `Ubuntu 24.04 LTS`.

```bash
# Launch interactive Ubuntu 24.04 LTS security verification shell
bash scripts/run_qemu.sh --ubuntu --optee-chain --secureboot
```
- **Interactive Commands Inside the Ubuntu 24.04 Shell (`root@jetson-ubuntu24:~#`)**:
```bash
# 1. Inspect comprehensive platform security status (OS, Kernel, OverlayFS, dm-verity, OP-TEE, fTPM, IMA, dpkg)
sec-status

# 2. Verify Ubuntu package managers
dpkg --version
apt --version

# 3. Verify writable OverlayFS upperdir operation
echo "Humanoid-Test-Config" > /etc/robot_runtime.conf && cat /etc/robot_runtime.conf

# 4. Attempt unauthorized write to underlying dm-verity EROFS lowerdir (/mnt/lower)
touch /mnt/lower/malicious_backdoor
# -> touch: cannot touch '/mnt/lower/malicious_backdoor': Read-only file system

# 5. Cleanly power off the virtual machine
poweroff
```

---

## 4. Red/Blue Team Attack Scenarios (`ATK-01` ~ `ATK-05`)

Each attack scenario executes against both a **Vulnerable Baseline (security feature disabled/absent)** and the **Hardened Platform (security feature enforced)** to demonstrate concrete defense effectiveness.

| Scenario ID | Attack Scenario | Vulnerable Baseline (Feature Absent) | Hardened Platform (Feature Enforced) | Automated Test Method |
| :---: | :--- | :--- | :--- | :--- |
| **ATK-01** | **Malicious Kernel Injection & Rogue Signing Key Bypass** | Without eFuse/signature verification, a modified kernel or a kernel signed by an attacker's rogue key boots normally (`COMPROMISED`) | 1) 1-byte kernel modification fails RSA-3072-PSS verification<br>2) Re-signing with a rogue key fails SoC eFuse (`FUSE_PKC_HASH`) comparison, halting boot (`BLOCKED`) | `test_atk01_secureboot_rogue_key_and_kernel_tamper` |
| **ATK-02** | **Unsigned / Tampered Rootkit Kernel Module (`.ko`) Load** | Without `CONFIG_MODULE_SIG_FORCE`, unsigned or modified `.ko` modules load into ring-0 kernel memory (`COMPROMISED`) | Missing signature or 1-byte modification in `.ko` binary fails `KernelModuleSigningKey` verification and blocks module load (`BLOCKED`) | `test_atk02_unsigned_and_tampered_kernel_module` |
| **ATK-03** | **Offline Rootfs Binary Tampering & Runtime Persistence Attack** | On standard read-write filesystems without `dm-verity`, sector modifications and binary backdoors persist across reboots (`COMPROMISED`) | 1) Offline 1-byte sector modification triggers `dm-verity` Merkle tree verification failure<br>2) Runtime `/mnt/lower` EROFS rejects writes (`EROFS`), and `tmpfs` `upperdir` changes are wiped clean on reboot (`BLOCKED`) | `test_atk03_dm_verity_offline_corruption_and_ro_enforcement` |
| **ATK-04** | **Stealth Malware Execution & Remote Attestation Quote Replay** | Without IMA PCR extension and nonce validation, malware execution goes unnoticed or old valid quotes are replayed (`COMPROMISED`) | 1) Executing an unauthorized binary extends fTPM `PCR 10`, diverging from the Golden PCR<br>2) Replaying a prior valid Quote fails Verifier single-use nonce checks<br>3) Forging the IMA log fails `PCR 10` hash-chain replay (`BLOCKED`) | `test_atk04_runtime_ima_tamper_and_attestation_replay` |
| **ATK-05** | **Filesystem Key Exfiltration & Rogue Client mTLS Intrusion** | Plaintext `.pem`/`.key` files on disk are stolen to clone robot identity, or unauthorized clients connect to the fleet server (`COMPROMISED`) | 1) Zero plaintext keys exist on disk and `CKA_EXTRACTABLE=FALSE` prevents raw key export<br>2) Connecting with an attacker's rogue certificate is rejected during the TLS 1.3 mutual authentication handshake (`BLOCKED`) | `test_atk05_key_exfiltration_and_rogue_mtls_client` |

---

## 5. Running the One-Click Attack Demo & Full Test Suite

### 5.1. One-Click Red/Blue Team Attack Simulation Demo
- Executes all five attack scenarios (`ATK-01` ~ `ATK-05`) and prints a side-by-side summary table comparing `[Vulnerable Baseline: COMPROMISED]` vs. `[Hardened Platform: BLOCKED]`.

```bash
bash scripts/run_attack_demo.sh
```

### 5.2. Running the Complete Automated Test Suite
- Executes all unit, integration, and attack scenario tests across Phases 2 through 7.

```bash
# Run all test suites (test_boot_optee, test_secureboot_chain, test_ftpm_ima, test_hsm_keys, test_secure_mtls, test_attack_scenarios)
python3 -m unittest discover -s tests -v

# Run only the Red/Blue Team attack scenario test suite
python3 -m unittest tests/test_attack_scenarios.py -v
```