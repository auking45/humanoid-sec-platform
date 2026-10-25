---
title: "보안 요구사항 정의서 (SRD)"
description: "부팅 체인, 커널, TEE, 무결성 측정, HSM 및 통신 보안 요구사항 상세 명세"
---

> **Document ID**: `SRD-HSEC-2026-V1`  
> **Target Platform**: NVIDIA Jetson Humanoid Platform (QEMU aarch64 virt verification & L4T 6.x)  
> **Status**: Approved / Baseline

---

## 1. 개요 (Overview)

본 문서는 휴머노이드 로봇 제어 시스템을 위한 종합 보안 요구사항 명세서(System Security Requirements Document, SRD)입니다. 로봇의 하드웨어 루트 오브 트러스트(RoT)부터 운영체제(OS), 런타임 무결성 검증, 암호키 관리, 클라우드 양방향 보안 통신(mTLS)에 이르는 전 생명주기 보안 요구사항을 정의하고, 이를 검증하기 위한 기준 및 테스트 산출물을 매핑합니다.

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
| :--- | :--- | :---: | :--- | :--- | :--- |
| **SRD-BOOT-001** | Root of Trust 기반 검증 체인 | **MUST** | 시스템 부팅은 변조 불가능한 RoT(QEMU Secure ROM/Jetson BootROM)에서 시작하여 TF-A BL31, OP-TEE Core, U-Boot/EDK2, Linux 커널 순으로 서명을 연속 검증해야 한다. | 서명되지 않거나 잘못된 서명을 가진 부트 스테이지 진입 시 부팅이 즉시 중단되어야 함. | `tests/test_boot_optee.py` |
| **SRD-BOOT-002** | Secure World / Normal World 격리 | **MUST** | ARM TrustZone 기술을 적용하여 Secure World(EL3, S-EL1, S-EL0)와 Normal World(NS-EL1, NS-EL0) 간의 하드웨어 메모리 및 레지스터 격리를 보장해야 한다. | Normal World에서 Secure World 메모리 영역(TrustZone DRAM) 직접 접근 시 버스 오류(SError/External Abort) 발생 확인. | `tests/test_boot_optee.py` |
| **SRD-BOOT-003** | 롤백 방지 (Anti-Rollback) | **SHOULD** | 부팅 펌웨어는 단조 증가 카운터(Monotonic Counter) 또는 eFuse 기반 버전을 확인하여 취약한 구버전 펌웨어로의 다운그레이드를 차단해야 한다. | 낮은 보안 버전 넘버를 가진 바이너리 플래시 시도 시 로더 단계에서 거부됨. | 시뮬레이션 테스트 |

---

### 2.2. 커널 하드닝 (`SRD-KERN`)

| ID | 요구사항 명칭 | 중요도 | 상세 내용 | 검증 기준 (Acceptance Criteria) | 검증 테스트 |
| :--- | :--- | :---: | :--- | :--- | :--- |
| **SRD-KERN-001** | KSPP 권고 보안 설정 적용 | **MUST** | 커널은 Linux Kernel Self-Protection Project(KSPP) 권고에 따라 주소 공간 난수화(KASLR), 스택 보호(`CONFIG_STACKPROTECTOR_STRONG`), 엄격한 메모리 권한(W^X)을 강제해야 한다. | 커널 빌드 `.config` 검증 및 부팅 후 `/sys/kernel/security` 확인. | `tests/test_boot_optee.py` |
| **SRD-KERN-002** | 강제 커널 모듈 서명 | **MUST** | 동적 로드되는 모든 커널 모듈(`.ko`)은 사전에 승인된 키로 암호학적으로 서명되어야 하며, 미서명 모듈의 로드는 커널 수준에서 전면 차단되어야 한다 (`CONFIG_MODULE_SIG_FORCE=y`). | 미서명 또는 변조된 모듈 `insmod` 시도 시 `-EKEYREJECTED` 오류와 함께 거부됨. | `tests/test_boot_optee.py` |
| **SRD-KERN-003** | Dual-Target 호환성 설계 | **MUST** | QEMU 검증용 커널 설정과 실제 NVIDIA Jetson 보드용 커널 설정은 동일한 보안 베이스라인(`security_hardening.config`)을 공유해야 한다. | `merge_config.sh`를 통해 보드 타겟과 QEMU 타겟이 동일한 보안 config를 상속함. | 빌드 검증 |

---

### 2.3. ARM TrustZone & OP-TEE / fTPM (`SRD-TEE`)

