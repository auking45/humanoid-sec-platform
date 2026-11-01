# Feature 01 — NVIDIA Jetson Secure Boot & Stage 2 UEFI db Deep-Dive

> **Purpose**: Defines the technical implementation specifications of the hardware Root of Trust (RoT) dual-stage Secure Boot and encrypted bootloader pipeline for production humanoid robots based on NVIDIA Jetson Orin/Thor.  
> **Target Standard**: NVIDIA Jetson Linux R39.2.1 (JetPack 7.2.1), Tegra234 / Tegra264 Official Secure Boot Developer Guide (`SecureBoot.html`)  
> **Status**: Approved / Production Baseline  

---

## 1. Architectural Overview & Chain of Trust

Humanoid robots face constant physical tampering and chip-off threats. Any firmware or kernel image that fails to match the hardware eFuse hash digest must be blocked at the BootROM level before executing normal world code.

[![Secure Boot Sequence](../../diagrams/secure_boot_sequence.svg)](../../diagrams/secure_boot_sequence.html)
> 💡 *Click to open the [Archify Interactive Viewer](../../diagrams/secure_boot_sequence.html) for boot sequence timeline animation.*

---

## 2. NVIDIA Tegra SoC eFuse Register Specifications

Hardware fuses blown irreversibly (One-Time Programmable) during production board provisioning:

| eFuse Register | Bit Width | Value / Provisioning Target | Security Role in Production Humanoids |
| :--- | :---: | :--- | :--- |
| `SecurityMode` | 1 bit | `0x1` (`SECURITY_MODE_ENABLED`) | Disables debug JTAG ports; enforces Production Secure Boot |
| `BootSecurityInfo` | 32 bits | `0x00000209` | `0x1` RSA-3072 PKC + `0x8` SBK encryption + `0x200` OEM Key valid flag |
| `FUSE_PKC_HASH` | 256 bits | SoftHSMv2 `SecureBootKey` (RSA-3072) SHA-256 Digest | Authoritative fingerprint of the Stage 1 BootROM/MB2 public key |
| `FUSE_SECURE_BOOT_KEY` | 256 bits | 256-bit AES symmetric key (`SBK`) | CPUBL and bootloader container symmetric encryption key |
| `OEM_K1` / `OEM_KDK0` | 256 bits | 256-bit OEM root key derivation entropy | Root entropy for OP-TEE EKB, fTPM EPS seed, and LUKS key derivation |

### 2.1. Official `<genericfuse>` XML (`configs/secureboot/fuse_config.xml`)
```xml
<genericfuse MagicId="0x45535546" version="1.0.0">
  <fuse name="BootSecurityInfo" size="4" value="0x00000209" />
  <fuse name="SecurityMode" size="4" value="0x1" />
  <fuse name="PublicKeyHash" size="64" value="4a96c03f4f2596bfb14330a4c02544d59fbc347cd3dcc8dba14e85b112b9e02d..." />
  <fuse name="SecureBootKey" size="32" value="0x112233445566778899aabbccddeeff00112233445566778899aabbccddeeff00" />
  <fuse name="OemK1" size="32" value="0x99aabbccddeeff00112233445566778899aabbccddeeff001122334455667788" />
</genericfuse>
```

---

## 3. EKB (Encrypted KeyBlob) v2.1 Structure & Tag Provisioning

The v2.1 EKB binary (`build/images/eks_t234.img`) generated from `OemK1` (T234) following `gen_ekb.py`:

```text
+-------------------------------------------------------------------------+
| EKB Header (NVEKBP\0\0, version 2.1, 16-byte random IV, Auth Tag)       |
+-------------------------------------------------------------------------+
| Tag 1  (sym_key, 32B)    : UEFI/CPUBL kernel & DTB payload decryption key|
| Tag 2  (sym_key2, 16B)   : LUKS full-disk master volume key             |
| Tag 4  (auth_key, 16B)   : OP-TEE RPMB UEFI Authenticated Variable key  |
| Tag 5  (hwkey_app, 16B)  : Custom hardware crypto accelerator access key|
| Tag 91 (ftpm_sn, 32B)    : fTPM 2.0 unique hardware serial number       |
| Tag 92 (ftpm_eps, 32B)   : fTPM 2.0 Primary Endorsement Seed (EPS)      |
+-------------------------------------------------------------------------+
```

---

## 4. 8,192-byte NVDA Boot Component Header (BCH) Layout

Header mapping following `jetson_uefi_services.h`:

- **Offset `0x0000` (`0`)**: `NVDA` (`BCH_HEADER_MAGIC`)
- **Offset `0x0098` (`152`)**: Stage 2 UEFI db public key SHA-256 digest (32 bytes)
- **Offset `0x0100` (`256`)**: Stage 1 BootROM/MB2 PKC (RSA-3072, 384 bytes) signature
- **Offset `0x0280` (`640`)**: Stage 2 UEFI db (RSA-3072, 384 bytes) signature
- **Offset `0x1400` (`5120`)**: `BCRT` magic + 80B AAD (KDF label `CPUBL-PAYLOAD-DK`, 12B IV)
- **Offset `0x1450` (`5200`)**: AES-256-GCM 16-byte Authentication Tag
- **Offset `0x2000` (`8192`)**: ISO/IEC 9797-1 Method 2 padded encrypted kernel payload

---

## 5. Dual-Stage Verification & Tamper-Resistance Proof

Automated tests `test_atk01_secureboot_rogue_key_and_kernel_tamper` and `test_atk06_uefi_db_signature_forgery_and_authvar_tamper` mathematically verify that corrupted ciphertexts, forged PKC keys, modified EKB blobs, or altered UEFI db signatures immediately abort the boot sequence (`SECURE_BOOT_VIOLATION`, Exit code 2).

