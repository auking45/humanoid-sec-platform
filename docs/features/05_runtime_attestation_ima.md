# Feature 05 — Linux IMA 측정, fTPM PCR 10 & 원격 증명 (Remote Attestation) 상세 기술 명세

> **문서 목적**: 로봇 런타임 환경에서 실행되는 모든 바이너리를 하드웨어 레지스터에 연쇄 누적 측정하고, 관제 센터(Fleet Verifier)와의 챌린지-응답을 통해 감염/변조된 로봇을 관제망에서 즉각 격리하는 제로 트러스트(Zero-Trust) 원격 증명 아키텍처를 정의함.  
> **적용 표준**: TCG TPM 2.0 Attestation Architecture, Linux Integrity Measurement Architecture (IMA)  
> **상태**: Approved / Production Baseline  

---

## 1. 아키텍처 개요 및 원격 증명 시퀀스

정적 텔레메트리("OK" 문자열 보고)는 악성코드에 의해 위조되거나 재전송(Replay)될 수 있으므로, 하드웨어 fTPM의 전자서명과 매 회차 난수 챌린지를 결합한 증거 수집 체계를 구현함.

[![Remote Attestation Flow](../diagrams/remote_attestation_flow.svg)](../diagrams/remote_attestation_flow.html)
> 💡 *클릭 시 [Archify 인터랙티브 뷰어](../diagrams/remote_attestation_flow.html)로 이동하여 챌린지-응답 및 무결성 평가 시퀀스 확인 가능.*

---

## 2. Linux IMA(무결성 측정 아키텍처) 및 PCR 10 연쇄 해싱

- **커널 부팅 파라미터**:
  - `ima_policy=tcb ima_hash=sha256`: 시스템의 모든 실행 파일(ELF 바이너리 및 공유 라이브러리)의 해시 측정을 강제.
- **PCR 10 Extend 메커니즘**:
  - 바이너리가 `execve` 호출로 실행될 때마다 리눅스 커널이 SHA-256 해시를 계산하고, OP-TEE fTPM TA로 SMC를 호출하여 PCR 10을 확장:
  $$\text{PCR}_{10}^{\text{new}} = \text{SHA256}\left(\text{PCR}_{10}^{\text{old}} \parallel \text{SHA256}(\text{Binary\_Content})\right)$$
  - 단방향 해시 함수의 성질로 인해, **공격자가 특정 악성코드 실행 기록만 삭제하거나 조작하는 것이 수학적으로 불가능**.

---

## 3. 원격 증명 증거 번들 (Attestation Bundle) 명세

로봇의 `apps/attestation_agent/`가 관제 서버로 전송하는 증거 페이로드:

```json
{
  "nonce": "32바이트 일회용 암호학적 챌린지 난수",
  "quote": {
    "attest_data": "fTPM 2.0 TPMS_ATTEST 구조체 (Nonce, PCR 10 합성 해시 바인딩)",
    "signature": "fTPM Attestation Key(AK)의 ECDSA P-256 서명",
    "pcr_composite": { "10": "현재 시점의 PCR 10 최종 누적 해시" }
  },
  "ima_log": [
    { "pcr": 10, "template_hash": "...", "file_hash": "...", "file_path": "/usr/bin/ros2" }
  ],
  "storage": {
    "roothash": "현재 마운트된 dm-verity 머클 루트 해시",
    "signature_file": "verity.roothash.sig"
  }
}
```

---

## 4. 관제 센터(Fleet Verifier) 4단계 평가 엔진

`apps/attestation_agent/verifier.py`의 평가 로직:

1. **Nonce 신선도 검사 (Freshness Check)**:
   - 서버가 발급했던 난수와 일치하고 1회만 사용되었는지 확인 &rarr; **과거 정상 Quote 재전송(Replay) 원천 차단 (ATK-04A)**.
2. **AK 하드웨어 서명 검증**:
   - `DeviceEnrollmentCa.crt` 체인에 등록된 정식 fTPM Attestation Key로 서명되었는지 확인.
3. **IMA 로그 재생성 및 PCR 10 대조 (Log Replay Verification)**:
   - 보고된 IMA 로그 목록을 순서대로 SHA-256 해시 연쇄하여 최종 합성값을 계산하고, fTPM Quote 내부의 PCR 10 값과 비트 단위 일치 검증 &rarr; **스텔스 악성코드 탐지 (ATK-04B)**.
4. **dm-verity 무결성 검증**:
   - 스토리지 Root Hash가 SoftHSMv2 `DmVeritySigningKey`로 유효하게 서명되었는지 검증 &rarr; **스토리지 위조 차단 (ATK-04C)**.

---

## 5. 실증 방어 검증 (ATK-04 & ATK-09)

- `test_atk04_runtime_ima_tamper_and_attestation_replay`: Nonce 재사용 및 PCR 10 불일치 시 즉각 `UNTRUSTED` 판정 검증 완료.
- `test_atk09_ima_appraisal_bypass_and_stripped_xattr`: `security.ima` 서명이 제거된 바이너리 실행 시 커널 레벨에서 `EACCES` 차단 검증 완료.

