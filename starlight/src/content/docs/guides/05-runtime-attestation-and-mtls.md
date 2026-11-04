---
title: "05. 런타임 원격 증명과 mTLS: 로봇과 클라우드의 상호 신뢰 구축"
description: "원격지 로봇 제로 트러스트, Linux IMA 바이너리 측정, fTPM PCR 10 해시 연쇄, Nonce 챌린지 및 mTLS 1.3"
---

> **문서 목적**: 원격지에서 자율 동작하는 휴머노이드 로봇과 클라우드 관제 센터 간의 제로 트러스트(Zero-Trust) 신뢰 구축 원리, Linux IMA 및 fTPM 2.0 기반 원격 증명(Remote Attestation)과 Secure World mTLS(Mutual TLS) 상호 인증 메커니즘을 입문자 눈높이에서 알기 쉽게 설명함.  
> **대상 독자**: 시스템 보안 입문자, 클라우드/로봇 통신 네트워크 엔지니어, 백엔드/인프라 보안 아키텍트  
> **상태**: Production Guide  

---

## 1. 원격지 로봇의 신뢰 딜레마: "이 로봇이 정말 안전한 상태인가?"

휴머노이드 로봇은 제조 공장, 물류 창고, 의료 현장 등 물리적으로 격리된 장소에서 독자적으로 동작하며 클라우드 관제 서버로부터 주행 및 모터 제어 명령을 수신함.  
이때 클라우드 관제 센터는 심각한 보안 질문에 직면하게 됨:

> **"지금 접속해 온 로봇이 악성코드나 루트킷에 감염되어 제어권을 탈취당한 상태라면 어떻게 구별할 것인가?"**

단순히 아이디와 패스워드, 혹은 파일로 저장된 인증서만으로는 이를 검증할 수 없음:
- 해커가 로봇을 해킹한 후 인증서 파일을 복제하여 자신의 PC에서 가짜 로봇 행세를 할 수 있음.
- 로봇의 통신 데몬은 정상인 척 위장하면서, 백그라운드에서는 악성 제어 루프를 돌리고 있을 수 있음.

이를 해결하기 위해 하드웨어 기반의 **원격 증명 (Remote Attestation)**과 **Secure World mTLS (상호 인증)**이 필수적임.

---

## 2. 런타임 실행 측정: Linux IMA와 fTPM PCR 10

시스템이 부팅된 후 실행되는 모든 소프트웨어의 흔적을 기록하는 기술이 바로 리눅스 커널의 **IMA (Integrity Measurement Architecture)**임:

[![fTPM PCR 10 Hash-Chain](/humanoid-sec-platform/diagrams/tpm_pcr_extend_flow.svg)](/humanoid-sec-platform/diagrams/tpm_pcr_extend_flow.html)
> 💡 *클릭 시 [Archify 인터랙티브 뷰어](/humanoid-sec-platform/diagrams/tpm_pcr_extend_flow.html)로 이동하여 IMA 바이너리 측정 및 fTPM PCR 10 해시 연쇄 시퀀스 확인 가능.*

### 2.1. `execve()` 시스템 콜 인터셉트
1. 사용자가 셸에서 `./motor_controller` 바이너리를 실행하면 커널의 `execve()` 시스템 콜이 호출됨.
2. 실행 직전 커널 내부의 IMA 서브시스템이 제어권을 가로챔.
3. IMA는 실행될 파일의 내용을 읽어 **SHA-256 해시값**을 계산하고, 메모리 내 이벤트 로그(`/sys/kernel/security/ima/ascii_runtime_measurements`)에 한 줄을 추가함.

### 2.2. fTPM PCR 10 하드웨어 해시 확장 (Extend)
계산된 파일 해시는 단순히 로그 파일에만 남지 않고, **하드웨어 fTPM 2.0의 PCR 10 레지스터로 전달**되어 누적 암호화됨:

$$\text{PCR 10}_{new} = \text{SHA-256}(\text{PCR 10}_{old} \parallel \text{File-SHA256})$$

- 해커가 루트 권한을 얻어 IMA 로그 파일을 메모리에서 위조하거나 삭제하더라도, **Secure World(fTPM) 내부의 PCR 10 하드웨어 레지스터 값은 절대 조작할 수 없음**.
- 한 번이라도 비인가 바이너리가 실행되면 PCR 10의 결과값은 정상 시스템 기준값(Golden Baseline)에서 영원히 벗어나게 됨.

---

## 3. 원격 증명 (Remote Attestation)과 챌린지-응답

클라우드 관제 센터가 로봇의 건강 상태를 원격으로 증명받는 과정은 암호학적 **도전-응답(Challenge-Response)** 방식으로 진행됨:

