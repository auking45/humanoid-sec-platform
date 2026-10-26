---
title: "보안 요구사항 정의서 (SRD)"
description: "부팅 체인, 커널, TEE, 무결성 측정, HSM 및 통신 보안 요구사항 상세 명세"
---

> **Document ID**: `SRD-HSEC-2026-V1`  
> **Target Platform**: NVIDIA Jetson Humanoid Platform (QEMU aarch64 virt verification & L4T 6.x)  
> **Status**: Approved / Baseline

---

## 1. 개요 (Overview)

- **문서 목적**: 휴머노이드 로봇 제어 시스템을 위한 종합 보안 요구사항 명세서(System Security Requirements Document, SRD).
- **보안 범위**: 하드웨어 루트 오브 트러스트(RoT)부터 운영체제(OS), 런타임 무결성 검증, 암호키 관리, 클라우드 양방향 mTLS 통신에 이르는 전 생명주기 보안 요구사항 정의 및 허용 기준/테스트 산출물 매핑.

### 요구사항 식별자(ID) 체계
- `SRD-BOOT-xxx`: 부팅 체인 및 신뢰 체인(Chain of Trust) 요구사항
- `SRD-KERN-xxx`: 커널 하드닝 및 보안 서브시스템 요구사항
- `SRD-TEE-xxx`: ARM TrustZone, OP-TEE 및 fTPM 요구사항
- `SRD-STOR-xxx`: 스토리지 무결성 및 불변 파일시스템(EROFS/dm-verity) 요구사항
- `SRD-MEAS-xxx`: 런타임 측정(IMA) 및 원격 증명(Remote Attestation) 요구사항
- `SRD-HSM-xxx`: 키 계층, HSM(SoftHSMv2) 및 무평문 키(Zero-Plaintext) 요구사항
- `SRD-COMM-xxx`: Secure World 연동 mTLS 보안 통신 요구사항
- `SRD-ENV-xxx`: 개발 및 빌드 환경(DevContainer, CI/CD) 요구사항

---

## 2. 보안 요구사항 상세 명세

### 2.1. 부팅 체인 및 Secure Boot (`SRD-BOOT`)

| ID | 요구사항 명칭 | 중요도 | 상세 내용 | 검증 기준 (Acceptance Criteria) | 검증 테스트 |
| :---: | :--- | :---: | :--- | :--- | :---: |
| **SRD-BOOT-001** | Root of Trust 기반 검증 체인 | **MUST** | 시스템 부팅은 변조 불가능한 RoT(QEMU Secure ROM/Jetson BootROM)에서 시작하여 TF-A BL31, OP-TEE Core, Linux 커널 순으로 암호 서명 연속 검증 필수. | 서명 미검증 또는 변조 바이너리 로드 시 부팅 즉각 중단. | `tests/test_boot_optee.py`, `tests/test_secureboot_chain.py` |
| **SRD-BOOT-002** | Secure World / Normal World 격리 | **MUST** | ARM TrustZone 기술을 적용하여 Secure World(EL3, S-EL1, S-EL0)와 Normal World(NS-EL1, NS-EL0) 간 하드웨어 메모리 및 레지스터 격리 보장. | Normal World에서 Secure World 메모리 영역 접근 시 SError/Abort 발생 확인. | `tests/test_boot_optee.py` |
| **SRD-BOOT-003** | 롤백 방지 (Anti-Rollback) | **SHOULD** | 부팅 펌웨어는 단조 증가 카운터 또는 보안 버전을 확인하여 취약한 구버전 펌웨어로의 다운그레이드 원천 차단. | 낮은 보안 버전 바이너리 플래시 시도 시 로더 단계 거부. | 시뮬레이션 테스트 |
| **SRD-BOOT-004** | NVIDIA Tegra PKC Secure Boot 컨테이너 검증 | **MUST** | NVIDIA Jetson 하드웨어 온칩 퓨즈(`PKC_HASH`) 및 512바이트 `NVD1` 인증 컨테이너 헤더 검증. SoftHSM RSA-3072 서명 및 퓨즈 해시 일치 확인. | 1바이트 페이로드 변조 또는 불일치 퓨즈 주입 시 부팅 즉각 거절(`SECURE_BOOT_VIOLATION`). | `tests/test_secureboot_chain.py` |
| **SRD-BOOT-005** | TrustZone Cold Boot 통합 시퀀스 | **MUST** | PFLASH0(`flash0.bin`) 펌웨어 기반 TF-A BL1/BL2/BL31 -> OP-TEE OS(Early fTPM TA) -> Linux Kernel(PSCI v1.1) 순차 연동 콜드 부팅 보장. | UART1 OP-TEE fTPM 초기화 및 UART0 Linux `/dev/tee0`, `/dev/tpmrm0` 디바이스 바인딩 성공. | `tests/test_secureboot_chain.py` |

---

### 2.2. 커널 하드닝 (`SRD-KERN`)

