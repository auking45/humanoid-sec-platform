# System Architecture Specification

> **Target Platform**: NVIDIA Jetson Humanoid Robot Control Architecture (L4T 6.x & QEMU aarch64 virt)  
> **Status**: Approved / Baseline

---

## 1. 아키텍처 개요 및 신뢰 경계 (Trust Boundary)

본 플랫폼은 휴머노이드 로봇의 고신뢰성 제어를 위해 **하드웨어 수준의 신뢰 경계(Hardware Trust Boundary)**를 수립하고, ARMv8/ARMv9 TrustZone 기술을 기반으로 보안 영역(Secure World)과 일반 운영체제 영역(Normal World)을 엄격히 분리합니다.

```mermaid
graph TB
    subgraph "Hardware Security Perimeter (Root of Trust)"
        ROM["BootROM (Immutable QEMU Secure ROM / Jetson Fuse RoT)"]
        RPMB_HW["RPMB Storage (QEMU emulated eMMC RPMB)"]
        CRYPTO_ENG["Hardware Cryptographic Accelerator"]
    end

    subgraph "TrustZone Secure World (TEE)"
        subgraph "EL3 - Secure Monitor"
            TFA["TF-A (BL31 - Secure Monitor & PSCI)"]
        end
        subgraph "S-EL1 - Trusted OS"
            OPTEE_CORE["OP-TEE Core (Kernel & Memory Manager)"]
        end
        subgraph "S-EL0 - Trusted Applications (TAs)"
            FTPM_TA["fTPM TA (ms-tpm-20-ref TPM 2.0 Engine)"]
            PKCS11_TA["PKCS#11 TA (Cryptographic Token & Keys)"]
        end
    end

    subgraph "Normal World (REE - Rich Execution Environment)"
        subgraph "NS-EL1 - Hardened Linux Kernel"
            L4T_KERNEL["Hardened L4T Linux Kernel 6.x<br/>(KSPP / Module Sig / dm-verity / IMA / TEE Driver)"]
            TEE_DRV["TEE Client Driver (/dev/tee0)"]
            FTPM_DRV["TCG fTPM Driver (/dev/tpmrm0)"]
            DM_VERITY["dm-verity Subsystem"]
            IMA_SUB["IMA (Integrity Measurement Architecture)"]
        end

        subgraph "NS-EL0 - User Space"
            TEE_SUPP["tee-supplicant (RPMB & FS Proxy Daemon)"]
            INITRAMFS["Authenticated Initramfs"]
            ROOTFS["Read-Only EROFS Rootfs"]
            MTLS_APP["Humanoid mTLS Client (OpenSSL 3.x Provider)"]
            ATTEST_APP["Remote Attestation Agent (tpm2-tools)"]
            ROBOT_CORE["Robot Control Middleware (ROS 2 / Isaac)"]
        end
    end

    %% Connections
    ROM --> TFA
    TFA --> OPTEE_CORE
    OPTEE_CORE --> FTPM_TA
    OPTEE_CORE --> PKCS11_TA
    OPTEE_CORE <--> RPMB_HW

    TFA --> L4T_KERNEL
    L4T_KERNEL <--> TEE_DRV
    TEE_DRV <--> OPTEE_CORE
    FTPM_DRV <--> FTPM_TA
    TEE_SUPP <--> TEE_DRV

    L4T_KERNEL --> INITRAMFS --> DM_VERITY --> ROOTFS
    IMA_SUB --> FTPM_DRV

    MTLS_APP <--> PKCS11_TA
    ATTEST_APP <--> FTPM_DRV
    ROBOT_CORE --> ROOTFS
```

---

## 2. 보안 부팅 체인 (Secure Boot Chain)

시스템은 변조 불가능한 RoT(Root of Trust)에서 시작하여 각 단계의 펌웨어 및 커널 이미지를 암호학적으로 검증한 후 제어권을 넘깁니다.

