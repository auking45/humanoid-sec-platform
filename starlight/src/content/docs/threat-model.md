---
title: "휴머노이드 로봇 위협 모델링 (STRIDE)"
description: "로봇 특화 공격 표면 분석, STRIDE 위협 매트릭스 및 방어 통제 매핑"
---

> **Methodology**: STRIDE (Spoofing, Tampering, Repudiation, Information Disclosure, Denial of Service, Elevation of Privilege)  
> **Target System**: NVIDIA Jetson Humanoid Robot Autonomous Platform  
> **Status**: Approved / Baseline

---

## 1. 배경 및 휴머노이드 로봇 특화 위협 환경

휴머노이드 로봇은 공장, 물류창고, 의료시설, 일상생활 등 인간과 물리적으로 인접한 환경에서 자율 작동합니다. 따라서 사이버 공격의 결과가 단순한 데이터 유출에 그치지 않고 **물리적 파괴(Physical Damage), 인명 상해(Human Safety Hazards), 제어권 탈취를 통한 오작동**으로 직결될 수 있습니다.

또한 데이터센터 서버와 달리 공격자가 로봇 본체에 물리적으로 직접 접근(Physical Access)할 수 있는 열린 환경에 노출되므로, 하드웨어 물리 공격부터 클라우드 무선 원격 공격까지 전방위적인 방어 체계가 요구됩니다.

---

## 2. 공격 표면 (Attack Surface Analysis)

[![STRIDE Threat Model](/humanoid-sec-platform/diagrams/threat_model_stride.svg)](/humanoid-sec-platform/diagrams/threat_model_stride.html)
> 💡 *클릭 시 [Archify 인터랙티브 뷰어](/humanoid-sec-platform/diagrams/threat_model_stride.html)로 이동하여 공격 표면, STRIDE 위협, 구현된 보안 통제, SRD 요구사항 간의 연결 관계를 인터랙티브하게 탐색할 수 있습니다.*

1. **물리 및 하드웨어 인터페이스**:
   - 로봇 분해 후 eMMC/UFS 플래시 칩을 분리하여 오프라인에서 루트 파일시스템 변조 및 개인키 덤프 시도.
   - 유지보수 포트(UART, JTAG)를 통한 부트로더 인터럽트 및 쉘 획득.
   - 내부 모터 제어 CAN 버스 또는 라이다/카메라 센서 이더넷 라인 패킷 스니핑 및 조작.
2. **네트워크 및 무선 통신 인터페이스**:
   - 가짜 클라우드 관제 서버로 위장한 중간자 공격(Man-in-the-Middle, MITM).
   - 악의적으로 변조된 펌웨어 또는 오염된 인공지능 신경망 가중치(Weights) OTA 배포.
3. **소프트웨어 런타임 인터페이스**:
   - ROS 2 제어 노드의 메모리 손상 취약점을 통한 임의 코드 실행.
   - 루트 권한 획득 후 커널 모듈(`.ko`) 주입을 통한 루트킷(Rootkit) 설치.

---

## 3. STRIDE 위협 분석 매트릭스

| 위협 카테고리 (STRIDE) | 위협 시나리오 (Threat Scenario) | 위험도 | 영향도 (Impact) | 대응 보안 통제 (Security Control) |
| :--- | :--- | :---: | :--- | :--- |
| **Spoofing (신원 도용)** | 공격자가 가짜 로봇으로 위장하여 클라우드 관제망에 접속하거나, 가짜 클라우드가 로봇에 악의적 제어 명령 하달 | **High** | 악의적 모션 명령 주입, 허위 센서 데이터 보고 | OP-TEE PKCS#11 TA 격리 키 기반 **TLS 1.3 mTLS**, fTPM Remote Attestation |
| **Tampering (데이터 변조)** | 플래시 메모리 칩을 직접 수정하여 악성 바이너리 삽입 또는 부트로더/커널 변조 | **Critical** | 로봇 오작동, 사람과의 충돌사고 유발 | **Root of Trust 기반 Secure Boot**, **EROFS + dm-verity**, 커널 모듈 강제 서명 |
| **Repudiation (부인 방지)** | 변조된 시스템에서 비인가 명령이 수행되었으나 로그 조작으로 원인 규명 불가 | **Medium** | 사후 포렌식 불가, 법적 책임 규명 불가 | **IMA 런타임 측정 -> fTPM PCR 10 해시 체이닝**, 조작 불가능한 불변 감사 로그 |
| **Information Disclosure (정보 유출)** | 디스크 덤프 또는 메모리 스누핑을 통해 로봇 장치 인증서 개인키 및 기밀 AI 모델 추출 | **Critical** | 장치 복제(Cloning), 지적 재산권(IP) 도난 | **Zero Plaintext Key 정책**, 개인키의 Secure World / RPMB 하드웨어 격리 |
| **Denial of Service (서비스 거부)** | DoS 공격을 통해 로봇 제어 루프 중단 또는 부팅 블록 유발 | **High** | 로봇 균형 상실 및 전도, 인명 안전 사고 | **Watchdog 연동 페일세이프(Fail-Safe)**, 검증 실패 시 안전 정지 모드 진입 |
| **Elevation of Privilege (권한 상승)** | 사용자 공간 애플리케이션 취약점을 통해 커널 링 0 권한 장악 및 TEE 침해 시도 | **Critical** | 시스템 전면 장악, TEE 우회 시도 | **KSPP 커널 하드닝**, ARM TrustZone 하드웨어 메모리 격리 (EL3 / S-EL1) |

---

## 4. 보안 통제(Security Controls) 매핑 테이블

본 플랫폼에서 구현된 세부 기술과 대응되는 위협 및 요구사항의 매핑 관계입니다.

```text
 STRIDE Threats               Technical Security Controls            Security Requirements (SRD)
 ─────────────────            ───────────────────────────            ───────────────────────────
 Device Cloning / Spoofing ──> OP-TEE PKCS#11 TA + fTPM ───────────> SRD-COMM / SRD-MEAS
 Flash Storage Tampering   ──> EROFS + dm-verity Block Integrity ──> SRD-STOR / SRD-BOOT
 Plaintext Key Leakage     ──> SoftHSMv2 PKCS#11 URI Pipeline ────> SRD-HSM Policy
 Rootkit / Kernel Exploit  ──> KSPP Hardening + Forced Mod Sign ──> SRD-KERN
```

> 💡 *자세한 컴포넌트별 매핑은 상단 [STRIDE 다이어그램](/humanoid-sec-platform/diagrams/threat_model_stride.html)을 참조하십시오.*

---

## 5. 잔여 위험(Residual Risk) 및 운영 고려사항

1. **물리적 사이드채널 및 글리치 공격 (Fault Injection / Power Analysis)**:
   - 본 플랫폼은 소프트웨어/에뮬레이션 보안 계층을 주로 다루며, 실물 보드 양산 시에는 하드웨어 차폐 및 클록 글리치 방지 실드 등의 물리 하드웨어 설계가 병행되어야 합니다.
2. **SoftHSMv2 환경에서 물리 HSM으로의 전환**:
   - 개발 및 CI/CD 환경에서는 편의성과 재현성을 위해 SoftHSMv2를 사용하지만, 운영 릴리스 서버에서는 동일한 PKCS#11 API를 지원하는 FIPS 140-2/3 Level 3 인증 하드웨어 HSM(Hardware Security Module)으로 전환해야 합니다.