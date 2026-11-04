# Security Beginner's Guide to ARM TrustZone and fTPM 2.0

> **Purpose**: Explains the limitations of software-only security, the architectural principles of ARM TrustZone hardware isolation, and the mechanics of OP-TEE firmware TPM (fTPM 2.0) and RPMB anti-rollback storage in clear, beginner-friendly terms.
> **Audience**: Security beginners, Linux systems developers, embedded firmware engineers
> **Status**: Production Guide

> [!TIP] 📽️ **Interactive Seminar Slide Deck (Reveal.js)**
> An interactive fullscreen presentation deck is available for this technology guide:
> 👉 **[Open Fullscreen Slide Deck (`guide_02_trustzone_and_ftpm.html`)](/humanoid-sec-platform/presentations/guide_02_trustzone_and_ftpm.html)** | [📊 Presentation Hub](/humanoid-sec-platform/presentations/index.html)

---

## 1. Why Software Alone Cannot Stop OS Exploitation

In traditional operating system architectures, the kernel (Ring 0 / EL1) holds omnipotent authority over memory and peripheral devices.
However, this model suffers from a foundational flaw:

> **"What happens if an attacker exploits a kernel bug and seizes Ring 0 kernel privileges?"**

Once the kernel is compromised, all software-based defenses—antivirus, SELinux policies, iptables rules, and DAC permissions—can be silently neutralized by the attacker. Because the kernel itself is untrusted, security programs running inside it can no longer reliably prove their own integrity.

To resolve this paradox, ARM introduced hardware-enforced compartmentalization that even a rogue kernel cannot violate: **ARM TrustZone technology**.

---

## 2. ARM TrustZone Architecture: Two Worlds

TrustZone splits a single physical CPU core and bus infrastructure into **two isolated hardware domains**:

[![ARM TrustZone World Switch](../../diagrams/trustzone_world_switch.svg)](../../diagrams/trustzone_world_switch.html)
> 💡 *Click to open the [Archify Interactive Viewer](../../diagrams/trustzone_world_switch.html) illustrating Normal World and Secure World hardware SMC context transitions.*

### 2.1. Normal World vs Secure World
1. **Normal World (Rich Execution Environment - REE)**:
   - Houses the standard **Linux Kernel 6.8 (EL1)** and **user applications (EL0)**.
   - Assumed untrusted (Zero-Trust): because complex network stacks and AI frameworks run here, vulnerabilities are anticipated.
2. **Secure World (Trusted Execution Environment - TEE)**:
   - Houses the minimal, security-hardened **OP-TEE Core (S-EL1)** and isolated **Trusted Applications (TA, S-EL0)**.
   - Never exposes open network sockets or raw disk filesystems; only executes trusted cryptographic workloads.

### 2.2. Hardware Memory Firewall (TZDRAM)
The memory controller on TrustZone-enabled SoCs (such as NVIDIA Orin/Thor) monitors hardware **Non-Secure (NS) bus bits**:
- Normal World memory transactions carry the signal `NS = 1`.
- If a Normal World CPU core attempts to read or write to Secure World physical RAM (TZDRAM / Secure SRAM), **the memory controller hardware halts the transaction and raises a hardware Bus Fault exception**.
- Even if a root exploit allows arbitrary kernel physical memory patching, the Secure World remains physically untouchable.

### 2.3. World Transitions via SMC (Secure Monitor Call)
Transitioning between worlds requires an architectural assembly instruction: **`smc #0` (Secure Monitor Call)**:
1. The Linux kernel driver (`tee.ko`) loads request registers and executes `smc #0`.
2. The core traps into the highest privilege level: **EL3 (TF-A Secure Monitor)**.
3. TF-A saves Normal World registers, flips the hardware NS bit to `0`, and transfers control to **Secure World (OP-TEE)**.
4. OP-TEE processes the cryptographic request and returns only output parameters back through EL3.

---

