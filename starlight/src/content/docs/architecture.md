---
title: "시스템 아키텍처 명세서 (System Architecture)"
description: "하드웨어 신뢰 경계, TF-A/OP-TEE, 커널 하드닝, EROFS + dm-verity 스토리지 무결성"
---

> **Target Platform**: NVIDIA Jetson Humanoid Robot Control Architecture (L4T 6.x & QEMU aarch64 virt)  
> **Status**: Approved / Baseline

---

## 1. 아키텍처 개요 및 신뢰 경계 (Trust Boundary)

- **하드웨어 신뢰 경계 수립**: ARMv8/ARMv9 TrustZone 하드웨어 격리 기술 기반 보안 영역(Secure World)과 일반 운영체제 영역(Normal World) 분리.
- **물리 하드웨어 비의존 검증**: QEMU `aarch64` `virt` 머신 상에서 Secure World(EL3, S-EL1, S-EL0)와 Normal World(NS-EL1, NS-EL0) 간 보안 인터페이스 동일 에뮬레이션.

[![System Architecture](/humanoid-sec-platform/diagrams/system_architecture.svg)](/humanoid-sec-platform/diagrams/system_architecture.html)
> 💡 *클릭 시 [Archify 인터랙티브 뷰어](/humanoid-sec-platform/diagrams/system_architecture.html)로 이동하여 테마 변경 및 신뢰 경계 줌을 지원함.*

---

## 2. 보안 부팅 체인 (Secure Boot Chain)

- **신뢰 체인(Chain of Trust)**: 변조 불가능한 RoT(Root of Trust)에서 출발하여 각 단계별 바이너리 암호 서명 검증 후 제어권 순차 이양.
- **TrustZone Cold Boot 시퀀스**:
  - `TF-A BL1 (EL3)`: PFLASH0(`flash0.bin`) 오프셋 `0x0`에서 실행 시작, 플랫폼 하드웨어 초기화 및 BL2 로드.
  - `TF-A BL2 (Secure-EL1)`: FIP(Firmware Image Package, 오프셋 `0x40000`) 파싱, BL31(EL3 Runtime) 및 BL32(OP-TEE OS) 로드.
  - `TF-A BL31 (EL3)`: SMC 디스패처 초기화 및 S-EL1 Secure World로 실행 이양.
  - `OP-TEE OS (S-EL1)`: 코어 초기화, UART1(`0x09040000`) 디버그 채널 오픈, Early fTPM TA(`bc50d971-d4c9-42c4-82cb-343fb7f37896`) 기동, RPMB 보안 스토리지 바인딩 및 PSCI 핸드오프 준비 완료.
  - `Linux Kernel 6.8 Noble (Normal World NS-EL1)`: PSCI v1.1 프로브 후 Normal World 부팅, OP-TEE SMC 드라이버 로드(`/dev/tee0`, `/dev/teepriv0`), fTPM 플랫폼 디바이스 드라이버 로드(`/dev/tpmrm0`), IMA 서브시스템 활성화 및 Initramfs `/init` 실행.
- **상태 영속화**: 가상 eMMC RPMB 파티션을 통해 fTPM NVRAM 및 OP-TEE Secure Storage의 리플레이 방지 및 영속성 보장.

[![Secure Boot Sequence](/humanoid-sec-platform/diagrams/secure_boot_sequence.svg)](/humanoid-sec-platform/diagrams/secure_boot_sequence.html)
> 💡 *클릭 시 [Archify 인터랙티브 뷰어](/humanoid-sec-platform/diagrams/secure_boot_sequence.html)로 이동하여 부팅 타임라인 애니메이션 재생 가능.*

---

## 3. NVIDIA Jetson Linux R39.2.1 공식 Secure Boot 아키텍처 (SBKPKC + EKB + UEFI Secure Boot)

NVIDIA Jetson Linux R39.2.1 (JetPack 7.2.1, Tegra234 Orin / Tegra264 Thor) 공식 Secure Boot 가이드(`SecureBoot.html`) 및 L4T OP-TEE PTA 소스(`jetson_uefi_services.c`, `jetson_ekb_extraction_t234.c`, `gen_ekb.py`) 규격을 1:1 반영하여 실제 Jetson 보드 플래싱(`odmfuse.sh` / `l4t_initrd_flash.sh`)과 호환되는 2단계 Secure Boot 파이프라인 구축:

