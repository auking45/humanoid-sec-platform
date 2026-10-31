# NVIDIA Jetson Physical Hardware Deployment & Flashing Guide

> **Target Platform**: NVIDIA Jetson AGX Orin / Orin NX / Orin Nano (T234) and Jetson Thor (T264)  
> **BSP Version**: JetPack 7.2.1 / Jetson Linux R39.2.1 (Linux Kernel 6.8 Noble LTS)  
> **Security Standards**: SRD-SEC-001 (SoC eFuse/PKC), SRD-TEE-001 (OP-TEE/EKB), SRD-STR-001/002 (EROFS/dm-verity)

---

## 1. Overview & Deployment Architecture

This guide specifies standard engineering procedures to deploy and permanently flash the security architecture validated in the QEMU virtual platform (NVIDIA Tegra PKC Secure Boot, EKB AES-256-GCM encryption, KSPP hardened Linux 6.8 kernel, SoftHSM offline-signed immutable EROFS + dm-verity storage, OP-TEE fTPM/PKCS#11 runtime) onto **physical NVIDIA Jetson boards powering humanoid robots**.

### 4-Stage Deployment Workflow
1. **Target Kernel Build (`--target tegra`)**: Compile production Linux kernel combining Tegra defconfig and security hardening fragments without QEMU drivers.
2. **eFuse Fusing (One-Time Programmable, OTP)**: Permanently burn the SHA-256 digest of `SecureBootKey_pub.pem` derived from SoftHSMv2 into SoC eFuse registers.
3. **EKB & Bootloader Staging**: Place `gen_ekb.py`-generated `eks_t234.img` and 8KB NVDA BCH signed kernel containers into the L4T flashing workspace.
4. **Board Flashing & Storage Verification**: Flash the immutable EROFS root filesystem and dm-verity Merkle hash tree to NVMe SSD or eMMC and verify first-boot integrity.

---

## 2. Hardware Preparation & Force Recovery Mode

### Hardware Requirements
- **Host Workstation**: Ubuntu 22.04 LTS / 24.04 LTS x86_64 host (DevContainer or native Linux).
- **Interface Cable**: High-speed USB-C to USB-A/C data cable (Host ↔ Jetson recovery port).
- **Power Supply**: Official Jetson 19V/24V DC power adapter (stable supply mandatory).

### Force Recovery Sequence
1. Unplug the power cable from the Jetson board to power down completely.
2. Connect the **USB Type-C Flashing Port** to the host PC using the data cable.
3. Press and hold the **Force Recovery button** (middle button).
4. Press and release the **Power button** (right button).
5. Release the **Force Recovery button** after 2 seconds.
6. Verify USB device recognition on the host workstation:
   ```bash
   ./scripts/flash_jetson_hardware.sh check-board
   ```
   - Successful detection output:
     `Bus 001 Device 005: ID 0955:7023 NVIDIA Corp. APX` (0955:7023 = Jetson AGX Orin)

---

## 3. Production Hardware Target Kernel Compilation

Compile the authentic Tegra kernel including SoC drivers and security hardening while excluding QEMU virtualization drivers:

```bash
# Build Tegra-specific hardened kernel
./scripts/build_kernel.sh --target tegra

# Sign and encrypt official R39.2.1 8KB NVDA BCH container
./scripts/sign_jetson_secureboot.sh sign \
  --in build/kernel/arch/arm64/boot/Image \
  --out build/images/kernel.signed
```

---

## 4. SoC eFuse Burning Pipeline (Safety & Execution)

> [!CAUTION]
> **eFuse burning is an IRREVERSIBLE ONE-TIME PROGRAMMABLE (OTP) operation.**  
> If signing keys (`SecureBootKey`) are lost or burned improperly, the hardware is permanently rendered unbootable (Hard Brick). Always ensure full SoftHSM token backup before proceeding.

### 4.1. eFuse XML Specification
Inspect [`configs/secureboot/fuse_config.xml`](file:///home/auking45/repos/humanoid-sec-platform/configs/secureboot/fuse_config.xml):
- `PublicKeyHash`: Specifies 256-bit SHA-256 digest of SoftHSM `SecureBootKey_pub.pem`.
- `BootSecurityInfo`: `0x209` (RSA 3072 + SHA256 PKC scheme enabled).
- `SecurityMode`: `0x0` (open/test stage) vs. `0x1` (production lock).

### 4.2. Simulation Testing (`--test` mode)
Simulate fuse burning without modifying physical hardware:
```bash
./scripts/flash_jetson_hardware.sh fuse --board jetson-agx-orin-devkit --chip t234 --dry-run
```
- Direct L4T invocation:
  ```bash
  sudo ./odmfuse.sh -i 0x23 -c configs/secureboot/fuse_config.xml --test jetson-agx-orin-devkit
  ```

### 4.3. Permanent Hardware Fusing (Live Burn)
Upon full validation and formal approval, execute live fuse burning:
```bash
./scripts/flash_jetson_hardware.sh fuse --board jetson-agx-orin-devkit --chip t234 --live-burn
```

---

## 5. EKB Encryption & Staging

Stage symmetric key containers (EKB) for Secure World (OP-TEE):
```bash
# Automatically stage EKB, signed kernel, and public certs into Linux_for_Tegra/
./scripts/flash_jetson_hardware.sh prepare-payloads --board jetson-agx-orin-devkit --chip t234
```
- Core staged artifacts:
  - `Linux_for_Tegra/bootloader/eks.img`: T234 EKB (loaded by OP-TEE)
  - `Linux_for_Tegra/bootloader/pkc_pub.pem`: PKC public key for BootROM
  - `Linux_for_Tegra/kernel/kernel.signed`: 8KB NVDA BCH signed kernel

---

## 6. Board Flashing

### 6.1. NVMe SSD Immutable Rootfs Flashing (Recommended)
Flash high-performance NVMe storage for humanoid robots:
```bash
# Preview flash command
./scripts/flash_jetson_hardware.sh flash --board jetson-agx-orin-devkit --storage nvme0n1p1 --dry-run

# Execute physical hardware flash
sudo ./sources/Linux_for_Tegra/flash.sh \
  -u keys_hsm/certs/SecureBootKey_pub.pem \
  jetson-agx-orin-devkit nvme0n1p1
```

### 6.2. Initrd EROFS Large Storage Flash (`l4t_initrd_flash.sh`)
Directly flash Ubuntu 24.04 Noble LTS EROFS (`ubuntu_rootfs.erofs`) and dm-verity (`ubuntu_rootfs.verity`):
```bash
sudo ./sources/Linux_for_Tegra/tools/kernel_flash/l4t_initrd_flash.sh \
  -u keys_hsm/certs/SecureBootKey_pub.pem \
  --external-device nvme0n1p1 \
  -c tools/kernel_flash/flash_l4t_t234_nvme.xml \
  --showlogs jetson-agx-orin-devkit nvme0n1p1
```

---

## 7. Post-Boot Runtime Security Verification

After the board reboots, access the serial UART console or SSH session (`root@jetson-board`) and inspect security state:

```bash
# Execute pre-installed diagnostic helper
sec-status
```

### Key Verification Metrics
1. **Secure Boot Status**:
   - `dmesg | grep -i "secure boot"` -> `Secure Boot: Enabled (PKC: RSA 3072, SBK: Enabled)`
2. **OP-TEE & fTPM Devices**:
   - Confirm `/dev/tee0`, `/dev/teepriv0`, and `/dev/tpmrm0` presence
   - `tpm2_pcrread sha256:10` -> Displays real-time cumulative boot measurements
3. **dm-verity Immutability & OverlayFS**:
   - `/mnt/lower` -> EROFS read-only mount (1-byte modification triggers immediate kernel I/O error)
   - `/` -> OverlayFS union with upper `tmpfs` rw layer (fully compatible with Ubuntu package managers)
4. **Cloud mTLS Handshake**:
   - `apps/mtls_client/mtls_client --server cloud-fleet.local:8443`
   - Verifies hardware token in-place signing via OP-TEE PKCS#11 TA without plaintext key exposure.

---

## 8. Troubleshooting

| Symptom | Probable Cause | Corrective Action |
| :--- | :--- | :--- |
| NVIDIA APX device not visible in `lsusb` | Defective USB cable or failed recovery trigger | Replace with high-speed data cable; re-attempt 2-second recovery button sequence |
| `odmfuse.sh: Error: PKC key verification failed` | SoftHSM key hash mismatch | Re-run `./scripts/sign_jetson_secureboot.sh burn-fuses` to regenerate XML |
| `VFS: Unable to mount root fs` after flash | dm-verity roothash mismatch or missing initrd | Check `build/images/ubuntu_verity_params.env` and re-package initrd |
| `ima: No TPM chip found, activating TPM-bypass!` | Early driver race condition | Verify `0001-optee-init-before-ftpm-and-ima.patch` is applied to kernel |