```mermaid
sequenceDiagram
    autonumber
    participant ROM as BootROM / Secure ROM (EL3)
    participant TFA as TF-A BL31 (EL3)
    participant OPTEE as OP-TEE (S-EL1)
    participant RPMB as Virtual RPMB (Secure Storage)
    participant KERNEL as L4T Linux Kernel (NS-EL1)
    participant INIT as Initramfs (NS-EL0)
    participant ROOT as EROFS + dm-verity (NS-EL1)

    ROM->>TFA: RSA/ECDSA Signature Verification
    Note over TFA: Initialize GICv3, CPU cores & EL3 vectors
    TFA->>OPTEE: Load & Authenticate OP-TEE Core (BL32)
    OPTEE->>RPMB: Authenticate RPMB key & Mount secure NVRAM
    OPTEE->>OPTEE: Start fTPM TA & PKCS#11 TA
    TFA->>KERNEL: Authenticate & Jump to Linux Kernel (BL33)
    Note over KERNEL: Enforce KSPP hardening & Lock memory mappings
    KERNEL->>INIT: Unpack & execute verified initramfs
    INIT->>ROOT: Read Root Hash & Verify RSA signature via SoftHSM cert
    INIT->>ROOT: Activate dm-verity device-mapper on EROFS
    ROOT-->>KERNEL: Switch root to verified /dev/mapper/root-verity
    Note over KERNEL: Mount /sys, /proc, start tee-supplicant & Robot control
```

---

## 3. Dual-Target 커널 빌드 및 하드닝 아키텍처

실제 로봇 하드웨어(NVIDIA Jetson)와 QEMU 에뮬레이터 간의 보안 정책 괴리를 없애기 위해 **3계층 커널 설정 아키텍처**를 채택합니다.

```text
                                [ NVIDIA L4T Base defconfig ]
                               (tegra_defconfig / 공식 BSP 기준)
                                             │
                                             ▼
                      [ configs/kernel/security_hardening.config ]
                  (KSPP 권고안, 모듈 서명 강제, EROFS, dm-verity, IMA, fTPM)
                                             │
                       ┌─────────────────────┴─────────────────────┐
                       │                                           │
                       ▼                                           ▼
             [ Real Jetson Target ]                      [ QEMU virt Target ]
     (실제 Jetson Orin/Thor 플래시 이미지)          + [ configs/kernel/qemu_compat.config ]
                                              (VirtIO 드라이버, PL011 콘솔, QEMU PCI)
```

### 3.1. 보안 하드닝 핵심 파라미터 (`security_hardening.config`)
- **메모리 보호 및 익스플로잇 차단**:
  - `CONFIG_KASLR=y`: 커널 코드 주소 공간 난수화
  - `CONFIG_STRICT_KERNEL_RWX=y` & `CONFIG_STRICT_MODULE_RWX=y`: 실행 가능 메모리에 쓰기 금지 (W^X)
  - `CONFIG_STACKPROTECTOR_STRONG=y`: 스택 버퍼 오버플로우 탐지
  - `CONFIG_FORTIFY_SOURCE=y`: 버퍼 경계 런타임 검사
  - `CONFIG_SLAB_FREELIST_RANDOM=y` & `CONFIG_SLAB_FREELIST_HARDENED=y`: 힙 공격 완화
- **무결성 강제**:
  - `CONFIG_MODULE_SIG=y` & `CONFIG_MODULE_SIG_FORCE=y`: 미서명 커널 모듈 적재 전면 차단
  - `CONFIG_MODULE_SIG_ALL=y` & `CONFIG_MODULE_SIG_SHA256=y`: 빌드 시 자동 서명
  - `CONFIG_DM_VERITY=y` & `CONFIG_DM_VERITY_VERIFY_ROOTHASH_SIG=y`: 루트 해시 서명 검증
  - `CONFIG_EROFS_FS=y`: 초경량 압축 읽기 전용 파일시스템
- **신뢰 환경 및 증명 연동**:
  - `CONFIG_TEE=y` & `CONFIG_OPTEE=y`: OP-TEE SMC 드라이버
  - `CONFIG_TCG_TPM=y` & `CONFIG_TCG_FTPM_TEE=y`: OP-TEE fTPM 통신 드라이버
  - `CONFIG_IMA=y` & `CONFIG_IMA_MEASURE_PCR_IDX=10`: 실행 바이너리 fTPM PCR 10 측정

---

## 4. 스토리지 무결성 파이프라인 (EROFS + dm-verity)

운영체제 런타임 변조 및 랜섬웨어, 지속성(Persistence) 악성코드 주입을 원천 차단하기 위해 루트 파일시스템을 불변(Immutable) 상태로 배포합니다.

