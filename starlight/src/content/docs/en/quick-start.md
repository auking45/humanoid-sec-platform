---
title: "Quick Start Guide"
description: "Setup guide for development and QEMU emulation via VS Code Dev Container & host CLI wrapper"
---

## 1. Prerequisites

- **Docker 24.0+** & **Docker Compose v2.x**
- **VS Code** with [Dev Containers Extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) (Recommended)
- Minimum 50GB free disk space (for L4T sources, ccache, and build cache)

---

## 2. Getting Started with VS Code Dev Container

1. Open this repository in VS Code.
2. Press `F1` and select `Dev Containers: Reopen in Container`.
3. Once built and launched, the complete toolchain is ready:
   - `aarch64-linux-gnu-gcc` cross-compiler
   - QEMU `aarch64` emulator (`qemu-system-aarch64`)
   - SoftHSMv2 PKCS#11 crypto token
   - `tpm2-tools` & `erofs-utils`
   - `ccache` acceleration (isolated 20GB cache volume)

---

## 3. Host Terminal Execution (`scripts/env_container.sh`)

Run containerized build and test commands directly from host CLI without VS Code:

```bash
# 1. Build container image
./scripts/env_container.sh build

# 2. Open interactive bash shell
./scripts/env_container.sh bash

# 3. Download sources & launch QEMU (Phase 2+)
./scripts/env_container.sh ./scripts/fetch_l4t_sources.sh
./scripts/env_container.sh ./scripts/run_qemu.sh
```

---

## 4. Build Volume Cache Configuration

Data is preserved across container rebuilds via dedicated Docker volumes:

| Host Docker Volume | Container Mount Path | Purpose |
| :--- | :--- | :--- |
| `humanoid_cache_downloads` | `/workspace/.cache/downloads` | NVIDIA official archive tarballs |
| `humanoid_cache_sources` | `/workspace/sources` | Extracted L4T source tree |
| `humanoid_cache_ccache` | `/workspace/.cache/ccache` | 20GB cross-compilation cache |
| `humanoid_cache_softhsm` | `/workspace/.cache/softhsm` | SoftHSMv2 PKCS#11 token database |
