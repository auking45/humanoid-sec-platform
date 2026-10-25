# AGENTS.md — Humanoid Security Platform (`humanoid-sec-platform`)

> **Description**: QEMU-based security verification & hardening platform for NVIDIA Jetson humanoid robots (L4T, OP-TEE, fTPM, dm-verity/IMA, PKCS#11 HSM, and Secure World mTLS).

## 1. 프로젝트 개요 (Project Overview)
본 프로젝트는 **NVIDIA Jetson 기반 휴머노이드 로봇**의 시스템 보안을 설계, 문서화, 구현 및 CI/CD 환경에서 자동 검증하기 위한 플랫폼임. 실제 하드웨어 보드 없이도 핵심 보안 기능(Secure Boot, Kernel Hardening, OP-TEE, fTPM, Remote Attestation, Storage Integrity, Secure mTLS)을 **QEMU `aarch64` (`virt` 머신)** 환경에서 검증하며, 모든 소스코드는 **NVIDIA JetPack(L4T) 공식 릴리스 소스**를 기반으로 구축함.

---

## 2. 최우선 작업 원칙 (Golden Rules for AI Agents)

1. **설계 및 문서화 우선 (Design & Documentation First)**
   - 코드 작성 전 전체 아키텍처, 위협 모델, 키 계층 구조, 상세 요구사항 및 마스터 실행 체크리스트(`docs/roadmap_checklist.md`) 문서화 완료 필수.
   - 신규 기능 추가 또는 설계 변경 시 관련 문서(`docs/`, `docs/en/`)를 선행(또는 동시) 업데이트함.
2. **체크리스트 기반 단계별 진행 (Checklist-Driven Execution)**
   - 마스터 플랜 수립 후 `docs/roadmap_checklist.md`의 항목을 순차 진행하며 완료 시 `[x]` 체크 및 검증 결과 기록.
3. **작고 원자적인 커밋 (Small, Atomic Git Commits)**
   - 다수 작업 또는 다단계 파일의 일괄 커밋 금지.
   - **논리적 최소 단위**(예: 문서 1건, 설정 파일 1건, 스크립트 1건 등) 완료 시마다 문법/동작 검증 후 즉시 개별 커밋함.
   - 커밋 메시지는 Conventional Commits(`docs:`, `build:`, `feat:`, `test:`, `ci:`) 형식을 준수함.
4. **VS Code Dev Container & CI/CD 단일 환경 (DevContainer & Container-First)**
   - 개발자는 **VS Code Dev Containers (`.devcontainer/`)**를 통해 컨테이너 내부에서 개발/빌드/디버깅 수행. CI/CD 또한 동일한 `docker/Dockerfile` 및 `docker/docker-compose.yml`을 공유하여 환경 차이 원천 배제.
   - 대용량 L4T 원본 타르볼(`.cache/downloads`), 소스 트리(`sources/`), 빌드 캐시(`.cache/ccache`, `build/`), SoftHSM 토큰(`.cache/softhsm`)을 호스트 볼륨으로 분리하여 재다운로드 및 재빌드 방지.
5. **평문 비밀키 커밋 절대 금지 (Zero Plaintext Key Policy)**
   - 테스트용 목적이라도 `.pem`, `.key` 평문 개인키 파일의 커밋을 엄격히 금지함. 모든 오프라인 서명키는 SoftHSMv2(PKCS#11) 토큰 내부에서 동적 생성하고 `pkcs11:` URI로만 참조함.
6. **Archify 기반 시각화 다이어그램 표준 (Archify-First Visual Documentation)**
   - 시스템 아키텍처, 부팅 시퀀스, 키 계층, 통신 프로토콜, 위협 모델 다이어그램은 **Archify (`tt-a1i/archify`)**를 표준 도구로 사용함.
   - 다이어그램 생성 시 다음 3대 아티팩트를 세트로 동시 유지 및 관리함:
     1. **타입 검증된 JSON-IR (`docs/diagrams/*.json`)**: 다이어그램 원본 모델 및 레이아웃 명세
     2. **인터랙티브 독립형 HTML (`docs/diagrams/*.html`)**: 브라우저 기반 동적 탐색기 (테마 전환, 줌, 트레이스)
     3. **독립형 벡터 SVG (`docs/diagrams/*.svg`)**: 마크다운 문서 및 웹사이트 인라인 임베드용 고화질 벡터 이미지
   - 마크다운 문서(`docs/*.md`, `README.md`)에는 `[![Title](diagrams/xxx.svg)](diagrams/xxx.html)` 형식으로 임베드하여 인라인 확인 및 클릭 시 풀스크린 인터랙티브 뷰어로 전환되도록 구성함.
7. **개조식 및 명사형 종결 문체 원칙 (Bullet & Noun-Ending Technical Writing)**
   - 모든 기술 문서(`docs/*.md`, `README.md`, `starlight/`)는 구어체/경어체(`~합니다`, `~입니다`)를 전면 배제함.
   - 간결하고 명확한 기술 명세를 위해 **개조식(Bullet Points) 및 명사형 종결 어미(`~함`, `~임`, `~구축`, `~적용`, `~보장`, `~제공`, `~수행`, `~검증`)**를 엄격히 준수함.
8. **국문/영문 다국어 문서화 표준 (Bilingual i18n Documentation)**
   - 모든 핵심 설계 및 기술 문서는 국문(`docs/*.md`)과 영문(`docs/en/*.md`)을 대칭적으로 작성 및 유지 관리함.
   - Astro Starlight 공식 문서 포털(`starlight/`)의 i18n 언어 선택기(Language Switcher)를 통해 국문/영문 문서를 완벽히 상호 전환 가능하도록 구성함.

---

## 3. 권장 디렉토리 구조 (Repository Layout)

```text
.
├── AGENTS.md                       # AI 에이전트 작업 지침, 아키텍처 요약 및 커밋/문서화 원칙
├── README.md                       # 프로젝트 소개, 빠른 시작(DevContainer & CLI), 아키텍처 개요
├── .gitignore                      # 빌드 아티팩트, 캐시, L4T 소스, 평문 키 파일 제외 설정
├── .devcontainer/
│   └── devcontainer.json           # VS Code Dev Container 설정 (docker-compose 연동, 추천 익스텐션 포함)
├── docker/
│   ├── Dockerfile                  # 크로스 툴체인, QEMU, SoftHSMv2, tpm2-tools, erofs-utils, ccache 포함
│   ├── docker-compose.yml          # DevContainer 및 CI 공용 컨테이너/볼륨 마운트 정의
│   └── entrypoint.sh               # 컨테이너 진입점 (권한 매핑, ccache, SoftHSM 토큰 디렉토리 초기화)
├── .github/workflows/
│   ├── ci_security_verify.yml      # 컨테이너 기반 자동 빌드 및 Headless QEMU 보안 검증 파이프라인
│   └── deploy_docs.yml             # Astro Starlight 문서 포털 GitHub Pages 자동 배포 파이프라인
├── docs/
│   ├── roadmap_checklist.md        # 전체 단계별 마스터 플랜 및 진행 상황 체크리스트 (Single Source of Truth)
│   ├── requirements.md             # 상세 보안 요구사항 명세서 (SRD - 번호 부여 및 테스트 매핑)
│   ├── architecture.md             # 부팅 체인, Trust Boundary, 하드닝, EROFS/dm-verity/IMA 아키텍처
│   ├── key_management_hsm.md       # SoftHSMv2(오프라인) & OP-TEE PKCS#11/fTPM(런타임) 키 계층 및 mTLS 설계
│   ├── threat_model.md             # 휴머노이드 로봇 위협 모델링 (STRIDE) 및 보안 통제 매핑
│   └── diagrams/                   # Archify 검증 다이어그램 (JSON-IR 명세, 인터랙티브 HTML, 독립형 SVG)
├── starlight/                      # Astro Starlight 기반 공식 기술 문서 포털 (사이버펑크 네온 테마)
├── tools/
│   └── archify/                    # Archify CLI 렌더러, SVG 추출기 및 스키마 검증기
├── scripts/
│   ├── env_container.sh            # 호스트 CLI에서 컨테이너 내부 명령을 실행하는 래퍼 스크립트
│   ├── sync_docs_to_starlight.py   # docs/ 마크다운 및 다이어그램 에셋을 Starlight로 자동 동기화
│   ├── fetch_l4t_sources.sh        # NVIDIA 공식 L4T BSP/Public Sources/Rootfs 다운로드 및 SHA256 캐시 검증
│   ├── build_tfa_optee.sh          # TF-A + OP-TEE (fTPM TA, PKCS#11 TA 포함) 빌드 스크립트
│   ├── build_kernel.sh             # L4T 커널 + 보안 하드닝/QEMU 호환 config fragment 병합 및 빌드
│   ├── build_rootfs.sh             # EROFS 이미지 생성, dm-verity 해시 트리 생성 및 서명, initramfs 패키징
│   └── run_qemu.sh                 # QEMU(virt, secure=on, RPMB 에뮬레이션, 네트워크 포워딩) 실행 스크립트
├── configs/
│   ├── kernel/
│   │   ├── qemu_compat.config      # QEMU virt 머신 부팅용 디바이스 드라이버 fragment
│   │   └── security_hardening.config # KSPP 하드닝, 모듈 서명, fTPM, dm-verity, EROFS, IMA/EVM fragment
│   └── optee/
│       └── ftpm_pkcs11.conf        # OP-TEE 빌드 옵션 (CFG_PKCS11_TA=y, Early fTPM TA 등)
├── keys_hsm/
│   ├── setup_softhsm.sh            # SoftHSMv2 토큰 초기화 및 PKCS#11 서명키(SecureBoot/Kernel/IMA/Verity) 생성
│   └── sign_helper.sh              # PKCS#11 URI 기반 서명 유틸리티 래퍼
├── apps/
│   ├── mtls_client/                # OP-TEE PKCS#11 TA / fTPM 연동 OpenSSL 3.x Provider 기반 mTLS 클라이언트
│   └── attestation_agent/          # fTPM Quote + IMA 로그 수집 및 원격 검증(Verifier) 테스트 에이전트
└── tests/
    ├── test_boot_optee.py          # QEMU 부팅, OP-TEE 로드 및 xtest 자동 검증 (pytest + pexpect)
    ├── test_ftpm_ima.py            # /dev/tpmrm0 인식, PCR 확장, IMA 측정 및 dm-verity 마운트 검증
    └── test_secure_mtls.py         # Secure World 내부 키를 이용한 Cloud-Humanoid mTLS 핸드셰이크 검증
```

---

## 4. 단계별 마스터 로드맵 (Phased Execution Plan)

- **Phase 0: 전체 설계 및 상세 문서화 (`docs/*`, `docs/en/*`)**
  - 코드 작성 전 요구사항(SRD), 시스템 아키텍처, 키 관리/HSM 설계, 위협 모델, 마스터 체크리스트 국/영문 완성.
  - Archify 기반 6대 핵심 다이어그램(JSON-IR, HTML, SVG) 구축 및 Starlight 기술 문서 포털 연동.
- **Phase 1: VS Code Dev Container & Docker 빌드/캐시 환경 구축 (`.devcontainer/`, `docker/`)**
  - 로컬 DevContainer와 CI 환경에서 동일하게 동작하는 크로스 컴파일 및 QEMU 에뮬레이션 컨테이너 환경 구축.
- **Phase 2: NVIDIA L4T 공식 소스 확보 및 QEMU 베이스 부팅 (`scripts/fetch_*`, `build_*`, `run_qemu.sh`)**
  - L4T 공식 커널/OP-TEE 소스 확보 후 QEMU(`virt`, `secure=on`)에서 TF-A -> OP-TEE -> L4T Kernel -> Initramfs 베이스라인 부팅 검증.
- **Phase 3: OP-TEE fTPM TA & PKCS#11 TA 통합**
  - `ms-tpm-20-ref` fTPM 및 OP-TEE `pkcs11` TA 탑재, QEMU RPMB 연동, 리눅스 `/dev/tpmrm0` 및 `pkcs11-tool` 동작 검증.
- **Phase 4: SoftHSMv2 키 관리 파이프라인 구축 (`keys_hsm/`)**
  - SoftHSMv2 기반 오프라인 서명키 생성 및 RFC 7512 PKCS#11 URI 서명 헬퍼 구현.
- **Phase 5: 커널 하드닝 및 EROFS + dm-verity + IMA 무결성 검증**
  - KSPP 커널 하드닝 적용, SoftHSM 키로 커널 모듈/dm-verity/IMA 서명, 부팅 무결성 검증 및 fTPM PCR 확장 확인.
- **Phase 6: Secure World 기반 mTLS 및 Remote Attestation 구현 (`apps/`, `tests/`)**
  - Normal World 개인키 노출 없이 OP-TEE(PKCS#11 TA/fTPM)와 OpenSSL 3.x Provider를 연동한 mTLS 통신 및 Attestation E2E 자동 테스트 완성.
