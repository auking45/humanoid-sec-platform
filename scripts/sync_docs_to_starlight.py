#!/usr/bin/env python3
"""
sync_docs_to_starlight.py — Sync repository documentation & Archify diagrams into Astro Starlight
"""
import os
import shutil
import re

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DOCS_DIR = os.path.join(REPO_ROOT, "docs")
DIAGRAMS_DIR = os.path.join(DOCS_DIR, "diagrams")
STARLIGHT_DIR = os.path.join(REPO_ROOT, "starlight")
STARLIGHT_CONTENT = os.path.join(STARLIGHT_DIR, "src", "content", "docs")
STARLIGHT_PUBLIC = os.path.join(STARLIGHT_DIR, "public")
STARLIGHT_DIAGRAMS = os.path.join(STARLIGHT_PUBLIC, "diagrams")

DOC_MAPPINGS = [
    {
        "src": os.path.join(REPO_ROOT, "README.md"),
        "dest": "index.md",
        "title": "휴머노이드 보안 플랫폼 (Humanoid Security Platform)",
        "description": "NVIDIA Jetson 휴머노이드 로봇을 위한 QEMU 기반 보안 하드닝 및 검증 플랫폼",
    },
    {
        "src": os.path.join(DOCS_DIR, "architecture.md"),
        "dest": "architecture.md",
        "title": "시스템 아키텍처 명세서 (System Architecture)",
        "description": "하드웨어 신뢰 경계, TF-A/OP-TEE, 커널 하드닝, EROFS + dm-verity 스토리지 무결성",
    },
    {
        "src": os.path.join(DOCS_DIR, "requirements.md"),
        "dest": "requirements.md",
        "title": "보안 요구사항 정의서 (SRD)",
        "description": "부팅 체인, 커널, TEE, 무결성 측정, HSM 및 통신 보안 요구사항 상세 명세",
    },
    {
        "src": os.path.join(DOCS_DIR, "key_management_hsm.md"),
        "dest": "key-management-hsm.md",
        "title": "키 관리 및 HSM / Secure mTLS 아키텍처",
        "description": "Zero Plaintext Key 정책, SoftHSMv2 오프라인 서명 및 OP-TEE 런타임 mTLS",
    },
    {
        "src": os.path.join(DOCS_DIR, "threat_model.md"),
        "dest": "threat-model.md",
        "title": "휴머노이드 로봇 위협 모델링 (STRIDE)",
        "description": "로봇 특화 공격 표면 분석, STRIDE 위협 매트릭스 및 방어 통제 매핑",
    },
    {
        "src": os.path.join(DOCS_DIR, "roadmap_checklist.md"),
        "dest": "roadmap-checklist.md",
        "title": "마스터 로드맵 & 실행 체크리스트",
        "description": "Phase 0부터 Phase 6까지의 전체 실행 계획 및 단계별 검증 추적 (Single Source of Truth)",
    },
]

def ensure_dirs():
    os.makedirs(STARLIGHT_CONTENT, exist_ok=True)
    os.makedirs(STARLIGHT_DIAGRAMS, exist_ok=True)

def copy_diagram_assets():
    print("[*] Copying Archify diagrams to Starlight public assets...")
    if os.path.exists(DIAGRAMS_DIR):
        for f in os.listdir(DIAGRAMS_DIR):
            if f.endswith((".html", ".svg", ".json")):
                src_path = os.path.join(DIAGRAMS_DIR, f)
                dest_path = os.path.join(STARLIGHT_DIAGRAMS, f)
                shutil.copy2(src_path, dest_path)
        print(f"[+] Synced {len(os.listdir(STARLIGHT_DIAGRAMS))} diagram assets to public/diagrams/")

