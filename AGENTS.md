# AGENTS.md — Humanoid Security Platform (`humanoid-sec-platform`)

> **Description**: QEMU-based security verification & hardening platform for NVIDIA Jetson humanoid robots (L4T, OP-TEE, fTPM, dm-verity/IMA, PKCS#11 HSM, and Secure World mTLS).

## 1. 프로젝트 개요 (Project Overview)
본 프로젝트는 **NVIDIA Jetson 기반 휴머노이드 로봇**의 시스템 보안을 설계, 문서화, 구현 및 CI/CD 환경에서 자동 검증하기 위한 레포지토리입니다. 실제 하드웨어 보드 없이도 핵심 보안 기능(Secure Boot, Kernel Hardening, OP-TEE, fTPM, Remote Attestation, Storage Integrity, Secure mTLS)을 **QEMU `aarch64` (`virt` 머신)** 환경에서 검증하며, 모든 소스코드는 **NVIDIA JetPack(L4T) 공식 릴리스 소스**를 기반으로 합니다.

---

## 2. 최우선 작업 원칙 (Golden Rules for AI Agents)

1. **설계 및 문서화 우선 (Design & Documentation First)**
   - 코드를 한 줄이라도 작성하기 전에 전체 아키텍처, 위협 모델, 키 계층 구조, 상세 요구사항 및 마스터 실행 체크리스트(`docs/roadmap_checklist.md`)를 먼저 철저히 문서화합니다.
   - 새로운 기능을 추가하거나 설계를 변경할 때는 반드시 관련 문서(`docs/`)를 먼저(또는 동시에) 업데이트합니다.
2. **체크리스트 기반 단계별 진행 (Checklist-Driven Execution)**
   - 전체 마스터 플랜을 세운 뒤, `docs/roadmap_checklist.md`의 항목을 하나씩 진행하며 완료 시 `[x]`로 체크하고 검증 결과를 기록합니다.
3. **작고 원자적인 커밋 (Small, Atomic Git Commits)**
   - 여러 작업이나 여러 단계의 파일을 한꺼번에 묶어서 커밋하지 않습니다.
   - **하나의 논리적 최소 단위**(예: 문서 1개 작성, `.devcontainer` 설정 추가, 다운로드 스크립트 1개 구현 등)가 끝날 때마다 문법/동작 검증 후 즉시 분리하여 커밋합니다.
   - 커밋 메시지는 Conventional Commits(`docs:`, `build(devcontainer):`, `feat(l4t):`, `feat(optee):`, `feat(hsm):`, `test(qemu):`, `ci:`) 형식을 엄격히 준수합니다.
4. **VS Code Dev Container & CI/CD 단일 환경 (DevContainer & Container-First)**
   - 로컬 개발자는 **VS Code Dev Containers (`.devcontainer/`)**를 통해 컨테이너 내부에서 바로 개발/빌드/디버깅하고, CI/CD는 동일한 `docker/Dockerfile` 및 `docker/docker-compose.yml`을 공유하여 환경 차이를 원천 차단합니다.
   - 대용량 L4T 원본 타르볼(`.cache/downloads`), 소스 트리(`sources/`), 빌드 캐시(`.cache/ccache`, `build/`), SoftHSM 토큰(`.cache/softhsm`)은 볼륨으로 분리하여 재다운로드 및 전체 재빌드를 방지합니다.
5. **평문 비밀키 커밋 절대 금지 (Zero Plaintext Key Policy)**
   - 테스트용이라도 `.pem`, `.key` 개인키 파일을 레포지토리에 커밋하지 않습니다. 모든 오프라인 서명키는 SoftHSMv2(PKCS#11) 내부에서 동적 생성하고 `pkcs11:` URI로만 참조합니다.

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
│   └── ci_security_verify.yml      # 컨테이너 기반 자동 빌드 및 Headless QEMU 보안 검증 파이프라인
├── docs/
│   ├── roadmap_checklist.md        # 전체 단계별 마스터 플랜 및 진행 상황 체크리스트 (Single Source of Truth)
│   ├── requirements.md             # 상세 보안 요구사항 명세서 (SRD - 번호 부여 및 테스트 매핑)
│   ├── architecture.md             # 부팅 체인, Trust Boundary, 하드닝, EROFS/dm-verity/IMA 아키텍처
│   ├── key_management_hsm.md       # SoftHSMv2(오프라인) & OP-TEE PKCS#11/fTPM(런타임) 키 계층 및 mTLS 설계
│   └── threat_model.md             # 휴머노이드 로봇 위협 모델링 (STRIDE) 및 보안 통제 매핑
├── scripts/
│   ├── env_container.sh            # 호스트 CLI에서 컨테이너 내부 명령을 실행하는 래퍼 스크립트
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

- **Phase 0: 전체 설계 및 상세 문서화 (`docs/*`)**
  - 코드 작성 전 요구사항, 시스템 아키텍처, 키 관리/HSM 설계, 위협 모델, 마스터 체크리스트 문서 완성.
- **Phase 1: VS Code Dev Container & Docker 빌드/캐시 환경 구축 (`.devcontainer/`, `docker/`)**
  - 로컬 VS Code Dev Container와 CI에서 동일하게 동작하는 컨테이너 환경 구축 및 검증.
- **Phase 2: NVIDIA L4T 공식 소스 확보 및 QEMU 베이스 부팅 (`scripts/fetch_*`, `build_*`, `run_qemu.sh`)**
  - L4T 커널/OP-TEE 소스를 받아 QEMU(`virt`, `secure=on`)에서 TF-A -> OP-TEE -> L4T Kernel -> Initramfs 부팅 성공.
- **Phase 3: OP-TEE fTPM TA & PKCS#11 TA 통합**
  - `ms-tpm-20-ref` fTPM 및 OP-TEE `pkcs11` TA 탑재, QEMU RPMB 연동, Linux에서 `/dev/tpmrm0` 및 `pkcs11-tool` 동작 확인.
- **Phase 4: SoftHSMv2 키 관리 파이프라인 구축 (`keys_hsm/`)**
  - SoftHSMv2 기반 오프라인 서명키 생성 및 PKCS#11 서명 헬퍼 구현.
- **Phase 5: 커널 하드닝 및 EROFS + dm-verity + IMA 무결성 검증**
  - 커널 하드닝 fragment 적용, SoftHSM 키로 커널 모듈/dm-verity/IMA 서명, 부팅 시 무결성 검증 및 fTPM PCR 확장 확인.
- **Phase 6: Secure World 기반 mTLS 및 Remote Attestation 구현 (`apps/`, `tests/`)**
  - Normal World에 개인키 노출 없이 OP-TEE(PKCS#11 TA 또는 fTPM)와 OpenSSL 3.x Provider를 연동한 mTLS 통신 및 Attestation E2E 자동 테스트 완성.
