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

## 3. STRIDE 위협 분석 매트릭스 및 10대 실증 공격 시나리오

> 💡 *공격 시나리오별 심층 기술 명세 및 방어 검증 코드는 [공격 시나리오 및 다계층 방어 검증 가이드](./attack_defense_guide.md) 참조.*

| 위협 카테고리 (STRIDE) | 공격 시나리오 ID 및 명칭 | 위험도 | 영향도 (Impact) | 대응 보안 통제 (Security Control) |
| :---: | :--- | :---: | :--- | :--- |
| **Spoofing (신원 도용)** | **ATK-05**: 파일시스템 개인키 탈취 및 복제 로봇 mTLS 침투<br>**ATK-10**: 관제 통신 중간자 공격(MITM) 및 허위 명령 주입 | **Critical** | 비인가 장치 관제망 접속, 로봇 복제, 허위 모션 주입 | **Zero Plaintext Key 정책**, OP-TEE PKCS#11 TA 격리, **TLS 1.3 mTLS (상호 인증) + PFS** |
| **Tampering (데이터 변조)** | **ATK-01**: 부트로더/커널 암호문 변조 및 사설 서명키 우회<br>**ATK-03**: 오프라인 플래시 칩 분리 후 바이너리 변조<br>**ATK-06**: Stage 2 UEFI db 서명 위조 및 AuthVar 변조<br>**ATK-09**: 런타임 실행 바이너리 변조 및 IMA xattr 서명 제거 | **Critical** | 백도어 커널 구동, 제어 바이너리 영구 오염, 비인가 프로세스 실행 | **Root of Trust 기반 Secure Boot (PKC + eFuse + SBKPKC)**, **EROFS + dm-verity**, **Stage 2 UEFI db RSA-3072**, **IMA Appraisal (`ima_policy=tcb`)** |
| **Repudiation (부인 방지)** | **ATK-04**: 스텔스 악성코드 실행 및 원격 증명 Quote 재전송 | **Medium** | 침해 사실 은폐, 허위 상태 보고, 사후 포렌식 불가 | **IMA 런타임 측정 -> fTPM PCR 10 해시 체이닝**, Fresh Nonce 기반 Remote Attestation |
| **Information Disclosure (정보 유출)** | **ATK-05**: 디스크 덤프를 통한 개인키 및 AI 모델 추출<br>**ATK-07**: 물리 메모리(`/dev/mem`) 직접 탈취 | **Critical** | 핵심 지적 재산권(IP) 탈취, 시스템 제어 토큰 노출 | **Zero Plaintext Key (`CKA_EXTRACTABLE=FALSE`)**, **KSPP 하드닝 (`CONFIG_STRICT_DEVMEM=y`)** |
| **Denial of Service (서비스 거부)** | DoS 공격을 통한 로봇 실시간 제어 루프 중단 및 관제 불능 유발 | **High** | 로봇 균형 상실 및 전도, 인명 안전 사고 | **Watchdog 연동 페일세이프(Fail-Safe)**, 검증 실패 시 안전 정지 모드 진입 |
| **Elevation of Privilege (권한 상승)** | **ATK-02**: 비인가 루트킷 커널 모듈(`.ko`) 주입<br>**ATK-07**: 커널 런타임 공격 표면 장악 (eBPF, 힙 오염)<br>**ATK-08**: Normal World의 TrustZone 보안 메모리 침범 및 롤백 | **Critical** | 커널 링 0 장악, TrustZone TZDRAM 침해, 이전 취약 상태 복원 | **`CONFIG_MODULE_SIG_FORCE=y`**, **KSPP 커널 하드닝**, **ARM TrustZone 하드웨어 메모리 방화벽**, **RPMB Write Counter 인증** |

---

## 4. 보안 통제(Security Controls) 매핑 테이블

플랫폼 구현 핵심 기술과 대응 위협 및 보안 요구사항(SRD) 매핑 구조:

```text
 STRIDE Threats               Technical Security Controls            Verification Tests (tests/)
 ─────────────────            ───────────────────────────            ───────────────────────────
 Device Cloning / Spoofing ──> OP-TEE PKCS#11 TA + fTPM ───────────> test_atk05, test_atk10
 Flash Storage Tampering   ──> EROFS + dm-verity Block Integrity ──> test_atk03
 Plaintext Key Leakage     ──> SoftHSMv2 PKCS#11 URI Pipeline ────> test_atk05
 Rootkit / Kernel Exploit  ──> KSPP Hardening + Forced Mod Sign ──> test_atk02, test_atk07
 Secure Boot Bypass        ──> NVIDIA PKC + Stage 2 UEFI db + EKB ─> test_atk01, test_atk06
 TrustZone / Rollback      ──> ARM TrustZone + RPMB Counter ───────> test_atk08
 Runtime Binary Tamper     ──> IMA Appraisal (imasig) ────────────> test_atk09
 Stale / Replayed Quote    ──> fTPM PCR 10 + Nonce Challenge ─────> test_atk04
```

> 💡 *컴포넌트별 상세 매핑은 상단 [STRIDE 다이어그램](./diagrams/threat_model_stride.html) 참조.*

---

## 5. 잔여 위험(Residual Risk) 및 운영 고려사항

1. **물리적 사이드채널 및 글리치 공격 (Fault Injection / Power Analysis)**:
   - 본 플랫폼은 소프트웨어/에뮬레이션 보안 계층을 중심으로 검증함. 실물 로봇 양산 보드 적용 시 하드웨어 쉴드 및 전원/클록 글리치 방어 회로 병행 필수.
2. **SoftHSMv2 환경에서 물리 HSM으로의 전환**:
   - 개발 및 CI/CD 환경에서는 편의성과 재현성을 위해 SoftHSMv2를 활용하되, 프로덕션 릴리스 시 동일한 PKCS#11 API를 지원하는 FIPS 140-2/3 Level 3 인증 물리 HSM(Hardware Security Module)으로 무수정 전환 수행.

