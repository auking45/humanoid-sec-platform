# Threat Modeling & Security Controls Mapping (STRIDE)

> **Methodology**: STRIDE (Spoofing, Tampering, Repudiation, Information Disclosure, Denial of Service, Elevation of Privilege)  
> **Target System**: NVIDIA Jetson Humanoid Robot Autonomous Platform  
> **Status**: Approved / Baseline

---

## 1. 배경 및 휴머노이드 로봇 특화 위협 환경

- **물리적 안전 위험**: 휴머노이드 로봇은 인간과 동일한 물리 공간에서 협업 및 자율 작동함에 따라, 사이버 공격이 데이터 유출을 넘어 **물리적 파괴, 인명 상해, 제어권 탈취로 인한 오작동**으로 직결됨.
- **물리 접근 공격 표면**: 원격 데이터센터 서버와 달리 공격자가 하드웨어 본체에 직접 접근(Physical Access) 가능한 환경에 노출되어 하드웨어 덤프부터 무선 MITM까지 전방위 방어 필수.

---

## 2. 공격 표면 (Attack Surface Analysis)

[![STRIDE Threat Model](./diagrams/threat_model_stride.svg)](./diagrams/threat_model_stride.html)
> 💡 *클릭 시 [Archify 인터랙티브 뷰어](./diagrams/threat_model_stride.html)로 이동하여 공격 표면, STRIDE 위협, 구현된 보안 통제, SRD 요구사항 간의 연결 관계 인터랙티브 탐색 지원.*

1. **물리 및 하드웨어 인터페이스**:
   - 로봇 분해 후 eMMC/UFS 플래시 칩 분리를 통한 오프라인 루트 파일시스템 변조 및 개인키 덤프 시도.
   - 유지보수 포트(UART, JTAG)를 통한 부트로더 인터럽트 및 디버그 쉘 획득.
   - 내부 모터 제어 CAN 버스 또는 라이다/카메라 센서 이더넷 라인 패킷 스니핑 및 조작.
2. **네트워크 및 무선 통신 인터페이스**:
   - 가짜 클라우드 관제 서버 위장을 통한 중간자 공격(MITM) 및 허위 명령 주입.
   - 악의적으로 변조된 펌웨어 또는 오염된 AI 모델 가중치(Weights) OTA 배포.
3. **소프트웨어 런타임 인터페이스**:
   - ROS 2 제어 노드의 메모리 손상 취약점을 통한 임의 코드 실행.
   - 루트 권한 획득 후 악성 커널 모듈(`.ko`) 주입을 통한 루트킷(Rootkit) 설치.

---

## 3. STRIDE 위협 분석 매트릭스

| 위협 카테고리 (STRIDE) | 위협 시나리오 (Threat Scenario) | 위험도 | 영향도 (Impact) | 대응 보안 통제 (Security Control) |
| :---: | :--- | :---: | :--- | :--- |
| **Spoofing (신원 도용)** | 가짜 로봇 위장 관제망 접속 또는 가짜 클라우드의 악의적 제어 명령 하달 | **High** | 악의적 모션 명령 주입, 허위 센서 데이터 보고 | OP-TEE PKCS#11 TA 격리 키 기반 **TLS 1.3 mTLS**, fTPM Remote Attestation |
| **Tampering (데이터 변조)** | 플래시 메모리 칩 직접 수정을 통한 악성 바이너리 삽입 및 커널 변조 | **Critical** | 로봇 오작동, 인명 충돌 사고 유발 | **Root of Trust 기반 Secure Boot**, **EROFS + dm-verity**, 커널 모듈 강제 서명 |
| **Repudiation (부인 방지)** | 변조된 시스템의 비인가 명령 수행 후 로그 조작으로 원인 규명 은폐 | **Medium** | 사후 포렌식 불가, 법적 책임 규명 불가 | **IMA 런타임 측정 -> fTPM PCR 10 해시 체이닝**, 조작 불가능한 불변 감사 로그 |
| **Information Disclosure (정보 유출)** | 디스크 덤프 또는 메모리 스누핑을 통한 장치 인증서 개인키 및 기밀 AI 모델 추출 | **Critical** | 장치 복제(Cloning), 핵심 지적 재산권(IP) 탈취 | **Zero Plaintext Key 정책**, 개인키의 Secure World / RPMB 하드웨어 격리 |
| **Denial of Service (서비스 거부)** | DoS 공격을 통한 로봇 실시간 제어 루프 중단 및 관제 불능 유발 | **High** | 로봇 균형 상실 및 전도, 인명 안전 사고 | **Watchdog 연동 페일세이프(Fail-Safe)**, 검증 실패 시 안전 정지 모드 진입 |
| **Elevation of Privilege (권한 상승)** | 애플리케이션 취약점을 통한 커널 링 0 권한 장악 및 TEE 침해 시도 | **Critical** | 시스템 전면 장악, TEE 우회 시도 | **KSPP 커널 하드닝**, ARM TrustZone 하드웨어 메모리 격리 (EL3 / S-EL1) |

---

## 4. 보안 통제(Security Controls) 매핑 테이블

플랫폼 구현 핵심 기술과 대응 위협 및 보안 요구사항(SRD) 매핑 구조:

```text
 STRIDE Threats               Technical Security Controls            Security Requirements (SRD)
 ─────────────────            ───────────────────────────            ───────────────────────────
 Device Cloning / Spoofing ──> OP-TEE PKCS#11 TA + fTPM ───────────> SRD-COMM / SRD-MEAS
 Flash Storage Tampering   ──> EROFS + dm-verity Block Integrity ──> SRD-STOR / SRD-BOOT
 Plaintext Key Leakage     ──> SoftHSMv2 PKCS#11 URI Pipeline ────> SRD-HSM Policy
 Rootkit / Kernel Exploit  ──> KSPP Hardening + Forced Mod Sign ──> SRD-KERN
```

> 💡 *컴포넌트별 상세 매핑은 상단 [STRIDE 다이어그램](./diagrams/threat_model_stride.html) 참조.*

---

## 5. 잔여 위험(Residual Risk) 및 운영 고려사항

1. **물리적 사이드채널 및 글리치 공격 (Fault Injection / Power Analysis)**:
   - 본 플랫폼은 소프트웨어/에뮬레이션 보안 계층을 중심으로 검증함. 실물 로봇 양산 보드 적용 시 하드웨어 쉴드 및 전원/클록 글리치 방어 회로 병행 필수.
2. **SoftHSMv2 환경에서 물리 HSM으로의 전환**:
   - 개발 및 CI/CD 환경에서는 편의성과 재현성을 위해 SoftHSMv2를 활용하되, 프로덕션 릴리스 시 동일한 PKCS#11 API를 지원하는 FIPS 140-2/3 Level 3 인증 물리 HSM(Hardware Security Module)으로 무수정 전환 수행.

