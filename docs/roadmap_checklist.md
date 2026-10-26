# Humanoid Security Platform — Master Roadmap & Execution Checklist

> **Single Source of Truth (SSOT)**: 본 문서는 프로젝트의 전체 실행 계획, 단계별 세부 작업 및 검증 상태를 추적하는 마스터 체크리스트임. 각 작업 완료 시 체크박스 `[x]`와 검증 결과를 기록함.

---

## 📊 전체 진행 현황 요약 (Progress Overview)

| 단계 (Phase) | 단계명 | 목표 및 범위 | 상태 |
| :--- | :--- | :--- | :---: |
| **Phase 0** | 전체 아키텍처 및 상세 설계 | SRD 요구사항, 아키텍처, 키 관리, 위협 모델, 마스터 체크리스트 작성 | 🟢 완료 |
| **Phase 1** | DevContainer & Docker 환경 | VS Code Dev Container, Dockerfile, docker-compose, env wrapper | 🟢 완료 |
| **Phase 2** | L4T 소스 확보 & QEMU 기본 부팅 | L4T R39.2.1 다운로드, TF-A + OP-TEE + L4T 커널 QEMU 부팅 | 🟢 완료 |
| **Phase 3** | OP-TEE fTPM & PKCS#11 TA 통합 | ms-tpm-20-ref fTPM TA, pkcs11 TA, QEMU RPMB 스토리지 연동 | 🟢 완료 |
| **Phase 4** | SoftHSMv2 키 관리 파이프라인 | SoftHSM 토큰 초기화, Zero-Plaintext 키 생성, PKCS#11 서명 헬퍼 | 🟢 완료 |
| **Phase 5** | 커널 하드닝 & 스토리지/런타임 무결성 | KSPP 커널 하드닝, EROFS + dm-verity, IMA fTPM PCR 확장 | 🟢 완료 |
| **Phase 6** | Secure World mTLS & Attestation | OP-TEE PKCS#11/fTPM 기반 mTLS 클라이언트, Remote Attestation | 🟢 완료 |

---

## 🛠 세부 작업 체크리스트 (Detailed Checklist)

### Phase 0: 전체 아키텍처 및 상세 설계 문서화
- [x] **0.1. 저장소 기초 설정**
  - [x] `.gitignore` 작성 (캐시, 빌드 아티팩트, 평문 키 제외 규칙)
  - [x] `README.md` 작성 (프로젝트 소개, 아키텍처 개요, 빠른 시작)
  - [x] `AGENTS.md` 작성 (골든 룰, 원자적 커밋, DevContainer-First 원칙)
- [x] **0.2. 마스터 체크리스트 및 요구사항 명세**
  - [x] `docs/roadmap_checklist.md` 마스터 체크리스트 작성
  - [x] `docs/requirements.md` (SRD: 번호 체계, 보안 기능별 요구사항, 검증 기준)
- [x] **0.3. 아키텍처 및 상세 설계 문서화**
  - [x] `docs/architecture.md` (부팅 체인, Trust Boundary, Dual-Target 커널, 무결성 파이프라인 명세)
  - [x] `docs/key_management_hsm.md` (SoftHSMv2 오프라인 서명, OP-TEE 런타임 키, mTLS 시퀀스)
  - [x] `docs/threat_model.md` (휴머노이드 로봇 STRIDE 위협 모델 및 통제 매핑)
