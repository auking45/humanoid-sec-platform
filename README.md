# Humanoid Security Platform (`humanoid-sec-platform`)

> **QEMU-based security verification & hardening platform for NVIDIA Jetson humanoid robots (L4T, OP-TEE, fTPM, dm-verity/IMA, PKCS#11 HSM, and Secure World mTLS).**

[![CI Security Verification](https://github.com/auking45/humanoid-sec-platform/actions/workflows/ci_security_verify.yml/badge.svg)](https://github.com/auking45/humanoid-sec-platform/actions/workflows/ci_security_verify.yml)
[![Deploy Documentation](https://github.com/auking45/humanoid-sec-platform/actions/workflows/deploy_docs.yml/badge.svg)](https://github.com/auking45/humanoid-sec-platform/actions/workflows/deploy_docs.yml)
[![Documentation Portal](https://img.shields.io/badge/Docs-Starlight%20Portal-00f0ff.svg)](https://auking45.github.io/humanoid-sec-platform/)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![Dev Container](https://img.shields.io/badge/Dev%20Container-Ready-green?logo=visualstudiocode)](.devcontainer/devcontainer.json)

🌐 **[English Documentation](docs/en/README.md)** | **[공식 기술 문서 포털 (Starlight)](https://auking45.github.io/humanoid-sec-platform/)**

---

## 1. 개요 (Overview)

- **배경**: 차세대 휴머노이드 로봇은 AI 제어 컴퓨터(NVIDIA Jetson AGX Orin/Thor)를 탑재하고 물리 환경에서 직접 구동됨에 따라, 물리적 침해 및 공급망 공격, 비인가 제어 명령 주입 방지를 위한 **심층 방어(Defense-in-Depth)** 보안 아키텍처 필수 요구.
- **플랫폼 목적**: 실물 하드웨어 보드 없이도 CI/CD 파이프라인 및 로컬 개발 환경에서 NVIDIA JetPack(L4T) 기반 보안 설계를 100% 동일하게 에뮬레이션 및 사전 검증하는 QEMU `aarch64` (`virt` 머신) 기반 보안 검증 플랫폼.

---

## 2. 핵심 아키텍처 및 보안 기능 (Key Architecture & Features)

[![Humanoid Security Platform Architecture](docs/diagrams/system_architecture.svg)](docs/diagrams/system_architecture.html)
> 💡 *이미지 클릭 시 [Archify 인터랙티브 뷰어 (HTML)](docs/diagrams/system_architecture.html)로 이동하여 테마 전환, 경로 트레이싱, 컴포넌트 포커스 기능 지원.*

- **공식 L4T 소스 기반 (Official L4T Source Integration)**:
  - NVIDIA JetPack 7.2.1 (Jetson Linux R39.2.1, Linux Kernel 6.8, Ubuntu 24.04 Noble, Jetson Thor & Orin) 공식 Kernel, OP-TEE, Sample Rootfs 기반 구축.
- **Dual-Target 커널 설정 체계**:
  - `[L4T 기본 defconfig]` + `[security_hardening.config]` + `[qemu_compat.config]` 분리 설계를 통해 실물 보드와 100% 보안 정책 호환성 유지.
- **OP-TEE 기반 fTPM & PKCS#11 TA**:
  - Microsoft Reference Implementation (`ms-tpm-20-ref`) fTPM TA 및 OP-TEE `pkcs11` TA 탑재, QEMU 가상 RPMB 스토리지 연동.
- **스토리지 및 런타임 무결성 (EROFS + dm-verity + IMA)**:
  - 고성능 압축 읽기 전용 파일시스템(`EROFS`) + `dm-verity` 블록 해시 트리 암호 서명 검증.
  - 리눅스 `IMA`를 통한 실행 바이너리 무결성 측정 및 fTPM PCR 10 확장 기록.
- **Zero Plaintext Key 정책 & SoftHSMv2**:
  - 코드베이스 내 평문 개인키(`.pem`, `.key`) 저장 전면 배제.
  - 오프라인 서명키는 SoftHSMv2(PKCS#11) 토큰 내부 생성 및 RFC 7512 `pkcs11:` URI 참조.
- **Secure World 기반 Cloud-Humanoid mTLS**:
  - Normal World 파일시스템에 개인키 비노출 원칙 준수.
  - OP-TEE PKCS#11 TA 내부 장치 키 격리 보관 및 OpenSSL 3.x Provider 연동 상호 인증 수행.

---

## 3. 빠른 시작 (Quick Start)

### 3.1. 사전 준비 (Prerequisites)
- Docker 24.0+ 및 Docker Compose v2.x
- VS Code 및 [Dev Containers 확장 프로그램](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) (권장)

### 3.2. VS Code Dev Container 실행 (권장)
1. VS Code에서 본 레포지토리 오픈.
2. `F1` 키 입력 후 `Dev Containers: Reopen in Container` 선택.
3. 컨테이너 내부 자동 구성 완료:
   - `aarch64-linux-gnu-gcc` 크로스 툴체인
   - QEMU `aarch64` 에뮬레이터 (`virt` 머신, RPMB 가상화)
   - SoftHSMv2, `tpm2-tools`, `erofs-utils`, `ccache` (20GB 캐시 볼륨)

### 3.3. 호스트 CLI 환경 실행
```bash
# 컨테이너 환경 래퍼 스크립트를 통한 실행
./scripts/env_container.sh make help
```

---

## 4. 디렉토리 구조 (Directory Layout)

```text
.
├── AGENTS.md                       # AI 에이전트 작업 지침, 아키텍처 요약 및 커밋/문서화 원칙
├── README.md                       # 프로젝트 소개, 빠른 시작, 아키텍처 개요
├── .gitignore                      # 캐시, 빌드 아티팩트, 평문 키 제외 설정
├── .devcontainer/                  # VS Code Dev Container 정의
├── docker/                         # 빌드 및 CI 공용 Dockerfile & Compose
├── docs/                           # 마스터 체크리스트, SRD, 아키텍처, 키 관리, 위협 모델 (국문)
│   ├── en/                         # 영문 공식 문서 (English Documentation)
│   └── diagrams/                   # Archify 검증 다이어그램 (JSON-IR, HTML, SVG)
├── starlight/                      # Astro Starlight 공식 기술 문서 포털 (사이버펑크 네온 테마)
├── tools/
│   └── archify/                    # Archify CLI 렌더러 및 SVG 추출 도구
├── scripts/                        # 소스 다운로드, 빌드, QEMU 실행 래퍼
├── configs/                        # 커널 및 OP-TEE 빌드 설정 fragments
├── keys_hsm/                       # SoftHSMv2 토큰 초기화 및 PKCS#11 서명 헬퍼
├── apps/                           # mTLS 클라이언트 및 Attestation 에이전트 소스
└── tests/                          # QEMU 기반 pytest E2E 보안 자동화 검증
```

---

## 5. 상세 문서 링크 (Documentation Links)

| 문서명 | 국문 (Korean) | 영문 (English) |
| :--- | :--- | :--- |
| **마스터 실행 체크리스트** | [roadmap_checklist.md](docs/roadmap_checklist.md) | [roadmap_checklist.md](docs/en/roadmap_checklist.md) |
| **보안 요구사항 명세서** | [requirements.md](docs/requirements.md) | [requirements.md](docs/en/requirements.md) |
| **시스템 아키텍처 명세서** | [architecture.md](docs/architecture.md) | [architecture.md](docs/en/architecture.md) |
| **키 관리 및 HSM/mTLS 아키텍처** | [key_management_hsm.md](docs/key_management_hsm.md) | [key_management_hsm.md](docs/en/key_management_hsm.md) |
| **휴머노이드 위협 모델링** | [threat_model.md](docs/threat_model.md) | [threat_model.md](docs/en/threat_model.md) |
| **Archify 다이어그램 컬렉션** | [docs/diagrams/](docs/diagrams/) | [docs/diagrams/](docs/diagrams/) |

---

## 6. 라이선스 (License)

본 프로젝트는 [Apache-2.0 License](LICENSE) 하에 배포됨.
