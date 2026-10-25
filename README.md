# Humanoid Security Platform (`humanoid-sec-platform`)

> **QEMU-based security verification & hardening platform for NVIDIA Jetson humanoid robots (L4T, OP-TEE, fTPM, dm-verity/IMA, PKCS#11 HSM, and Secure World mTLS).**

[![CI Security Verification](https://github.com/auking45/humanoid-sec-platform/actions/workflows/ci_security_verify.yml/badge.svg)](https://github.com/auking45/humanoid-sec-platform/actions)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![Dev Container](https://img.shields.io/badge/Dev%20Container-Ready-green?logo=visualstudiocode)](.devcontainer/devcontainer.json)

---

## 1. 개요 (Overview)

차세대 **휴머노이드 로봇(Humanoid Robot)**은 고성능 인공지능 제어 컴퓨터(NVIDIA Jetson AGX Orin / Thor 등)를 탑재하고 실제 물리 환경과 상호작용합니다. 물리적 침해(Physical Access) 및 공급망 공격, 악의적 제어 명령 주입 등으로부터 로봇을 안전하게 보호하기 위해서는 하드웨어 루트 오브 트러스트(Hardware Root of Trust)부터 커널, 스토리지, 클라우드 통신 채널에 이르는 **심층 방어(Defense-in-Depth)** 보안 체계가 필수적입니다.

본 프로젝트는 **실물 하드웨어 보드 없이도 CI/CD 파이프라인 및 개발 환경에서 NVIDIA JetPack (L4T) 기반 보안 설계를 100% 동일하게 에뮬레이션 및 검증**할 수 있는 QEMU `aarch64` (`virt` 머신) 기반 보안 하드닝 및 검증 플랫폼입니다.

---

## 2. 핵심 아키텍처 및 보안 기능 (Key Architecture & Features)

> 🌐 **[Archify 인터랙티브 시스템 아키텍처 다이어그램 열기 (HTML)](docs/diagrams/system_architecture.html)**  
> *(다크/라이트 모드, 경로 트레이싱, 컴포넌트 포커스 및 SVG/PNG 내보내기 지원)*

```text
 ┌────────────────────────────────────────────────────────────────────────┐
 │ Hardware & QEMU Virt: BootROM (EL3 RoT) ─── Virtual eMMC RPMB Storage   │
 └──────────────────────────────────┬─────────────────────────────────────┘
                                    │ Cryptographic Verification
 ┌──────────────────────────────────▼─────────────────────────────────────┐
 │ TrustZone Secure World: TF-A (BL31) ── OP-TEE Core (S-EL1)             │
 │                         └── fTPM 2.0 TA & PKCS#11 TA (Secure SRAM)     │
 └──────────────────────────────────┬─────────────────────────────────────┘
                                    │ SMC /dev/tee0 & TCG Driver
 ┌──────────────────────────────────▼─────────────────────────────────────┐
 │ Normal World (Linux):   Hardened L4T Linux Kernel 6.x (KSPP / IMA)     │
 │                         ├── Read-Only EROFS + dm-verity Rootfs         │
 │                         ├── Cloud-Humanoid mTLS Client (OpenSSL 3.x)   │
 │                         └── Remote Attestation Agent (tpm2-tools)      │
 └──────────────────────────────────┬─────────────────────────────────────┘
                                    │ TLS 1.3 mTLS & Remote Quote
 ┌──────────────────────────────────▼─────────────────────────────────────┐
 │ Cloud Infrastructure:   Cloud Fleet Manager & Remote Attest Verifier   │
 └────────────────────────────────────────────────────────────────────────┘
```

- **공식 L4T 소스 기반 (Official L4T Source Integration)**:
  - NVIDIA JetPack 6.x (L4T R36.x) 공식 Kernel, OP-TEE, Rootfs 소스를 사용합니다.
- **Dual-Target 커널 설정 전략**:
  - `[L4T 기본 defconfig]` + `[security_hardening.config]` + `[qemu_compat.config]` 분리 설계를 적용하여 QEMU에서 검증된 보안 정책을 실물 보드에 1:1 무수정 이식할 수 있습니다.
- **OP-TEE 기반 fTPM & PKCS#11 TA**:
  - Microsoft Reference Implementation (`ms-tpm-20-ref`) fTPM TA와 OP-TEE `pkcs11` TA를 탑재하여 QEMU 가상 RPMB 스토리지에 보안 상태를 보관합니다.
- **스토리지 및 런타임 무결성 (EROFS + dm-verity + IMA)**:
  - 고성능 압축 파일시스템인 `EROFS` 상에 `dm-verity` 해시 트리를 구축하고, 부팅 시 커널이 서명을 검증합니다.
  - 리눅스 무결성 측정 아키텍처(`IMA`)를 통해 실행 파일/라이브러리의 다이제스트를 fTPM PCR(PCR 10)에 확장 기록합니다.
- **Zero Plaintext Key 정책 & SoftHSMv2**:
  - 저장소에 개인키(`.pem`, `.key`)를 일절 커밋하지 않습니다. 오프라인 서명키는 SoftHSMv2 PKCS#11 토큰 내에서 생성/운용되며, 향후 물리 HSM으로 URI만 교체 가능합니다.
- **Secure World 기반 Cloud-Humanoid mTLS**:
  - 로봇의 장치 식별 개인키를 Normal World 파일시스템에 노출하지 않고, OP-TEE PKCS#11 TA / fTPM 내부에서 연산하여 OpenSSL 3.x Provider로 mTLS 채널을 확립합니다.

---

## 3. 빠른 시작 (Quick Start)

### 3.1. 사전 준비 (Prerequisites)
- Docker 24.0+ 및 Docker Compose v2.x
- VS Code 및 [Dev Containers 확장 프로그램](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) (권장)

### 3.2. VS Code Dev Container로 시작 (권장)
1. VS Code에서 본 레포지토리를 엽니다.
2. `F1` 키를 누르고 `Dev Containers: Reopen in Container`를 선택합니다.
3. 컨테이너 내부 터미널에서 모든 툴체인(aarch64 GCC, QEMU, SoftHSM, tpm2-tools, erofs-utils 등)이 자동으로 세팅됩니다.

### 3.3. 호스트 CLI 환경에서 실행
```bash
# 컨테이너 환경 래퍼 스크립트를 통한 빌드 및 실행
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
├── docs/                           # 마스터 체크리스트, SRD, 아키텍처, 키 관리, 위협 모델
├── scripts/                        # 다운로드, 빌드, QEMU 실행 래퍼 스크립트
├── configs/                        # 커널 및 OP-TEE 빌드 설정 fragments
├── keys_hsm/                       # SoftHSMv2 토큰 초기화 및 PKCS#11 서명 헬퍼
├── apps/                           # mTLS 클라이언트 및 Attestation 에이전트 소스
└── tests/                          # QEMU 기반 pytest E2E 보안 자동화 검증
```

---

## 5. 상세 문서 링크 (Documentation Links)

- [마스터 실행 체크리스트 (Roadmap Checklist)](docs/roadmap_checklist.md)
- [보안 요구사항 명세서 (Requirements SRD)](docs/requirements.md)
- [시스템 아키텍처 명세서 (System Architecture)](docs/architecture.md)
- [키 관리 및 HSM/mTLS 아키텍처 (Key Management & HSM)](docs/key_management_hsm.md)
- [휴머노이드 위협 모델링 (Threat Model STRIDE)](docs/threat_model.md)
- [Archify 검증 다이어그램 컬렉션 (Interactive Diagrams)](docs/diagrams/)

---

## 6. 라이선스 (License)

본 프로젝트는 [Apache-2.0 License](LICENSE) 하에 배포됩니다.
