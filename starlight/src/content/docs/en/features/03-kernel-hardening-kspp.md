---
title: "03. Linux 6.8 KSPP Kernel Hardening & Forced Module Signing Deep-Dive"
description: "Memory protection, unprivileged eBPF restriction, and SoftHSM RSA-3072 forced module signing"
---

> **Purpose**: Defines the technical hardening specifications and forced module signature architecture minimizing the attack surface and mitigating ring-0 privilege escalation on the L4T kernel (Linux 6.8, Ubuntu 24.04 Noble).
> **Target Standard**: Kernel Self-Protection Project (KSPP), Linux Kernel Module Cryptographic Signing
> **Status**: Approved / Production Baseline

---

## 1. Architectural Overview & Defense-in-Depth

The kernel directly governs robot motor actuators, industrial sensor buses (CAN, SPI, I2C), and the communications stack. A single control-flow hijacking vulnerability can directly result in physical collision or hardware damage.

[![Kernel Hardening Layers](/humanoid-sec-platform/diagrams/kernel_hardening_layers.svg)](/humanoid-sec-platform/diagrams/kernel_hardening_layers.html)
> 💡 *Click to open the [Archify Interactive Viewer](/humanoid-sec-platform/diagrams/kernel_hardening_layers.html) for defense-in-depth visual layers.*

---

## 2. KSPP Core Memory Hardening (configs/kernel/security_hardening.config)

### 2.1. Physical Memory Direct Access Prohibition
- `CONFIG_STRICT_DEVMEM=y` & `CONFIG_IO_STRICT_DEVMEM=y`:
  - Blocks userspace processes from mapping physical RAM or peripheral registers via `/dev/mem` or `/dev/kmem`.
  - Prevents sniffing resident cryptographic keys or robot firmware secrets.

### 2.2. Kernel Address Space Layout Randomization (KASLR)
- `CONFIG_RANDOMIZE_BASE=y`: Randomizes the kernel base address upon boot, defeating fixed-offset ROP/JOP gadget chains.
- `CONFIG_RANDOMIZE_MODULE_REGION_FULL=y`: Extends randomization to dynamic kernel module memory regions.

### 2.3. Page Table & Usercopy Integrity
- `CONFIG_PAGE_TABLE_CHECK=y` & `CONFIG_PAGE_TABLE_CHECK_ENFORCE=y`: Aborts execution immediately upon illegal page permission escalations.
- `CONFIG_HARDENED_USERCOPY=y`: Validates object bounds across the user/kernel memory boundary.

---

## 3. Allocator & Stack Hardening

| Kernel Symbol | Security Mechanism | Mitigated Threat |
| :--- | :--- | :--- |
| `CONFIG_SLAB_FREELIST_HARDENED=y` | Obfuscates SLUB freelist pointers via XOR cookies | Heap overflow, Use-After-Free (UAF) |
| `CONFIG_SLAB_FREELIST_RANDOM=y` | Shuffles heap chunk allocation ordering | Deterministic heap grooming exploits |
| `CONFIG_SHUFFLE_PAGE_ALLOCATOR=y` | Randomizes page allocator freelists | Adjacent page manipulation attacks |
| `CONFIG_STACKPROTECTOR_STRONG=y` | Inserts cryptographic stack canaries | Stack buffer overflows (Stack Smashing) |
| `CONFIG_INIT_ON_ALLOC_DEFAULT_ON=y` | Zeroes newly allocated memory | Uninitialized memory data leakage |

---

## 4. Attack Surface Reduction

- `CONFIG_BPF_UNPRIV_DEFAULT_OFF=y`: Restricts eBPF execution to privileged administrators, neutralizing speculative execution side-channels.
- `CONFIG_SECURITY_DMESG_RESTRICT=y`: Prevents unprivileged `dmesg` reading to stop KASLR kernel address leaks.
- `CONFIG_PROTECTED_HARDLINKS=y` & `CONFIG_PROTECTED_SYMLINKS=y`: Defeats TOCTOU symlink hijacking vulnerabilities.

---

## 5. Forced Kernel Module Signing (`CONFIG_MODULE_SIG_FORCE=y`)

- **Strict Enforcement Policy**:
  - `CONFIG_MODULE_SIG=y`, `CONFIG_MODULE_SIG_FORCE=y`, `CONFIG_MODULE_SIG_ALL=y`, `CONFIG_MODULE_SIG_SHA256=y`.
  - Any unsigned or tampered `.ko` binary is immediately rejected by the kernel loader with `EKEYREJECTED`.
- **SoftHSMv2 Signing Pipeline**:
  - Signs drivers using `KernelModuleSigningKey` (RSA-3072, ID `01`) via RFC 7512 URI:
  ```bash
  sign_helper.sh kmod --in build/drivers/custom_sensor.ko
  ```
- **Automated Verification (ATK-02 & ATK-07)**:
  - Both unsigned rootkit injection and `/dev/mem` snooping are verified blocked (`tests/test_attack_scenarios.py`).