## 3. Discrete TPM (dTPM) vs OP-TEE Firmware TPM (fTPM)

The Trusted Platform Module (TPM) is the global standard for cryptographic measurements and secure key storage:

| Comparison | Discrete TPM (dTPM) | OP-TEE Firmware TPM (fTPM) — Our Platform |
| :--- | :--- | :--- |
| **Implementation** | Soldered dedicated IC connected via I2C/SPI bus | Software TA running inside ARM TrustZone Secure World |
| **Physical Security** | **Vulnerable to Inter-Chip Probing**: Logic analyzers attached to external bus pins can sniff unencrypted keys | **Probing-Immune**: All bus transactions remain strictly on-chip inside SoC silicon |
| **BOM Cost** | Extra silicon cost ($2 ~ $5 per robot) | **$0 (Zero additional hardware bill-of-materials)** |
| **Performance** | Constrained by slow serial bus clock rates | Multi-megabyte/s on-chip SRAM throughput |
| **Standard Compliance** | TCG TPM 2.0 compliant | TCG TPM 2.0 compliant (`ms-tpm-20-ref` official reference TA) |

Our platform integrates the **`ms-tpm-20-ref` fTPM 2.0 TA** inside OP-TEE, eliminating external hardware costs while neutralizing physical bus-sniffing attacks.

---

## 4. TPM PCR Hash-Chaining & Cumulative Integrity Measurement

fTPM's central feature is system integrity measurement through **Platform Configuration Registers (PCRs)**.

[![fTPM PCR 10 Hash-Chain](../../diagrams/tpm_pcr_extend_flow.svg)](../../diagrams/tpm_pcr_extend_flow.html)
> 💡 *Click to open the [Archify Interactive Viewer](../../diagrams/tpm_pcr_extend_flow.html) showing PCR 10 hash extension and remote challenge-response flows.*

### 4.1. The One-Way Mathematical Nature of PCR Extend
Standard CPU registers allow arbitrary overwrite (`MOV reg, 0`).
In contrast, TPM PCRs feature **no overwrite instruction**. They can only be modified through the cryptographic **Extend** operation:

$$\text{PCR}_{new} = \text{SHA-256}(\text{PCR}_{old} \parallel \text{Hash}(\text{Executed Binary}))$$

- At boot, PCR 10 starts at zero.
- Whenever an executable runs, the Linux IMA subsystem measures its cryptographic digest and issues an Extend call to fTPM PCR 10.
- **Irreversibility**: If malware executes even once, PCR 10 diverges from the golden baseline. Mathematically, no attacker—even with kernel privileges—can restore or spoof the register back to its clean state without rebooting.

---

## 5. RPMB (Replay Protected Memory Block) Anti-Rollback

A common embedded attack is the **Rollback (Replay) Attack**: an attacker replaces an encrypted flash partition with an older, legitimate backup containing a known security vulnerability.

eMMC and UFS memory chips mitigate this through an isolated **RPMB hardware partition**:
1. **Shared eFuse Authentication Key**: During provisioning, a secret key is burned into SoC eFuses and flash controller memory.
2. **Monotonic Write Counter**: Each write operation increments an internal, non-resettable hardware counter.
3. **Replay Rejection**: If an attacker attempts to write stale data with an older counter value, the flash hardware rejects the write immediately.

OP-TEE and fTPM store all non-volatile NVRAM data and anti-rollback counters inside **RPMB storage (`CFG_RPMB_FS=y`)**.

---

## 6. Summary

- **ARM TrustZone**: Isolates cryptographic keys and sensitive algorithms in Secure World, rendering them unreachable even if Normal World Linux is completely compromised.
- **fTPM 2.0**: Delivers hardware-grade TCG TPM 2.0 capabilities with zero additional BOM cost and immunity against bus probing.
- **PCR Hash-Chaining**: Cryptographically captures all software execution into non-resettable registers.
- **RPMB Anti-Rollback**: Prevents software downgrade attacks via hardware monotonic counters.

