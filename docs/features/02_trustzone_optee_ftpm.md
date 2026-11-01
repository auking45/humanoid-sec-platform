# Feature 02 — ARM TrustZone, OP-TEE OS & fTPM 2.0 상세 기술 명세

> **문서 목적**: 로봇 런타임 환경에서 일반 OS(리눅스 커널)가 공격자에게 전면 장악되더라도, 하드웨어 수준에서 격리된 Secure World(S-EL1/S-EL0) 내 암호 자산과 TPM 상태를 보호하는 TEE 아키텍처 명세를 정의함.  
> **적용 표준**: GlobalPlatform TEE 규격, ARM TrustZone Architecture, TCG TPM 2.0 Library Specification  
> **상태**: Approved / Production Baseline  

---

## 1. 아키텍처 개요 및 하드웨어 메모리 방화벽

Normal World(리눅스 커널)와 Secure World(OP-TEE)는 ARM TrustZone 하드웨어 버스 방화벽(TZASC)에 의해 물리적으로 분리됨.

- **TZDRAM (0x0e100000 ~ 0x10000000, 32MB)**:
  - Secure World 전용 물리 RAM 영역.
  - 리눅스 커널(NS-EL1)이 해당 주소 범위에 접근 시 즉각 **하드웨어 Bus Error / Data Abort 발생**.
- **공유 메모리 (SHM Pool)**:
  - 파라미터 교환은 오직 <code>/dev/tee0</code> 드라이버가 할당한 비보안 공유 메모리를 통해서만 수행.
- **SMC (Secure Monitor Call)**:
  - Normal World &rarr; EL3 TF-A Secure Monitor &rarr; S-EL1 OP-TEE Core로 안전하게 문맥 전환.

---

## 2. OP-TEE 4.2 Core 및 Early TA 아키텍처

양산 로봇의 부팅 타이밍 요구사항을 만족하기 위해, 파일시스템 마운트 전 초기화 단계에서 필수 TA를 펌웨어에 내장:

```text
[ TF-A BL31 ] ──(BL32 로드)──> [ OP-TEE Core (S-EL1) ]
                                      │
         ┌────────────────────────────┼────────────────────────────┐
         ▼                            ▼                            ▼
  [ Early fTPM TA ]            [ PKCS#11 TA ]             [ RPMB Driver ]
  (UUID: bc50d971-...)         (UUID: fd02c9da-...)        (Hardware Anti-Replay)
  - PCR 10 해시 연쇄           - mTLS 개인키 격리 봉인     - 단조 증가 카운터 검증
  - /dev/tpmrm0 인터페이스     - C_Sign 서명 연산 수행     - fTPM NVRAM 영구 저장
```

- **`CFG_IN_TREE_EARLY_TAS`**: fTPM TA(`bc50d971-d4c9-42c4-82cb-343fb7f37896`)를 OP-TEE 바이너리에 인라인 임베드하여 커널 초기 부팅 시점부터 TPM 명령 수신 대기.
- **`CFG_PKCS11_TA=y`**: PKCS#11 v2.40 표준 API를 지원하는 Trusted Application 기본 활성화.

---

## 3. fTPM 2.0 (ms-tpm-20-ref) 및 리눅스 커널 연동

- **물리 칩셋 없는 완전한 TPM 2.0**:
  - Microsoft Open-Source TPM 2.0 Reference 실장을 OP-TEE TA로 포팅.
  - L4T 커널의 <code>drivers/char/tpm/tpm_ftpm_tee.c</code> 드라이버를 통해 사용자 공간에 <code>/dev/tpm0</code> 및 <code>/dev/tpmrm0</code> (Resource Manager) 노출.
- **핵심 레지스터 및 명령어**:
  - `TPM2_PCR_Extend(PCR 10, Hash)`: Linux IMA 연동 무결성 로그 누적.
  - `TPM2_Quote(AK_Handle, Nonce, PCR_Selection)`: 원격 증명 서명 생성.
  - `TPM2_GetRandom(Num_Bytes)`: 하드웨어 암호학적 난수 공급.

---

## 4. eMMC RPMB (Replay Protected Memory Block) 롤백 방지

공격자가 eMMC 플래시의 이전 스냅샷을 덮어써서 폐기된 키나 이전 취약 상태로 복원하는 롤백 공격(Rollback Attack)을 차단:

1. **인증된 쓰기 (Authenticated Write)**:
   - OP-TEE와 eMMC 컨트롤러만 공유하는 비밀 대칭키(EKB 유도)로 HMAC-SHA256 인증 프레임 생성.
2. **단조 증가 카운터 (Monotonic Write Counter)**:
   - RPMB 쓰기 성공 시마다 eMMC 내부 하드웨어 카운터가 `N`에서 `N+1`로 영구 증가.
3. **재전송 거부 (ATK-08 실증)**:
   - 과거 스냅샷 프레임(카운터 `N`)을 재주입 시도 시, 컨트롤러 카운터(`N+1`)와 불일치하여 `TEE_ERROR_SECURITY` 에러를 반환하며 즉시 거절.

---

## 5. 검증 결과 및 기능 테스트

- **GlobalPlatform xtest 100% 통과**:
  - `regression_1033` (Supplicant Plugin), `regression_2001~2004` (iSocket TCP/UDP API) 등 전 테스트 케이스(133개 서브테스트) 무오류 통과.
- **ATK-08 공격 방어**:
  - 루트 커널에서의 TZDRAM 직접 접근 차단 및 가상 RPMB 단조 증가 카운터 불일치 감지 검증 완료 (`tests/test_attack_scenarios.py`).

