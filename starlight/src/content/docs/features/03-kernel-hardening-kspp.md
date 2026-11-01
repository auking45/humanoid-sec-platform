---
title: "03. Linux 6.8 KSPP 커널 하드닝 & 모듈 서명 강제 상세 명세"
description: "물리 메모리 격리, unprivileged eBPF 차단 및 SoftHSM RSA-3072 모듈 서명"
---

> **문서 목적**: 로봇 런타임 제어 루프를 구동하는 L4T 커널(Linux 6.8, Ubuntu 24.04 Noble)의 링 0 권한 장악 및 메모리 손상 취약점 공격 표면을 최소화하기 위한 KSPP 하드닝 및 모듈 서명 강제 체계를 정의함.  
> **적용 표준**: Kernel Self-Protection Project (KSPP), Linux Kernel Module Signing Architecture  
> **상태**: Approved / Production Baseline  

---

## 1. 아키텍처 개요 및 다계층 방어 구조

커널 공간은 로봇의 모터 액추에이터, 센서 버스(CAN, SPI, I2C), 네트워크 스택을 직접 제어하므로, 단 하나의 제어 흐름 가로채기(Control-Flow Hijacking)도 치명적 안전 사고로 직결됨.

[![Kernel Hardening Layers](/humanoid-sec-platform/diagrams/kernel_hardening_layers.svg)](/humanoid-sec-platform/diagrams/kernel_hardening_layers.html)
> 💡 *클릭 시 [Archify 인터랙티브 뷰어](/humanoid-sec-platform/diagrams/kernel_hardening_layers.html)로 이동하여 EL0부터 TrustZone까지의 보안 계층 확인 가능.*

---

## 2. KSPP 핵심 메모리 보호 및 익스플로잇 완화 (configs/kernel/security_hardening.config)

### 2.1. 물리 메모리 직접 접근 차단
- `CONFIG_STRICT_DEVMEM=y` & `CONFIG_IO_STRICT_DEVMEM=y`:
  - 일반 및 루트 사용자가 <code>/dev/mem</code>을 열어 커널 물리 RAM 또는 디바이스 레지스터를 직접 매핑하는 행위를 원천 차단.
  - 디스크나 메모리에 상주하는 비밀 암호키 스누핑 방어.

### 2.2. 주소 공간 레이아웃 난수화 (KASLR)
- `CONFIG_RANDOMIZE_BASE=y`: 부팅 시마다 커널 텍스트 및 데이터 오프셋을 랜덤 배치하여 ROP/JOP 체인 무력화.
- `CONFIG_RANDOMIZE_MODULE_REGION_FULL=y`: 커널 모듈 메모리 영역 난수화.

### 2.3. 페이지 테이블 및 유저 복사 검증
- `CONFIG_PAGE_TABLE_CHECK=y` & `CONFIG_PAGE_TABLE_CHECK_ENFORCE=y`: 페이지 테이블 엔트리의 불법 권한 상승 감지 시 즉각 패닉 유도.
- `CONFIG_HARDENED_USERCOPY=y`: 사용자 공간과 커널 공간 간 <code>copy_from_user</code> 경계 검사 강제.

---

## 3. 메모리 할당자 (Allocator) 및 스택 보호

| 설정 심볼 | 방어 메커니즘 | 방어 대상 공격 |
| :--- | :--- | :--- |
| `CONFIG_SLAB_FREELIST_HARDENED=y` | SLUB 프리리스트 포인터를 XOR Cookie로 암호화 | 힙 오버플로우, UAF (Use-After-Free) |
| `CONFIG_SLAB_FREELIST_RANDOM=y` | 힙 청크 할당 순서 난수화 | 힙 레이아웃 예측 공격 (Heap Grooming) |
| `CONFIG_SHUFFLE_PAGE_ALLOCATOR=y` | 페이지 할당자 프리리스트 셔플링 | 인접 페이지 오염 공격 |
| `CONFIG_STACKPROTECTOR_STRONG=y` | 함수 진입/반환 시 스택 카나리 무결성 검사 | 스택 버퍼 오버플로우 (Stack Smashing) |
| `CONFIG_INIT_ON_ALLOC_DEFAULT_ON=y` | 신규 메모리 할당 시 0으로 초기화 | 미초기화 메모리 정보 누출 |

---

## 4. 공격 표면 축소 (Attack Surface Reduction)

- `CONFIG_BPF_UNPRIV_DEFAULT_OFF=y`: 일반 사용자의 unprivileged eBPF 적재를 전면 금지하여 Spectre 투기적 실행 공격 표면 제거.
- `CONFIG_SECURITY_DMESG_RESTRICT=y`: <code>dmesg</code> 접근을 관리자 권한으로 한정하여 주소 정보 누출(KASLR 우회) 방지.
- `CONFIG_PROTECTED_HARDLINKS=y` & `CONFIG_PROTECTED_SYMLINKS=y`: TOCTOU 심볼릭 링크 하이재킹 공격 차단.
- `CONFIG_PROTECTED_FIFOS=2` & `CONFIG_PROTECTED_REGULAR=2`: 스푸핑 방지 FIFO/파일 보호.

---

## 5. 커널 모듈 강제 서명 (`CONFIG_MODULE_SIG_FORCE=y`)

- **무결성 강제 정책**:
  - `CONFIG_MODULE_SIG=y`, `CONFIG_MODULE_SIG_FORCE=y`, `CONFIG_MODULE_SIG_ALL=y`, `CONFIG_MODULE_SIG_SHA256=y`.
  - 서명이 존재하지 않거나 유효하지 않은 커널 모듈은 로드 요청 시 커널 레벨에서 즉시 **<code>EKEYREJECTED</code> 반환 및 차단**.
- **SoftHSMv2 서명 연동**:
  - `KernelModuleSigningKey` (ID `01`, RSA-3072)를 사용하여 평문 키 노출 없이 빌드 타임에 서명 첨부:
  ```bash
  sign_helper.sh kmod --in build/drivers/custom_sensor.ko
  ```
- **실증 검증 (ATK-02)**:
  - 변조된 `.ko` 파일 주입 및 위조 서명 주입 공격 시 커널 verifier에서 100% 거절 완료 (`tests/test_attack_scenarios.py`).