- **공식 `<genericfuse>` XML 및 eFuse 테이블 (`configs/secureboot/fuse_config.xml`, `tegra_fuses.json`)**:
  - NVIDIA `odmfuse.sh` / `fskp_fuseburn.py` 표준 `<genericfuse MagicId="0x45535546" version="1.0.0">` XML 생성:
    - `PublicKeyHash`: SoftHSMv2 `SecureBootKey`(RSA-3072, ID `06`) 공개키 SHA-512 / SHA-256 해시
    - `SecureBootKey` (`SBK`): 부트로더 `SBKPKC` 암호화용 256비트 AES 대칭키 (SoftHSMv2 PKCS#11 결정론적 KDF 유도)
    - `OemK1` / `OemK2` (`T234` Orin) 및 `OemKdk0` (`T264` Thor): OP-TEE EKB 및 fTPM/LUKS 루트 유도 키 (256비트)
    - `BootSecurityInfo`: `0x00000209` (`0x1` RSA-3072 PKC | `0x8` SBK 암호화 활성화 | `0x200` `BSI_OEM_KEY_VALID_MASK`)
    - `SecurityMode`: `0x1` (`SECURITY_MODE_ENABLED_MASK` — Production Secure Boot 강제)
- **공식 `gen_ekb.py` 기반 EKB (`build/images/eks_t234.img`, `eks_t264.img`) 생성 및 OP-TEE 추출 검증**:
  - R39.2.1 공식 `sources/optee/optee/samples/hwkey-agent/host/tool/gen_ekb/gen_ekb.py`를 호출하여 `OemK1` (`T234` NIST-SP-800-108 CMAC KDF) 및 `OemKdk0` (`T264` KBKDF-HMAC-SHA256) 기반 `NVEKBP\0\0` v2.1 EKB 이미지 생성:
    - `Tag 1` (`ekb_kernel_encryption_key`, `sym_key`, 32B): UEFI/CPUBL 커널 및 DTB 암호화 키
    - `Tag 2` (`ekb_disk_encryption_key`, `sym_key2`, 16B): LUKS 디스크 암호화 키 (`gen_luks_passphrase.py` 연동 검증)
    - `Tag 4` (`ekb_uefi_var_auth_key`, `auth_key`, 16B): UEFI 변수 인증 키 (`jetson_user_key_pta_uefi_vars_auth`)
    - `Tag 5` (`ekb_hwkey_app_key`, 16B) 및 `Tag 91`/`92` (`ftpm_sn`, `ftpm_eps_seed`, 64B)
- **8,192바이트(`0x2000`) `NVDA` Boot Component Header (`BCH`) 및 2단계 서명/암호화**:
  - `sources/optee/optee/optee_os/core/pta/tegra/include/jetson_uefi_services.h` 규격 준수:
    - 오프셋 `0x0000`: `NVDA` (`BCH_HEADER_MAGIC`) + Stage 1 `PKC` (RSA-3072) 서명 + Stage 2 `UEFI db` (RSA-3072) 서명 + `SBK` AES-CMAC 바인딩 태그
    - 오프셋 `0x1400` (`5120`, `BCH_HEADER_AAD_OFFSET`, 80바이트): `BCRT` 매직, 패딩된 암호문 길이(`5124`), KDF 버전 `VER1`(`5136`), KDF 레이블 `CPUBL-PAYLOAD-DK`(`5168`), 12바이트 AES-GCM IV(`5188`)
    - 오프셋 `0x1450` (`5200`, `BCH_HEADER_TAG_OFFSET`, 16바이트): AES-256-GCM 인증 태그
    - 페이로드: ISO/IEC 9797-1 Method 2 (`0x80 0x00...`, `get_one_and_zeros_padding`) 패딩 후 EKB `sym_key`로부터 `nist_sp_800_108_hmac_kdf`로 유도한 256비트 `DK`로 `AES-256-GCM` 암호화
- **부트 검증, 복호화 및 변조 거부(Tamper-Resistance) 파이프라인**:
  - `scripts/sign_jetson_secureboot.sh`: `burn-fuses`, `gen-ekb`, `verify-ekb`, `sign`, `verify`, `tamper-test` 6대 명령 제공.
  - QEMU(`--secureboot`) 부팅 시 `fuse_config.xml` 및 `eks_t234.img` 무결성 검증 후 `kernel.signed`의 Stage 1 `PKC` / Stage 2 `UEFI db` 서명 검증 및 EKB `sym_key` 기반 `AES-256-GCM` 복호화(`build/run/kernel.decrypted`)를 거쳐 부팅 수행.
  - 커널 암호문 1바이트 변조, `<genericfuse>` XML 불일치, EKB 변조, UEFI `db` 서명 훼손 탐지 시 부팅 즉각 중단(`SECURE_BOOT_VIOLATION`, Exit code 2).

---

## 4. Dual-Target 커널 빌드 및 하드닝 아키텍처

- **설계 원칙**: 실제 Jetson 하드웨어와 QEMU 검증 환경 간 보안 정책 괴리 원천 배제를 위한 3계층 커널 설정 체계 채택.

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

### 4.1. 보안 하드닝 핵심 파라미터 (`security_hardening.config`)
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

## 5. 스토리지 무결성 파이프라인 (EROFS + dm-verity & OverlayFS)

- **불변 파일시스템**: 운영체제 런타임 변조 및 랜섬웨어, 지속성(Persistence) 악성코드 차단을 위한 읽기 전용 EROFS 루트 파일시스템 구축.
- **블록 레벨 무결성**: 커널 `dm-verity` 장치 매퍼를 통해 4KB 데이터 블록 단위 실시간 해시 트리 무결성 검증.
- **듀얼 프로파일 루트 파일시스템 및 OverlayFS 통합 (`--minimal` vs `--ubuntu`)**:
  - **고속 검증 프로파일 (`--minimal`, 기본값)**: GitHub Actions CI 및 빠른 부팅 검증을 위한 1.2MB 정적 C `initramfs` 기반 부팅 체인 검증 및 내장 대화형 보안 쉘 제공.
  - **공식 L4T Ubuntu 24.04 Noble 프로파일 (`--ubuntu`)**: NVIDIA JetPack 7.2.1 (L4T R39.2.1) 공식 Sample Rootfs(`Tegra_Linux_Sample-Root-Filesystem_R39.2.1_aarch64.tbz2`)를 불변 `EROFS` 이미지(`ubuntu_rootfs.erofs`)로 패키징 및 `dm-verity` 해시 트리(`ubuntu_rootfs.verity`) 서명 검증.
  - **OverlayFS 계층 결합 및 `switch_root` 전환**: 부팅 시 `initramfs`에서 `dm-verity` 검증을 통과한 읽기 전용 EROFS를 하위 계층(`lowerdir`)으로 마운트하고, 쓰기 가능한 상위 계층(`upperdir`, `workdir`)을 `OverlayFS`로 결합한 뒤 `switch_root`를 통해 정식 Ubuntu 24.04 사용자 공간(`bash`, `dpkg`, `.deb` 패키지 설치 및 런타임 보안 테스트 환경)으로 제어권 전환.

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
> 💡 *클릭 시 [Archify 인터랙티브 뷰어](/humanoid-sec-platform/diagrams/storage_integrity_pipeline.html)로 이동하여 빌드/서명 단계와 런타임 검증/측정 단계의 인터랙티브 플로우 확인 가능.*

---

## 6. 런타임 무결성 측정 (IMA) 및 fTPM PCR 확장 파이프라인

- **동적 바이너리 측정**: 실행 파일, 스크립트, 공유 라이브러리 실행 시 리눅스 커널 IMA 서브시스템이 다이제스트를 자동 산출하여 fTPM PCR 10에 확장 기록.
- **불변 감사 로그**: 런타임 측정 로그를 `/sys/kernel/security/ima/runtime_measurements`에 유지하여 원격 증명(Remote Attestation) 시 변조 여부 검증에 활용.

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

## 7. QEMU aarch64 가상 에뮬레이션 아키텍처

실제 로봇 보드 없이도 모든 보안 메커니즘을 동일하게 검증할 수 있도록 구성된 QEMU `virt` 머신 토폴로지 구성:

| 항목 | 설정값 / 기술 | 설명 |
| :---: | :---: | :--- |
| **Machine Model** | `virt,secure=on,gic-version=2` | ARMv8 TrustZone 보안 상태(`secure=on`) 활성화 |
| **CPU** | `cortex-a57` (4 Cores) | aarch64 표준 코어 에뮬레이션 |
| **RAM** | `2048MB` (Normal World + Secure World DRAM) | 메모리 공간 하드웨어 분리 |
| **PFLASH0** | `build/firmware/flash0.bin` (64MB) | BL1(0x0) 및 FIP(BL2/BL31/OP-TEE, 0x40000) 통합 펌웨어 |
| **DTB Injection** | `.cache/run/virt_boot.dtb` | `microsoft,ftpm` 호환 노드 및 initrd/bootargs 동적 삽입 |
| **Secure Storage** | Virtual RPMB Socket (OP-TEE `tee-supplicant` 연동) | Replay-Protected Memory Block 에뮬레이션 |
| **네트워크** | User-net (`hostfwd=tcp::2222-:22,tcp::8443-:8443`) | SSH 디버깅 및 Cloud mTLS 통신 검증 포워딩 |
| **Serial 콘솔** | PL011 UART0 (Normal), UART1 (Secure World OP-TEE Console) | 로그 분리 출력 및 자동화 테스트 캡처 |