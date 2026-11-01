# Feature 02 — ARM TrustZone, OP-TEE OS & fTPM 2.0 Deep-Dive

> **Purpose**: Defines the Trusted Execution Environment (TEE) specifications guaranteeing hardware-level isolation for cryptographic assets and TPM state even upon total Normal World (Linux kernel) compromise.  
> **Target Standard**: GlobalPlatform TEE Specifications, ARM TrustZone Architecture, TCG TPM 2.0 Library Specification  
> **Status**: Approved / Production Baseline  

---

## 1. Architectural Overview & Hardware Memory Firewall

The Normal World (Linux Kernel) and Secure World (OP-TEE) are physically separated by the ARM TrustZone Address Space Controller (TZASC).

- **TZDRAM (0x0e100000 ~ 0x10000000, 32MB)**:
  - Dedicated Secure World physical RAM region.
  - Any access attempt by the non-secure kernel (NS-EL1) immediately triggers a **hardware Bus Error / Data Abort**.
- **Shared Memory (SHM Pool)**:
  - Parameter marshalling passes strictly through non-secure shared memory buffers allocated by `/dev/tee0`.
- **SMC (Secure Monitor Call)**:
  - Normal World &rarr; EL3 TF-A Secure Monitor &rarr; S-EL1 OP-TEE Core for atomic context switching.

---

## 2. OP-TEE 4.2 Core & Early TA Architecture

To satisfy strict boot-timing requirements for production humanoids, essential security TAs are compiled directly into the firmware image:

```text
[ TF-A BL31 ] ──(Loads BL32)──> [ OP-TEE Core (S-EL1) ]
                                       │
         ┌─────────────────────────────┼─────────────────────────────┐
         ▼                             ▼                             ▼
  [ Early fTPM TA ]             [ PKCS#11 TA ]              [ RPMB Driver ]
  (UUID: bc50d971-...)          (UUID: fd02c9da-...)         (Hardware Anti-Replay)
  - PCR 10 hash chaining        - mTLS private key sealed    - Monotonic write counter
  - /dev/tpmrm0 interface       - In-SRAM C_Sign execution   - Persistent fTPM NVRAM
```

- **`CFG_IN_TREE_EARLY_TAS`**: Inlines the fTPM TA (`bc50d971-d4c9-42c4-82cb-343fb7f37896`) directly into the OP-TEE binary.
- **`CFG_PKCS11_TA=y`**: Activates the GlobalPlatform-compliant PKCS#11 v2.40 Trusted Application.

---

## 3. fTPM 2.0 (ms-tpm-20-ref) & Linux Kernel Integration

- **Discrete TPM-Free Architecture**:
  - Ports the Microsoft Open-Source TPM 2.0 Reference implementation into an OP-TEE TA.
  - Exposed via `drivers/char/tpm/tpm_ftpm_tee.c` as `/dev/tpm0` and `/dev/tpmrm0`.
- **Core Commands**:
  - `TPM2_PCR_Extend(PCR 10, Hash)`: Hash-chains Linux IMA execution measurements.
  - `TPM2_Quote(AK_Handle, Nonce, PCR_Selection)`: Generates cryptographic remote attestation quotes.
  - `TPM2_GetRandom(Num_Bytes)`: Supplies hardware-entropy random bytes.

---

## 4. eMMC RPMB Anti-Rollback Defense

Prevents rollback attacks where an attacker flashes a previous eMMC snapshot to restore revoked keys or obsolete vulnerable firmware:

1. **Authenticated Writes**: HMAC-SHA256 authenticated data frames signed with a secret shared between OP-TEE and the eMMC controller.
2. **Monotonic Write Counter**: Increments permanently from `N` to `N+1` upon every successful write.
3. **Replay Rejection (ATK-08)**: Replayed frames matching counter `N` are rejected with `TEE_ERROR_SECURITY` against current counter `N+1`.

---

## 5. Verification & Test Suite

- **100% GlobalPlatform xtest Pass**:
  - Complete pass across all test suites including `regression_1033` (Supplicant Plugin loader) and `regression_2001~2004` (iSocket TCP/UDP API).
- **ATK-08 Attack Defense**:
  - Verified hardware boundary enforcement and RPMB counter freshness verification (`tests/test_attack_scenarios.py`).

