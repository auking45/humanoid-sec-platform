#!/usr/bin/env python3
"""
sync_docs_to_starlight.py — Sync repository documentation & Archify diagrams into Astro Starlight (Bilingual: ko & en)
"""
import os
import shutil
import re

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DOCS_DIR = os.path.join(REPO_ROOT, "docs")
DOCS_EN_DIR = os.path.join(DOCS_DIR, "en")
DIAGRAMS_DIR = os.path.join(DOCS_DIR, "diagrams")
STARLIGHT_DIR = os.path.join(REPO_ROOT, "starlight")
STARLIGHT_CONTENT = os.path.join(STARLIGHT_DIR, "src", "content", "docs")
STARLIGHT_CONTENT_EN = os.path.join(STARLIGHT_CONTENT, "en")
STARLIGHT_PUBLIC = os.path.join(STARLIGHT_DIR, "public")
STARLIGHT_DIAGRAMS = os.path.join(STARLIGHT_PUBLIC, "diagrams")

DOC_MAPPINGS_KO = [
    {
        "src": os.path.join(REPO_ROOT, "README.md"),
        "dest": "index.md",
        "title": "휴머노이드 보안 플랫폼 (Humanoid Security Platform)",
        "description": "NVIDIA Jetson 휴머노이드 로봇을 위한 QEMU 기반 보안 하드닝 및 검증 플랫폼",
        "is_home": True,
        "hero_title": "Humanoid Security Platform",
        "hero_tagline": "NVIDIA Jetson 휴머노이드 로봇을 위한 QEMU 및 L4T 보안 검증 플랫폼 (OP-TEE, fTPM, EROFS dm-verity, Secure mTLS)",
        "actions": [
            {"text": "빠른 시작 가이드", "link": "/humanoid-sec-platform/quick-start/", "icon": "right-arrow", "variant": "primary"},
            {"text": "시스템 아키텍처", "link": "/humanoid-sec-platform/architecture/", "icon": "open-book", "variant": "secondary"},
            {"text": "Archify 다이어그램", "link": "/humanoid-sec-platform/diagrams/", "icon": "external", "variant": "minimal"},
        ]
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

DOC_MAPPINGS_EN = [
    {
        "src": os.path.join(DOCS_EN_DIR, "README.md"),
        "dest": os.path.join("en", "index.md"),
        "title": "Humanoid Security Platform",
        "description": "QEMU-based security verification & hardening platform for NVIDIA Jetson humanoid robots",
        "is_home": True,
        "hero_title": "Humanoid Security Platform",
        "hero_tagline": "QEMU & L4T Security Verification for NVIDIA Jetson Humanoid Robots (OP-TEE, fTPM, EROFS dm-verity, and Secure mTLS)",
        "actions": [
            {"text": "Quick Start Guide", "link": "/humanoid-sec-platform/en/quick-start/", "icon": "right-arrow", "variant": "primary"},
            {"text": "System Architecture", "link": "/humanoid-sec-platform/en/architecture/", "icon": "open-book", "variant": "secondary"},
            {"text": "Archify Diagrams", "link": "/humanoid-sec-platform/en/diagrams/", "icon": "external", "variant": "minimal"},
        ]
    },
    {
        "src": os.path.join(DOCS_EN_DIR, "architecture.md"),
        "dest": os.path.join("en", "architecture.md"),
        "title": "System Architecture Specification",
        "description": "Hardware trust boundaries, TF-A/OP-TEE, kernel hardening, and EROFS + dm-verity storage integrity",
    },
    {
        "src": os.path.join(DOCS_EN_DIR, "requirements.md"),
        "dest": os.path.join("en", "requirements.md"),
        "title": "Security Requirements Document (SRD)",
        "description": "Comprehensive specifications for boot chain, kernel, TEE, integrity measurement, HSM, and communication security",
    },
    {
        "src": os.path.join(DOCS_EN_DIR, "key_management_hsm.md"),
        "dest": os.path.join("en", "key-management-hsm.md"),
        "title": "Key Management & HSM / Secure mTLS Architecture",
        "description": "Zero Plaintext Key policy, SoftHSMv2 offline signing, and OP-TEE runtime mTLS pipeline",
    },
    {
        "src": os.path.join(DOCS_EN_DIR, "threat_model.md"),
        "dest": os.path.join("en", "threat-model.md"),
        "title": "Humanoid Robot Threat Model (STRIDE)",
        "description": "Robot-specific attack surfaces, STRIDE threat analysis matrix, and defense control mapping",
    },
    {
        "src": os.path.join(DOCS_EN_DIR, "roadmap_checklist.md"),
        "dest": os.path.join("en", "roadmap-checklist.md"),
        "title": "Master Roadmap & Execution Checklist",
        "description": "Phased master execution plan from Phase 0 to Phase 6 with verification tracking (Single Source of Truth)",
    },
]

def ensure_dirs():
    os.makedirs(STARLIGHT_CONTENT, exist_ok=True)
    os.makedirs(STARLIGHT_CONTENT_EN, exist_ok=True)
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

def prepare_markdown(content: str, item: dict) -> str:
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

    title = item["title"]
    description = item["description"]
    is_home = item.get("is_home", False)

    if is_home:
        actions_str = ""
        for act in item.get("actions", []):
            actions_str += f"""    - text: "{act['text']}"\n      link: {act['link']}\n      icon: {act['icon']}\n      variant: {act['variant']}\n"""
        hero_title = item.get("hero_title", "Humanoid Security Platform")
        frontmatter = f"""---
title: "{title}"
description: "{description}"
template: splash
hero:
  title: "{hero_title}"
  tagline: "{item['hero_tagline']}"
  actions:
{actions_str}---

"""
    else:
        frontmatter = f"""---
title: "{title}"
description: "{description}"
---

"""
    return frontmatter + content

def sync_document_list(doc_list: list):
    for item in doc_list:
        if not os.path.exists(item["src"]):
            print(f"[-] Warning: Source not found: {item['src']}")
            continue
        with open(item["src"], "r", encoding="utf-8") as f:
            raw = f.read()
        processed = prepare_markdown(raw, item)
        dest_path = os.path.join(STARLIGHT_CONTENT, item["dest"])
        os.makedirs(os.path.dirname(dest_path), exist_ok=True)
        with open(dest_path, "w", encoding="utf-8") as f:
            f.write(processed)
        print(f"[+] Generated: {dest_path}")

def generate_quick_start():
    # Korean version (concise noun-ending style)
    quick_start_ko = os.path.join(STARLIGHT_CONTENT, "quick-start.md")
    content_ko = """---
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
"""
    with open(quick_start_ko, "w", encoding="utf-8") as f:
        f.write(content_ko)
    print(f"[+] Generated: {quick_start_ko}")

    # English version
    quick_start_en = os.path.join(STARLIGHT_CONTENT_EN, "quick-start.md")
    content_en = """---
title: "Quick Start Guide"
description: "Setup guide for development and QEMU emulation via VS Code Dev Container & host CLI wrapper"
---

## 1. Prerequisites

- **Docker 24.0+** & **Docker Compose v2.x**
- **VS Code** with [Dev Containers Extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) (Recommended)
- Minimum 50GB free disk space (for L4T sources, ccache, and build cache)

---

## 2. Getting Started with VS Code Dev Container

1. Open this repository in VS Code.
2. Press `F1` and select `Dev Containers: Reopen in Container`.
3. Once built and launched, the complete toolchain is ready:
   - `aarch64-linux-gnu-gcc` cross-compiler
   - QEMU `aarch64` emulator (`qemu-system-aarch64`)
   - SoftHSMv2 PKCS#11 crypto token
   - `tpm2-tools` & `erofs-utils`
   - `ccache` acceleration (isolated 20GB cache volume)

---

## 3. Host Terminal Execution (`scripts/env_container.sh`)

Run containerized build and test commands directly from host CLI without VS Code:

```bash
# 1. Build container image
./scripts/env_container.sh build

# 2. Open interactive bash shell
./scripts/env_container.sh bash

# 3. Download sources & launch QEMU (Phase 2+)
./scripts/env_container.sh ./scripts/fetch_l4t_sources.sh
./scripts/env_container.sh ./scripts/run_qemu.sh
```

---

## 4. Build Volume Cache Configuration

Data is preserved across container rebuilds via dedicated Docker volumes:

| Host Docker Volume | Container Mount Path | Purpose |
| :--- | :--- | :--- |
| `humanoid_cache_downloads` | `/workspace/.cache/downloads` | NVIDIA official archive tarballs |
| `humanoid_cache_sources` | `/workspace/sources` | Extracted L4T source tree |
| `humanoid_cache_ccache` | `/workspace/.cache/ccache` | 20GB cross-compilation cache |
| `humanoid_cache_softhsm` | `/workspace/.cache/softhsm` | SoftHSMv2 PKCS#11 token database |
"""
    with open(quick_start_en, "w", encoding="utf-8") as f:
        f.write(content_en)
    print(f"[+] Generated: {quick_start_en}")

def generate_diagrams_gallery():
    # Korean version (concise noun-ending style)
    diagrams_ko = os.path.join(STARLIGHT_CONTENT, "diagrams.md")
    content_ko = """---
title: "Archify 인터랙티브 다이어그램 갤러리"
description: "Archify로 검증 렌더링된 휴머노이드 보안 플랫폼의 시스템 아키텍처, 부팅 체인, 키 계층, 통신 프로토콜"
---

휴머노이드 보안 플랫폼의 6대 핵심 보안 아키텍처 다이어그램 명세.  
각 다이어그램은 **독립형 벡터 SVG** 및 브라우저 조작이 가능한 **Archify 인터랙티브 뷰어**로 제공됨.

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
    with open(diagrams_ko, "w", encoding="utf-8") as f:
        f.write(content_ko)
    print(f"[+] Generated: {diagrams_ko}")

    # English version
    diagrams_en = os.path.join(STARLIGHT_CONTENT_EN, "diagrams.md")
    content_en = """---
title: "Archify Interactive Diagrams Gallery"
description: "Validated architectural diagrams for humanoid security platform: system architecture, boot chain, key hierarchy, protocols"
---

Interactive and standalone vector diagrams illustrating the 6 core security pillars of the platform.  
Each diagram is provided as a **standalone vector SVG** and an **interactive Archify HTML explorer**.

---

## 1. System Architecture

[![System Architecture](/humanoid-sec-platform/diagrams/system_architecture.svg)](/humanoid-sec-platform/diagrams/system_architecture.html)

<div class="archify-container">
  <iframe src="/humanoid-sec-platform/diagrams/system_architecture.html" title="System Architecture"></iframe>
</div>

> 🔗 [Open Fullscreen](/humanoid-sec-platform/diagrams/system_architecture.html)

---

## 2. Secure Boot Chain (Sequence)

[![Secure Boot Sequence](/humanoid-sec-platform/diagrams/secure_boot_sequence.svg)](/humanoid-sec-platform/diagrams/secure_boot_sequence.html)

<div class="archify-container">
  <iframe src="/humanoid-sec-platform/diagrams/secure_boot_sequence.html" title="Secure Boot Sequence"></iframe>
</div>

> 🔗 [Open Fullscreen](/humanoid-sec-platform/diagrams/secure_boot_sequence.html)

---

## 3. Cryptographic Key Hierarchy

[![Key Hierarchy](/humanoid-sec-platform/diagrams/key_hierarchy.svg)](/humanoid-sec-platform/diagrams/key_hierarchy.html)

<div class="archify-container">
  <iframe src="/humanoid-sec-platform/diagrams/key_hierarchy.html" title="Key Hierarchy"></iframe>
</div>

> 🔗 [Open Fullscreen](/humanoid-sec-platform/diagrams/key_hierarchy.html)

---

## 4. Secure World-Based Cloud-Humanoid mTLS

[![Secure mTLS Sequence](/humanoid-sec-platform/diagrams/secure_mtls_sequence.svg)](/humanoid-sec-platform/diagrams/secure_mtls_sequence.html)

<div class="archify-container">
  <iframe src="/humanoid-sec-platform/diagrams/secure_mtls_sequence.html" title="Secure mTLS Sequence"></iframe>
</div>

> 🔗 [Open Fullscreen](/humanoid-sec-platform/diagrams/secure_mtls_sequence.html)

---

## 5. Storage & Runtime Integrity Pipeline (EROFS + dm-verity + IMA)

[![Storage Integrity Pipeline](/humanoid-sec-platform/diagrams/storage_integrity_pipeline.svg)](/humanoid-sec-platform/diagrams/storage_integrity_pipeline.html)

<div class="archify-container">
  <iframe src="/humanoid-sec-platform/diagrams/storage_integrity_pipeline.html" title="Storage Integrity Pipeline"></iframe>
</div>

> 🔗 [Open Fullscreen](/humanoid-sec-platform/diagrams/storage_integrity_pipeline.html)

---

## 6. STRIDE Threat Modeling & Security Controls

[![STRIDE Threat Model](/humanoid-sec-platform/diagrams/threat_model_stride.svg)](/humanoid-sec-platform/diagrams/threat_model_stride.html)

<div class="archify-container">
  <iframe src="/humanoid-sec-platform/diagrams/threat_model_stride.html" title="STRIDE Threat Model"></iframe>
</div>

> 🔗 [Open Fullscreen](/humanoid-sec-platform/diagrams/threat_model_stride.html)
"""
    with open(diagrams_en, "w", encoding="utf-8") as f:
        f.write(content_en)
    print(f"[+] Generated: {diagrams_en}")

def main():
    ensure_dirs()
    copy_diagram_assets()
    print("[*] Syncing Korean documentation...")
    sync_document_list(DOC_MAPPINGS_KO)
    print("[*] Syncing English documentation...")
    sync_document_list(DOC_MAPPINGS_EN)
    generate_quick_start()
    generate_diagrams_gallery()
    print("[+] Bilingual documentation sync complete!")

if __name__ == "__main__":
    main()
