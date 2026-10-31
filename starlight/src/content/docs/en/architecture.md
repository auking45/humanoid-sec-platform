---
title: "System Architecture Specification"
description: "Hardware trust boundaries, TF-A/OP-TEE, kernel hardening, and EROFS + dm-verity storage integrity"
---

> **Target Platform**: NVIDIA Jetson Humanoid Robot Control Architecture (L4T 6.x & QEMU aarch64 virt)  
> **Status**: Approved / Baseline

---

## 1. Architecture Overview & Trust Boundaries

- **Hardware Trust Boundary**: Enforces hardware isolation between Secure World and Normal World using ARMv8/ARMv9 TrustZone technology.
- **Physical-Independent Verification**: Accurately emulates Secure World (EL3, S-EL1, S-EL0) and Normal World (NS-EL1, NS-EL0) interfaces on QEMU `aarch64` `virt` machines.

[![System Architecture](/humanoid-sec-platform/diagrams/system_architecture.svg)](/humanoid-sec-platform/diagrams/system_architecture.html)
> 💡 *Click to view the [Archify Interactive Diagram](/humanoid-sec-platform/diagrams/system_architecture.html) with theme switching and trust boundary zooming.*

---

## 2. Secure Boot Chain

- **Cryptographic Chain of Trust**: Starts at immutable BootROM (EL3 RoT), sequentially verifying cryptographic signatures before transferring execution control.
- **TrustZone Cold Boot Sequence**:
  - `TF-A BL1 (EL3)`: Starts execution from PFLASH0 (`flash0.bin`) offset `0x0`, initializes platform hardware, and loads BL2.
  - `TF-A BL2 (Secure-EL1)`: Parses FIP (Firmware Image Package, offset `0x40000`), loading BL31 (EL3 Runtime) and BL32 (OP-TEE OS).
  - `TF-A BL31 (EL3)`: Initializes SMC dispatchers and transfers execution to S-EL1 Secure World.
  - `OP-TEE OS (S-EL1)`: Core initialization, opens UART1 (`0x09040000`) debug console, starts Early fTPM TA (`bc50d971-d4c9-42c4-82cb-343fb7f37896`), binds RPMB secure storage, and prepares PSCI handoff.
  - `Linux Kernel 6.8 Noble (Normal World NS-EL1)`: Boots via PSCI v1.1 handoff, probes OP-TEE SMC driver (`/dev/tee0`, `/dev/teepriv0`), initializes fTPM platform driver (`/dev/tpmrm0`), enables IMA subsystem, and executes userspace `/init`.
- **State Persistence**: Emulated eMMC RPMB partition guarantees replay protection and persistence for fTPM NVRAM and OP-TEE secure storage.

[![Secure Boot Sequence](/humanoid-sec-platform/diagrams/secure_boot_sequence.svg)](/humanoid-sec-platform/diagrams/secure_boot_sequence.html)
> 💡 *Click to view the [Archify Interactive Diagram](/humanoid-sec-platform/diagrams/secure_boot_sequence.html) with boot timeline trace animations.*

---

## 3. NVIDIA Jetson Linux R39.2.1 Official Secure Boot Architecture (SBKPKC + EKB + UEFI Secure Boot)

Implements the official NVIDIA Jetson Linux R39.2.1 (JetPack 7.2.1, Tegra234 Orin / Tegra264 Thor) Secure Boot Developer Guide (`SecureBoot.html`) and L4T OP-TEE PTA specifications (`jetson_uefi_services.c`, `jetson_ekb_extraction_t234.c`, `gen_ekb.py`) for 1:1 compatibility with physical Jetson board flashing (`odmfuse.sh` / `l4t_initrd_flash.sh`):

