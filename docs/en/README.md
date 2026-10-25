# Humanoid Security Platform (`humanoid-sec-platform`)

> **QEMU-based security verification & hardening platform for NVIDIA Jetson humanoid robots (L4T, OP-TEE, fTPM, dm-verity/IMA, PKCS#11 HSM, and Secure World mTLS).**

[![CI Security Verification](https://github.com/auking45/humanoid-sec-platform/actions/workflows/ci_security_verify.yml/badge.svg)](https://github.com/auking45/humanoid-sec-platform/actions/workflows/ci_security_verify.yml)
[![Deploy Documentation](https://github.com/auking45/humanoid-sec-platform/actions/workflows/deploy_docs.yml/badge.svg)](https://github.com/auking45/humanoid-sec-platform/actions/workflows/deploy_docs.yml)
[![Documentation Portal](https://img.shields.io/badge/Docs-Starlight%20Portal-00f0ff.svg)](https://auking45.github.io/humanoid-sec-platform/en/)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![Dev Container](https://img.shields.io/badge/Dev%20Container-Ready-green?logo=visualstudiocode)](.devcontainer/devcontainer.json)

🌐 **[한국어 문서 (Korean Documentation)](../../README.md)** | **[Official Documentation Portal](https://auking45.github.io/humanoid-sec-platform/en/)**

---

## 1. Overview

- **Background**: Next-generation humanoid robots operate in close proximity to humans while powered by high-performance autonomous computing platforms (e.g., NVIDIA Jetson AGX Orin/Thor). A robust **Defense-in-Depth** security architecture is mandatory to mitigate physical tampering, supply-chain contamination, and unauthorized control injection.
- **Platform Objective**: Provide a containerized QEMU `aarch64` (`virt` machine) security verification platform that emulates the complete NVIDIA JetPack (L4T) security stack with zero physical board dependency.

---

## 2. Key Architecture & Features

[![Humanoid Security Platform Architecture](../diagrams/system_architecture.svg)](../diagrams/system_architecture.html)
> 💡 *Click the diagram to open the [Archify Interactive Viewer (HTML)](../diagrams/system_architecture.html) with dark/light theme switching, path tracing, component focus, and vector export.*

- **Official L4T Release Integration**:
  - Built upon NVIDIA JetPack 6.x (L4T R36.x) official Kernel, OP-TEE, and sample root filesystem.
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

### 3.3. Run from Host Terminal
```bash
# Execute build and test commands via container wrapper
./scripts/env_container.sh make help
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
| **Master Roadmap Checklist** | [roadmap_checklist.md](../roadmap_checklist.md) | [roadmap_checklist.md](roadmap_checklist.md) |
| **Security Requirements (SRD)** | [requirements.md](../requirements.md) | [requirements.md](requirements.md) |
| **System Architecture** | [architecture.md](../architecture.md) | [architecture.md](architecture.md) |
| **Key Management & HSM / mTLS** | [key_management_hsm.md](../key_management_hsm.md) | [key_management_hsm.md](key_management_hsm.md) |
| **Threat Modeling (STRIDE)** | [threat_model.md](../threat_model.md) | [threat_model.md](threat_model.md) |
| **Archify Diagrams Collection** | [docs/diagrams/](../diagrams/) | [docs/diagrams/](../diagrams/) |

---

## 6. License

Distributed under the [Apache-2.0 License](../../LICENSE).
