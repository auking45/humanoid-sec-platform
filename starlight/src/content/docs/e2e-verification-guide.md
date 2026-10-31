---
title: "E2E 보안 검증 및 공격 시뮬레이션 가이드"
description: "전 계층 E2E 보안 검증 매뉴얼 및 취약 환경 vs 하드닝 플랫폼 Red/Blue Team 공격 시나리오(ATK-01~05)"
---

> **Document ID**: `HSP-VER-001`  
> **Target Platform**: NVIDIA JetPack 7.2.1 (Jetson Linux R39.2.1 / Kernel 6.8 / Ubuntu 24.04 Noble) & QEMU `aarch64` (`virt`, `secure=on`)

---

## 1. 개요 및 검증 철학 (Overview & Verification Philosophy)

- 본 문서는 **Humanoid Security Platform**의 전체 보안 계층(Secure Boot, TrustZone OP-TEE/fTPM, Kernel Hardening, EROFS + `dm-verity` + `OverlayFS`, IMA, SoftHSMv2/PKCS#11 mTLS, Remote Attestation)을 처음부터 끝까지 직접 실행하고 검증하기 위한 **End-to-End (E2E) 실습 매뉴얼**임.
- 단순 정상 동작 확인(Happy Path)에 그치지 않고, **해당 보안 통제가 비활성화되었거나 없을 때(Vulnerable Baseline) 공격이 어떻게 성공하는지**와 **하드닝 통제가 활성화되었을 때(Hardened Platform) 동일한 공격이 어떻게 즉시 차단·탐지되는지**를 1:1로 비교 검증함.
- 모든 검증 절차는 개발자 로컬 환경(VS Code Dev Container / Linux CLI) 및 GitHub Actions CI 파이프라인에서 동일하게 재현되도록 구성함.

---

## 2. E2E 검증 아키텍처 및 단계별 매트릭스 (Verification Matrix)

| 검증 단계 | 보안 도메인 | 검증 스크립트 / 명령 | 연관 SRD 요구사항 | 자동화 테스트 슈트 |
| :---: | :--- | :--- | :---: | :--- |
| **Step 1** | **HSM 키 프로비저닝 & 무평문 키 감사** | `keys_hsm/setup_softhsm.sh`<br>`keys_hsm/audit_zero_keys.sh` | `SRD-HSM-001` ~ `003` | `tests/test_hsm_keys.py` |
| **Step 2** | **NVIDIA Tegra PKC Secure Boot & eFuse** | `scripts/sign_jetson_secureboot.sh` | `SRD-BOOT-001` ~ `003` | `tests/test_secureboot_chain.py` |
| **Step 3** | **Dual-Profile Rootfs (`dm-verity` + `OverlayFS`)** | `scripts/build_rootfs.sh --minimal`<br>`scripts/build_rootfs.sh --ubuntu` | `SRD-STOR-001` ~ `004` | `tests/test_ftpm_ima.py` |
| **Step 4** | **TrustZone Cold Boot & Ubuntu 24.04 전환** | `scripts/run_qemu.sh --ubuntu --optee-chain --secureboot` | `SRD-TEE-001` ~ `004` | `tests/test_boot_optee.py`<br>`tests/test_secureboot_chain.py` |
| **Step 5** | **PKCS#11 mTLS 1.3 & Remote Attestation** | `apps/mtls_client/mtls_ verify.py`<br>`apps/attestation_agent/verifier.py` | `SRD-COM-001` ~ `002`<br>`SRD-INT-001` ~ `003` | `tests/test_secure_mtls.py` |
| **Step 6** | **Red/Blue Team 5대 공격 시나리오 실증** | `scripts/run_attack_demo.sh` | 전 계층 통합 방어 | `tests/test_attack_scenarios.py` |

---

## 3. 단계별 E2E 검증 절차 (Step-by-Step Verification Procedure)

### 3.1. Step 1 — SoftHSMv2 토큰 초기화 및 무평문 키(Zero Plaintext Key) 감사
- 오프라인 서명키(`SecureBootKey`, `KernelModuleSigningKey`, `DmVeritySigningKey`, `ImaSigningKey`, `DeviceEnrollmentCaKey`) 및 로봇 신원 키(`HumanoidDeviceIdentityKey`)를 SoftHSMv2 토큰 내부에서 비추출(`CKA_EXTRACTABLE=FALSE`) 속성으로 생성하고 디스크 내 평문 개인키 부재를 검증함.

```bash
# 1. SoftHSMv2 토큰 초기화 및 PKCS#11 키쌍 프로비저닝
bash keys_hsm/setup_softhsm.sh

# 2. 저장소 전체 무평문 개인키(.pem, .key) 전수 감사 실행
bash keys_hsm/audit_zero_keys.sh
```
- **기대 결과**:
  - `keys_hsm/certs/` 하위에 공개키 및 인증서만 추출되며, 개인키는 PKCS#11 토큰 내부에만 존재함.
  - `Zero Plaintext Key Policy: PASSED (0 plaintext private keys)` 출력 확인.

### 3.2. Step 2 — NVIDIA Jetson Tegra PKC Secure Boot 서명 및 eFuse 검증
- SoC eFuse 설정 파일(`configs/secureboot/tegra_fuses.json`)에 `SecureBootKey` 공개키의 SHA-256 다이제스트(`FUSE_PKC_HASH`)를 기록하고, Linux 커널 이미지를 `NVD1` 인증 컨테이너(`build/images/kernel.signed`)로 서명 및 검증함.

```bash
# 1. SoC eFuse 프로비저닝 (FUSE_PKC_HASH 및 보안 모드 활성화)
bash scripts/sign_jetson_secureboot.sh burn-fuses --out configs/secureboot/tegra_fuses.json

# 2. 커널 이미지 서명 및 eFuse 대조 검증
bash scripts/sign_jetson_secureboot.sh sign --in build/kernel/arch/arm64/boot/Image --out build/images/kernel.signed
bash scripts/sign_jetson_secureboot.sh verify --in build/images/kernel.signed

# 3. 1바이트 변조 및 미등록 키(Rogue Key) 차단 자가 테스트
bash scripts/sign_jetson_secureboot.sh tamper-test
```
- **기대 결과**:
  - 정상 서명 컨테이너는 `PASS: Container authenticated successfully` 출력.
  - 1바이트 페이로드 변조, 서명 변조, 미등록 eFuse 해시 대조 시 즉시 `FAIL` 반환 및 부팅 차단 확인.

### 3.3. Step 3 — Dual-Profile 불변 루트 파일시스템(`EROFS` + `dm-verity`) 빌드
- 목적에 따라 초경량 검증 프로필(`--minimal`) 또는 NVIDIA JetPack 7.2.1 공식 Ubuntu 24.04 LTS 전체 프로필(`--ubuntu`)을 불변 EROFS 이미지 및 SHA-256 `dm-verity` Merkle 해시 트리로 패키징함.

```bash
# Profile 1: CI 및 초고속 부팅 검증용 Minimal EROFS + dm-verity 빌드
bash scripts/build_rootfs.sh --minimal

# Profile 2: 공식 L4T R39.2.1 Ubuntu 24.04 LTS 전체 EROFS + dm-verity 빌드
bash scripts/build_rootfs.sh --ubuntu
```
- **기대 결과**:
  - `build/images/ubuntu_rootfs.erofs` (읽기 전용 데이터 이미지), `build/images/ubuntu_rootfs.verity` (Merkle 해시 트리), `build/images/ubuntu_verity.roothash.sig` (SoftHSMv2 PKCS#11 서명) 생성 완료.
  - 빌드 과정 내 `veritysetup verify` 및 1바이트 변조 데이터 차단 테스트(`Tamper-resistance verification: PASSED`) 자동 통과.

### 3.4. Step 4 — TrustZone Cold Boot 및 Ubuntu 24.04 `OverlayFS` 런타임 검증
- `TF-A (BL1 -> BL2 -> BL31)` -> `OP-TEE (BL32 + Early fTPM TA + PKCS#11 TA)` -> `Linux Kernel 6.8` -> `Initramfs (dm-verity 검증 마운트 + OverlayFS 결합)` -> `Ubuntu 24.04 LTS`로 이어지는 전체 콜드 부팅 체인을 기동함.

```bash
# 대화형 Ubuntu 24.04 LTS 보안 셸 기동
bash scripts/run_qemu.sh --ubuntu --optee-chain --secureboot
```
- **Ubuntu 24.04 셸(`root@jetson-ubuntu24:~#`) 내부 실습 명령어**:
```bash
# 1. 플랫폼 보안 상태 종합 점검 (OS, Kernel, OverlayFS, dm-verity, OP-TEE, fTPM, IMA, dpkg)
sec-status

# 2. Ubuntu 패키지 매니저 동작 및 설치된 패키지 확인
dpkg --version
apt --version

# 3. OverlayFS 쓰기 계층(upperdir) 동작 확인 (정상 쓰기 허용)
echo "Humanoid-Test-Config" > /etc/robot_runtime.conf && cat /etc/robot_runtime.conf

# 4. 하단 dm-verity EROFS 원본 계층(/mnt/lower) 덮어쓰기 공격 시도 (읽기 전용 차단 확인)
touch /mnt/lower/malicious_backdoor
# -> touch: cannot touch '/mnt/lower/malicious_backdoor': Read-only file system

# 5. 검증 완료 후 가상머신 안전 종료
poweroff
```

---

## 4. Red/Blue Team 공격 시나리오 명세 (`ATK-01` ~ `ATK-05`)

보안 통제가 없는 취약 환경(Vulnerable Baseline)과 본 플랫폼의 하드닝 환경(Hardened Platform)에서 동일한 공격을 수행하여 방어 효과를 실증함.

| 시나리오 ID | 공격 명칭 (Attack Scenario) | 취약 환경 (보안 기능 미적용 시) | 하드닝 플랫폼 (보안 기능 적용 시) | 검증 테스트 메소드 |
| :---: | :--- | :--- | :--- | :--- |
| **ATK-01** | **악성 커널 주입 및 위조 키(`Rogue Key`) 서명 우회 공격** | 서명/eFuse 검증 부재로 변조된 커널 또는 공격자 키로 서명된 커널이 그대로 부팅됨 (`COMPROMISED`) | 1) 커널 1바이트 변조 시 RSA-3072-PSS 서명 불일치로 즉시 차단<br>2) 공격자의 위조 키로 재서명하더라도 SoC eFuse(`FUSE_PKC_HASH`) 해시와 불일치하여 부팅 즉시 거부 (`BLOCKED`) | `test_atk01_secureboot_rogue_key_and_kernel_tamper` |
| **ATK-02** | **서명되지 않은 악성 커널 모듈(`.ko` 루트킷) 로드 공격** | `CONFIG_MODULE_SIG_FORCE` 미적용 시 미서명 모듈 또는 변조된 `.ko` 파일이 커널 공간에 적재됨 (`COMPROMISED`) | `KernelModuleSigningKey` 서명이 없거나 모듈 코드가 1바이트라도 변조된 경우 서명 검증이 즉시 실패하여 커널 모듈 적재 차단 (`BLOCKED`) | `test_atk02_unsigned_and_tampered_kernel_module` |
| **ATK-03** | **루트 파일시스템 바이너리 오프라인 변조 및 런타임 영구 감염(Persistence) 공격** | 일반 쓰기 가능(rw) 파일시스템 및 해시 트리 미적용 시 디스크 섹터 변조 및 시스템 바이너리 변조가 영구 유지됨 (`COMPROMISED`) | 1) 오프라인 디스크 섹터 1바이트 변조 시 `dm-verity` Merkle 트리 검증 실패로 즉시 차단<br>2) 런타임 하단 `/mnt/lower` EROFS는 커널 수준 읽기 전용으로 수정 불가하며, `OverlayFS` 상위 계층(`tmpfs`) 변경분은 재부팅 시 100% 휘발 복구됨 (`BLOCKED`) | `test_atk03_dm_verity_offline_corruption_and_ro_enforcement` |
| **ATK-04** | **런타임 악성 바이너리 실행 은폐 및 원격 증명(Quote) 재전송(Replay) 공격** | IMA 측정 및 Nonce 검증 부재 시 악성코드 실행 후에도 정상 노드로 위장하거나 이전 정상 Quote를 재전송하여 검증 통과 (`COMPROMISED`) | 1) 비인가 바이너리 실행 시 fTPM `PCR 10` 값이 변경되어 Golden PCR과 불일치<br>2) 이전 정상 Quote 재전송 시 Verifier의 일회용 Nonce 불일치로 차단<br>3) IMA 이벤트 로그만 위조할 경우 `PCR 10` 해시 체인 재연산 불일치로 즉시 적발 (`BLOCKED`) | `test_atk04_runtime_ima_tamper_and_attestation_replay` |
| **ATK-05** | **파일시스템 개인키 탈취(Key Exfiltration) 및 위조 인증서 mTLS 침투 공격** | 디스크에 보관된 `.pem`/`.key` 개인키 파일이 탈취되어 복제 로봇 생성 및 미인가 클라이언트의 서버 접속 허용 (`COMPROMISED`) | 1) 디스크 내 평문 개인키 0건 및 PKCS#11 `CKA_EXTRACTABLE=FALSE` 정책으로 키 추출 원천 불가<br>2) 공격자 자체 서명(Rogue CA) 인증서로 mTLS 접속 시도 시 TLS 1.3 상호 인증 단계에서 핸드셰이크 즉시 거절 (`BLOCKED`) | `test_atk05_key_exfiltration_and_rogue_mtls_client` |

---

## 5. 원클릭 공격 데모 및 전체 테스트 슈트 실행 방법 (Automated Execution)

### 5.1. 원클릭 Red/Blue Team 공격 시뮬레이션 데모 실행
- `ATK-01`부터 `ATK-05`까지의 5대 공격 시나리오를 순차 실행하고 **[취약 환경 결과 vs 하드닝 방어 결과]** 요약 리포트를 출력함.

```bash
bash scripts/run_attack_demo.sh
```

### 5.2. 전체 단위·통합·공격 시나리오 테스트 슈트 일괄 실행
- Phase 2 ~ Phase 7의 모든 보안 검증 테스트를 일괄 실행함.

```bash
# 전체 테스트 슈트 실행 (test_boot_optee, test_secureboot_chain, test_ftpm_ima, test_hsm_keys, test_secure_mtls, test_attack_scenarios)
python3 -m unittest discover -s tests -v

# 공격 시나리오 테스트만 단독 실행
python3 -m unittest tests/test_attack_scenarios.py -v
```