---
title: "빠른 시작 가이드 (Quick Start)"
description: "VS Code Dev Container 및 호스트 CLI를 통한 개발 및 QEMU 에뮬레이션 환경 구축 가이드"
---

## 1. 사전 요구사항 (Prerequisites)

- **Docker 24.0+** 및 **Docker Compose v2.x**
- **VS Code** 및 [Dev Containers 확장 프로그램](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) (권장)
- 최소 50GB 이상의 여유 디스크 공간 (L4T 소스, ccache, 빌드 캐시용)

---

## 2. VS Code Dev Container 시작 절차

1. 본 저장소를 VS Code로 열기
2. `F1` 키 입력 후 `Dev Containers: Reopen in Container` 선택
3. 컨테이너 빌드 및 실행 완료 시 모든 툴체인 준비 완료:
   - `aarch64-linux-gnu-gcc` 크로스 컴파일러
   - QEMU `aarch64` 에뮬레이터 (`qemu-system-aarch64`)
   - SoftHSMv2 PKCS#11 암호화 토큰
   - `tpm2-tools` 및 `erofs-utils`
   - 컴파일 가속용 `ccache` (20GB 캐시 볼륨 분리)

---

## 3. 호스트 터미널 실행 CLI (`scripts/env_container.sh`)

VS Code 없이 호스트 CLI 환경에서 컨테이너 내부 빌드/테스트 수행 가능:

```bash
# 1. 컨테이너 이미지 빌드
./scripts/env_container.sh build

# 2. 인터랙티브 bash 쉘 실행
./scripts/env_container.sh bash

# 3. 소스 다운로드 및 QEMU 실행 (Phase 2 이후)
./scripts/env_container.sh ./scripts/fetch_l4t_sources.sh
./scripts/env_container.sh ./scripts/run_qemu.sh
```

---

## 4. 빌드 볼륨 캐시 구성

호스트의 Docker 볼륨으로 분리되어 컨테이너 재시작 시에도 영구 보존됨:

| 호스트 볼륨 | 컨테이너 마운트 경로 | 용도 |
| :--- | :--- | :--- |
| `humanoid_cache_downloads` | `/workspace/.cache/downloads` | NVIDIA 공식 타르볼 캐시 |
| `humanoid_cache_sources` | `/workspace/sources` | 압축 해제된 L4T 소스 트리 |
| `humanoid_cache_ccache` | `/workspace/.cache/ccache` | 20GB 크로스 컴파일 캐시 |
| `humanoid_cache_softhsm` | `/workspace/.cache/softhsm` | SoftHSMv2 PKCS#11 토큰 저장소 |
