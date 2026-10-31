---
title: "NVIDIA Jetson 물리 하드웨어 배포 및 플래싱 가이드"
description: "실제 Orin/Thor 물리 보드 복구 모드 진입, eFuse 영구 소각, EKB 스테이징 및 flash.sh 배포 절차"
---

> **Target Platform**: NVIDIA Jetson AGX Orin / Orin NX / Orin Nano (T234) 및 Jetson Thor (T264)  
> **BSP Version**: JetPack 7.2.1 / Jetson Linux R39.2.1 (Linux Kernel 6.8 Noble LTS)  
> **Security Standards**: SRD-SEC-001 (SoC eFuse/PKC), SRD-TEE-001 (OP-TEE/EKB), SRD-STR-001/002 (EROFS/dm-verity)

---

## 1. 개요 및 하드웨어 배포 아키텍처

본 가이드는 QEMU 가상 머신 환경에서 검증 완료된 보안 체계(NVIDIA Tegra PKC Secure Boot, EKB AES-256-GCM 암호화, KSPP 하드닝 리눅스 6.8 커널, SoftHSM 오프라인 서명 기반 불변 EROFS + dm-verity 스토리지, OP-TEE fTPM/PKCS#11 런타임)를 **실제 휴머노이드 로봇 탑재용 NVIDIA Jetson 물리 보드에 영구 배포 및 플래싱하기 위한 엔지니어링 표준 절차**를 명세함.

### 하드웨어 배포 4단계 흐름도
1. **타깃 커널 빌드 (`--target tegra`)**: QEMU 드라이버를 배제하고 순수 Tegra BSP 및 보안 하드닝 config fragment를 결합한 프로덕션 커널 컴파일.
2. **eFuse 퓨징 (One-Time Programmable, OTP)**: SoftHSMv2에서 안전하게 파생된 공개키(`SecureBootKey_pub.pem`)의 SHA-256 다이제스트를 Jetson SoC 내부 FUSE 레지스터에 영구 기록.
3. **EKB 및 부트로더 스테이징**: `gen_ekb.py`로 생성된 `eks_t234.img` 및 서명된 8KB NVDA BCH 커널 컨테이너를 L4T 플래시 파이프라인에 배치.
4. **보드 플래싱 및 스토리지 검증**: NVMe SSD 또는 eMMC 파티션에 불변 EROFS 루트 파일시스템과 dm-verity 해시 트리를 기록하고 최초 부팅 무결성 확인.

---

## 2. 물리 하드웨어 준비 및 복구 모드 (Force Recovery) 진입

### 하드웨어 인터페이스 요건
- **호스트 PC**: Ubuntu 22.04 LTS / 24.04 LTS x86_64 개발 머신 (DevContainer 또는 네이티브 Linux).
- **연결 케이블**: 고품질 USB-C to USB-A/C 데이터 케이블 (호스트 ↔ Jetson 복구 포트 연결용).
- **전원 공급**: Jetson 공식 19V/24V DC 어댑터 (안정적인 전원 인가 필수).

### Force Recovery Mode 진입 시퀀스
1. Jetson 보드의 전원 케이블을 분리하여 전원 완전 차단.
2. 호스트 PC와 Jetson의 **USB Type-C Flashing Port**(보드 전면 또는 디버그 포트)를 케이블로 직결.
3. 보드의 **Force Recovery 버튼(가운데 버튼)**을 누른 상태 유지.
4. **Power 버튼(우측 버튼)**을 1회 눌러 전원 인가.
5. 약 2초 후 **Force Recovery 버튼**에서 손을 뗌.
6. 호스트 터미널에서 USB 연결 인식 상태 검증:
   ```bash
   ./scripts/flash_jetson_hardware.sh check-board
   ```
   - 정상 감지 시 출력 예시:
     `Bus 001 Device 005: ID 0955:7023 NVIDIA Corp. APX` (0955:7023 = Jetson AGX Orin)

---

## 3. 프로덕션 하드웨어 타깃 커널 컴파일

QEMU 에뮬레이션 전용 드라이버(`qemu_compat.config`)를 제외하고, 실제 Tegra 하드웨어 SoC 컨트롤러 및 보안 하드닝 설정만 포함된 정품 커널을 빌드함:

```bash
# Tegra 하드웨어 전용 하드닝 커널 빌드
./scripts/build_kernel.sh --target tegra

# 공식 R39.2.1 8KB NVDA BCH 컨테이너 암호화 및 서명
./scripts/sign_jetson_secureboot.sh sign \
  --in build/kernel/arch/arm64/boot/Image \
  --out build/images/kernel.signed
```

---

## 4. SoC eFuse 퓨징 파이프라인 (안전 절차 및 소각)

> [!CAUTION]
> **eFuse 소각은 물리적으로 되돌릴 수 없는 일회성 작업(Irreversible OTP)임.**  
> 서명키(`SecureBootKey`)가 분실되거나 잘못 소각될 경우 보드가 영구적으로 부팅 불능(Hard Brick) 상태에 빠짐. 반드시 SoftHSM 토큰 백업 완료 후 진행할 것.

### 4.1. eFuse XML 명세 검증
NVIDIA 공식 R39.2.1 규격 설정 파일 [`configs/secureboot/fuse_config.xml`](file:///home/auking45/repos/humanoid-sec-platform/configs/secureboot/fuse_config.xml)을 점검:
- `PublicKeyHash`: SoftHSM `SecureBootKey_pub.pem`의 256-bit SHA-256 해시값 지정.
- `BootSecurityInfo`: `0x209` (RSA 3072 + SHA256 PKC 체계 활성화).
- `SecurityMode`: 테스트 단계에서는 `0x0`(열림), 최종 양산 배포 시 `0x1`(잠금).

### 4.2. 가상 시뮬레이션 테스트 (`--test` 모드)
물리 eFuse를 소각하기 전, 플래그 명령과 키 다이제스트 유효성을 무위험 상태로 시뮬레이션 검증:
```bash
./scripts/flash_jetson_hardware.sh fuse --board jetson-agx-orin-devkit --chip t234 --dry-run
```
- 실제 실행 명령 (L4T 내부):
  ```bash
  sudo ./odmfuse.sh -i 0x23 -c configs/secureboot/fuse_config.xml --test jetson-agx-orin-devkit
  ```

### 4.3. 영구 하드웨어 소각 실행 (Live Burn)
모든 키 검증 및 시뮬레이션 통과 후, 승인 하에 실제 퓨징 단행:
```bash
./scripts/flash_jetson_hardware.sh fuse --board jetson-agx-orin-devkit --chip t234 --live-burn
```

---

## 5. EKB 암호화 및 L4T 스테이징

eFuse 소각 완료 후, Secure World(OP-TEE)에서 사용할 대칭키 컨테이너(EKB)를 스테이징:
```bash
# EKB 및 서명된 커널/인증서를 Linux_for_Tegra/ 경로로 자동 복사
./scripts/flash_jetson_hardware.sh prepare-payloads --board jetson-agx-orin-devkit --chip t234
```
- 배치되는 주요 아티팩트:
  - `Linux_for_Tegra/bootloader/eks.img`: T234 EKB (OP-TEE 내부 로드용)
  - `Linux_for_Tegra/bootloader/pkc_pub.pem`: BootROM 검증용 PKC 공개키
  - `Linux_for_Tegra/kernel/kernel.signed`: 8KB NVDA BCH 서명 커널

---

## 6. 물리 보드 플래싱 (Flashing)

### 6.1. NVMe SSD 불변 스토리지 플래싱 (권장)
휴머노이드 로봇의 고속 대용량 스토리지를 위해 NVMe SSD에 플래싱 수행:
```bash
# 사전 드라이런 명령 확인
./scripts/flash_jetson_hardware.sh flash --board jetson-agx-orin-devkit --storage nvme0n1p1 --dry-run

# 실제 하드웨어 플래싱 단행
sudo ./sources/Linux_for_Tegra/flash.sh \
  -u keys_hsm/certs/SecureBootKey_pub.pem \
  jetson-agx-orin-devkit nvme0n1p1
```

### 6.2. Initrd 대용량 EROFS 플래싱 (`l4t_initrd_flash.sh`)
Ubuntu 24.04 Noble LTS EROFS 불변 이미지(`ubuntu_rootfs.erofs`) 및 dm-verity 해시 트리(`ubuntu_rootfs.verity`)를 대용량 NVMe 드라이브에 직접 기록하는 경우:
```bash
sudo ./sources/Linux_for_Tegra/tools/kernel_flash/l4t_initrd_flash.sh \
  -u keys_hsm/certs/SecureBootKey_pub.pem \
  --external-device nvme0n1p1 \
  -c tools/kernel_flash/flash_l4t_t234_nvme.xml \
  --showlogs jetson-agx-orin-devkit nvme0n1p1
```

---

## 7. 부팅 후 런타임 하드웨어 보안 진단

플래싱 완료 후 보드가 리부팅되면 직렬 콘솔(UART) 또는 SSH 세션(`root@jetson-board`)에 접속하여 보안 상태를 즉시 진단:

```bash
# 내장 보안 상태 진단 유틸리티 실행
sec-status
```

### 필수 확인 지표
1. **Secure Boot 활성화 여부**:
   - `dmesg | grep -i "secure boot"` -> `Secure Boot: Enabled (PKC: RSA 3072, SBK: Enabled)`
2. **OP-TEE & fTPM 드라이버 등록**:
   - `/dev/tee0`, `/dev/teepriv0`, `/dev/tpmrm0` 존재 확인
   - `tpm2_pcrread sha256:10` -> IMA에 의해 누적 측정된 실시간 PCR 10 해시값 출력 확인
3. **dm-verity 불변성 및 OverlayFS 결합**:
   - `/mnt/lower` -> EROFS 마운트 (읽기 전용, 1바이트 변조 시 커널 I/O 에러 차단)
   - `/` -> OverlayFS (상위 `tmpfs` rw 계층 결합으로 기존 Ubuntu 패키지 관리자 완벽 호환)
4. **Cloud mTLS 클라이언트 연동**:
   - `apps/mtls_client/mtls_client --server cloud-fleet.local:8443`
   - Normal World에 평문 키 노출 없이 OP-TEE PKCS#11 TA 하드웨어 토큰 내부 서명을 통한 상호 TLS 1.3 핸드셰이크 성공 확인.

---

## 8. 문제 해결 (Troubleshooting)

| 증상 | 추정 원인 | 해결 절차 |
| :--- | :--- | :--- |
| `lsusb`에 NVIDIA APX 장치 미표시 | USB-C 케이블 불량 또는 Recovery 진입 실패 | 고속 데이터 케이블 교체, Recovery 버튼 2초 누름 시퀀스 재시도 |
| `odmfuse.sh: Error: PKC key verification failed` | SoftHSM 키 다이제스트 불일치 | `./scripts/sign_jetson_secureboot.sh burn-fuses` 재실행하여 XML 재생성 |
| 플래싱 후 `VFS: Unable to mount root fs` | dm-verity roothash 불일치 또는 initrd 누락 | `build/images/ubuntu_verity_params.env` 파라미터 재확인 및 initrd 재패키징 |
| IMA 실행 시 `TPM-bypass` 경고 발생 | OP-TEE 초기화 지연 레이스 | 커널에 `0001-optee-init-before-ftpm-and-ima.patch` 패치 적용 여부 점검 |