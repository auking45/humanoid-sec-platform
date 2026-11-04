---
title: "01. 키 관리와 PKCS#11: 왜 비밀키를 디스크에 저장하면 안 되는가?"
description: "보안 입문자를 위한 평문 키의 위험성, SoftHSMv2 토큰 격리 및 C_Sign 서명 위임의 모든 것"
---

> **문서 목적**: 암호화 키 관리의 기초 개념, 디스크 평문 키 보관의 치명적 취약점, 그리고 PKCS#11 표준과 HSM(Hardware Security Module)을 통한 서명 위임 아키텍처를 입문자 눈높이에서 알기 쉽게 설명함.  
> **대상 독자**: 시스템 보안 입문자, 임베디드/로봇 소프트웨어 엔지니어, DevSecOps 엔지니어  
> **상태**: Production Guide  

---

## 1. 보안의 제1원칙: "디스크의 비밀키는 이미 해커의 키다"

소프트웨어 개발 시 인증서와 암호키를 다룰 때 흔히 저지르는 가장 위험한 실수는 **비밀키(`.pem`, `.key` 파일)를 파일시스템 경로(`/etc/ssl/private/`)에 저장**하는 것임.

많은 개발자가 파일 권한을 `chmod 600`으로 설정하면 안전하다고 생각하지만, 이는 운영체제 커널이 정상 동작할 때만 유효한 논리적 장벽에 불과함:

1. **오프라인 칩오프(Chip-off) 공격**: 로봇이 물리적으로 탈취되면 eMMC/UFS 플래시 메모리 칩을 떼어내어 상용 덤프 장비로 10초 만에 파일시스템 전체를 복제할 수 있음. 파일 권한은 오프라인 환경에서 아무런 보호를 제공하지 못함.
2. **커널 취약점 및 루트 권한 탈취**: 소프트웨어 버그로 루트(UID 0) 권한이 장악되면 디스크의 모든 평문 키는 즉각 외부로 유출(Exfiltration)됨.
3. **메모리 덤프 및 콜드 부트(Cold Boot)**: 프로세스가 디스크의 키 파일을 메모리로 읽어 들이는 순간, 프로세스 코어 덤프나 물리 RAM 덤프를 통해 평문 키가 그대로 노출됨.

따라서 최신 임베디드 보안의 절대 원칙은 **"호스트 파일시스템에는 단 1바이트의 비밀키도 평문으로 존재해서는 안 된다(Zero Plaintext Key)"**는 것임.

---

## 2. 비밀키를 지키는 구원투수: HSM과 PKCS#11의 원리

그렇다면 비밀키를 파일로 저장하지 않고 어떻게 서명과 암호화를 수행할 수 있는가?  
해답은 **하드웨어 보안 토큰(HSM / Secure World) 내부로 연산을 위임**하는 것임.

