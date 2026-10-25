# Humanoid Security Platform — Master Roadmap & Execution Checklist

> **Single Source of Truth (SSOT)**: This document is the master checklist tracking the overall execution plan, phased detailed tasks, and verification status of the project. As each task completes, the corresponding checkbox `[x]` and verification results are recorded.

---

## 📊 Progress Overview

| Phase | Phase Name | Scope & Objectives | Status |
| :--- | :--- | :--- | :---: |
| **Phase 0** | Overall Architecture & Detailed Design | SRD requirements, architecture, key management, threat model, master checklist | 🟢 Completed |
| **Phase 1** | DevContainer & Docker Environment | VS Code Dev Container, Dockerfile, docker-compose, env wrapper | 🟢 Completed |
| **Phase 2** | L4T Source Fetch & QEMU Baseline Boot | L4T R36.x download, TF-A + OP-TEE + L4T kernel QEMU boot | 🟢 Completed |
| **Phase 3** | OP-TEE fTPM & PKCS#11 TA Integration | ms-tpm-20-ref fTPM TA, pkcs11 TA, QEMU RPMB storage integration | 🟡 Up Next |
| **Phase 4** | SoftHSMv2 Key Management Pipeline | SoftHSM token initialization, zero-plaintext key generation, PKCS#11 sign helper | ⚪ Pending |
| **Phase 5** | Kernel Hardening & Storage/Runtime Integrity | KSPP kernel hardening, EROFS + dm-verity, IMA fTPM PCR extension | ⚪ Pending |
| **Phase 6** | Secure World mTLS & Remote Attestation | OP-TEE PKCS#11/fTPM mTLS client, Remote Attestation agent | ⚪ Pending |

---

## 🛠 Detailed Checklist

### Phase 0: Overall Architecture & Detailed Design Documentation
- [x] **0.1. Repository Baseline Setup**
  - [x] Write `.gitignore` (cache, build artifacts, plaintext key exclusion rules)
  - [x] Write `README.md` (project introduction, architecture overview, quickstart)
  - [x] Write `AGENTS.md` (golden rules, atomic commits, DevContainer-First principle)
- [x] **0.2. Master Checklist & Requirements Specification**
  - [x] Write `docs/roadmap_checklist.md` master checklist
  - [x] Write `docs/requirements.md` (SRD: numbering scheme, security requirements, verification criteria)
- [x] **0.3. Architecture & Detailed Design Documentation**
  - [x] Write `docs/architecture.md` (boot chain, Trust Boundary, Dual-Target kernel, integrity pipeline)
  - [x] Write `docs/key_management_hsm.md` (SoftHSMv2 offline signing, OP-TEE runtime keys, mTLS sequence)
  - [x] Write `docs/threat_model.md` (humanoid robot STRIDE threat model & control mapping)
