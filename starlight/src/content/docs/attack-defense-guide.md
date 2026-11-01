---
title: "공격 시나리오 및 다계층 방어 검증 가이드"
description: "10대 핵심 공격 벡터별 취약 기본 상태와 하드닝 플랫폼 방어 메커니즘 심층 명세 (ATK-01~10)"
---

> **문서 목적**: 휴머노이드 로봇 자율주행 및 물리 제어 환경에서 사이버 공격이 인명 피해 및 물리적 파괴로 이어지는 위험을 차단하기 위해, 플랫폼에 적용된 10대 보안 기능(Security Controls)의 도입 당위성을 입증하고 실제 공격 벡터에 대한 기술적 방어 메커니즘을 규명함.  
> **검증 도구**: `tests/test_attack_scenarios.py` (Red/Blue Team Attack Simulation Suite)  
> **보안 원칙**: 심층 방어 (Defense-in-Depth), 최소 권한 원칙 (Least Privilege), 비인가 변경 즉각 거부 (Fail-Secure)  

---

## 1. 10대 공격-방어 매트릭스 (End-to-End Attack & Defense Matrix)

| 공격 ID | 단계 (Phase) | 공격 시나리오 명칭 | STRIDE 분류 | 취약 기본 상태 (Vulnerable Baseline) | 적용된 보안 통제 (Hardened Control) | 방어 결과 (Security Outcome) |
| :---: | :---: | :--- | :---: | :--- | :--- | :--- |
| **ATK-01** | Phase 2 | 부트로더/커널 암호문 변조 및 사설 서명키 우회 | **Tampering / Elevation** | 무결성 검증 부재로 임의 조작된 악성 커널이 무단 로드 및 실행됨 | **NVIDIA Tegra PKC + SoC eFuse + SBKPKC 8KB BCH 컨테이너** | eFuse 해시 불일치 및 AES-GCM 인증 실패로 부팅 즉각 차단 (`Exit 2`) |
| **ATK-02** | Phase 2/4 | 비인가 루트킷 커널 모듈(`.ko`) 주입 | **Tampering / Elevation** | 서명되지 않은 임의의 커널 모듈이 `insmod`로 적재되어 링 0 권한 장악 | **`CONFIG_MODULE_SIG_FORCE=y` + SoftHSMv2 RSA-3072 서명** | 서명 부재 또는 서명 불일치 모듈 로드 시 `EKEYREJECTED`로 거부 |
| **ATK-03** | Phase 5 | 오프라인 플래시 칩 분리 후 바이너리 변조 | **Tampering** | eMMC/UFS 플래시 수정 내용이 영구 지속되어 제어 바이너리 오염 | **EROFS 불변 파일시스템 + dm-verity 블록 해시 트리 + HSM 서명** | 변조된 4KB 섹터 읽기 시 I/O 에러(`EIO`) 발생 및 위조 루트해시 거부 |
| **ATK-04** | Phase 3/6 | 스텔스 악성코드 실행 및 증명 Quote 재전송 | **Tampering / Repudiation** | 런타임 침해 후 원격 관제에 정상 상태로 위장 보고(Replay) 가능 | **fTPM PCR 10 해시 연쇄 + Fresh Nonce 기반 Remote Attestation** | 넌스 재사용 차단 및 PCR 불일치로 관제 서버 즉시 `UNTRUSTED` 판정 |
| **ATK-05** | Phase 4/6 | 파일시스템 개인키 탈취 및 복제 로봇 mTLS 침투 | **Information Disclosure / Spoofing** | 디스크 상의 평문 키(`.key`) 덤프로 관제망 무단 침투 및 명령 탈취 | **Zero Plaintext Key 정책 + PKCS#11 Non-extractable 토큰 격리** | 평문 키 파일 전무(0건) 및 위조 자체 서명 인증서 TLS 핸드셰이크 거절 |
| **ATK-06** | Phase 0/2 | Stage 2 UEFI db 서명 위조 및 AuthVar 변조 | **Tampering / Elevation** | 부트로더 인증 단계 우회 및 보안 변수 조작으로 영구 악성 루틴 상주 | **Stage 2 UEFI db (RSA-3072) + EKB Tag 4 UEFI 변수 인증키 연동** | BCH 헤더 내부 Stage 2 db 서명 손상 시 복호화 및 부팅 즉시 중단 |
| **ATK-07** | Phase 2 | 커널 런타임 공격 표면 장악 및 물리 메모리 직접 탈취 | **Elevation / Information Disclosure** | `/dev/mem` 직접 접근 및 unprivileged eBPF를 통한 링 0 메모리 스누핑 | **KSPP 하드닝 (`STRICT_DEVMEM`, `BPF_UNPRIV_DEFAULT_OFF` 등)** | 물리 메모리 주소 매핑 전면 차단 및 일반 권한 eBPF 로드 원천 거부 |
| **ATK-08** | Phase 3 | Normal World의 TrustZone 보안 메모리 침범 및 롤백 | **Tampering / Elevation** | 비보안 OS 커널 권한으로 Secure World(TZDRAM) 접근 및 상태 되돌리기 | **ARM TrustZone 하드웨어 메모리 방화벽 + RPMB Write Counter 인증** | 하드웨어 버스 에러 발생 및 직전 카운터 상태 재사용 시 Replay 거부 |
| **ATK-09** | Phase 5 | 런타임 실행 바이너리 변조 및 IMA xattr 서명 제거 | **Tampering** | 실행 바이너리의 무결성 검증 부재로 프로세스 변조 실행 가능 | **IMA Appraisal (`ima_policy=tcb`) + HSM ECDSA 서명 강제** | 유효한 `security.ima` 서명이 없는 바이너리 실행 시 `EACCES` 차단 |
| **ATK-10** | Phase 6 | 관제 통신 중간자 공격(MITM) 및 허위 명령 주입 | **Spoofing / Tampering** | 비보안 또는 단방향 TLS 통신으로 허위 모션/비상정지 해제 패킷 주입 | **TLS 1.3 mTLS (상호 인증) + PFS (Perfect Forward Secrecy)** | 미인증 클라이언트/위조 서버 접속 즉각 단절 및 패킷 스니핑 복독 불가 |

