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
  - [x] Write `scripts/fetch_l4t_sources.sh` (download NVIDIA JetPack 7.2.1 / Jetson Linux R39.2.1 BSP, Public Sources, Rootfs and verify cache)
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
- [x] **3.1. fTPM TA Build & OP-TEE Integration**
  - [x] Microsoft Reference Implementation (`ms-tpm-20-ref`) fTPM TA integration completed (`bc50d971-d4c9-42c4-82cb-343fb7f37896.ta`)
  - [x] Embedded as Early TA inside OP-TEE Core (`tee-pager_v2.bin`) ensuring immediate TPM2 availability at early boot
- [x] **3.2. QEMU RPMB Virtual Secure Storage Integration**
  - [x] OP-TEE RPMB filesystem (`CFG_RPMB_FS=y`) build and `tee-supplicant` integration support configured
  - [x] Automated launch of `tee-supplicant` daemon in initramfs for RPMB secure storage servicing
- [x] **3.3. Linux Kernel fTPM Driver Activation & Verification**
  - [x] Hardened kernel configuration `CONFIG_TCG_FTPM_TEE=y`, `CONFIG_TCG_TPM=y` enabled and local compilation verified
  - [x] Device node recognition (`/dev/tpmrm0`, `/dev/tpm0`) and automated test suite validation completed
- [x] **3.4. OP-TEE PKCS#11 TA Activation**
  - [x] `CFG_PKCS11_TA=y` configuration and Cryptoki TA (`fd02c9da-306c-48c7-a49c-bbd827ae86ee.ta`) built
  - [x] Linux userspace client libraries (`libteec.so`, `libckteec.so`) cross-compiled and bundled into minimal verification initramfs

---

### Phase 4: SoftHSMv2-Based Offline Key Management Pipeline
- [x] **4.1. SoftHSMv2 Token Initialization Script**
  - [x] Write `keys_hsm/setup_softhsm.sh` (initializes token `HumanoidSecToken`)
  - [x] Generate Kernel Module Signing Key (RSA 3072, ID: 01) and DmVeritySigningKey (RSA 3072, ID: 02)
  - [x] Generate IMA file signing key (ECDSA P-384, ID: 03) and Device Enrollment CA Key (ECDSA P-256, ID: 04)
  - [x] Enforce never-extractable / sensitive attributes and establish public key / certificate extraction pipeline (`keys_hsm/certs/`)
- [x] **4.2. PKCS#11 URI Signing Helper Implementation**
  - [x] Write `keys_hsm/sign_helper.sh` (RFC 7512 `pkcs11:` URI and in-token C_Sign wrapper)
  - [x] Construct kernel module (`.ko`), dm-verity roothash, and IMA signing and verification (`verify`) pipeline
- [x] **4.3. Zero Plaintext Key Audit**
  - [x] Write `keys_hsm/audit_zero_keys.sh` and pass full CI/local tree zero plaintext key audit (0 plaintext keys on disk)

---

### Phase 5: Kernel Hardening & EROFS + dm-verity + IMA Integrity Verification
- [x] **5.1. Apply Kernel Hardening Configuration**
  - [x] Write `configs/kernel/security_hardening.config` (KSPP recommendations: module signature enforcement, stack protector, ASLR, strict memory protection)
  - [x] Merge fragment into Linux Kernel 6.8 Noble build and verify compilation
- [x] **5.2. EROFS + dm-verity Immutable Rootfs Build**
  - [x] Write `scripts/build_rootfs.sh` (generate immutable EROFS image `rootfs.erofs`)
  - [x] Generate Merkle hash tree (`rootfs.verity`) with `veritysetup` and sign Root Hash with SoftHSM `DmVeritySigningKey` (`verity.roothash.sig`)
  - [x] Self-verify dm-verity baseline integrity and verify immediate tamper-resistance against 1-byte data corruption