| ID | 요구사항 명칭 | 중요도 | 상세 내용 | 검증 기준 (Acceptance Criteria) | 검증 테스트 |
| :--- | :--- | :---: | :--- | :--- | :--- |
| **SRD-TEE-001** | OP-TEE OS 통합 | **MUST** | 시스템은 S-EL1에서 동작하는 OP-TEE OS를 구동하고, Normal World 리눅스와 TEE SMC 인터페이스를 통해 신뢰 실행 환경(TEE)을 제공해야 한다. | 리눅스에서 `/dev/tee0`, `/dev/teepriv0` 인식 및 `tee-supplicant` 정상 데몬 동작. | `tests/test_boot_optee.py` |
| **SRD-TEE-002** | fTPM (Firmware TPM) TA 구현 | **MUST** | OP-TEE 내부에서 Microsoft Reference Implementation(`ms-tpm-20-ref`) fTPM TA가 동작하여 리눅스 커널(`CONFIG_TCG_FTPM_TEE`)에 표준 TPM 2.0 인터페이스를 노출해야 한다. | 리눅스에서 `/dev/tpmrm0` 및 `/dev/tpm0` 생성 및 `tpm2_getcap` 명령 응답 성공. | `tests/test_ftpm_ima.py` |
| **SRD-TEE-003** | 가상 RPMB 지속 스토리지 | **MUST** | fTPM의 NVRAM 상태 및 Secure Storage 데이터는 재부팅 후에도 지속 유지되도록 가상 eMMC RPMB 파티션에 안전하게 암호화 저장되어야 한다. | QEMU 재부팅 후에도 fTPM NV 인덱스 및 PCR 상태 보존 검증. | `tests/test_ftpm_ima.py` |
| **SRD-TEE-004** | OP-TEE PKCS#11 TA 지원 | **MUST** | Secure World 내에서 암호화 키를 격리 생성 및 운용할 수 있도록 `CFG_PKCS11_TA=y`를 탑재하고 사용자 공간 `libckteec.so`를 지원해야 한다. | `pkcs11-tool --module /usr/lib/libckteec.so -L` 명령으로 슬롯 목록 정상 조회. | `tests/test_boot_optee.py` |

---

### 2.4. 스토리지 무결성 & 불변 파일시스템 (`SRD-STOR`)

| ID | 요구사항 명칭 | 중요도 | 상세 내용 | 검증 기준 (Acceptance Criteria) | 검증 테스트 |
| :--- | :--- | :---: | :--- | :--- | :--- |
| **SRD-STOR-001** | Read-Only EROFS 루트 파일시스템 | **MUST** | 운영체제 루트 파일시스템(Rootfs)은 고성능 압축 읽기 전용 파일시스템인 EROFS로 구성되어 런타임 쓰기 공격을 차단해야 한다. | 루트 마운트가 Read-Only로 설정되어 임의 파일 수정 불가 확인. | `tests/test_ftpm_ima.py` |
| **SRD-STOR-002** | dm-verity 블록 무결성 검증 | **MUST** | 커널은 `dm-verity` 장치 매퍼를 통해 EROFS 스토리지의 모든 데이터 블록을 읽을 때마다 암호학적 해시 트리로 실시간 무결성을 검증해야 한다. | 디스크 이미지 내 1바이트 임의 변조 시 커널 I/O Error 발생 및 접근 차단. | `tests/test_ftpm_ima.py` |
| **SRD-STOR-003** | Root Hash 암호학적 서명 | **MUST** | dm-verity 머클 트리의 최상위 Root Hash는 오프라인 서명키로 서명되어야 하며, 커널/Initramfs는 공인인증서로 서명을 검증한 후에만 마운트해야 한다. | 변조된 Root Hash 또는 잘못된 서명 주입 시 마운트 실패 및 커널 패닉 유도. | `tests/test_ftpm_ima.py` |

---

### 2.5. 런타임 무결성 측정 및 원격 증명 (`SRD-MEAS`)

| ID | 요구사항 명칭 | 중요도 | 상세 내용 | 검증 기준 (Acceptance Criteria) | 검증 테스트 |
| :--- | :--- | :---: | :--- | :--- | :--- |
| **SRD-MEAS-001** | IMA (Integrity Measurement Architecture) | **MUST** | 리눅스 커널의 IMA 서브시스템을 활성화하여 실행되는 모든 바이너리 및 동적 라이브러리의 해시를 fTPM PCR 10에 순차 확장(Extend) 기록해야 한다. | 파일 실행 시 `/sys/kernel/security/ima/ascii_runtime_measurements`에 기록 생성 및 fTPM PCR 10 값 변경 확인. | `tests/test_ftpm_ima.py` |
| **SRD-MEAS-002** | Remote Attestation 증명 패키징 | **MUST** | 원격 관제 클라우드가 로봇의 무결성을 신뢰할 수 있도록 fTPM AK(Attestation Key) 기반 Quote 및 IMA 로그를 수집하여 서명된 증명 리포트를 생성해야 한다. | `apps/attestation_agent`가 생성한 Quote가 Verifier에서 정상 검증됨. | `tests/test_secure_mtls.py` |