---

## 2. 상세 공격 시나리오별 심층 기술 명세

### [ATK-01] 부트로더/커널 암호문 변조 및 사설 서명키 우회 (Secure Boot)
- **공격 벡터**: 로봇의 플래시 메모리(eMMC)에 물리적으로 접근한 공격자가 커널 바이너리에 백도어 또는 악성 Syscall 훅을 주입하고, 자체 생성한 사설 RSA 키로 서명하여 기동 시도.
- **취약 환경 결과**: Secure Boot 및 SoC eFuse 검증이 꺼진 장비는 변조된 커널을 정상으로 인식하고 부팅하여 시스템 전권을 공격자에게 이양함.
- **방어 메커니즘**:
  - NVIDIA Jetson Orin/Thor SoC eFuse에 소각된 `FUSE_PKC_HASH`와 대조하여 부팅 직전 Stage 1 PKC 공개키 무결성 검증.
  - 8KB NVDA BCH 컨테이너의 AES-256-GCM 인증 태그를 검증하여 암호문 내 단 1비트의 변조라도 발생 시 복호화 실패 및 부팅 즉각 중단(`SECURE_BOOT_VIOLATION`, Exit code 2).
- **검증 코드**: `test_atk01_secureboot_rogue_key_and_kernel_tamper`

---

### [ATK-02] 비인가 루트킷 커널 모듈(`.ko`) 주입 (Kernel Module Signing)
- **공격 벡터**: 일반 애플리케이션 취약점으로 루트 권한을 획득한 공격자가 모터 드라이버나 센서 드라이버로 위장한 악성 커널 모듈(`.ko`)을 로드하여 커널 공간 장악 시도.
- **취약 환경 결과**: 커널 모듈 서명이 강제되지 않는 커널(`CONFIG_MODULE_SIG_FORCE=n`)은 서명 없는 루트킷을 적재하여 안티바이러스 및 감사 로그를 무력화함.
- **방어 메커니즘**:
  - 커널 빌드 시 `CONFIG_MODULE_SIG_FORCE=y`를 강제 적용.
  - SoftHSMv2 내부의 비공개 `KernelModuleSigningKey`(RSA-3072)로 서명된 모듈만 커널 공간 적재를 허용하며, 서명이 없거나 위조된 서명을 지닌 모듈은 커널 레벨에서 즉각 `EKEYREJECTED` 반환.