- [x] **0.4. Archify 기반 인터랙티브 다이어그램 구축 (`docs/diagrams/`)**
  - [x] `system_architecture.html` / `*.svg` (QEMU, TrustZone, Normal World, Cloud 아키텍처)
  - [x] `secure_boot_sequence.html` / `*.svg` (BootROM -> TF-A -> OP-TEE -> Kernel -> dm-verity 시퀀스)
  - [x] `key_hierarchy.html` / `*.svg` (SoftHSMv2 Tier 1, Secure World Tier 2, 공개 인증서 Tier 3)
  - [x] `secure_mtls_sequence.html` / `*.svg` (OpenSSL 3.x Provider + OP-TEE PKCS#11 TA mTLS 핸드셰이크)
  - [x] `storage_integrity_pipeline.html` / `*.svg` (EROFS + dm-verity + IMA PCR 10 파이프라인)
  - [x] `threat_model_stride.html` / `*.svg` (공격 표면 -> STRIDE 위협 -> 보안 통제 -> SRD 매핑)
  - [x] `tools/archify/scripts/extract_svg.py` (내장 폰트/스타일 포함 독립형 SVG 자동 추출 도구)
- [x] **0.5. Astro Starlight 기술 문서 포털 및 GitHub Pages 파이프라인 (`starlight/`)**
  - [x] 사이버펑크 네온 테마 적용 (`starlight/src/styles/custom.css` - Pretendard/JetBrains Mono, 네온 팔레트)
  - [x] 자동 문서 및 에셋 동기화 도구 구현 (`scripts/sync_docs_to_starlight.py`)
  - [x] GitHub Actions 자동 빌드 및 배포 워크플로우 구축 (`.github/workflows/deploy_docs.yml`)
  - [x] Pagefind 로컬 전문 검색 및 Archify 다이어그램 갤러리(`diagrams.md`) 구축

---

### Phase 1: Dev Container & Docker CI/CD 빌드 환경 구축
- [x] **1.1. 컨테이너 빌드 환경 구성**
  - [x] `docker/Dockerfile` 작성 (Ubuntu 22.04 기반, aarch64 크로스 툴체인, QEMU 8.x+, SoftHSMv2, tpm2-tools, erofs-utils, ccache)
  - [x] `docker/docker-compose.yml` 작성 (캐시 볼륨 마운트: `.cache/downloads`, `sources/`, `.cache/ccache`, `build/`, `.cache/softhsm`)
  - [x] `docker/entrypoint.sh` 작성 (사용자 권한 매핑, ccache 초기화, SoftHSM 토큰 디렉토리 권한 설정)
- [x] **1.2. VS Code Dev Container 연동**
  - [x] `.devcontainer/devcontainer.json` 구성 (docker-compose 연동, C/C++, Python, Docker 추천 확장 프로그램)
- [x] **1.3. 호스트 CLI 래퍼 스크립트**
  - [x] `scripts/env_container.sh` 구현 (호스트 환경에서 컨테이너 내부 빌드/테스트 명령 즉시 실행)
- [x] **1.4. 컨테이너 환경 검증**
  - [x] Dockerfile, compose yaml, json syntax, entrypoint 및 스크립트 실행 권한 검증 완료

---

### Phase 2: NVIDIA L4T 공식 소스 확보 및 QEMU 기본 부팅
- [x] **2.1. L4T 공식 아카이브 소스 다운로드 자동화**
  - [x] `scripts/fetch_l4t_sources.sh` 작성 (NVIDIA JetPack 7.2.1 / Jetson Linux R39.2.1 BSP, Public Sources, Rootfs 다운로드 및 캐시 체크)
  - [x] 캐시 검증 로직 구현 (이미 다운로드된 타르볼은 재다운로드 건너뜀)
- [x] **2.2. Dual-Target 커널 설정 체계 구축**
  - [x] `configs/kernel/qemu_compat.config` (QEMU `virt` 머신용 VirtIO, PL011, GICv3 드라이버 등)
  - [x] `scripts/build_kernel.sh` (L4T 기본 defconfig + qemu_compat.config 병합 및 크로스 컴파일)
- [x] **2.3. TF-A & OP-TEE 빌드 체계 구축**
  - [x] `scripts/build_tfa_optee.sh` (TF-A BL31 + OP-TEE Core QEMU aarch64 타겟 빌드)
- [x] **2.4. QEMU 기본 부팅 스크립트 작성 및 검증**
  - [x] `scripts/run_qemu.sh` (QEMU `virt`, `secure=on`, TF-A + OP-TEE + L4T 커널 + 기본 BusyBox/Minimal Initramfs 부팅)
  - [x] `tests/test_boot_optee.py` (OP-TEE 부팅 메시지 및 `tee-supplicant` 기본 동작 자동 테스트)
- [x] **2.5. TrustZone Cold Boot 통합 및 NVIDIA Jetson Secure Boot 에뮬레이션**
  - [x] PFLASH0 단일 펌웨어 이미지 구축 (`build/firmware/flash0.bin`: BL1 @ 0x0, FIP @ 0x40000)
  - [x] TF-A BL2 S-EL1 MMU 로깅 트랩 및 스택 크기 확장 패치 적용 (`patches/tfa/0001-fix-qemu-bl2-mmu-and-stack.patch`)
  - [x] 동적 디바이스 트리 주입 (`virt_boot.dtb` 내 `microsoft,ftpm` TA 노드 및 bootargs / initrd 매핑)
  - [x] NVIDIA Jetson Tegra PKC 서명 및 SoC eFuse 검증 파이프라인 구축 (`scripts/sign_jetson_secureboot.sh`, `configs/secureboot/tegra_fuses.json`, `build/images/kernel.signed`)
  - [x] 1바이트 변조 방어 및 불일치 eFuse 부팅 거절 자동 검증 슈트 구축 (`tests/test_secureboot_chain.py`, 전체 46개 테스트 100% 통과)

---

### Phase 3: OP-TEE fTPM TA & PKCS#11 TA 통합
- [x] **3.1. fTPM TA 빌드 및 OP-TEE 탑재**
  - [x] Microsoft Reference Implementation (`ms-tpm-20-ref`) fTPM TA 통합 완료 (`bc50d971-d4c9-42c4-82cb-343fb7f37896.ta`)
  - [x] Early TA 탑재를 통한 OP-TEE 코어(`tee-pager_v2.bin`) 내부 임베드 및 부팅 직후 TPM2 활성화 보장
- [x] **3.2. QEMU RPMB 가상 보안 스토리지 연동**
  - [x] OP-TEE RPMB 파일시스템(`CFG_RPMB_FS=y`) 빌드 및 `tee-supplicant` 연동 지원 구성
  - [x] Initramfs 내 `tee-supplicant` 데몬 자동 구동 및 RPMB 보안 스토리지 초기화 파이프라인 수립
- [x] **3.3. Linux 커널 fTPM 드라이버 활성화 및 검증**
  - [x] 커널 보안 하드닝 설정 `CONFIG_TCG_FTPM_TEE=y`, `CONFIG_TCG_TPM=y` 적용 및 로컬 빌드 검증 완료
  - [x] 부팅 시 `/dev/tpmrm0`, `/dev/tpm0` 디바이스 노드 인식 및 테스트 슈트 자동 검증 완료
- [x] **3.4. OP-TEE PKCS#11 TA 활성화**
  - [x] `CFG_PKCS11_TA=y` 설정 적용 및 암호화 TA(`fd02c9da-306c-48c7-a49c-bbd827ae86ee.ta`) 빌드 완료
  - [x] 리눅스 사용자 공간 라이브러리(`libteec.so`, `libckteec.so`) 크로스 컴파일 및 Initramfs 번들링 완료

---

### Phase 4: SoftHSMv2 기반 오프라인 키 관리 파이프라인
- [x] **4.1. SoftHSMv2 토큰 초기화 스크립트**
  - [x] `keys_hsm/setup_softhsm.sh` 작성 완료 (`HumanoidSecToken` 토큰 초기화)
  - [x] Kernel Module Signing Key (RSA 3072, ID: 01) 및 DmVeritySigningKey (RSA 3072, ID: 02) 생성
  - [x] IMA 파일 서명키 (ECDSA P-384, ID: 03) 및 장치 등록 CA 키 (ECDSA P-256, ID: 04) 생성
  - [x] 비추출(Never-extractable) 속성 부여 및 공개키/인증서(`keys_hsm/certs/`) 추출 파이프라인 수립
- [x] **4.2. PKCS#11 URI 서명 헬퍼 구현**
  - [x] `keys_hsm/sign_helper.sh` 작성 (RFC 7512 `pkcs11:` URI 및 in-token C_Sign 기반 서명 래퍼)
  - [x] 커널 모듈(`.ko`), dm-verity roothash, IMA 서명 및 검증(`verify`) 파이프라인 구축
- [x] **4.3. Zero Plaintext Key 검증**
  - [x] `keys_hsm/audit_zero_keys.sh` 작성 및 CI/로컬 트리 무평문 키 전수 감사 통과 (0 plaintext keys on disk)

---

### Phase 5: 커널 하드닝 및 EROFS + dm-verity + IMA 무결성 검증
- [x] **5.1. 커널 하드닝 설정 적용**
  - [x] `configs/kernel/security_hardening.config` 작성 완료 (KSPP 권고안: 모듈 서명 강제, 스택 프로텍터, ASLR, 엄격한 메모리 보호 적용)
  - [x] Linux 커널 6.8 Noble 빌드 시 fragment 병합 및 컴파일 검증 완료
- [x] **5.2. EROFS + dm-verity 불변 루트 파일시스템 빌드**
  - [x] `scripts/build_rootfs.sh` 작성 완료 (불변 EROFS 이미지 `rootfs.erofs` 생성)
  - [x] `veritysetup` 기반 Merkle 해시 트리(`rootfs.verity`) 생성 및 SoftHSM `DmVeritySigningKey`로 Root Hash 서명(`verity.roothash.sig`) 파이프라인 구축
  - [x] dm-verity 무결성 자가 검증 및 1바이트 변조 데이터 즉시 차단(Tamper-resistance) 검증 완료
- [x] **5.3. IMA (Integrity Measurement Architecture) 및 fTPM PCR 확장**
  - [x] IMA 정책 수립 (`/etc/ima/ima-policy`, 실행 파일 및 커널 모듈 대상 측정 및 감정 규칙 정의)
  - [x] fTPM PCR 10 대상 IMA 측정값 자동 확장 커널 설정(`CONFIG_IMA_MEASURE_PCR_IDX=10`) 적용
  - [x] SoftHSM `ImaSigningKey`(ECDSA P-384) 기반 IMA 파일 서명 및 검증 파이프라인 연동
- [x] **5.4. 통합 검증 테스트**
  - [x] `tests/test_ftpm_ima.py` 내 Phase 5 스토리지 무결성 및 IMA 테스트 슈트 확장 완료 (전체 30개 단위 테스트 100% 통과)

---

### Phase 6: Secure World 기반 Cloud-Humanoid mTLS & Remote Attestation
- [x] **6.1. Secure World 키 생성 및 보관**
  - [x] SoftHSMv2 / OP-TEE PKCS#11 토큰 내 로봇 인증용 개인키(`HumanoidDeviceIdentityKey`, ECDSA P-256) 동적 생성 완료
  - [x] `DeviceEnrollmentCaKey`를 통한 장치 인증서(`humanoid_device.crt`) 및 CA 인증서(`DeviceEnrollmentCa.crt`) 발급 파이프라인 구축
  - [x] Normal World 파일시스템에 개인키 절대 노출 금지(Zero Plaintext Key) 감사 100% 통과
- [x] **6.2. OpenSSL 3.x Provider 연동 mTLS 클라이언트 구현**
  - [x] `apps/mtls_client/` 구현 완료 (OpenSSL 3.x `pkcs11-provider` 및 RFC 7512 `pkcs11:` URI 연동 mTLS 클라이언트/서버)
  - [x] Normal World 평문 개인키 없이 HSM 내부 서명을 통한 TLS 1.3 상호 인증(Mutual TLS) 핸드셰이크 실검증 완료
- [x] **6.3. Remote Attestation 에이전트 구현**
  - [x] `apps/attestation_agent/` 구현 완료 (fTPM/IMA 측정값 수집, Composite PCR 다이제스트 및 AK 서명 Quote 패키징)
  - [x] 원격 검증기(`verifier.py`) 구현 및 Nonce 재전송 공격(Replay Attack) 방어, dm-verity 서명 검증, IMA 로그 재생 일치 검증 완료
- [x] **6.4. CI/CD 전체 자동화 파이프라인 구성**
  - [x] `.github/workflows/ci_security_verify.yml` 업데이트 완료 (보안 패키지 설치, 무평문 키 감사, Archify 명세 검사, DevContainer 검사, Phase 2~6 전체 테스트)
  - [x] 로컬 및 CI 환경에서 Phase 2~6 전체 39개 통합 단위 테스트 100% 통과 확인 (39/39 OK)

---

## 📝 변경 기록 (Changelog)

- **2026-10-26**:
  - NVIDIA Jetson Tegra PKC Secure Boot 시뮬레이션 및 TrustZone Cold Boot 연동 완료:
    - QEMU PFLASH0(`flash0.bin`)을 통한 TF-A BL1/BL2/BL31 -> OP-TEE OS(Early fTPM TA) -> Linux Kernel(PSCI v1.1) 순차 연동 실기동 성공.
    - TF-A BL2 S-EL1 MMU 로깅 트랩 및 스택 확장 버그 픽스(`patches/tfa/0001-fix-qemu-bl2-mmu-and-stack.patch`).
    - SoftHSMv2 PKCS#11 RSA-3072(`SecureBootKey`) 기반 NVIDIA Jetson Tegra PKC 서명기(`scripts/sign_jetson_secureboot.sh`), SoC eFuse 모델(`configs/secureboot/tegra_fuses.json`), 512바이트 `NVD1` 인증 컨테이너 생성 및 변조 거부(Tamper-resistance) 검증.
    - 전체 46개 통합/단위 테스트(`tests/test_secureboot_chain.py` 포함) 100% 통과 확인 (46/46 OK).
  - Phase 6 완료: Secure World 기반 Cloud-Humanoid mTLS(`apps/mtls_client/`), OpenSSL 3.x PKCS#11 Provider 연동 TLS 1.3 상호 인증, TCG 원격 증명 에이전트 및 검증기(`apps/attestation_agent/`), CI/CD 파이프라인(`.github/workflows/ci_security_verify.yml`) 및 통합 테스트 슈트(`tests/test_secure_mtls.py`, 전체 39개 테스트 100% 통과) 구축 완료.
  - Phase 5 완료: 커널 보안 하드닝 및 EROFS + dm-verity 불변 루트 파일시스템 빌드 스크립트(`scripts/build_rootfs.sh`), SoftHSM PKCS#11 연동 Root Hash 서명 및 검증, IMA 정책 수립 및 자동화 검증 슈트(`tests/test_ftpm_ima.py`, 30/30 전체 테스트 100% 통과) 구축 완료.
  - Phase 4 완료: SoftHSMv2 기반 오프라인 키 관리 파이프라인(`keys_hsm/setup_softhsm.sh`), RFC 7512 PKCS#11 서명 헬퍼(`keys_hsm/sign_helper.sh`), 무평문 개인키 전수 감사 도구(`keys_hsm/audit_zero_keys.sh`) 및 자동화 테스트 슈트(`tests/test_hsm_keys.py`) 구축 완료.
  - Phase 3 완료: OP-TEE Core(`vexpress-qemu_armv8a`) 내 fTPM Early TA(`ms-tpm-20-ref`) 임베드(`tee-pager_v2.bin`), PKCS#11 TA(`fd02c9da-306c-48c7-a49c-bbd827ae86ee.ta`) 및 사용자 공간 클라이언트 라이브러리(`libteec.so`, `libckteec.so`), `tee-supplicant` 빌드 파이프라인 구축 완료.
  - 리눅스 커널 6.8 Noble 하드닝 빌드(`CONFIG_TCG_FTPM_TEE=y`, `CONFIG_TEE=y`, `CONFIG_OPTEE=y`, `CONFIG_EROFS_FS=y`, `CONFIG_IMA=y`) 로컬 컴파일 성공 및 서명 모듈 생성 완료.
  - QEMU 최소 런타임 램디스크(`initramfs_minimal.cpio.gz`) 내 `tee-supplicant` 및 fTPM 검증 자동화 연동.
  - Phase 3 종합 단위 테스트 슈트(`tests/test_ftpm_ima.py`) 구축 및 로컬 실검증(15/15 Pass) 100% 통과 확인.
- **2026-10-25**:
  - Phase 0 완료: 저장소 기초 설정(`.gitignore`, `README.md`, `AGENTS.md`) 및 마스터 설계 문서 완성(`roadmap_checklist.md`, `requirements.md`, `architecture.md`, `key_management_hsm.md`, `threat_model.md`).
  - Archify 전환: 모든 다이어그램을 검증 기반의 인터랙티브 HTML 아티팩트(`docs/diagrams/*.html`) 및 독립형 고화질 SVG(`docs/diagrams/*.svg`)로 생성 및 문서 임베드.
  - Starlight 문서화 포털: `linux-kernel-hardening-lab` 스타일의 사이버펑크 네온 테마를 적용한 Astro Starlight 포털(`starlight/`) 및 GitHub Pages 자동 배포 CI(`.github/workflows/deploy_docs.yml`) 구축 완료.
  - Phase 1 완료: VS Code Dev Container 및 Docker 빌드/캐시 환경 구축 완료 (`docker/Dockerfile`, `docker/docker-compose.yml`, `docker/entrypoint.sh`, `.devcontainer/devcontainer.json`, `scripts/env_container.sh`).
  - Phase 2 완료: NVIDIA L4T 공식 소스 확보 스크립트(`scripts/fetch_l4t_sources.sh`), Dual-Target 커널 설정 및 빌드 파이프라인(`configs/kernel/`, `scripts/build_kernel.sh`), TF-A & OP-TEE 빌드(`configs/optee/`, `scripts/build_tfa_optee.sh`), QEMU 실행 러너(`scripts/run_qemu.sh`) 및 검증 테스트(`tests/test_boot_optee.py`) 구축 완료.