def prepare_markdown(content: str, title: str, description: str, is_home: bool = False) -> str:
    # Strip existing frontmatter if any
    if content.startswith("---"):
        parts = content.split("---", 2)
        if len(parts) >= 3:
            content = parts[2].strip()

    # If first line is a markdown header matching the title, strip it to prevent duplicate headers
    lines = content.splitlines()
    if lines and lines[0].startswith("# "):
        lines = lines[1:]
    content = "\n".join(lines).strip()

    # Rewrite relative paths for diagrams in Starlight context
    content = re.sub(r'\(docs/diagrams/([^)]+)\)', r'(/humanoid-sec-platform/diagrams/\1)', content)
    content = re.sub(r'\(diagrams/([^)]+)\)', r'(/humanoid-sec-platform/diagrams/\1)', content)

    if is_home:
        frontmatter = f"""---
title: "{title}"
description: "{description}"
template: splash
hero:
  title: |
    Humanoid Security
    Platform
  tagline: "QEMU & L4T Security Verification for NVIDIA Jetson Humanoid Robots (OP-TEE, fTPM, EROFS dm-verity, and Secure mTLS)"
  actions:
    - text: "빠른 시작 가이드"
      link: /humanoid-sec-platform/quick-start/
      icon: right-arrow
      variant: primary
    - text: "시스템 아키텍처"
      link: /humanoid-sec-platform/architecture/
      icon: open-book
      variant: secondary
    - text: "Archify 다이어그램"
      link: /humanoid-sec-platform/diagrams/
      icon: external
      variant: minimal
---

"""
    else:
        frontmatter = f"""---
title: "{title}"
description: "{description}"
---

"""
    return frontmatter + content

def sync_documents():
    print("[*] Syncing markdown documentation to Starlight content collection...")
    for item in DOC_MAPPINGS:
        if not os.path.exists(item["src"]):
            print(f"[-] Warning: Source not found: {item['src']}")
            continue
        with open(item["src"], "r", encoding="utf-8") as f:
            raw = f.read()
        is_home = (item["dest"] == "index.md")
        processed = prepare_markdown(raw, item["title"], item["description"], is_home=is_home)
        dest_path = os.path.join(STARLIGHT_CONTENT, item["dest"])
        with open(dest_path, "w", encoding="utf-8") as f:
            f.write(processed)
        print(f"[+] Generated: {dest_path}")

    # Generate Quick Start page
    generate_quick_start()

    # Generate Diagrams Gallery page
    generate_diagrams_gallery()

def generate_quick_start():
    quick_start_path = os.path.join(STARLIGHT_CONTENT, "quick-start.md")
    content = """---
title: "빠른 시작 가이드 (Quick Start)"
description: "VS Code Dev Container 및 호스트 CLI를 통한 개발 및 QEMU 에뮬레이션 환경 구축 가이드"
---

## 1. 사전 요구사항 (Prerequisites)

- **Docker 24.0+** 및 **Docker Compose v2.x**
- **VS Code** 및 [Dev Containers 확장 프로그램](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) (권장)
- 최소 50GB 이상의 여유 디스크 공간 (L4T 소스, ccache, 빌드 캐시용)

---

## 2. VS Code Dev Container로 시작 (권장)

1. 본 레포지토리를 VS Code로 엽니다.
2. `F1` 키를 누르고 `Dev Containers: Reopen in Container`를 선택합니다.
3. 컨테이너가 빌드되고 시작되면 모든 툴체인이 준비됩니다:
   - `aarch64-linux-gnu-gcc` 크로스 컴파일러
   - QEMU `aarch64` 에뮬레이터 (`qemu-system-aarch64`)
   - SoftHSMv2 PKCS#11 암호화 토큰
   - `tpm2-tools` 및 `erofs-utils`
   - 컴파일 가속용 `ccache` (20GB 캐시 볼륨 분리)

---

## 3. 호스트 터미널에서 실행 (`scripts/env_container.sh`)

VS Code 없이 호스트 CLI 환경에서 컨테이너 내부 작업을 수행할 수 있습니다.

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

다음 경로들은 호스트의 Docker 볼륨으로 분리되어 컨테이너가 재시작되어도 데이터가 보존됩니다:

| 호스트 볼륨 | 컨테이너 마운트 경로 | 용도 |
| :--- | :--- | :--- |
| `humanoid_cache_downloads` | `/workspace/.cache/downloads` | NVIDIA 공식 타르볼 캐시 |
| `humanoid_cache_sources` | `/workspace/sources` | 압축 해제된 L4T 소스 트리 |
| `humanoid_cache_ccache` | `/workspace/.cache/ccache` | 20GB 크로스 컴파일 캐시 |
| `humanoid_cache_softhsm` | `/workspace/.cache/softhsm` | SoftHSMv2 PKCS#11 토큰 저장소 |
"""
    with open(quick_start_path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"[+] Generated: {quick_start_path}")

