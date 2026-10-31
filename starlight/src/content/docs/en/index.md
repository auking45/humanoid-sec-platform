---
title: "Humanoid Security Platform"
description: "QEMU-based security verification & hardening platform for NVIDIA Jetson humanoid robots"
template: splash
hero:
  title: "Humanoid Security Platform"
  tagline: "QEMU & L4T Security Verification for NVIDIA Jetson Humanoid Robots (OP-TEE, fTPM, EROFS dm-verity, and Secure mTLS)"
  actions:
    - text: "Quick Start Guide"
      link: /humanoid-sec-platform/en/quick-start/
      icon: right-arrow
      variant: primary
    - text: "System Architecture"
      link: /humanoid-sec-platform/en/architecture/
      icon: open-book
      variant: secondary
    - text: "Archify Diagrams"
      link: /humanoid-sec-platform/en/diagrams/
      icon: external
      variant: minimal
---

> **QEMU-based security verification & hardening platform for NVIDIA Jetson humanoid robots (L4T, OP-TEE, fTPM, dm-verity/IMA, PKCS#11 HSM, and Secure World mTLS).**

[![CI Security Verification](https://github.com/auking45/humanoid-sec-platform/actions/workflows/ci_security_verify.yml/badge.svg)](https://github.com/auking45/humanoid-sec-platform/actions/workflows/ci_security_verify.yml)
[![Deploy Documentation](https://github.com/auking45/humanoid-sec-platform/actions/workflows/deploy_docs.yml/badge.svg)](https://github.com/auking45/humanoid-sec-platform/actions/workflows/deploy_docs.yml)
[![Documentation Portal](https://img.shields.io/badge/Docs-Starlight%20Portal-00f0ff.svg)](https://auking45.github.io/humanoid-sec-platform/en/)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://github.com/auking45/humanoid-sec-platform/blob/main/LICENSE)
[![Dev Container](https://img.shields.io/badge/Dev%20Container-Ready-green?logo=visualstudiocode)](https://github.com/auking45/humanoid-sec-platform/blob/main/.devcontainer/devcontainer.json)

🌐 **[한국어 문서 (Korean Documentation)](/humanoid-sec-platform/)** | **[Official Documentation Portal](https://auking45.github.io/humanoid-sec-platform/en/)**

---

## 1. Overview

- **Background**: Next-generation humanoid robots operate in close proximity to humans while powered by high-performance autonomous computing platforms (e.g., NVIDIA Jetson AGX Orin/Thor). A robust **Defense-in-Depth** security architecture is mandatory to mitigate physical tampering, supply-chain contamination, and unauthorized control injection.
- **Platform Objective**: Provide a containerized QEMU `aarch64` (`virt` machine) security verification platform that emulates the complete NVIDIA JetPack (L4T) security stack with zero physical board dependency.

---

## 2. Key Architecture & Features

[![Humanoid Security Platform Architecture](/humanoid-sec-platform/diagrams/system_architecture.svg)](/humanoid-sec-platform/diagrams/system_architecture.html)
> 💡 *Click the diagram to open the [Archify Interactive Viewer (HTML)](/humanoid-sec-platform/diagrams/system_architecture.html) with dark/light theme switching, path tracing, component focus, and vector export.*

- **Official L4T Release Integration**:
  - Built upon NVIDIA JetPack 7.2.1 (Jetson Linux R39.2.1, Linux Kernel 6.8, Ubuntu 24.04 Noble, Jetson Thor & Orin) official Kernel, OP-TEE, and sample root filesystem.
- **Dual-Target Kernel Configuration Strategy**:
  - Three-tier configuration system: `[L4T Base defconfig]` + `[security_hardening.config]` + `[qemu_compat.config]` guaranteeing 100% security policy alignment between QEMU and physical Jetson hardware.
- **OP-TEE fTPM & PKCS#11 Trusted Applications**:
  - Houses Microsoft Reference (`ms-tpm-20-ref`) fTPM TA and OP-TEE `pkcs11` TA backed by virtual eMMC RPMB replay-protected storage.
- **Storage & Runtime Integrity (EROFS + dm-verity + IMA)**:
  - Immutable read-only `EROFS` rootfs verified by cryptographic `dm-verity` Merkle hash tree.
  - Linux `IMA` measures executed binaries into fTPM PCR 10 for tamper-proof remote attestation.
- **Zero Plaintext Key Policy & SoftHSMv2**:
  - Zero private keys (`.pem`, `.key`) committed to source code or git history.
  - Offline signing keys generated inside SoftHSMv2 (PKCS#11) tokens and referenced solely via RFC 7512 `pkcs11:` URIs.
- **Secure World Cloud-Humanoid mTLS**:
  - Robot identity private keys sealed within OP-TEE Secure World SRAM (non-extractable).
  - OpenSSL 3.x Provider transparently delegates TLS 1.3 handshake cryptographic signatures to Secure World.

---

## 3. Quick Start

### 3.1. Prerequisites
- Docker 24.0+ & Docker Compose v2.x
- VS Code & [Dev Containers Extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) (Recommended)

### 3.2. Launch with VS Code Dev Container (Recommended)
1. Open this repository in VS Code.
2. Press `F1` and select `Dev Containers: Reopen in Container`.
3. Toolchain automatically initialized inside container:
   - `aarch64-linux-gnu-gcc` cross-compiler
   - QEMU `aarch64` emulator (`virt` machine with RPMB emulation)
   - SoftHSMv2, `tpm2-tools`, `erofs-utils`, `ccache` (20GB persistent cache volume)

### 3.3. Unified Master CLI (`./humanoid.sh`) One-Click Execution
- From a fresh `git clone`, `./humanoid.sh` orchestrates the entire lifecycle from scratch: **HSM Key Provisioning → L4T Source Fetch → TF-A/OP-TEE/Kernel/EROFS Build → Secure Boot Signing → QEMU Boot Verification → 52 Automated Tests & 5 Red/Blue Team Attack Scenarios**.

```bash
# 1. One-click end-to-end setup, build, boot verification & attack test from scratch (Minimal profile)
./humanoid.sh all --minimal

# 2. Full L4T R39.2.1 Ubuntu 24.04 LTS (dm-verity + OverlayFS) build & E2E verification
./humanoid.sh all --ubuntu

# 3. Launch interactive QEMU security shell (Ubuntu 24.04 LTS or Minimal profile)
./humanoid.sh run --ubuntu
./humanoid.sh run --minimal

# 4. Run full 52-test verification suite and Red/Blue Team 5 attack simulations
./humanoid.sh verify
./humanoid.sh attack

# 5. Inspect build artifacts, HSM token keys, and SoC eFuse status
./humanoid.sh status
```

---

## 4. Directory Layout

```text
.
├── AGENTS.md                       # AI Agent instructions, architecture summary & writing rules
├── README.md                       # Project introduction & architecture overview (Korean)
├── .gitignore                      # Cache, build artifacts, and private key exclusions
├── .devcontainer/                  # VS Code Dev Container configuration
├── docker/                         # Cross-toolchain Dockerfile & Compose definitions
├── docs/                           # Architecture, requirements, threat models & checklists (Korean)
│   ├── en/                         # English documentation
│   └── diagrams/                   # Archify validated diagrams (JSON-IR, HTML, SVG)
├── starlight/                      # Astro Starlight technical documentation portal
├── tools/
│   └── archify/                    # Archify CLI renderer & SVG extraction tool
├── scripts/                        # Fetch, build, and QEMU execution wrappers
├── configs/                        # Kernel & OP-TEE configuration fragments
├── keys_hsm/                       # SoftHSMv2 setup & PKCS#11 signing utilities
├── apps/                           # mTLS client & Attestation agent sources
└── tests/                          # Automated pytest verification suites on QEMU
```

---

## 5. Documentation Links

| Document | Korean (국문) | English (영문) |
| :--- | :--- | :--- |
| **Master Roadmap Checklist** | [roadmap_checklist.md](/humanoid-sec-platform/roadmap-checklist/) | [roadmap_checklist.md](/humanoid-sec-platform/en/roadmap-checklist/) |
| **E2E Verification & Attack Lab** | [e2e_verification_guide.md](../e2e_verification_guide.md) | [e2e_verification_guide.md](e2e_verification_guide.md) |
| **Security Requirements (SRD)** | [requirements.md](/humanoid-sec-platform/requirements/) | [requirements.md](/humanoid-sec-platform/en/requirements/) |
| **System Architecture** | [architecture.md](/humanoid-sec-platform/architecture/) | [architecture.md](/humanoid-sec-platform/en/architecture/) |
| **Key Management & HSM / mTLS** | [key_management_hsm.md](/humanoid-sec-platform/key-management-hsm/) | [key_management_hsm.md](/humanoid-sec-platform/en/key-management-hsm/) |
| **Threat Modeling (STRIDE)** | [threat_model.md](/humanoid-sec-platform/threat-model/) | [threat_model.md](/humanoid-sec-platform/en/threat-model/) |
| **Archify Diagrams Collection** | [Archify Diagrams](/humanoid-sec-platform/en/diagrams/) | [Archify Diagrams](/humanoid-sec-platform/en/diagrams/) |

---

## 6. License

Distributed under the [Apache-2.0 License](https://github.com/auking45/humanoid-sec-platform/blob/main/LICENSE).