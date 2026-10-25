# Security Requirements Document (SRD)

> **Document ID**: `SRD-HSEC-2026-V1`  
> **Target Platform**: NVIDIA Jetson Humanoid Platform (QEMU aarch64 virt verification & L4T 6.x)  
> **Status**: Approved / Baseline

---

## 1. Overview

- **Document Purpose**: System Security Requirements Document (SRD) defining comprehensive security controls for humanoid robot controllers.
- **Scope**: Lifecycle coverage from hardware Root of Trust (RoT) to OS hardening, runtime verification, key management, and cloud mTLS.

### Requirement Identifier (ID) Conventions
- `SRD-BOOT-xxx`: Boot chain and Chain of Trust requirements
- `SRD-KERN-xxx`: Kernel hardening and isolation requirements
- `SRD-TEE-xxx`: ARM TrustZone, OP-TEE, and fTPM requirements
- `SRD-STOR-xxx`: Storage integrity and immutable filesystem requirements
- `SRD-MEAS-xxx`: Runtime measurement (IMA) and Remote Attestation requirements
- `SRD-HSM-xxx`: Key hierarchy, HSM (SoftHSMv2), and Zero-Plaintext requirements
- `SRD-COMM-xxx`: Secure World client mTLS communication requirements
- `SRD-ENV-xxx`: DevContainer and CI/CD reproducible environment requirements

---

## 2. Detailed Security Requirements

### 2.1. Boot Chain & Secure Boot (`SRD-BOOT`)

| ID | Title | Priority | Specification | Acceptance Criteria | Test Target |
| :--- | :--- | :---: | :--- | :--- | :--- |
| **SRD-BOOT-001** | Root of Trust Verification Chain | **MUST** | Sequential cryptographic signature validation from immutable BootROM to TF-A, OP-TEE, and Linux kernel. | Boot instantly halts upon unverified or tampered binary load. | `tests/test_boot_optee.py` |
| **SRD-BOOT-002** | Secure World / Normal World Isolation | **MUST** | Hardware memory and register isolation via ARM TrustZone (EL3, S-EL1 vs NS-EL1). | Direct access from Normal World into TrustZone DRAM triggers SError/Abort. | `tests/test_boot_optee.py` |
| **SRD-BOOT-003** | Anti-Rollback Protection | **SHOULD** | Monotonic counters or security versions verify firmware to prevent downgrade attacks. | Flashing lower security version is rejected at loader stage. | Simulation test |

---

### 2.2. Kernel Hardening (`SRD-KERN`)

| ID | Title | Priority | Specification | Acceptance Criteria | Test Target |
| :--- | :--- | :---: | :--- | :--- | :--- |
| **SRD-KERN-001** | KSPP Defense Baseline | **MUST** | Enforces KASLR, stack protection (`CONFIG_STACKPROTECTOR_STRONG`), and strict W^X executable memory. | Kernel `.config` validated and runtime `/sys/kernel/security` checked. | `tests/test_boot_optee.py` |
| **SRD-KERN-002** | Mandatory Kernel Module Signing | **MUST** | All dynamically loaded `.ko` modules must be cryptographically signed (`CONFIG_MODULE_SIG_FORCE=y`). | Loading unsigned module fails with `-EKEYREJECTED`. | `tests/test_boot_optee.py` |
| **SRD-KERN-003** | Dual-Target Compatibility | **MUST** | Shared base security baseline (`security_hardening.config`) between physical Jetson and QEMU. | `merge_config.sh` produces identical security policy for board and emulator. | Build check |

---

### 2.3. ARM TrustZone & OP-TEE / fTPM (`SRD-TEE`)

| ID | Title | Priority | Specification | Acceptance Criteria | Test Target |
| :--- | :--- | :---: | :--- | :--- | :--- |
| **SRD-TEE-001** | OP-TEE OS Integration | **MUST** | Executes OP-TEE in S-EL1, exposing standard TEE SMC interfaces to Linux. | `/dev/tee0` recognized and `tee-supplicant` daemon runs cleanly. | `tests/test_boot_optee.py` |
| **SRD-TEE-002** | fTPM 2.0 TA Implementation | **MUST** | Operates Microsoft Reference (`ms-tpm-20-ref`) fTPM TA, exposing `/dev/tpmrm0` to Linux. | `/dev/tpmrm0` created and `tpm2_getcap` query succeeds. | `tests/test_ftpm_ima.py` |
| **SRD-TEE-003** | Virtual RPMB Persistent Storage | **MUST** | Encrypted NVRAM and secure storage states persist across reboots via virtual eMMC RPMB partition. | fTPM NV indices and PCR values preserved across QEMU reboots. | `tests/test_ftpm_ima.py` |
| **SRD-TEE-004** | OP-TEE PKCS#11 TA Support | **MUST** | Integrates `CFG_PKCS11_TA=y` for hardware-isolated cryptographic operations and `libckteec.so` client. | `pkcs11-tool --module /usr/lib/libckteec.so -L` lists token slots. | `tests/test_boot_optee.py` |