```text
[클라우드 서버]                                            [휴머노이드 로봇]
      |                                                          |
      |--1. Attestation Challenge (32바이트 난수: Nonce)---------->|
      |                                                          |
      |                                                          +--2. fTPM에 TPM2_Quote 요청
      |                                                          |     (PCR 10, Nonce, Key=AK)
      |                                                          |
      |                                                          +--3. fTPM이 하드웨어 내부에서
      |                                                          |     PCR 10 값과 Nonce를 묶어
      |                                                          |     증명키(AK)로 서명 생성
      |                                                          |
      |<--4. TPM2_Quote 번들 + IMA 측정 로그 전송------------------|
      |
+-----+----------------------------------------------------------+
| 클라우드 검증 로직:                                                |
| - 서명 검증: fTPM 증명키(AK)의 X.509 인증서로 서명값 검증         |
| - 신선도 확인: Quote 내부의 Nonce가 내가 방금 보낸 난수와 일치하는가? |
|   (과거 정상 상태일 때 캡처한 Quote를 재전송하는 Replay Attack 차단) |
| - 골든 기준 대조: IMA 로그를 재생하여 계산한 PCR 10 값이         |
|   Quote에 서명된 PCR 10 값과 일치하는가?                       |
|   => 판정: [TRUSTED: 제어권 부여] / [COMPROMISED: 격리 및 차단] |
+----------------------------------------------------------------+
```

---

## 4. 왜 일반 HTTPS(단방향 TLS)로는 부족한가? (mTLS의 필요성)

우리가 웹 브라우저로 네이버나 구글에 접속할 때는 **단방향 TLS (Server-Only Authentication)**를 사용함:
- 브라우저는 서버가 진짜 구글인지(서버 인증서) 꼼꼼히 확인하지만,
- 서버는 브라우저가 누구인지 인증서로 검사하지 않고 일반 아이디/비밀번호에 의존함.

하지만 인간의 안전을 위협할 수 있는 산업용 휴머노이드 로봇에서는 이것으로 부족함.  
반드시 **mTLS (Mutual TLS: 상호 인증)**를 적용해야 함:

```text
[단방향 TLS vs 상호 mTLS 비교]
- 단방향 TLS: 클라이언트만 서버를 검증함 (서버는 가짜 클라이언트의 침투에 취약)
- 상호 mTLS: 서버도 클라이언트의 X.509 인증서와 서명을 하드웨어 레벨에서 상호 검증함!
```

---

## 5. Secure World mTLS: 비밀키 노출 없는 TLS 1.3 핸드셰이크

기존 mTLS의 치명적 결함은 클라이언트 인증서에 대응하는 **개인키(`client.key`)를 파일로 보관**하여 해커에게 유출될 수 있다는 점이었음.  
우리 플랫폼은 이를 **OpenSSL 3.x Provider와 OP-TEE PKCS#11 TA의 연동**으로 완벽히 해결함:

[![Secure World mTLS Sequence](/humanoid-sec-platform/diagrams/secure_mtls_sequence.svg)](/humanoid-sec-platform/diagrams/secure_mtls_sequence.html)
> 💡 *클릭 시 [Archify 인터랙티브 뷰어](/humanoid-sec-platform/diagrams/secure_mtls_sequence.html)로 이동하여 OpenSSL 3.x Provider와 OP-TEE 간 SMC 서명 위임 시퀀스 확인 가능.*

1. **클라이언트 인증서 요청**: 클라우드 서버가 핸드셰이크 중 `CertificateRequest`를 보냄.
2. **서명 위임**: 로봇의 mTLS 통신 클라이언트는 평문 키를 직접 읽지 않고, `pkcs11-provider`를 통해 **OP-TEE Secure World에 서명 연산(`C_Sign`)을 위임**함.
3. **Secure SRAM 서명**: 로봇의 신원 증명 비밀키(`HumanoidDeviceIdentityKey`, ECDSA P-256)는 **TrustZone 내부 Secure SRAM에만 존재**하며, 하드웨어 안에서 서명을 생성한 뒤 결과값만 반환함.
4. **TLS 1.3 완료**: 클라우드는 로봇의 하드웨어가 직접 서명한 인증을 확인하고 양방향 암호화 세션을 수립함.

---

## 6. 요약

1. **제로 트러스트 검증**: 원격지 로봇을 무조건 신뢰하지 않고, 하드웨어 기반 원격 증명과 상호 mTLS로 매 접속마다 검증함.
2. **IMA + fTPM PCR 10**: 실행된 모든 바이너리의 해시를 하드웨어 레지스터에 비가역적으로 체이닝하여 악성코드 은닉을 불가능하게 만듦.
3. **Nonce 챌린지**: 일회용 난수를 통해 이전 정상 상태의 서명을 재사용하는 재전송 공격(Replay Attack)을 원천 차단함.
4. **Secure World mTLS**: 비밀키가 Secure World 밖으로 1바이트도 노출되지 않는 상태에서 안전한 TLS 1.3 양방향 통신을 보장함.