- **검증 코드**: `test_atk02_unsigned_and_tampered_kernel_module`

---

### [ATK-03] 오프라인 플래시 칩 분리 후 바이너리 변조 (EROFS + dm-verity)
- **공격 벡터**: 로봇을 물리적으로 탈취한 공격자가 eMMC 칩을 분리(Chip-off)하여 덤프한 후, 루트 파일시스템의 `/bin/bash`나 `/usr/bin/robot_control` 바이너리에 악의적 코드를 주입하고 재실장.
- **취약 환경 결과**: 일반 ext4/read-write 파일시스템은 재부팅 시 변조된 바이너리를 그대로 실행하여 로봇 동작 명령을 가로챔.
- **방어 메커니즘**:
  - 파일시스템을 읽기 전용 EROFS로 구성하고 커널 dm-verity 머클 해시 트리로 4KB 블록 단위 무결성 보장.
  - 블록 읽기 요청 시 실시간 SHA-256 연산을 수행하여 변조 블록 감지 즉시 커널 I/O 에러(`EIO`)를 발생시키며 사용자 공간 실행을 원천 차단.
  - 공격자가 머클 트리를 재계산하여 루트 해시를 교체하더라도, 오프라인 HSM 키로 서명된 `verity.roothash.sig` 검증에 실패하여 마운트가 거부됨.
- **검증 코드**: `test_atk03_dm_verity_offline_corruption_and_ro_enforcement`

---

### [ATK-04] 스텔스 악성코드 실행 및 원격 증명 Quote 재전송 (fTPM + IMA Attestation)
- **공격 벡터**: 런타임에 메모리 상에서 비인가 코드를 실행한 후, 원격 관제 서버(Fleet Server)의 무결성 검증을 회피하기 위해 이전에 캡처해 둔 정상 상태의 Attestation Quote를 가로채 재전송(Replay Attack) 시도.
- **취약 환경 결과**: 정적 헬스체크 보고나 타임스탬프 없는 텔레메트리는 캡처된 패킷 재전송에 속아 침해된 로봇을 정상으로 오판함.
- **방어 메커니즘**:
  - 관제 서버가 매 검증 시마다 난수 챌린지(`Nonce`)를 발급하고, fTPM 2.0 엔진이 해당 Nonce를 서명 데이터에 직접 바인딩하여 Quote 생성(Replay 불가).
  - 런타임에 실행된 모든 바이너리의 측정 해시가 fTPM PCR 10에 연쇄 누적(Extend)되며, IMA 측정 로그와 PCR 10 합성 해시 간 1비트라도 불일치 시 `UNTRUSTED`로 판정하여 관제망에서 즉시 격리.
- **검증 코드**: `test_atk04_runtime_ima_tamper_and_attestation_replay`

---

### [ATK-05] 파일시스템 개인키 탈취 및 복제 로봇 mTLS 침투 (Zero Plaintext Key)
- **공격 벡터**: 공격자가 디스크 덤프나 백업 아티팩트 검색을 통해 mTLS 인증서 개인키(`.pem`, `.key`)를 탈취하여, 임의의 PC에서 가짜 로봇으로 위장해 관제 서버에 접속 시도.
- **취약 환경 결과**: 디스크에 평문 개인키가 노출된 시스템은 키 유출 시 원격 관제망 전체가 장악되고 로봇 복제(Cloning)가 가능해짐.
- **방어 메커니즘**:
  - 플랫폼 전체에 Zero Plaintext Key 정책을 적용하여 디스크 어디에도 평문 개인키 파일 저장을 엄격히 금지(`audit_zero_keys.sh` 통과 필수).
  - 로봇의 기기 인증 키는 OP-TEE PKCS#11 TA 또는 SoftHSM 토큰 내부에서 추출 불가(`CKA_EXTRACTABLE=FALSE`) 속성으로 생성.
  - 관제 서버는 TLS 1.3 mTLS 핸드셰이크 시 공식 CA가 서명한 인증서 체인과 Secure World 토큰 기반 서명을 검증하므로, 공격자의 자체 서명 인증서 연결을 즉시 거절.