```mermaid
flowchart TD
    SRC["L4T Sample Rootfs (Ubuntu / Tegra User Space)"]
    EROFS_TOOL["mkfs.erofs (High Performance Read-Only)"]
    RAW_FS["rootfs.erofs (Immutable Read-Only Image)"]

    VERITY_TOOL["veritysetup format (Cryptographic Hash Tree Generator)"]
    VERITY_IMG["rootfs.verity (Data Blocks + Merkle Hash Tree)"]
    ROOT_HASH["Merkle Root Hash (SHA-256 Digest)"]

    SIGN_TOOL["keys_hsm/sign_helper.sh (SoftHSMv2 PKCS#11 Private Key)"]
    SIGNED_HASH["root_hash.p7s / Signature Block"]

    SRC --> EROFS_TOOL --> RAW_FS
    RAW_FS --> VERITY_TOOL --> VERITY_IMG
    VERITY_TOOL --> ROOT_HASH
    ROOT_HASH --> SIGN_TOOL --> SIGNED_HASH

    subgraph "Boot Verification on Robot / QEMU"
        KERNEL_VERIFY["Kernel dm-verity & Initramfs"]
        PUB_CERT["Public Verification Certificate (Built into Kernel keyring)"]

        SIGNED_HASH & PUB_CERT --> KERNEL_VERIFY
        VERITY_IMG --> KERNEL_VERIFY
        KERNEL_VERIFY -->|Valid| MOUNT["Mount /dev/mapper/rootfs (Verified Block Access)"]
        KERNEL_VERIFY -->|Tampered| PANIC["Kernel Panic / Halt Boot"]
    end
```

---

## 5. 런타임 무결성 측정 (IMA) 및 fTPM PCR 확장 파이프라인

로봇 운영 중 동적으로 로드되는 실행 파일, 스크립트, 공유 라이브러리는 리눅스 IMA 서브시스템에 의해 감시되며, 모든 측정값은 fTPM PCR 10에 즉시 반영됩니다.

```mermaid
sequenceDiagram
    participant PROC as User Space Process (e.g. Isaac ROS Node)
    participant KERNEL as Linux Kernel (VFS / Execve)
    participant IMA as Kernel IMA Engine
    participant FTPM as OP-TEE fTPM TA
    participant LOG as /sys/kernel/security/ima/runtime_measurements

    PROC->>KERNEL: sys_execve("/usr/bin/robot_controller")
    KERNEL->>IMA: Trigger file measurement hook
    IMA->>IMA: Compute SHA-256 digest of binary
    IMA->>FTPM: TPM2_PCR_Extend(PCR 10, Digest)
    Note over FTPM: PCR[10] = SHA256(PCR[10] || Digest)
    IMA->>LOG: Append entry to ASCII measurement list
    KERNEL->>PROC: Execute binary if policy allows
```

---

## 6. QEMU aarch64 가상 에뮬레이션 아키텍처

실제 로봇 보드 없이도 모든 보안 메커니즘을 동일하게 검증할 수 있도록 구성된 QEMU `virt` 머신 토폴로지입니다.

| 항목 | 설정값 / 기술 | 설명 |
| :--- | :--- | :--- |
| **Machine Model** | `virt,secure=on,virtualization=on,gic-version=3` | ARMv8 TrustZone 보안 상태(`secure=on`) 활성화 |
| **CPU** | `cortex-a57` 또는 `cortex-a72` (4 Cores) | aarch64 표준 코어 에뮬레이션 |
| **RAM** | `4096MB` (3072MB Normal World + 1024MB Secure World DRAM) | 메모리 공간 하드웨어 분리 |
| **Secure Storage** | Virtual RPMB Socket (OP-TEE `tee-supplicant` 연동) | Replay-Protected Memory Block 에뮬레이션 |
| **네트워크** | User-net (`hostfwd=tcp::2222-:22,tcp::8443-:8443`) | SSH 디버깅 및 Cloud mTLS 통신 검증 포워딩 |
| **Serial 콘솔** | PL011 UART0 (Normal), UART1 (Secure World OP-TEE Console) | 로그 분리 출력 및 자동화 테스트 캡처 |