| ID | 요구사항 명칭 | 중요도 | 상세 내용 | 검증 기준 (Acceptance Criteria) | 검증 테스트 |
| :---: | :--- | :---: | :--- | :--- | :---: |
| **SRD-KERN-001** | KSPP 권고 보안 설정 적용 | **MUST** | KSPP 권고에 따라 주소 공간 난수화(KASLR), 스택 보호(`CONFIG_STACKPROTECTOR_STRONG`), 엄격한 메모리 쓰기 금지(W^X) 강제 적용. | 커널 `.config` 파라미터 검증 및 부팅 후 보안 속성 확인. | `tests/test_boot_optee.py` |
| **SRD-KERN-002** | 강제 커널 모듈 서명 | **MUST** | 동적 로드되는 모든 커널 모듈(`.ko`)은 승인된 키로 서명되어야 하며 미서명 모듈 적재 전면 차단 (`CONFIG_MODULE_SIG_FORCE=y`). | 미서명 또는 변조 모듈 `insmod` 시 `-EKEYREJECTED` 오류 반환 및 로드 거절. | `tests/test_boot_optee.py` |
| **SRD-KERN-003** | Dual-Target 호환성 설계 | **MUST** | QEMU 검증용 커널 설정과 실제 NVIDIA Jetson 보드용 커널 설정 간 동일 보안 베이스라인(`security_hardening.config`) 공유. | `merge_config.sh`를 통해 보드 타겟과 QEMU 타겟이 동일 보안 config 상속. | 빌드 검증 |

---

### 2.3. ARM TrustZone & OP-TEE / fTPM (`SRD-TEE`)

| ID | 요구사항 명칭 | 중요도 | 상세 내용 | 검증 기준 (Acceptance Criteria) | 검증 테스트 |
| :---: | :--- | :---: | :--- | :--- | :---: |
| **SRD-TEE-001** | OP-TEE OS 통합 | **MUST** | S-EL1에서 동작하는 OP-TEE OS를 구동하고, Normal World 리눅스와 TEE SMC 인터페이스를 통해 신뢰 실행 환경(TEE) 제공. | 리눅스 `/dev/tee0`, `/dev/teepriv0` 인식 및 `tee-supplicant` 데몬 정상 구동. | `tests/test_boot_optee.py` |
| **SRD-TEE-002** | fTPM (Firmware TPM) TA 구현 | **MUST** | OP-TEE 내부에서 Microsoft Reference (`ms-tpm-20-ref`) fTPM TA 구동 및 리눅스 커널(`CONFIG_TCG_FTPM_TEE`)에 표준 TPM 2.0 인터페이스 노출. | `/dev/tpmrm0`, `/dev/tpm0` 생성 및 `tpm2_getcap` 질의 성공. | `tests/test_ftpm_ima.py` |
| **SRD-TEE-003** | 가상 RPMB 지속 스토리지 | **MUST** | fTPM의 NVRAM 상태 및 Secure Storage 데이터는 가상 eMMC RPMB 파티션에 암호화 보관되어 재부팅 후에도 영속 유지 보장. | QEMU 재부팅 후에도 fTPM NV 인덱스 및 PCR 상태 보존 검증. | `tests/test_ftpm_ima.py` |
| **SRD-TEE-004** | OP-TEE PKCS#11 TA 지원 | **MUST** | Secure World 내 암호화 키 격리 생성/운용을 위해 `CFG_PKCS11_TA=y` 탑재 및 사용자 공간 `libckteec.so` 연동 제공. | `pkcs11-tool --module /usr/lib/libckteec.so -L`로 토큰 슬롯 목록 정상 조회. | `tests/test_boot_optee.py` |

---

### 2.4. 스토리지 무결성 & 불변 파일시스템 (`SRD-STOR`)

| ID | 요구사항 명칭 | 중요도 | 상세 내용 | 검증 기준 (Acceptance Criteria) | 검증 테스트 |
| :---: | :--- | :---: | :--- | :--- | :---: |
| **SRD-STOR-001** | Read-Only EROFS 루트 파일시스템 | **MUST** | 운영체제 루트 파일시스템(Rootfs)은 읽기 전용 EROFS로 구성하여 런타임 쓰기 공격 차단. | 루트 마운트 Read-Only 설정 확인 및 임의 파일 쓰기 시도 차단. | `tests/test_ftpm_ima.py` |
| **SRD-STOR-002** | dm-verity 블록 무결성 검증 | **MUST** | 커널은 `dm-verity`를 통해 EROFS 스토리지의 모든 데이터 블록을 읽을 때마다 암호 해시 트리로 실시간 무결성 검증. | 디스크 이미지 1바이트 임의 변조 시 커널 I/O Error 발생 및 접근 차단. | `tests/test_ftpm_ima.py` |
| **SRD-STOR-003** | Root Hash 암호학적 서명 | **MUST** | dm-verity 머클 트리의 최상위 Root Hash는 오프라인 키로 서명되며, Initramfs는 내장 인증서로 서명 검증 후 마운트. | 변조된 Root Hash 또는 불일치 서명 주입 시 마운트 거부 및 부팅 중단. | `tests/test_ftpm_ima.py` |

