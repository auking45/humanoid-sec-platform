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
- **State Persistence**: Emulated eMMC RPMB partition guarantees replay protection and persistence for fTPM NVRAM and OP-TEE secure storage.

[![Secure Boot Sequence](/humanoid-sec-platform/diagrams/secure_boot_sequence.svg)](/humanoid-sec-platform/diagrams/secure_boot_sequence.html)
> 💡 *Click to view the [Archify Interactive Diagram](/humanoid-sec-platform/diagrams/secure_boot_sequence.html) with boot timeline trace animations.*

---

## 3. Dual-Target Kernel Build & Hardening Strategy

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

### 3.1. Key Security Hardening Parameters (`security_hardening.config`)
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

## 4. Storage Integrity Pipeline (EROFS + dm-verity)

- **Immutable Filesystem**: Deploys an unmodifiable read-only `EROFS` rootfs to eliminate ransomware and persistence malware injection.
- **Block-Level Verification**: Linux `dm-verity` validates 4KB block-level Merkle tree hashes dynamically upon read access.

[![Storage Integrity Pipeline](/humanoid-sec-platform/diagrams/storage_integrity_pipeline.svg)](/humanoid-sec-platform/diagrams/storage_integrity_pipeline.html)
> 💡 *Click to view the [Archify Interactive Diagram](/humanoid-sec-platform/diagrams/storage_integrity_pipeline.html) covering offline build signing and runtime measurement flows.*

---

## 5. Runtime Integrity Measurement (IMA) & fTPM PCR Extension

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

## 6. QEMU aarch64 Virtual Emulation Topology

| Parameter | Specification | Description |
| :--- | :--- | :--- |
| **Machine Model** | `virt,secure=on,virtualization=on,gic-version=3` | Enables ARMv8 TrustZone secure state |
| **CPU Architecture** | `cortex-a57` or `cortex-a72` (4 Cores) | Standard aarch64 core emulation |
| **Memory Allocation** | `4096MB` (3072MB Normal World + 1024MB Secure World DRAM) | Physical address space partitioning |
| **Persistent Storage** | Virtual RPMB Socket (OP-TEE `tee-supplicant`) | Emulates eMMC RPMB hardware partition |
| **Networking** | User-net (`hostfwd=tcp::2222-:22,tcp::8443-:8443`) | Forwards SSH debug and mTLS verification ports |
| **Serial Console** | PL011 UART0 (Normal), UART1 (OP-TEE Console) | Dedicated channels for automated test log capture |