- [x] **0.4. Archify-Based Interactive Diagrams (`docs/diagrams/`)**
  - [x] `system_architecture.html` / `*.svg` (QEMU, TrustZone, Normal World, Cloud architecture)
  - [x] `secure_boot_sequence.html` / `*.svg` (BootROM -> TF-A -> OP-TEE -> Kernel -> dm-verity sequence)
  - [x] `key_hierarchy.html` / `*.svg` (SoftHSMv2 Tier 1, Secure World Tier 2, Public Certificates Tier 3)
  - [x] `secure_mtls_sequence.html` / `*.svg` (OpenSSL 3.x Provider + OP-TEE PKCS#11 TA mTLS handshake)
  - [x] `storage_integrity_pipeline.html` / `*.svg` (EROFS + dm-verity + IMA PCR 10 pipeline)
  - [x] `threat_model_stride.html` / `*.svg` (Attack surface -> STRIDE threats -> Security controls -> SRD mapping)
  - [x] `tools/archify/scripts/extract_svg.py` (Self-contained SVG extractor with embedded fonts and styling)
- [x] **0.5. Astro Starlight Technical Documentation Portal & GitHub Pages Pipeline (`starlight/`)**
  - [x] Apply Cyberpunk Neon theme (`starlight/src/styles/custom.css` - Pretendard/JetBrains Mono, neon palette)
  - [x] Implement automated documentation & asset sync tool (`scripts/sync_docs_to_starlight.py`)
  - [x] Configure GitHub Actions automated build and deploy workflow (`.github/workflows/deploy_docs.yml`)
  - [x] Configure Pagefind local full-text search & Archify diagram gallery (`diagrams.md`)

---

### Phase 1: Dev Container & Docker CI/CD Build Environment
- [x] **1.1. Container Build Environment Configuration**
  - [x] Write `docker/Dockerfile` (Ubuntu 22.04 base, aarch64 cross-toolchain, QEMU 8.x+, SoftHSMv2, tpm2-tools, erofs-utils, ccache)
  - [x] Write `docker/docker-compose.yml` (cache volume mounts: `.cache/downloads`, `sources/`, `.cache/ccache`, `build/`, `.cache/softhsm`)
  - [x] Write `docker/entrypoint.sh` (user permission mapping, ccache initialization, SoftHSM token directory permissions)
- [x] **1.2. VS Code Dev Container Integration**
  - [x] Configure `.devcontainer/devcontainer.json` (docker-compose integration, C/C++, Python, Docker extensions)
- [x] **1.3. Host CLI Wrapper Script**
  - [x] Implement `scripts/env_container.sh` (run build/test commands inside container directly from host CLI)
- [x] **1.4. Container Environment Verification**
  - [x] Verify Dockerfile, compose yaml, json syntax, entrypoint, and script execution permissions

---

### Phase 2: NVIDIA L4T Official Source Fetch & QEMU Baseline Boot
- [x] **2.1. L4T Official Archive Source Download Automation**
  - [x] Write `scripts/fetch_l4t_sources.sh` (download NVIDIA L4T R36.x / JetPack 6.x BSP, Public Sources, Rootfs and verify SHA256)
  - [x] Implement cache verification logic (skip re-downloading if tarball already exists)
- [x] **2.2. Dual-Target Kernel Configuration System**
  - [x] `configs/kernel/qemu_compat.config` (VirtIO, PL011, GICv3 drivers for QEMU `virt` machine)
  - [x] `scripts/build_kernel.sh` (merge L4T default defconfig + qemu_compat.config and cross-compile)
- [x] **2.3. TF-A & OP-TEE Build Pipeline**
  - [x] `scripts/build_tfa_optee.sh` (build TF-A BL31 + OP-TEE Core for QEMU aarch64 target)
- [x] **2.4. QEMU Baseline Boot Script & Verification**
  - [x] `scripts/run_qemu.sh` (boot QEMU `virt`, `secure=on`, TF-A + OP-TEE + L4T kernel + minimal initramfs)
  - [x] `tests/test_boot_optee.py` (automated test for OP-TEE boot messages and `tee-supplicant` baseline operation)

---

### Phase 3: OP-TEE fTPM TA & PKCS#11 TA Integration
- [ ] **3.1. fTPM TA Build & OP-TEE Integration**
  - [ ] Integrate Microsoft Reference Implementation (`ms-tpm-20-ref`) fTPM TA
  - [ ] Embed as Early TA or Static TA to activate TPM2 immediately upon boot
- [ ] **3.2. QEMU RPMB Virtual Secure Storage Integration**
  - [ ] Configure QEMU RPMB socket emulation and link with OP-TEE Secure Storage
  - [ ] Verify NVRAM state persistence across reboots
- [ ] **3.3. Linux Kernel fTPM Driver Activation & Verification**
  - [ ] Enable kernel configuration `CONFIG_TCG_FTPM_TEE=y`
  - [ ] Verify creation of `/dev/tpmrm0` and `/dev/tpm0` device nodes post-boot
  - [ ] Test `tpm2_getcap`, `tpm2_pcrread` functionality
- [ ] **3.4. OP-TEE PKCS#11 TA Activation**
  - [ ] Configure `CFG_PKCS11_TA=y` and link Linux userspace `libckteec.so`
  - [ ] Verify token slot recognition with `pkcs11-tool --module /usr/lib/libckteec.so -L`

---

### Phase 4: SoftHSMv2-Based Offline Key Management Pipeline
- [ ] **4.1. SoftHSMv2 Token Initialization Script**
  - [ ] Write `keys_hsm/setup_softhsm.sh`
  - [ ] Generate Secure Boot / Kernel Module Signing Key (RSA 3072 / ECDSA P-384)
  - [ ] Generate dm-verity Root Hash signing key
  - [ ] Generate IMA file signing key
- [ ] **4.2. PKCS#11 URI Signing Helper Implementation**
  - [ ] Write `keys_hsm/sign_helper.sh` (zero-plaintext signing pipeline using OpenSSL engine/provider pkcs11)
  - [ ] Integrate kernel module (`.ko`), dm-verity roothash, and IMA xattr signing
- [ ] **4.3. Zero Plaintext Key Audit**
  - [ ] Configure pre-commit / CI script to ensure no plaintext private keys exist in the git tree

---

### Phase 5: Kernel Hardening & EROFS + dm-verity + IMA Integrity Verification
- [ ] **5.1. Apply Kernel Hardening Configuration**
  - [ ] Write `configs/kernel/security_hardening.config` (KSPP recommendations: module signature enforcement, stack protector, ASLR, restricted memory access)
- [ ] **5.2. EROFS + dm-verity Immutable Rootfs Build**
  - [ ] Write `scripts/build_rootfs.sh` (generate EROFS compressed image from L4T Sample Rootfs)
  - [ ] Generate hash tree with `veritysetup`, sign Root Hash with SoftHSM key
  - [ ] Verify dm-verity integrity from kernel command-line or Initramfs before mounting
- [ ] **5.3. IMA (Integrity Measurement Architecture) & fTPM PCR Extension**
  - [ ] Configure IMA policy (`ima_policy=tcb`, measuring executables and modules)
  - [ ] Verify automatic extension of IMA measurements into fTPM PCR 10
- [ ] **5.4. Integration Verification Tests**
  - [ ] Write and automate `tests/test_ftpm_ima.py` (block tampered file execution and verify PCR measurement records)

---

### Phase 6: Secure World-Based Cloud-Humanoid mTLS & Remote Attestation
- [ ] **6.1. Secure World Key Generation & Storage**
  - [ ] Dynamically generate robot authentication private key inside OP-TEE PKCS#11 TA or fTPM
  - [ ] Verify private keys are never exposed to Normal World filesystem
- [ ] **6.2. OpenSSL 3.x Provider-Linked mTLS Client Implementation**
  - [ ] Implement `apps/mtls_client/` (C / Python client integrated with OpenSSL 3.x `pkcs11-provider` or `tpm2-openssl`)
  - [ ] Verify mutual TLS (mTLS) handshake with Cloud server via in-Secure-World signing operations
- [ ] **6.3. Remote Attestation Agent Implementation**
  - [ ] Implement `apps/attestation_agent/` (generate fTPM Quote + AK signature + package IMA Event Log)
  - [ ] Submit to Verifier service to remotely validate boot integrity and system state
- [ ] **6.4. CI/CD End-to-End Automation Pipeline**
  - [ ] Complete `.github/workflows/ci_security_verify.yml`
  - [ ] Confirm full Phase 2~6 automated security test suite (pytest) passes under headless QEMU

---

## 📝 Changelog

- **2026-10-25**:
  - Phase 0 completed: baseline repo setup (`.gitignore`, `README.md`, `AGENTS.md`) and master design documents completed (`roadmap_checklist.md`, `requirements.md`, `architecture.md`, `key_management_hsm.md`, `threat_model.md`).
  - Archify transition: all diagrams generated as validated interactive HTML artifacts (`docs/diagrams/*.html`) and standalone high-resolution SVGs (`docs/diagrams/*.svg`) embedded into documents.
  - Starlight documentation portal: Astro Starlight portal (`starlight/`) with Cyberpunk Neon theme matching `linux-kernel-hardening-lab` and GitHub Pages auto-deploy CI (`.github/workflows/deploy_docs.yml`) configured.
  - Phase 1 completed: VS Code Dev Container & Docker build/cache environment established (`docker/Dockerfile`, `docker/docker-compose.yml`, `docker/entrypoint.sh`, `.devcontainer/devcontainer.json`, `scripts/env_container.sh`).
  - Phase 2 completed: NVIDIA L4T official source fetcher (`scripts/fetch_l4t_sources.sh`), Dual-Target kernel configuration & build pipeline (`configs/kernel/`, `scripts/build_kernel.sh`), TF-A & OP-TEE build pipeline (`configs/optee/`, `scripts/build_tfa_optee.sh`), QEMU secure runner (`scripts/run_qemu.sh`), and automated verification test suite (`tests/test_boot_optee.py`) established.