- **검증 코드**: `test_atk05_key_exfiltration_and_rogue_mtls_client`

---

### [ATK-06] Stage 2 UEFI db 서명 위조 및 AuthVar 변조 (UEFI Security)
- **공격 벡터**: 공격자가 부팅 체인 중 CPUBL(UEFI) 단계의 검증을 우회하기 위해 Stage 2 UEFI `db` 서명 블록을 조작하거나, 비보안 UEFI 변수를 조작하여 Secure Boot 비활성화를 시도.
- **취약 환경 결과**: 1단계 서명만 확인하거나 UEFI 변수가 평문 플래시에 저장되는 시스템은 UEFI 변수 조작을 통해 보안 부팅 모드를 무력화할 수 있음.
- **방어 메커니즘**:
  - 8KB NVDA BCH 컨테이너 헤더 오프셋 `152~184`에 정식 UEFI db 공개키 해시를 강제하고, 오프셋 `640~1024`의 Stage 2 RSA-3072 서명 무결성을 철저히 검증.
  - EKB Tag 4(`ekb_uefi_var_auth_key`)를 통해 OP-TEE RPMB 기반 Authenticated Variable 저장소의 접근을 암호학적으로 인가함.
- **검증 코드**: `test_atk06_uefi_db_signature_forgery_and_authvar_tamper`

---

### [ATK-07] 커널 런타임 공격 표면 장악 및 물리 메모리 직접 탈취 (KSPP Hardening)
- **공격 벡터**: 로봇의 사용자 공간 프로세스를 탈취한 공격자가 `/dev/mem` 또는 unprivileged eBPF 취약점을 악용하여 커널 링 0 메모리에 직접 접근하고 제어 흐름 가로채기 시도.
- **취약 환경 결과**: 기본 범용 커널 설정은 `/dev/mem`을 통한 하드웨어 레지스터 및 RAM 스누핑을 허용하여 기밀 키 및 프로세스 메모리 탈취에 취약함.
- **방어 메커니즘**:
  - `CONFIG_STRICT_DEVMEM=y` 및 `CONFIG_IO_STRICT_DEVMEM=y`를 강제하여 사용자 공간에서의 물리 주소 메모리 매핑을 커널단에서 원천 차단.
  - `CONFIG_BPF_UNPRIV_DEFAULT_OFF=y`를 통해 일반 프로세스의 eBPF 로드를 방지하여 사이드채널 및 투기적 실행 공격 표면 최소화.
  - `CONFIG_SLAB_FREELIST_HARDENED=y`, `CONFIG_SHUFFLE_PAGE_ALLOCATOR=y`, `CONFIG_STACKPROTECTOR_STRONG=y`를 적용하여 힙/스택 익스플로잇 방어.
- **검증 코드**: `test_atk07_kernel_hardening_kspp_attack_surface`

---

### [ATK-08] Normal World의 TrustZone 보안 메모리 침범 및 롤백 (TrustZone & RPMB)
- **공격 벡터**: Normal World(Linux 커널)를 장악한 공격자가 물리 버스를 직접 프로그래밍하여 Secure World 메모리(TZDRAM, `0x0e100000`)에 직접 접근을 시도하거나, fTPM/TEE 영구 저장소 블록을 과거 상태로 복제하여 롤백(Rollback) 시도.
- **취약 환경 결과**: 메모리 격리가 취약한 아키텍처에서는 커널 권한 탈취가 곧 TEE 자산 탈취로 이어지며, 롤백을 통해 폐기된 키나 취약한 이전 펌웨어 복원 가능.
- **방어 메커니즘**:
  - ARM TrustZone 아키텍처 기반 하드웨어 버스 방화벽(TZASC)이 Secure World 물리 메모리(EL3/S-EL1) 접근을 차단하여 비인가 접근 시 버스 에러 발생.
  - OP-TEE Secure Storage는 단조 증가 카운터(Monotonic Write Counter)가 내장된 RPMB(Replay Protected Memory Block)를 사용하여 과거 스냅샷 재주입 시 카운터 불일치로 롤백 공격을 즉각 거부(`TEE_ERROR_SECURITY`).
- **검증 코드**: `test_atk08_trustzone_memory_isolation_and_rpmb_rollback`

---

