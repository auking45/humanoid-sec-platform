---
title: "06. Zero Plaintext Key 정책 & Secure World TLS 1.3 mTLS 상세 명세"
description: "평문 키 파일 0건 정책, OP-TEE PKCS#11 TA 격리 및 OpenSSL 3.x Provider 연동"
---

> **문서 목적**: 파일시스템 평문 개인키 파일 저장을 원천 배제하여 기기 복제(Cloning) 및 키 탈취를 방어하고, OP-TEE Secure World에 봉인된 키로 클라우드 관제 센터와 TLS 1.3 상호 인증(Mutual TLS)을 수행하는 통신 보안 명세를 정의함.  
> **적용 표준**: RFC 7512 (PKCS#11 URI), RFC 8446 (TLS 1.3), OpenSSL 3.x Provider Architecture  
> **상태**: Approved / Production Baseline  

---

## 1. 아키텍처 개요 및 키 계층 구조 (Key Hierarchy)

로봇 파일시스템 어디에도 평문 비밀키(`.pem`, `.key`)가 저장되지 않으며, 모든 오프라인 서명 및 런타임 통신 인증은 PKCS#11 하드웨어 토큰 내부에서만 실행됨.

[![Key Hierarchy](/humanoid-sec-platform/diagrams/key_hierarchy.svg)](/humanoid-sec-platform/diagrams/key_hierarchy.html)
> 💡 *클릭 시 [Archify 인터랙티브 뷰어](/humanoid-sec-platform/diagrams/key_hierarchy.html)로 이동하여 Tier 1 오프라인 서명키 및 Tier 2 Secure World 격리 키 구조 확인 가능.*

---

## 2. Zero Plaintext Key 정책 및 자동 감사 (`audit_zero_keys.sh`)

- **원칙**: 빌드 결과물, 저장소, 컨테이너, 디스크 이미지 어디에도 개인키 평문 파일 저장을 전면 금지.
- **`CKA_EXTRACTABLE=FALSE`**:
  - SoftHSMv2 및 OP-TEE PKCS#11 토큰 내부에 생성된 개인키 객체는 토큰 외부로 내보내기(Export)가 영구 차단됨.
- **감사 스크립트 (`keys_hsm/audit_zero_keys.sh`)**:
  - 파일시스템 전역을 스캔하여 `BEGIN ... PRIVATE KEY` 패턴의 평문 헤더 파일 존재 시 빌드 및 CI 배포 즉각 중단.

---

## 3. 오프라인 SoftHSMv2 서명 파이프라인 (RFC 7512 `pkcs11:` URI)

빌드 컨테이너 내부에서 평문 키 파일 노출 없이 표준 RFC 7512 URI를 통해 서명 연산 위임:

| 키 레이블 (Object Label) | 키 종류 / 알고리즘 | SoftHSM ID | 용도 |
| :--- | :---: | :---: | :--- |
| `KernelModuleSigningKey` | RSA 3072 / SHA-256 | `01` | L4T 커널 모듈(`.ko`) 컴파일 시 무결성 서명 및 Stage 2 UEFI db 검증 |
| `DmVeritySigningKey` | RSA 3072 / PSS SHA-256 | `02` | EROFS dm-verity Root Hash 암호 서명 (`verity.roothash.sig`) |
| `ImaSigningKey` | ECDSA P-384 / SHA-384 | `03` | 런타임 실행 바이너리 IMA xattr 디지털 서명 |
| `DeviceEnrollmentCaKey` | ECDSA P-256 / SHA-256 | `04` | 로봇 기기 신원 인증서 발급용 내부 루트 CA 키 |
| `SecureBootKey` | RSA 3072 / SHA-256 | `06` | Stage 1 BootROM/MB2 Tegra PKC Secure Boot 서명 |

```bash
# 평문 키 노출 없는 서명 실행 예시
sign_helper.sh kmod \
  --uri "pkcs11:token=HumanoidSecToken;object=KernelModuleSigningKey" \
  --in custom_driver.ko
```

---

## 4. Secure World 기반 TLS 1.3 mTLS 아키텍처

로봇의 일반 OS가 감염되더라도 클라우드 관제 통신용 인증키는 탈취할 수 없는 통신 보안 체계:

[![Secure mTLS Sequence](/humanoid-sec-platform/diagrams/secure_mtls_sequence.svg)](/humanoid-sec-platform/diagrams/secure_mtls_sequence.html)
> 💡 *클릭 시 [Archify 인터랙티브 뷰어](/humanoid-sec-platform/diagrams/secure_mtls_sequence.html)로 이동하여 OpenSSL 3.x Provider와 OP-TEE 간 SMC 서명 위임 시퀀스 확인 가능.*

- **OpenSSL 3.x `pkcs11-provider`**:
  - `apps/mtls_client/`가 TLS 1.3 핸드셰이크를 수행할 때, `CertificateVerify` 메시지 서명 요청을 OP-TEE PKCS#11 TA로 위임.
  - 서명 연산은 TrustZone Secure SRAM 내부에서 실행되며, 서명 결과(r, s)만 반환되므로 Normal World에 개인키가 단 1비트도 유출되지 않음.
- **완전 순방향 비밀성 (PFS - Perfect Forward Secrecy)**:
  - Ephemeral ECDHE 키 교환으로 매 세션마다 임시 대칭키를 유도하여, 과거 캡처된 패킷의 사후 복독 원천 방지.

---

## 5. 실증 방어 검증 (ATK-05 & ATK-10)

- `test_atk05_key_exfiltration_and_rogue_mtls_client`:
  - `audit_zero_keys.sh` 무결성 검증 통과 (평문 키 파일 0건).
  - 공격자가 자체 서명한 사설 인증서로 관제 서버(Fleet Server) 연결 시도 시 TLS 핸드셰이크 단계에서 100% 거절 완료.
- `test_atk10_mitm_network_spoofing_and_pfs_defense`:
  - 무선망 중간자(MITM) 프록시가 가짜 서버 인증서를 제시할 경우 로봇 클라이언트가 신뢰된 루트 CA 체인을 검증하여 즉시 연결 차단 완료.