def generate_diagrams_gallery():
    diagrams_path = os.path.join(STARLIGHT_CONTENT, "diagrams.md")
    content = """---
title: "Archify 인터랙티브 다이어그램 갤러리"
description: "Archify로 검증 렌더링된 휴머노이드 보안 플랫폼의 시스템 아키텍처, 부팅 체인, 키 계층, 통신 프로토콜"
---

본 페이지는 휴머노이드 보안 플랫폼의 6대 핵심 보안 아키텍처 다이어그램을 제공합니다.  
각 다이어그램은 **독립형 벡터 SVG** 및 브라우저에서 직접 조작할 수 있는 **Archify 인터랙티브 뷰어**로 제공됩니다.

---

## 1. 시스템 아키텍처 (System Architecture)

[![System Architecture](/humanoid-sec-platform/diagrams/system_architecture.svg)](/humanoid-sec-platform/diagrams/system_architecture.html)

<div class="archify-container">
  <iframe src="/humanoid-sec-platform/diagrams/system_architecture.html" title="System Architecture"></iframe>
</div>

> 🔗 [전체 화면으로 열기](/humanoid-sec-platform/diagrams/system_architecture.html)

---

## 2. 보안 부팅 체인 (Secure Boot Sequence)

[![Secure Boot Sequence](/humanoid-sec-platform/diagrams/secure_boot_sequence.svg)](/humanoid-sec-platform/diagrams/secure_boot_sequence.html)

<div class="archify-container">
  <iframe src="/humanoid-sec-platform/diagrams/secure_boot_sequence.html" title="Secure Boot Sequence"></iframe>
</div>

> 🔗 [전체 화면으로 열기](/humanoid-sec-platform/diagrams/secure_boot_sequence.html)

---

## 3. 암호 키 계층 구조 (Cryptographic Key Hierarchy)

[![Key Hierarchy](/humanoid-sec-platform/diagrams/key_hierarchy.svg)](/humanoid-sec-platform/diagrams/key_hierarchy.html)

<div class="archify-container">
  <iframe src="/humanoid-sec-platform/diagrams/key_hierarchy.html" title="Key Hierarchy"></iframe>
</div>

> 🔗 [전체 화면으로 열기](/humanoid-sec-platform/diagrams/key_hierarchy.html)

---

## 4. Secure World 기반 Cloud-Humanoid mTLS

[![Secure mTLS Sequence](/humanoid-sec-platform/diagrams/secure_mtls_sequence.svg)](/humanoid-sec-platform/diagrams/secure_mtls_sequence.html)

<div class="archify-container">
  <iframe src="/humanoid-sec-platform/diagrams/secure_mtls_sequence.html" title="Secure mTLS Sequence"></iframe>
</div>

> 🔗 [전체 화면으로 열기](/humanoid-sec-platform/diagrams/secure_mtls_sequence.html)

---

## 5. 스토리지 & 런타임 무결성 파이프라인 (EROFS + dm-verity + IMA)

[![Storage Integrity Pipeline](/humanoid-sec-platform/diagrams/storage_integrity_pipeline.svg)](/humanoid-sec-platform/diagrams/storage_integrity_pipeline.html)

<div class="archify-container">
  <iframe src="/humanoid-sec-platform/diagrams/storage_integrity_pipeline.html" title="Storage Integrity Pipeline"></iframe>
</div>

> 🔗 [전체 화면으로 열기](/humanoid-sec-platform/diagrams/storage_integrity_pipeline.html)

---

## 6. STRIDE 위협 모델링 & 보안 통제 매핑

[![STRIDE Threat Model](/humanoid-sec-platform/diagrams/threat_model_stride.svg)](/humanoid-sec-platform/diagrams/threat_model_stride.html)

<div class="archify-container">
  <iframe src="/humanoid-sec-platform/diagrams/threat_model_stride.html" title="STRIDE Threat Model"></iframe>
</div>

> 🔗 [전체 화면으로 열기](/humanoid-sec-platform/diagrams/threat_model_stride.html)
"""
    with open(diagrams_path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"[+] Generated: {diagrams_path}")

def main():
    ensure_dirs()
    copy_diagram_assets()
    sync_documents()
    print("[+] Documentation sync complete!")

if __name__ == "__main__":
    main()

