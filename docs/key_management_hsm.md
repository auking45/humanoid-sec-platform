# Key Management & HSM / mTLS Architecture

> **Security Policy**: Zero Plaintext Key Policy  
> **Target Cryptographic Standards**: PKCS#11 v2.40+, TPM 2.0, OpenSSL 3.x Provider Architecture  
> **Status**: Approved / Baseline

---

## 1. Zero Plaintext Key 정책 (Zero Plaintext Key Policy)

- **핵심 원칙**: 빌드 단계, CI/CD 파이프라인, 테스트 환경, 소스코드 커밋 어디에도 평문 개인키(`.pem`, `.key`) 저장 및 노출 전면 금지.
- **오프라인 빌드/서명 파이프라인**:
  - 모든 코드 서명 키(커널 모듈, dm-verity 루트 해시, IMA 정책 등)는 **SoftHSMv2 (PKCS#11 토큰)** 내부에서 생성 및 관리.
  - 서명 도구는 RFC 7512 **`pkcs11:` URI** 형식으로 키를 참조하여 서명 수행.
  - 환경변수(`PKCS11_MODULE_PATH`, `PKCS11_URI`) 교체만으로 엔터프라이즈 하드웨어 HSM(YubiHSM, Thales 등)으로 즉시 무수정 전환 가능.
- **로봇 런타임 장치 키 격리**:
  - 장치 고유 신원 증명 키 및 mTLS 클라이언트 개인키의 Normal World 파일시스템 저장 배제.
  - **OP-TEE PKCS#11 TA** 또는 **fTPM 2.0 엔진** 내부에서 키 생성 및 비추출(Non-extractable) 속성으로 봉인.

---

## 2. 암호 키 계층 구조 (Key Hierarchy)

[![Cryptographic Key Hierarchy](diagrams/key_hierarchy.svg)](diagrams/key_hierarchy.html)
> 💡 *클릭 시 [Archify 인터랙티브 뷰어](diagrams/key_hierarchy.html)로 이동하여 Tier 1 오프라인 빌드/서명, Tier 2 디바이스 Secure World, Tier 3 공개 인증서 간 인터랙티브 연관 관계 확인 지원.*

---

## 3. 오프라인 SoftHSMv2 키 관리 파이프라인

빌드 컨테이너 내부 SoftHSMv2 토큰 구성 및 슬롯 매핑 정보:

### 3.1. PKCS#11 토큰 및 객체 정의

| 토큰 레이블 (Token Label) | 객체 레이블 (Object Label) | 키 종류 / 알고리즘 | 용도 (Purpose) |
| :--- | :--- | :--- | :--- |
| `HumanoidSecToken` | `KernelModuleSigningKey` | RSA 3072 / SHA-256 | L4T 커널 모듈(`.ko`) 컴파일 시 무결성 서명 |
| `HumanoidSecToken` | `DmVeritySigningKey` | RSA 3072 / PSS SHA-256 | EROFS dm-verity Root Hash 암호 서명 |
| `HumanoidSecToken` | `ImaSigningKey` | ECDSA P-384 / SHA-384 | 런타임 실행 바이너리 IMA xattr 서명 |
| `HumanoidSecToken` | `DeviceEnrollmentCaKey` | ECDSA P-256 / SHA-256 | 로봇 Secure World 생성 키에 대한 mTLS 인증서 발급 |

### 3.2. 서명 유틸리티 래퍼 (`keys_hsm/sign_helper.sh`)
```bash
# 커널 모듈 서명 예시 (평문 키 노출 없음)
sign_helper.sh kmod \
  --uri "pkcs11:model=SoftHSM%20v2;token=HumanoidSecToken;object=KernelModuleSigningKey;type=private" \
  --in build/drivers/custom_driver.ko

# dm-verity Root Hash 서명 예시
sign_helper.sh verity \
  --uri "pkcs11:model=SoftHSM%20v2;token=HumanoidSecToken;object=DmVeritySigningKey;type=private" \
  --hash "${ROOTHASH}" \
  --out build/root_hash.p7s
```

---

## 4. Secure World 기반 Cloud-Humanoid mTLS 아키텍처

- **통신 보안 정책**: 관제 클라우드와 로봇 간 모든 제어 명령(RPC) 및 텔레메트리는 TLS 1.3 상호 인증(Mutual TLS) 강제 적용.
- **Provider 아키텍처**: OpenSSL 3.x의 Provider 메커니즘을 적용하여, 애플리케이션 변경 없이 `pkcs11-provider`를 통해 서명 연산을 OP-TEE 내부로 투명하게 위임.

```text
  [ Normal World (Non-Secure EL0) ]
┌─────────────────────────────────────────────────────────────┐
│  Robot Cloud Agent (apps/mtls_client)                       │
│  ├── Standard OpenSSL 3.x API (SSL_CTX_use_certificate)   │
└───────────────────────────────┬─────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────┐
│  OpenSSL 3.x Core Architecture                              │
│  ├── Default Provider (AES-GCM, SHA256, TLS 1.3 State)      │
│  └── PKCS#11 Provider (pkcs11-provider.so)                  │
└───────────────────────────────┬─────────────────────────────┘
                                │ (PKCS#11 API: C_SignInit, C_Sign)
                                ▼
┌─────────────────────────────────────────────────────────────┐
│  OP-TEE Client Library (libckteec.so)                       │
│  └── /dev/tee0 (TEEC_InvokeCommand via Linux Kernel)        │
└───────────────────────────────┬─────────────────────────────┘
                                │
════════════════════════════════╪═══════════════════════════════ (SMC Call: TrustZone Boundary)
                                │
  [ Secure World (S-EL1 / S-EL0) ]
                                ▼
┌─────────────────────────────────────────────────────────────┐
│  OP-TEE OS (S-EL1)                                          │
│  └── PKCS#11 Trusted Application (S-EL0 TA)                 │
│      ├── Isolated Token Memory                              │
│      └── Private Key (Robot Device Identity - ECDSA P-256)  │
│          └── Performs ECDSA-SHA256 Sign inside Secure SRAM  │
└─────────────────────────────────────────────────────────────┘
```

### 4.2. mTLS 핸드셰이크 시퀀스 (TLS 1.3 CertificateVerify)

[![Secure World mTLS Sequence](diagrams/secure_mtls_sequence.svg)](diagrams/secure_mtls_sequence.html)
> 💡 *클릭 시 [Archify 인터랙티브 뷰어](diagrams/secure_mtls_sequence.html)로 이동하여 핸드셰이크 트레이스 및 Secure SRAM 서명 위임 프로세스 시각화 확인 지원.*

---

## 5. 키 롤오버 및 폐기(Revocation) 전략

1. **장치 키 갱신 (Key Rollover)**:
   - 만료 주기 도래 시 OP-TEE 내부에서 신규 키 쌍 생성 후 fTPM Attestation Quote와 결합된 CSR(Certificate Signing Request)을 관제 서버로 제출.
   - 관제 서버의 무결성 검증 통과 후 신규 클라이언트 인증서 발급 및 주입.
2. **침해 감지 시 즉각 폐기 (Instant Revocation)**:
   - fTPM PCR 10 IMA 측정값 불일치 또는 비정상 부팅 감지 시, Cloud Verifier가 해당 로봇의 인증서를 CRL 및 OCSP에 즉각 등록하여 관제망 접속 전면 차단.