---

### 2.4. Storage Integrity & Immutable Filesystem (`SRD-STOR`)

| ID | Title | Priority | Specification | Acceptance Criteria | Test Target |
| :--- | :--- | :---: | :--- | :--- | :--- |
| **SRD-STOR-001** | Read-Only EROFS Rootfs | **MUST** | Read-only compressed EROFS root filesystem prevents runtime file tampering. | Root partition mounted read-only; arbitrary write attempts denied. | `tests/test_ftpm_ima.py` |
| **SRD-STOR-002** | dm-verity Block Integrity | **MUST** | Cryptographic hash tree verifies 4KB block integrity on demand upon each read access. | Modifying single disk byte causes immediate kernel I/O error and block denial. | `tests/test_ftpm_ima.py` |
| **SRD-STOR-003** | Root Hash Cryptographic Signing | **MUST** | Merkle tree Root Hash signed offline; Initramfs verifies signature against built-in X.509 cert. | Invalid root hash or signature causes immediate kernel panic / boot halt. | `tests/test_ftpm_ima.py` |

---

### 2.5. Runtime Measurement & Remote Attestation (`SRD-MEAS`)

| ID | Title | Priority | Specification | Acceptance Criteria | Test Target |
| :--- | :--- | :---: | :--- | :--- | :--- |
| **SRD-MEAS-001** | Kernel IMA Subsystem | **MUST** | Measures executable binaries and dynamic libraries into fTPM PCR 10 upon execution. | Execution logs recorded in `/sys/kernel/security/ima/` and PCR 10 extends. | `tests/test_ftpm_ima.py` |
| **SRD-MEAS-002** | Remote Attestation Packaging | **MUST** | Collects fTPM AK quotes and IMA logs into signed reports for remote verifier validation. | Quote generated by `apps/attestation_agent` validates on remote verifier. | `tests/test_secure_mtls.py` |

---

### 2.6. Key Management & HSM (`SRD-HSM`)

| ID | Title | Priority | Specification | Acceptance Criteria | Test Target |
| :--- | :--- | :---: | :--- | :--- | :--- |
| **SRD-HSM-001** | Zero-Plaintext Key Policy | **MUST** | Strict prohibition of plaintext private keys (`.pem`, `.key`) in repository commits. | Git history checks and CI security audit passes. | CI pipeline |
| **SRD-HSM-002** | SoftHSMv2 PKCS#11 Build Pipeline | **MUST** | Build and release signing keys generated in SoftHSMv2 and accessed via RFC 7512 URIs. | Token key creation and `pkcs11:` URI signing verified. | `keys_hsm/setup_softhsm.sh` |
| **SRD-HSM-003** | Transparent Hardware HSM Migration | **SHOULD** | Follows PKCS#11 standard, enabling physical HSM migration via environment variables. | Replacing module path and URI preserves full signing toolchain compatibility. | Unit test |

---

### 2.7. Secure World Communication (`SRD-COMM`)

| ID | Title | Priority | Specification | Acceptance Criteria | Test Target |
| :--- | :--- | :---: | :--- | :--- | :--- |
| **SRD-COMM-001** | Isolated Client Private Key | **MUST** | Robot mTLS client private key never stored on Normal World disk; sealed in OP-TEE TA. | No client private key file present in Linux filesystem. | `tests/test_secure_mtls.py` |
| **SRD-COMM-002** | OpenSSL 3.x Provider Integration | **MUST** | mTLS client utilizes `pkcs11-provider` to delegate TLS handshake signatures to Secure World. | TLS 1.3 mTLS connection succeeds with Secure SRAM signing delegation. | `tests/test_secure_mtls.py` |

---

### 2.8. Build & Verification Environment (`SRD-ENV`)

| ID | Title | Priority | Specification | Acceptance Criteria | Test Target |
| :--- | :--- | :---: | :--- | :--- | :--- |
| **SRD-ENV-001** | Unified DevContainer & CI | **MUST** | Shared Dockerfile and Compose setup between local development and CI pipelines. | 100% reproducible build results between local container and GitHub Actions. | DevContainer & CI |
| **SRD-ENV-002** | Persistent Volume Caching | **MUST** | Sources, downloads, ccache, and SoftHSM tokens preserved on host volumes. | Host volume mounts verified; 2nd-run builds show immediate cache hits. | Build check |