- [x] **5.3. IMA (Integrity Measurement Architecture) & fTPM PCR Extension**
  - [x] Configure IMA policy (`/etc/ima/ima-policy`, measuring executables and kernel modules into PCR 10)
  - [x] Enforce IMA PCR 10 extension in kernel configuration (`CONFIG_IMA_MEASURE_PCR_IDX=10`)
  - [x] Integrate SoftHSM `ImaSigningKey` (ECDSA P-384) signing and verification pipeline
- [x] **5.4. Integration Verification Tests**
  - [x] Extend `tests/test_ftpm_ima.py` with Phase 5 storage integrity and IMA test suite (100% pass across all 30 unit tests)

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

- **2026-10-26**:
  - Phase 5 completed: Kernel security hardening and immutable EROFS + dm-verity rootfs build pipeline (`scripts/build_rootfs.sh`), SoftHSM PKCS#11 root hash signing & verification, IMA policy formulation, and automated unit test suite expansion (`tests/test_ftpm_ima.py`, 30/30 unit tests passing 100%).
  - Phase 4 completed: SoftHSMv2 offline key management pipeline (`keys_hsm/setup_softhsm.sh`), RFC 7512 PKCS#11 signing helper (`keys_hsm/sign_helper.sh`), zero-plaintext private key audit tool (`keys_hsm/audit_zero_keys.sh`), and automated unit test suite (`tests/test_hsm_keys.py`) constructed and verified.
  - Phase 3 completed: OP-TEE Core (`vexpress-qemu_armv8a`) embedded with early fTPM TA (`ms-tpm-20-ref`) into `tee-pager_v2.bin`, PKCS#11 TA (`fd02c9da-306c-48c7-a49c-bbd827ae86ee.ta`), userspace client libraries (`libteec.so`, `libckteec.so`), and `tee-supplicant` build pipeline established.
  - Linux Kernel 6.8 Noble hardened build (`CONFIG_TCG_FTPM_TEE=y`, `CONFIG_TEE=y`, `CONFIG_OPTEE=y`, `CONFIG_EROFS_FS=y`, `CONFIG_IMA=y`) compiled locally and signed kernel modules generated.
  - Minimal QEMU ramdisk (`initramfs_minimal.cpio.gz`) automated with `tee-supplicant` and fTPM validation scripts.
  - Automated comprehensive Phase 3 test suite (`tests/test_ftpm_ima.py`) implemented with 100% pass rate (15/15 tests passing).
- **2026-10-25**:
  - Phase 0 completed: baseline repo setup (`.gitignore`, `README.md`, `AGENTS.md`) and master design documents completed (`roadmap_checklist.md`, `requirements.md`, `architecture.md`, `key_management_hsm.md`, `threat_model.md`).
  - Archify transition: all diagrams generated as validated interactive HTML artifacts (`docs/diagrams/*.html`) and standalone high-resolution SVGs (`docs/diagrams/*.svg`) embedded into documents.
  - Starlight documentation portal: Astro Starlight portal (`starlight/`) with Cyberpunk Neon theme matching `linux-kernel-hardening-lab` and GitHub Pages auto-deploy CI (`.github/workflows/deploy_docs.yml`) configured.
  - Phase 1 completed: VS Code Dev Container & Docker build/cache environment established (`docker/Dockerfile`, `docker/docker-compose.yml`, `docker/entrypoint.sh`, `.devcontainer/devcontainer.json`, `scripts/env_container.sh`).
  - Phase 2 completed: NVIDIA L4T official source fetcher (`scripts/fetch_l4t_sources.sh`), Dual-Target kernel configuration & build pipeline (`configs/kernel/`, `scripts/build_kernel.sh`), TF-A & OP-TEE build pipeline (`configs/optee/`, `scripts/build_tfa_optee.sh`), QEMU secure runner (`scripts/run_qemu.sh`), and automated verification test suite (`tests/test_boot_optee.py`) established.