[![PKCS#11 HSM Cryptographic Delegation](/humanoid-sec-platform/diagrams/pkcs11_hsm_signing_delegation.svg)](/humanoid-sec-platform/diagrams/pkcs11_hsm_signing_delegation.html)
> 💡 *클릭 시 [Archify 인터랙티브 뷰어](/humanoid-sec-platform/diagrams/pkcs11_hsm_signing_delegation.html)로 이동하여 취약한 평문 키 방식과 PKCS#11 서명 위임 방식의 인터랙티브 비교 확인 가능.*

### 2.1. PKCS#11 표준이란?
- **PKCS#11 (Cryptoki)**: 스마트카드, 하드웨어 보안 모듈(HSM), TEE(신뢰 실행 환경) 등 암호화 하드웨어와 애플리케이션 간의 통신을 규정하는 국제 표준 C API 규격임.
- **Never-Extractable (비추출 속성)**: HSM 내부에서 키를 생성할 때 `CKA_EXTRACTABLE = FALSE` 플래그를 설정함. 이 키는 하드웨어 밖으로 평문으로든 암호문으로든 **영원히 꺼낼 수 없음**.

### 2.2. 서명 위임(`C_Sign`)의 마법
애플리케이션이 TLS 통신이나 바이너리 검증을 위해 디지털 서명을 만들어야 할 때, 종전 방식과 PKCS#11 방식은 완전히 다르게 동작함:

```text
[취약한 기존 방식]
Application  --1. open("server.key")-->  Disk
Application  <--2. [평문 비밀키 전달]--  Disk (메모리 노출 위험!)
Application  --3. CPU RAM에서 직접 연산 및 서명 완료-->

[안전한 PKCS#11 방식]
Application  --1. 서명할 데이터의 해시 다이제스트(32바이트)만 전송-->  HSM 토큰
HSM 토큰      --2. 격리된 하드웨어 내부에서 비밀키로 비공개 서명 연산 수행-->
Application  <--3. 결과 서명값(R, S)만 반환받음 (비밀키 노출 0%)--  HSM 토큰
```

애플리케이션은 비밀키가 어떻게 생겼는지 구경조차 할 수 없으며, 단지 서명 결과만 돌려받음. 따라서 해커가 애플리케이션 메모리를 통째로 덤프하거나 루트 권한을 장악해도 비밀키를 복제하여 다른 곳으로 가져갈 수 없음.

---

## 3. RFC 7512 `pkcs11:` URI 표준

우리 플랫폼에서는 빌드 스크립트나 데몬 설정 파일 어디에도 하드코딩된 키 경로나 암호를 적지 않음. 대신 **RFC 7512 국제 표준 규격인 PKCS#11 URI 식별자**를 사용함:

```text
pkcs11:model=SoftHSM%20v2;token=HumanoidSecToken;id=%01;object=KernelModuleSigningKey;type=private
```

이 URI는 파일 경로가 아니라 **"보안 토큰 안에 격리되어 있는 01번 핸들의 키 객체를 지칭하는 포인터"**임:
- 빌드 시스템(`scripts/build_kernel.sh`, `scripts/build_rootfs.sh`)은 이 URI를 OpenSSL 엔진 및 커널 서명 툴(`sign-file`)에 전달함.
- OpenSSL은 내부 `pkcs11-provider`를 통해 SoftHSMv2 또는 OP-TEE Secure World에 접속하여 토큰 내부 서명을 요청함.

---

## 4. 우리 플랫폼의 3계층 키 아키텍처

[![Key Hierarchy](/humanoid-sec-platform/diagrams/key_hierarchy.svg)](/humanoid-sec-platform/diagrams/key_hierarchy.html)
> 💡 *클릭 시 [Archify 인터랙티브 뷰어](/humanoid-sec-platform/diagrams/key_hierarchy.html)로 이동하여 Tier 1 오프라인 빌드 키와 Tier 2 디바이스 런타임 키 계층 확인 가능.*

우리 플랫폼은 키의 라이프사이클과 위험도에 따라 명확히 3단계로 분리함:

1. **Tier 1: 오프라인 서명 환경 (SoftHSMv2 / 기업형 HSM)**
   - 커널 모듈 서명키(`KernelModuleSigningKey`, RSA-3072)
   - dm-verity 루트 해시 서명키(`DmVeritySigningKey`, RSA-3072)
   - IMA 파일 무결성 서명키(`ImaSigningKey`, ECDSA P-384)
   - 디바이스 인증서 발급 CA 키(`DeviceEnrollmentCaKey`, ECDSA P-256)
   - *특징*: 빌드 머신에서만 격리된 토큰 내부에서 사용되며, 로봇 디바이스에는 공개 인증서(`.crt`)만 탑재됨.
2. **Tier 2: 디바이스 하드웨어 & Secure World (OP-TEE & fTPM)**
   - 로봇 디바이스 고유 신원키(`HumanoidDeviceIdentityKey`, ECDSA P-256)
   - fTPM 2.0 기본 시드 및 원격 증명키(AK: Attestation Key)
   - *특징*: 로봇의 ARM TrustZone Secure SRAM 및 eMMC RPMB 하드웨어 영역에 봉인됨.
3. **Tier 3: 공개 검증 아티팩트 (Public Distribution)**
   - 커널 빌트인 키링(`certs/signing_key.x509`)
   - 로봇 디바이스 인증서(`humanoid_device.crt`)
   - *특징*: 외부에 공개되어도 보안상 아무런 문제가 없는 검증용 공개키들임.

---

## 5. 요약 및 실무 체크리스트

| 점검 항목 | 취약한 개발 관행 (Anti-Pattern) | 우리 플랫폼의 보안 표준 (Best Practice) |
| :--- | :--- | :--- |
| **키 파일 저장** | `id_rsa`, `server.key` 파일을 디스크에 저장 | 디스크 평문 키 저장 절대 금지, SoftHSMv2 토큰 격리 |
| **키 접근 제어** | `chmod 600` 파일 권한에 의존 | `CKA_EXTRACTABLE=FALSE` 하드웨어 비추출 강제 |
| **키 참조 방식** | `/etc/keys/signing_key.pem` 경로 하드코딩 | RFC 7512 `pkcs11:` URI 기반 추상화 포인터 사용 |
| **CI/CD 검증** | 릴리스 전 키 유출 여부 미점검 | `keys_hsm/audit_zero_keys.sh` 무평문 키 전수 자동 감사 |