### [ATK-09] 런타임 실행 바이너리 변조 및 IMA xattr 서명 제거 (IMA Appraisal)
- **공격 벡터**: 로봇 내부의 감시 도구를 우회하기 위해 공격자가 EROFS 외부의 쓰기 가능 파티션(OverlayFS upperdir)에 악성 유틸리티를 배포하거나 기존 실행 파일의 확장 속성(`security.ima`)을 고의로 삭제하여 실행 시도.
- **취약 환경 결과**: 무결성 평가(Appraisal)가 미적용된 환경은 파일 속성이 제거되거나 조작된 바이너리도 문제없이 실행함.
- **방어 메커니즘**:
  - Linux 커널 IMA Appraisal 정책(`ima_policy=tcb`, `appraise_type=imasig`)을 활성화하여 파일 실행 시 xattr의 디지털 서명을 강제 검증.
  - 유효한 SoftHSM `ImaSigningKey`로 서명되지 않았거나 서명이 제거된 파일은 실행 시 커널에서 즉시 접근 거부(`EACCES` / `EPERM`) 발생.
  - 모든 측정 실패 및 접근 내역은 audit 로그 및 fTPM PCR 10에 남겨 사후 부인 방지.
- **검증 코드**: `test_atk09_ima_appraisal_bypass_and_stripped_xattr`

---

### [ATK-10] 관제 통신 중간자 공격(MITM) 및 허위 명령 주입 (TLS 1.3 mTLS & PFS)
- **공격 벡터**: 로봇과 클라우드 관제 센터 간의 무선 네트워크(Wi-Fi, 5G)에 개입한 공격자가 ARP 스푸핑 또는 가짜 AP를 설치하여 통신 패킷을 도청하고 가짜 제어 명령을 주입하거나 위조된 서버 인증서를 제시.
- **취약 환경 결과**: 단방향 TLS 또는 암호화되지 않은 프로토콜을 사용하는 경우 로봇이 가짜 서버의 악의적 모션 명령을 수신하여 충돌 및 파괴 발생.
- **방어 메커니즘**:
  - TLS 1.3 상호 인증(Mutual TLS)을 적용하여 클라이언트와 서버가 서로 사전에 인가된 루트 CA 서명 인증서를 보유하고 있는지 강제 검증.
  - 임의의 위조 인증서를 제시하는 중간자 서버에 대해 로봇 클라이언트는 즉시 연결을 거절(`Certificate Verification Failed`).
  - Ephemeral Diffie-Hellman 키 교환을 통한 완전 순방향 비밀성(PFS)을 보장하여 세션 키가 영구 보호됨.
- **검증 코드**: `test_atk10_mitm_network_spoofing_and_pfs_defense`

---

## 3. 자동화 공격 시뮬레이션 실행 및 결과 확인

전체 10대 공격 시나리오는 통합 단위 테스트 프레임워크를 통해 일괄 검증 가능함:

```bash
# 컨테이너 또는 로컬 환경에서 10대 공격-방어 테스트 실행
python3 -m unittest tests/test_attack_scenarios.py -v
```

### 정상 실행 결과 기준 (Expected Passing Output):
```text
test_atk01_secureboot_rogue_key_and_kernel_tamper ... ok
test_atk02_unsigned_and_tampered_kernel_module ... ok
test_atk03_dm_verity_offline_corruption_and_ro_enforcement ... ok
test_atk04_runtime_ima_tamper_and_attestation_replay ... ok
test_atk05_key_exfiltration_and_rogue_mtls_client ... ok
test_atk06_uefi_db_signature_forgery_and_authvar_tamper ... ok
test_atk07_kernel_hardening_kspp_attack_surface ... ok
test_atk08_trustzone_memory_isolation_and_rpmb_rollback ... ok
test_atk09_ima_appraisal_bypass_and_stripped_xattr ... ok
test_atk10_mitm_network_spoofing_and_pfs_defense ... ok

----------------------------------------------------------------------
Ran 10 tests in 12.450s

OK
```

모든 테스트 케이스는 **취약 기준선(Vulnerable Baseline, 실패/침해 발생)**과 **하드닝 플랫폼(Hardened Platform, 방어/차단 성공)**을 직접 대조 검증함으로써 보안 아키텍처의 유효성을 실증함.