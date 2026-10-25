# Key Management & HSM / mTLS Architecture

> **Security Policy**: Zero Plaintext Key Policy  
> **Target Cryptographic Standards**: PKCS#11 v2.40+, TPM 2.0, OpenSSL 3.x Provider Architecture  
> **Status**: Approved / Baseline

---

## 1. Zero Plaintext Key 정책 (Zero Plaintext Key Policy)

본 플랫폼의 가장 핵심적인 보안 원칙은 **"어떤 빌드 단계, 어떤 테스트 환경, 어떤 소스코드 커밋에서도 평문 개인키(`.pem`, `.key`)가 디스크 파일시스템이나 Git 저장소에 노출되지 않는다"**는 것입니다.

- **빌드 및 릴리스 타임 (오프라인 서명)**:
  - 모든 코드 서명 키(커널 모듈, dm-verity 루트 해시, IMA 정책 등)는 **SoftHSMv2 (PKCS#11 토큰)** 내부에서 생성 및 보관됩니다.
  - 빌드 스크립트와 서명 툴은 절대 개인키를 파일로 덤프하지 않으며, `pkcs11:model=SoftHSM%20v2;token=HumanoidSecToken;object=KernelModKey`와 같은 **RFC 7512 PKCS#11 URI** 형식으로만 키를 참조하여 서명을 요청합니다.
  - 이 구조를 통해 프로덕션 환경으로 전환 시 코드 수정 없이 환경변수(`PKCS11_MODULE_PATH`, `PKCS11_URI`)만 변경하여 엔터프라이즈 하드웨어 HSM(YubiHSM, Thales Luna, AWS CloudHSM 등)으로 100% 매끄럽게 교체 가능합니다.
- **로봇 런타임 (장치 신원 및 클라우드 통신)**:
  - 로봇의 고유 장치 신원 증명 키 및 클라우드 관제 통신용 mTLS 개인키는 **Normal World 리눅스 파일시스템에 절대 저장되지 않습니다.**
  - 키는 **OP-TEE PKCS#11 TA** 또는 **fTPM 2.0 엔진** 내부에서 직접 생성되며, 개인키 추출 불가(Non-extractable) 속성으로 봉인됩니다.

---

## 2. 암호 키 계층 구조 (Key Hierarchy)

[![Cryptographic Key Hierarchy](diagrams/key_hierarchy.svg)](diagrams/key_hierarchy.html)
> 💡 *클릭 시 [Archify 인터랙티브 뷰어](diagrams/key_hierarchy.html)로 이동하여 Tier 1 오프라인 빌드/서명, Tier 2 디바이스 Secure World, Tier 3 공개 인증서의 연관 관계를 확인합니다.*

---

## 3. 오프라인 SoftHSMv2 키 관리 파이프라인

빌드 컨테이너 내부의 SoftHSMv2 토큰 구성 및 슬롯 매핑 정보입니다.

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

클라우드 관제 서버와 휴머노이드 로봇 간의 모든 원격 명령(RPC), 텔레메트리, 제어 명령은 TLS 1.3 상호 인증(Mutual TLS, mTLS)을 통해서만 전송됩니다.

### 4.1. OpenSSL 3.x Provider 아키텍처

OpenSSL 3.x의 최신 Provider 아키텍처를 적용하여, 애플리케이션 코드는 표준 OpenSSL API(`SSL_CTX`, `SSL_connect`)를 그대로 사용하되 실제 암호 연산은 Secure World로 투명하게 오프로드됩니다.

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
> 💡 *클릭 시 [Archify 인터랙티브 뷰어](diagrams/secure_mtls_sequence.html)로 이동하여 핸드셰이크 트레이스 및 Secure SRAM 서명 위임 프로세스를 시각적으로 확인할 수 있습니다.*

---

## 5. 키 롤오버 및 폐기(Revocation) 전략

1. **장치 키 갱신 (Key Rollover)**:
   - 만료 주기가 도래하면 로봇은 OP-TEE 내부에서 새로운 키 쌍을 생성하고, fTPM Attestation Quote와 결합된 CSR(Certificate Signing Request)을 관제 서버로 제출합니다.
   - 관제 서버가 무결성을 확인한 후 신규 클라이언트 인증서를 발급하여 주입합니다.
2. **침해 감지 시 즉각 폐기**:
   - fTPM PCR 10의 IMA 측정값 불일치 또는 비정상 부팅 감지 시, Cloud Verifier는 즉시 해당 로봇의 공용 인증서를 CRL(Certificate Revocation List) 및 OCSP에 등록하여 관제 네트워크 접속을 전면 차단합니다.

