# Feature 01 — NVIDIA Jetson Secure Boot & Stage 2 UEFI db 상세 기술 명세

> **문서 목적**: 실제 양산 휴머노이드 로봇 제품(NVIDIA Jetson Orin/Thor 기반)에 적용되는 하드웨어 Root of Trust(RoT) 기반 2단계 보안 부팅(Secure Boot) 및 암호화 부트로더 파이프라인의 실무 구현 명세를 정의함.  
> **적용 표준**: NVIDIA Jetson Linux R39.2.1 (JetPack 7.2.1), Tegra234 / Tegra264 공식 Secure Boot 가이드(`SecureBoot.html`)  
> **상태**: Approved / Production Baseline  

---

## 1. 아키텍처 개요 및 신뢰 체인 (Chain of Trust)

휴머노이드 로봇은 물리적 탈취 및 칩 오프(Chip-off) 공격에 상시 노출되어 있으므로, 하드웨어 eFuse에 소각된 해시값과 일치하지 않는 일체의 펌웨어/커널 실행을 BootROM 단계에서 원천 차단해야 함.

[![Secure Boot Sequence](../diagrams/secure_boot_sequence.svg)](../diagrams/secure_boot_sequence.html)
> 💡 *클릭 시 [Archify 인터랙티브 뷰어](../diagrams/secure_boot_sequence.html)로 이동하여 부팅 타임라인 애니메이션 확인 가능.*

---

## 2. NVIDIA Tegra SoC eFuse 레지스터 명세

양산 보드 배포 시 1회에 한해 비가역적으로 소각(OTP: One-Time Programmable)되는 하드웨어 eFuse 구성:

| eFuse 레지스터 | 비트 크기 | 프로비저닝 값 / 소각 대상 | 양산 제품에서의 보안 역할 |
| :--- | :---: | :--- | :--- |
| `SecurityMode` | 1 bit | `0x1` (`SECURITY_MODE_ENABLED`) | 디버그 JTAG 포트 비활성화 및 Production Secure Boot 강제 |
| `BootSecurityInfo` | 32 bits | `0x00000209` | `0x1` RSA-3072 PKC + `0x8` SBK 암호화 + `0x200` OEM Key 유효 플래그 |
| `FUSE_PKC_HASH` | 256 bits | SoftHSMv2 `SecureBootKey` (RSA-3072) SHA-256 해시 | Stage 1 BootROM/MB2가 검증할 정식 공개키 지문 (Fingerprint) |
| `FUSE_SECURE_BOOT_KEY` | 256 bits | 256비트 AES 대칭키 (`SBK`) | CPUBL 및 부트로더 페이로드 1차 대칭키 암호화 키 |
| `OEM_K1` / `OEM_KDK0` | 256 bits | 256비트 하드웨어 유도 루트 키 | OP-TEE EKB 및 fTPM/LUKS 디스크 암호화 키 파생의 루트 엔트로피 |

### 2.1. 공식 `<genericfuse>` XML (`configs/secureboot/fuse_config.xml`)
```xml
<genericfuse MagicId="0x45535546" version="1.0.0">
  <fuse name="BootSecurityInfo" size="4" value="0x00000209" />
  <fuse name="SecurityMode" size="4" value="0x1" />
  <fuse name="PublicKeyHash" size="64" value="4a96c03f4f2596bfb14330a4c02544d59fbc347cd3dcc8dba14e85b112b9e02d..." />
  <fuse name="SecureBootKey" size="32" value="0x112233445566778899aabbccddeeff00112233445566778899aabbccddeeff00" />
  <fuse name="OemK1" size="32" value="0x99aabbccddeeff00112233445566778899aabbccddeeff001122334455667788" />
</genericfuse>
```

---

## 3. EKB (Encrypted KeyBlob) v2.1 구조 및 태그 프로비저닝

`sources/optee/optee/samples/hwkey-agent/host/tool/gen_ekb/gen_ekb.py` 규격에 따라 `OemK1`(T234)으로부터 유도된 v2.1 암호화 키블롭(`build/images/eks_t234.img`):

```text
+-------------------------------------------------------------------------+
| EKB Header (NVEKBP\0\0, version 2.1, 16-byte random IV, Auth Tag)       |
+-------------------------------------------------------------------------+
| Tag 1  (sym_key, 32B)    : UEFI/CPUBL 커널 및 DTB 페이로드 복호화 대칭키      |
| Tag 2  (sym_key2, 16B)   : LUKS 암호화 디스크 마스터 볼륨 키              |
| Tag 4  (auth_key, 16B)   : OP-TEE RPMB 기반 UEFI Authenticated Variable 키  |
| Tag 5  (hwkey_app, 16B)  : 사용자 지정 보안 하드웨어 가속기 접근 키         |
| Tag 91 (ftpm_sn, 32B)    : fTPM 2.0 고유 하드웨어 일련번호                |
| Tag 92 (ftpm_eps, 32B)   : fTPM 2.0 Primary Endorsement Seed (EPS)       |
+-------------------------------------------------------------------------+
```

---

## 4. 8,192바이트 NVDA Boot Component Header (BCH) 레이아웃

`jetson_uefi_services.h` 규격에 따른 8KB 컨테이너 헤더 상세 오프셋 매핑:

- **Offset `0x0000` (`0`)**: `NVDA` (`BCH_HEADER_MAGIC`)
- **Offset `0x0098` (`152`)**: Stage 2 UEFI db 공개키 SHA-256 해시 (32바이트)
- **Offset `0x0100` (`256`)**: Stage 1 BootROM/MB2 PKC (RSA-3072, 384바이트) 서명
- **Offset `0x0280` (`640`)**: Stage 2 UEFI db (RSA-3072, 384바이트) 서명
- **Offset `0x1400` (`5120`)**: `BCRT` 매직 + 80B AAD (KDF 레이블 `CPUBL-PAYLOAD-DK`, 12B IV)
- **Offset `0x1450` (`5200`)**: AES-256-GCM 16바이트 인증 태그 (Authentication Tag)
- **Offset `0x2000` (`8192`)**: ISO/IEC 9797-1 Method 2 패딩된 커널 암호문 시작점

---

## 5. 2단계 검증 게이트 및 변조 방어 실증

```text
[ 부팅 시도 ]
      │
      ▼
[ Stage 1: eFuse FUSE_PKC_HASH 대조 ] ──(불일치)──> [ 즉각 차단: Boot Halted ]
      │ (일치)
      ▼
[ Stage 1: PKC RSA-3072 서명 검증 ]  ──(위조)───> [ 즉각 차단: Boot Halted ]
      │ (유효)
      ▼
[ Stage 2: UEFI db RSA-3072 서명 검증 ] ──(위조)──> [ 즉각 차단: SECURE_BOOT_VIOLATION ]
      │ (유효)
      ▼
[ EKB sym_key 기반 AES-256-GCM 복호화 ] ──(태그 불일치)─> [ 복호화 실패: Halt ]
      │ (성공)
      ▼
[ 복호화된 정식 커널(kernel.decrypted) 실행 ]
```

- **검증 도구**: `scripts/sign_jetson_secureboot.sh verify` 및 `tests/test_secureboot_chain.py`
- **방어 실증**: ATK-01(암호문 변조, 사설 키 주입, EKB 변조 차단) 및 ATK-06(Stage 2 UEFI db 서명 손상 차단) 100% 통과.