- **Official `<genericfuse>` XML & eFuse Table (`configs/secureboot/fuse_config.xml`, `tegra_fuses.json`)**:
  - Generates standard NVIDIA `odmfuse.sh` / `fskp_fuseburn.py` `<genericfuse MagicId="0x45535546" version="1.0.0">` XML:
    - `PublicKeyHash`: SHA-512 / SHA-256 digest of SoftHSMv2 `SecureBootKey` (RSA-3072, ID `06`) DER public key
    - `SecureBootKey` (`SBK`): 256-bit AES symmetric key for `SBKPKC` bootloader encryption (deterministically derived in SoftHSMv2 via PKCS#11)
    - `OemK1` / `OemK2` (`T234` Orin) & `OemKdk0` (`T264` Thor): 256-bit root keys for OP-TEE EKB, fTPM, and LUKS key derivation
    - `BootSecurityInfo`: `0x00000209` (`0x1` RSA-3072 PKC | `0x8` SBK Encryption Enabled | `0x200` `BSI_OEM_KEY_VALID_MASK`)
    - `SecurityMode`: `0x1` (`SECURITY_MODE_ENABLED_MASK` — enforces Production Secure Boot)
- **Official `gen_ekb.py` EKB Generation (`build/images/eks_t234.img`, `eks_t264.img`) & OP-TEE Extraction**:
  - Invokes official R39.2.1 `sources/optee/optee/samples/hwkey-agent/host/tool/gen_ekb/gen_ekb.py` using `OemK1` (`T234` NIST-SP-800-108 CMAC KDF) and `OemKdk0` (`T264` KBKDF-HMAC-SHA256) to generate `NVEKBP\0\0` v2.1 EKB blobs containing:
    - `Tag 1` (`ekb_kernel_encryption_key`, `sym_key`, 32B): UEFI/CPUBL kernel & DTB payload encryption key
    - `Tag 2` (`ekb_disk_encryption_key`, `sym_key2`, 16B): LUKS disk encryption root key (verified with `gen_luks_passphrase.py`)
    - `Tag 4` (`ekb_uefi_var_auth_key`, `auth_key`, 16B): UEFI variable authentication key (`jetson_user_key_pta_uefi_vars_auth`)
    - `Tag 5` (`ekb_hwkey_app_key`, 16B) and `Tag 91`/`92` (`ftpm_sn`, `ftpm_eps_seed`, 64B)
- **8,192-Byte (`0x2000`) `NVDA` Boot Component Header (`BCH`) & Two-Stage Auth/Encryption**:
  - Strictly follows `sources/optee/optee/optee_os/core/pta/tegra/include/jetson_uefi_services.h`:
    - Offset `0x0000`: `NVDA` (`BCH_HEADER_MAGIC`) + Stage 1 `PKC` (RSA-3072) signature + Stage 2 `UEFI db` (RSA-3072) signature + `SBK` AES-CMAC binding tag
    - Offset `0x1400` (`5120`, `BCH_HEADER_AAD_OFFSET`, 80 bytes): `BCRT` magic, padded ciphertext length (`5124`), KDF context `VER1` (`5136`), KDF label `CPUBL-PAYLOAD-DK` (`5168`), 12-byte AES-GCM IV (`5188`)
    - Offset `0x1450` (`5200`, `BCH_HEADER_TAG_OFFSET`, 16 bytes): AES-256-GCM authentication tag
    - Payload: Padded via ISO/IEC 9797-1 Method 2 (`0x80 0x00...`, `get_one_and_zeros_padding`) and encrypted with `AES-256-GCM` using 256-bit `DK` derived from EKB `sym_key` via `nist_sp_800_108_hmac_kdf`
- **Boot Verification, Decryption & Tamper-Rejection Pipeline**:
  - `scripts/sign_jetson_secureboot.sh`: Provides 6 commands (`burn-fuses`, `gen-ekb`, `verify-ekb`, `sign`, `verify`, `tamper-test`).
  - During QEMU (`--secureboot`) boot, validates `fuse_config.xml` and `eks_t234.img`, verifies Stage 1 `PKC` & Stage 2 `UEFI db` signatures on `kernel.signed`, decrypts the kernel payload via EKB `sym_key` (`AES-256-GCM`) into `build/run/kernel.decrypted`, and boots.
  - Immediately aborts boot (`SECURE_BOOT_VIOLATION`, Exit code 2) upon 1-byte ciphertext tamper, `<genericfuse>` XML mismatch, EKB corruption, or UEFI `db` signature corruption.

---

## 4. Dual-Target Kernel Build & Hardening Strategy

- **Design Principle**: Employs a 3-tier kernel configuration structure to eliminate security discrepancies between physical Jetson hardware and QEMU test environments.

```text
                                [ NVIDIA L4T Base defconfig ]
                               (Official tegra_defconfig baseline)
                                             │
                                             ▼
                      [ configs/kernel/security_hardening.config ]
               (KSPP baseline, Forced Module Signing, EROFS, dm-verity, IMA)
                                             │
                       ┌─────────────────────┴─────────────────────┐
                       │                                           │
                       ▼                                           ▼
             [ Real Jetson Target ]                      [ QEMU virt Target ]
         (Production Jetson Flash)                  + [ configs/kernel/qemu_compat.config ]
                                                  (VirtIO drivers, PL011 console, QEMU PCI)
```

### 4.1. Key Security Hardening Parameters (`security_hardening.config`)
- **Memory Defense & Exploit Mitigation**:
  - `CONFIG_KASLR=y`: Kernel address space layout randomization.
  - `CONFIG_STRICT_KERNEL_RWX=y` & `CONFIG_STRICT_MODULE_RWX=y`: Enforces W^X executable memory protection.
  - `CONFIG_STACKPROTECTOR_STRONG=y`: Stack canary buffer overflow defense.
  - `CONFIG_FORTIFY_SOURCE=y`: Runtime buffer bounds checking.
  - `CONFIG_SLAB_FREELIST_RANDOM=y` & `CONFIG_SLAB_FREELIST_HARDENED=y`: Heap metadata protection.
- **Integrity Enforcement**:
  - `CONFIG_MODULE_SIG=y` & `CONFIG_MODULE_SIG_FORCE=y`: Strict rejection of unsigned kernel modules.
  - `CONFIG_MODULE_SIG_ALL=y` & `CONFIG_MODULE_SIG_SHA256=y`: Automated module signing during build.
  - `CONFIG_DM_VERITY=y` & `CONFIG_DM_VERITY_VERIFY_ROOTHASH_SIG=y`: Cryptographic root hash validation.
  - `CONFIG_EROFS_FS=y`: High-performance compressed read-only filesystem.
- **Trusted Execution & Attestation**:
  - `CONFIG_TEE=y` & `CONFIG_OPTEE=y`: OP-TEE SMC client driver.
  - `CONFIG_TCG_TPM=y` & `CONFIG_TCG_FTPM_TEE=y`: OP-TEE fTPM communication interface.
  - `CONFIG_IMA=y` & `CONFIG_IMA_MEASURE_PCR_IDX=10`: Extends binary execution digests into fTPM PCR 10.

---

## 5. Storage Integrity Pipeline (EROFS + dm-verity & OverlayFS)

- **Immutable Filesystem**: Deploys an unmodifiable read-only `EROFS` rootfs to eliminate ransomware and persistence malware injection.
- **Block-Level Verification**: Linux `dm-verity` validates 4KB block-level Merkle tree hashes dynamically upon read access.
- **Dual-Profile Rootfs & OverlayFS Integration (`--minimal` vs `--ubuntu`)**:
  - **Fast Verification Profile (`--minimal`, default)**: Lightweight 1.2MB static C `initramfs` for sub-5-second GitHub Actions CI execution and rapid boot chain verification with a built-in interactive security shell.
  - **Official L4T Ubuntu 24.04 Noble Profile (`--ubuntu`)**: Packages the official NVIDIA JetPack 7.2.1 (L4T R39.2.1) Sample Rootfs (`Tegra_Linux_Sample-Root-Filesystem_R39.2.1_aarch64.tbz2`) into an immutable `EROFS` image (`ubuntu_rootfs.erofs`) backed by a signed `dm-verity` hash tree (`ubuntu_rootfs.verity`).
  - **OverlayFS Layering & `switch_root` Handoff**: At boot, `initramfs` verifies and mounts the read-only `dm-verity` EROFS image as `lowerdir`, merges a writable layer (`upperdir`, `workdir`) via `OverlayFS`, and executes `switch_root` into the full Ubuntu 24.04 userspace (`bash`, `dpkg`, `.deb` package installation, and runtime security testing).

```text
  [ Boot Stage: Initramfs Verifier ]
  ├── 1. Verify dm-verity Root Hash Signature (SoftHSM DmVeritySigningKey)
  ├── 2. Map VirtIO Block (/dev/vda + /dev/vdb) ──> /dev/mapper/dm-root (RO EROFS)
  ├── 3. Mount /dev/mapper/dm-root ───────────────> /mnt/lower (Immutable Base Ubuntu 24.04)
  ├── 4. Mount Writable Layer (tmpfs / ext4) ─────> /mnt/overlay/{upper,work}
  ├── 5. Mount OverlayFS (lower + upper) ─────────> /mnt/sysroot
  └── 6. Execute switch_root ─────────────────────> Ubuntu 24.04 LTS (/bin/bash, dpkg/apt)
```

[![Storage Integrity Pipeline](/humanoid-sec-platform/diagrams/storage_integrity_pipeline.svg)](/humanoid-sec-platform/diagrams/storage_integrity_pipeline.html)
> 💡 *Click to view the [Archify Interactive Diagram](/humanoid-sec-platform/diagrams/storage_integrity_pipeline.html) covering offline build signing and runtime measurement flows.*

---

## 6. Runtime Integrity Measurement (IMA) & fTPM PCR Extension

- **Dynamic Binary Measurement**: Kernel IMA intercepts `execve` calls, hashing binaries and shared libraries into fTPM PCR 10.
- **Immutable Audit Trail**: Maintains measurement events in `/sys/kernel/security/ima/runtime_measurements` for remote attestation quotes.

```text
 1. User Process  ──[sys_execve("/usr/bin/robot_node")]──> Linux Kernel VFS
 2. Linux Kernel  ──[Trigger Measurement Hook]───────────> Kernel IMA Engine
 3. Kernel IMA    ──[Compute SHA-256 Digest]─────────────> In-Memory Buffer
 4. Kernel IMA    ──[TPM2_PCR_Extend(PCR 10, Digest)]────> OP-TEE fTPM TA
 5. OP-TEE fTPM   ──[PCR[10] = SHA256(PCR[10] || Digest)]─> Secure NVRAM (RPMB)
 6. Kernel IMA    ──[Append Entry]───────────────────────> /sys/kernel/security/ima/measurements
 7. Linux Kernel  ──[Execute Process]────────────────────> Robot Node Running
```

---

## 7. QEMU aarch64 Virtual Emulation Topology

| Parameter | Specification | Description |
| :---: | :---: | :--- |
| **Machine Model** | `virt,secure=on,gic-version=2` | Enables ARMv8 TrustZone secure state |
| **CPU Architecture** | `cortex-a57` (4 Cores) | Standard aarch64 core emulation |
| **Memory Allocation** | `2048MB` (Normal World + Secure World DRAM) | Physical address space partitioning |
| **PFLASH0** | `build/firmware/flash0.bin` (64MB) | Monolithic firmware image with BL1(0x0) and FIP(0x40000) |
| **DTB Injection** | `.cache/run/virt_boot.dtb` | Injects `microsoft,ftpm` device node and initrd/bootargs |
| **Persistent Storage** | Virtual RPMB Socket (OP-TEE `tee-supplicant`) | Emulates eMMC RPMB hardware partition |
| **Networking** | User-net (`hostfwd=tcp::2222-:22,tcp::8443-:8443`) | Forwards SSH debug and mTLS verification ports |
| **Serial Console** | PL011 UART0 (Normal), UART1 (OP-TEE Console) | Dedicated channels for automated test log capture |