---

### 2.6. 키 관리 및 HSM (`SRD-HSM`)

| ID | 요구사항 명칭 | 중요도 | 상세 내용 | 검증 기준 (Acceptance Criteria) | 검증 테스트 |
| :--- | :--- | :---: | :--- | :--- | :--- |
| **SRD-HSM-001** | Zero-Plaintext Key 정책 | **MUST** | 레포지토리 코드베이스 및 커밋 히스토리에 어떤 경우에도 평문 개인키(`.pem`, `.key`)가 저장되지 않아야 한다. | Git 커밋 검사 및 CI 검사 통과 (`git grep`, trivy, gitleaks). | CI 파이프라인 |
| **SRD-HSM-002** | SoftHSMv2 PKCS#11 오프라인 서명 | **MUST** | 오프라인 빌드 및 서명(Secure Boot, 커널 모듈, dm-verity, IMA)에 사용되는 모든 개인키는 SoftHSMv2 토큰 내부에서 생성되고 PKCS#11 URI로만 접근해야 한다. | 키 생성 스크립트가 토큰 내 키를 생성하고 `pkcs11:` URI로 서명 수행 확인. | `keys_hsm/setup_softhsm.sh` |
| **SRD-HSM-003** | 하드웨어 HSM 투명 마이그레이션 | **SHOULD** | 소프트웨어 인터페이스가 PKCS#11 표준 규격을 따르므로 배포 환경 변경 시 HSM PKCS#11 모듈 경로 및 URI 변경만으로 물리 HSM(YubiHSM, Thales 등)으로 전환 가능해야 한다. | 환경변수 `PKCS11_MODULE_PATH` 교체만으로 서명 도구 호환성 유지. | 단위 테스트 |

---

### 2.7. Secure World 기반 통신 보안 (`SRD-COMM`)

| ID | 요구사항 명칭 | 중요도 | 상세 내용 | 검증 기준 (Acceptance Criteria) | 검증 테스트 |
| :--- | :--- | :---: | :--- | :--- | :--- |
| **SRD-COMM-001** | Secure World 격리 클라이언트 개인키 | **MUST** | 로봇과 관제 클라우드 간 상호 인증(mTLS)에 사용되는 장치 개인키는 Normal World 파일시스템에 존재하지 않고 OP-TEE PKCS#11 TA 또는 fTPM 내부에만 격리 보관되어야 한다. | Normal World 스토리지 어디에도 클라이언트 개인키 파일이 존재하지 않음. | `tests/test_secure_mtls.py` |
| **SRD-COMM-002** | OpenSSL 3.x Provider 기반 연동 | **MUST** | mTLS 클라이언트는 OpenSSL 3.x의 `pkcs11-provider` 또는 `tpm2-openssl`을 사용하여 TLS 핸드셰이크의 암호 서명 연산을 Secure World 내부로 위임해야 한다. | TLS 1.3 mTLS 연결이 성공하고 패킷 캡처 및 로그에서 서명 위임 확인. | `tests/test_secure_mtls.py` |

---

### 2.8. 개발 및 빌드 환경 (`SRD-ENV`)

| ID | 요구사항 명칭 | 중요도 | 상세 내용 | 검증 기준 (Acceptance Criteria) | 검증 테스트 |
| :--- | :--- | :---: | :--- | :--- | :--- |
| **SRD-ENV-001** | VS Code Dev Container & CI 단일화 | **MUST** | 로컬 개발 환경(VS Code Dev Containers)과 GitHub Actions CI 환경은 동일한 Dockerfile 및 구성을 사용하여 환경 불일치를 차단해야 한다. | 로컬 컨테이너 빌드 결과와 CI 빌드 결과가 100% 동일하게 재현됨. | DevContainer & CI |
| **SRD-ENV-002** | 볼륨 분리를 통한 빌드 캐시 최적화 | **MUST** | L4T 소스, 다운로드 타르볼, ccache 및 SoftHSM 토큰은 호스트 볼륨에 영속 저장되어 컨테이너 재시작 시에도 중복 다운로드/빌드를 방지해야 한다. | 캐시 볼륨 마운트 확인 및 2회차 빌드 시 즉각 캐시 히트 검증. | 빌드 검증 |