---

### 2.5. 런타임 무결성 측정 및 원격 증명 (`SRD-MEAS`)

| ID | 요구사항 명칭 | 중요도 | 상세 내용 | 검증 기준 (Acceptance Criteria) | 검증 테스트 |
| :---: | :--- | :---: | :--- | :--- | :---: |
| **SRD-MEAS-001** | IMA (Integrity Measurement Architecture) | **MUST** | 커널 IMA 서브시스템을 활성화하여 실행 바이너리 및 동적 라이브러리 해시를 fTPM PCR 10에 순차 확장(Extend) 기록. | 바이너리 실행 시 `/sys/kernel/security/ima/runtime_measurements` 기록 및 PCR 10 갱신 확인. | `tests/test_ftpm_ima.py` |
| **SRD-MEAS-002** | Remote Attestation 증명 패키징 | **MUST** | fTPM AK(Attestation Key) 기반 Quote 및 IMA 로그를 수집하여 서명된 원격 증명 리포트 패키징 및 Verifier 검증 제공. | `apps/attestation_agent` 생성 Quote의 원격 검증기 서명 검증 성공. | `tests/test_secure_mtls.py` |

---

### 2.6. 키 관리 및 HSM (`SRD-HSM`)

| ID | 요구사항 명칭 | 중요도 | 상세 내용 | 검증 기준 (Acceptance Criteria) | 검증 테스트 |
| :---: | :--- | :---: | :--- | :--- | :---: |
| **SRD-HSM-001** | Zero-Plaintext Key 정책 | **MUST** | 코드베이스 및 커밋 히스토리에 어떤 경우에도 평문 개인키(`.pem`, `.key`) 저장 전면 배제. | Git 커밋 검사 및 CI 보안 감사 통과. | CI 파이프라인 |
| **SRD-HSM-002** | SoftHSMv2 PKCS#11 오프라인 서명 | **MUST** | 빌드/서명용 모든 개인키는 SoftHSMv2 토큰 내부에서 생성되고 RFC 7512 PKCS#11 URI로만 접근 허용. | 키 생성 스크립트의 토큰 내 키 생성 및 `pkcs11:` URI 서명 동작 확인. | `keys_hsm/setup_softhsm.sh` |
| **SRD-HSM-003** | 하드웨어 HSM 투명 마이그레이션 | **SHOULD** | PKCS#11 표준 규격을 준수하여 환경변수(`PKCS11_MODULE_PATH`, `PKCS11_URI`) 변경만으로 물리 HSM 전환 지원. | 모듈 경로 및 URI 교체만으로 서명 파이프라인 무수정 유지. | 단위 테스트 |

---

### 2.7. Secure World 기반 통신 보안 (`SRD-COMM`)

| ID | 요구사항 명칭 | 중요도 | 상세 내용 | 검증 기준 (Acceptance Criteria) | 검증 테스트 |
| :---: | :--- | :---: | :--- | :--- | :---: |
| **SRD-COMM-001** | Secure World 격리 클라이언트 개인키 | **MUST** | 로봇-클라우드 상호 인증(mTLS)용 장치 개인키는 Normal World 파일시스템에 존재하지 않고 OP-TEE PKCS#11 TA 내부에만 격리 보관. | Normal World 스토리지 내 클라이언트 개인키 파일 비존재 확인. | `tests/test_secure_mtls.py` |
| **SRD-COMM-002** | OpenSSL 3.x Provider 기반 연동 | **MUST** | mTLS 클라이언트는 OpenSSL 3.x `pkcs11-provider`를 활용하여 TLS 핸드셰이크 서명 연산을 Secure World 내부로 위임 수행. | TLS 1.3 mTLS 연결 성공 및 Secure SRAM 서명 위임 로그 확인. | `tests/test_secure_mtls.py` |

---

### 2.8. 개발 및 빌드 환경 (`SRD-ENV`)

| ID | 요구사항 명칭 | 중요도 | 상세 내용 | 검증 기준 (Acceptance Criteria) | 검증 테스트 |
| :---: | :--- | :---: | :--- | :--- | :---: |
| **SRD-ENV-001** | VS Code Dev Container & CI 단일화 | **MUST** | 로컬 개발 환경(VS Code Dev Containers)과 GitHub Actions CI 환경은 동일한 Dockerfile 및 구성을 공유하여 환경 불일치 배제. | 로컬 컨테이너 빌드 결과와 CI 파이프라인 빌드 결과 간 100% 동일 재현. | DevContainer & CI |
| **SRD-ENV-002** | 볼륨 분리를 통한 빌드 캐시 최적화 | **MUST** | L4T 소스, 다운로드 타르볼, ccache 및 SoftHSM 토큰을 호스트 볼륨에 영속 저장하여 중복 다운로드/빌드 방지. | 캐시 볼륨 마운트 확인 및 2회차 빌드 시 즉각 캐시 히트 검증. | 빌드 검증 |