# Humanoid Security Platform — Master Roadmap & Execution Checklist

> **Single Source of Truth (SSOT)**: 본 문서는 프로젝트의 전체 실행 계획, 단계별 세부 작업 및 검증 상태를 추적하는 마스터 체크리스트임. 각 작업 완료 시 체크박스 `[x]`와 검증 결과를 기록함.

---

## 📊 전체 진행 현황 요약 (Progress Overview)

| 단계 (Phase) | 단계명 | 목표 및 범위 | 상태 |
| :--- | :--- | :--- | :---: |
| **Phase 0** | 전체 아키텍처 및 상세 설계 | SRD 요구사항, 아키텍처, 키 관리, 위협 모델, 마스터 체크리스트 작성 | 🟢 완료 |
| **Phase 1** | DevContainer & Docker 환경 | VS Code Dev Container, Dockerfile, docker-compose, env wrapper | 🟢 완료 |
| **Phase 2** | L4T 소스 확보 & QEMU 기본 부팅 | L4T R36.x 다운로드, TF-A + OP-TEE + L4T 커널 QEMU 부팅 | 🟢 완료 |
| **Phase 3** | OP-TEE fTPM & PKCS#11 TA 통합 | ms-tpm-20-ref fTPM TA, pkcs11 TA, QEMU RPMB 스토리지 연동 | 🟡 다음 예정 |
| **Phase 4** | SoftHSMv2 키 관리 파이프라인 | SoftHSM 토큰 초기화, Zero-Plaintext 키 생성, PKCS#11 서명 헬퍼 | ⚪ 대기 |
| **Phase 5** | 커널 하드닝 & 스토리지/런타임 무결성 | KSPP 커널 하드닝, EROFS + dm-verity, IMA fTPM PCR 확장 | ⚪ 대기 |
| **Phase 6** | Secure World mTLS & Attestation | OP-TEE PKCS#11/fTPM 기반 mTLS 클라이언트, Remote Attestation | ⚪ 대기 |

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
- [ ] **5.1. 커널 하드닝 설정 적용**
  - [ ] `configs/kernel/security_hardening.config` 작성 (KSPP 권고안: 모듈 서명 강제, 스택 프로텍터, 주소 공간 난수화, 무단 메모리 접근 차단 등)
- [ ] **5.2. EROFS + dm-verity 불변 루트 파일시스템 빌드**
  - [ ] `scripts/build_rootfs.sh` 작성 (L4T Sample Rootfs 기반 EROFS 압축 이미지 생성)
  - [ ] `veritysetup`으로 해시 트리 생성, SoftHSM 키로 Root Hash 서명
  - [ ] 커널 명령행(cmdline) 또는 Initramfs에서 dm-verity 무결성 검증 후 마운트
- [ ] **5.3. IMA (Integrity Measurement Architecture) 및 fTPM PCR 확장**
  - [ ] IMA 정책 구성 (`ima_policy=tcb`, 실행 파일 및 모듈 측정)
  - [ ] fTPM PCR 10에 IMA 측정값 자동 확장 검증
- [ ] **5.4. 통합 검증 테스트**
  - [ ] `tests/test_ftpm_ima.py` 작성 및 자동 실행 (변조된 파일 실행 시도시 차단 및 PCR 측정 기록 검증)

---

### Phase 6: Secure World 기반 Cloud-Humanoid mTLS & Remote Attestation
- [ ] **6.1. Secure World 키 생성 및 보관**
  - [ ] OP-TEE PKCS#11 TA 또는 fTPM 내부에서 로봇 인증용 개인키 동적 생성
  - [ ] Normal World 파일시스템에 개인키 절대 노출 금지 확인
- [ ] **6.2. OpenSSL 3.x Provider 연동 mTLS 클라이언트 구현**
  - [ ] `apps/mtls_client/` 구현 (OpenSSL 3.x `pkcs11-provider` 또는 `tpm2-openssl` 연동 C / Python 클라이언트)
  - [ ] Secure World 내부 서명 연산을 통한 Cloud 서버와의 상호 TLS(mTLS) 통신 검증
- [ ] **6.3. Remote Attestation 에이전트 구현**
  - [ ] `apps/attestation_agent/` 구현 (fTPM Quote 생성 + AK 서명 + IMA Event Log 패키징)
  - [ ] Verifier 서비스에 제출하여 부팅 무결성 및 시스템 상태 원격 검증
- [ ] **6.4. CI/CD 전체 자동화 파이프라인 구성**
  - [ ] `.github/workflows/ci_security_verify.yml` 작성
  - [ ] Headless QEMU 상에서 Phase 2~6 전체 보안 스펙 자동 테스트 (pytest) 통과 확인

---

## 📝 변경 기록 (Changelog)

- **2026-10-26**:
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
