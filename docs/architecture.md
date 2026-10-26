# System Architecture Specification

> **Target Platform**: NVIDIA Jetson Humanoid Robot Control Architecture (L4T 6.x & QEMU aarch64 virt)  
> **Status**: Approved / Baseline

---

## 1. 아키텍처 개요 및 신뢰 경계 (Trust Boundary)

- **하드웨어 신뢰 경계 수립**: ARMv8/ARMv9 TrustZone 하드웨어 격리 기술 기반 보안 영역(Secure World)과 일반 운영체제 영역(Normal World) 분리.
- **물리 하드웨어 비의존 검증**: QEMU `aarch64` `virt` 머신 상에서 Secure World(EL3, S-EL1, S-EL0)와 Normal World(NS-EL1, NS-EL0) 간 보안 인터페이스 동일 에뮬레이션.

[![System Architecture](diagrams/system_architecture.svg)](diagrams/system_architecture.html)
> 💡 *클릭 시 [Archify 인터랙티브 뷰어](diagrams/system_architecture.html)로 이동하여 테마 변경 및 신뢰 경계 줌을 지원함.*

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

[![Secure Boot Sequence](diagrams/secure_boot_sequence.svg)](diagrams/secure_boot_sequence.html)
> 💡 *클릭 시 [Archify 인터랙티브 뷰어](diagrams/secure_boot_sequence.html)로 이동하여 부팅 타임라인 애니메이션 재생 가능.*

---

## 3. NVIDIA Jetson Tegra PKC Secure Boot 시뮬레이션 아키텍처

실제 NVIDIA Jetson 하드웨어의 온칩 퓨즈(eFuses) 및 Tegra 부트 헤더 검증 메커니즘을 QEMU 에뮬레이션 환경에 완벽 구현:

- **SoC eFuse 공개키 해시 모델링 (`configs/secureboot/tegra_fuses.json`)**:
  - SoftHSMv2 PKCS#11 토큰 내 RSA-3072 서명키(`SecureBootKey`, ID: `06`)의 공개키 DER로부터 256비트 SHA-256 해시를 산출하여 SoC 하드웨어 퓨즈(`PKC_HASH`)에 프로비저닝.
  - `SecurityMode: 1` 설정으로 Production Secure Boot 모드 강제.
- **NVIDIA 인증 컨테이너 규격 (`NVD1` Container)**:
  - 512바이트 고정 규격 인증 헤더 구조:
    - 매직 식별자: `NVD1` (4바이트)
    - 컨테이너 버전: `0x00010000` (4바이트)
    - 페이로드 길이: 원본 커널 바이너리 바이트 크기 (8바이트)
    - 페이로드 SHA-256 다이제스트: (32바이트)
    - PKC 공개키 SHA-256 다이제스트: (32바이트)
    - RSA-3072 디지털 서명: PKCS#11 C_Sign 기반 페이로드 다이제스트 서명 (384바이트)
    - 예약 영역: 패딩 (48바이트)
- **부트 검증 및 변조 거부(Tamper-Resistance) 파이프라인**:
  - `scripts/sign_jetson_secureboot.sh` 유틸리티: `burn-fuses`, `sign`, `verify`, `tamper-test` 4단계 파이프라인 제공.
  - QEMU 부팅 전 컨테이너 내 PKC 해시와 SoC eFuse 일치 여부, 및 페이로드 암호 서명 무결성 검증.
  - 1바이트 변조 또는 불일치 퓨즈 탐지 시 부팅 즉각 중단(`SECURE_BOOT_VIOLATION`, Exit code 2).

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

## 5. 스토리지 무결성 파이프라인 (EROFS + dm-verity)

- **불변 파일시스템**: 운영체제 런타임 변조 및 랜섬웨어, 지속성(Persistence) 악성코드 차단을 위한 읽기 전용 EROFS 루트 파일시스템 구축.
- **블록 레벨 무결성**: 커널 `dm-verity` 장치 매퍼를 통해 4KB 데이터 블록 단위 실시간 해시 트리 무결성 검증.

[![Storage Integrity Pipeline](diagrams/storage_integrity_pipeline.svg)](diagrams/storage_integrity_pipeline.html)
> 💡 *클릭 시 [Archify 인터랙티브 뷰어](diagrams/storage_integrity_pipeline.html)로 이동하여 빌드/서명 단계와 런타임 검증/측정 단계의 인터랙티브 플로우 확인 가능.*

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

