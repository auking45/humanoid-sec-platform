---
title: "01. Key Management & PKCS#11: Why Plaintext Keys on Disk Are Fatal"
description: "Beginner guide to key security, SoftHSMv2 token isolation, and C_Sign signing delegation"
---

> **Purpose**: Demystifies fundamental cryptographic key management concepts, explains why storing plaintext keys on disk is fatal, and walks through the PKCS#11 standard and HSM-based signing delegation architecture in accessible terms.  
> **Audience**: Security beginners, embedded/robotics software developers, DevSecOps engineers  
> **Status**: Production Guide  

> [!TIP] 📽️ **Interactive Seminar Slide Deck (Reveal.js)**
> An interactive fullscreen presentation deck is available for this technology guide:
> 👉 **[Open Fullscreen Slide Deck (`guide_01_key_management_and_pkcs11.html`)](/humanoid-sec-platform/presentations/guide_01_key_management_and_pkcs11.html)** | [📊 Presentation Hub](/humanoid-sec-platform/presentations/index.html)  

---

## 1. Rule Zero of Security: "A Private Key on Disk Belongs to the Attacker"

The most dangerous pitfall in software engineering when dealing with certificates and crypto keys is **saving raw private key files (`.pem`, `.key`) on the host filesystem** (e.g., `/etc/ssl/private/`).

Many engineers believe setting file permissions to `chmod 600` is sufficient, but file permissions are purely logical kernel constructs that collapse under real-world attack vectors:

1. **Offline Flash Chip-Off Attacks**: If a humanoid robot is physically accessed, attackers can de-solder the eMMC/UFS memory chip and clone the entire raw partition in seconds using off-the-shelf programmers. Operating system permissions offer zero resistance offline.
2. **Kernel Exploitation & Privilege Escalation**: Once an attacker compromises root (UID 0) via any application buffer overflow or kernel bug, all plaintext files on disk are immediately exfiltrated.
3. **Core Dumps & Cold Boot Memory Theft**: The moment an application reads a private key into process RAM, raw key bytes become exposed to process memory crash dumps, swap leaks, or physical RAM probing.

Hence, modern zero-trust embedded platforms enforce a strict rule: **Zero Plaintext Keys on host filesystems.**

---

## 2. The Solution: Hardware Security Modules (HSM) and PKCS#11

How can an operating system sign binaries or establish TLS handshakes without storing private keys in files?  
The answer is **delegating cryptographic operations directly into hardware-isolated secure tokens (HSM / Secure World)**.

[![PKCS#11 HSM Cryptographic Delegation](/humanoid-sec-platform/diagrams/pkcs11_hsm_signing_delegation.svg)](/humanoid-sec-platform/diagrams/pkcs11_hsm_signing_delegation.html)
> 💡 *Click to open the [Archify Interactive Viewer](/humanoid-sec-platform/diagrams/pkcs11_hsm_signing_delegation.html) comparing vulnerable disk key storage against PKCS#11 in-token signing delegation.*

### 2.1. What is PKCS#11?
- **PKCS#11 (Cryptoki)**: An open international C API standard governing communication between applications and cryptographic hardware (smartcards, HSMs, USB tokens, and TEE enclaves).
- **Never-Extractable Property**: Keys generated inside the token are flagged with `CKA_EXTRACTABLE = FALSE`. Once generated, raw private key bytes can **never be extracted or copied outside the token boundary**.

### 2.2. In-Token Signing Delegation (`C_Sign`)
When an application needs to generate a digital signature, the execution path differs completely between legacy file methods and PKCS#11:

```text
[Vulnerable Legacy Approach]
Application  --1. open("server.key")-->  Disk
Application  <--2. [Raw Private Key]--   Disk (Exposed to RAM!)
Application  --3. Computes signature in process memory (Compromised if crashed)-->

[Hardened PKCS#11 Delegation Approach]
Application  --1. Sends only 32-byte payload hash digest-->  HSM Token
HSM Token    --2. Executes private key math inside isolated silicon-->
Application  <--3. Receives only final signature (R, S) (0% key exposure)--  HSM Token
```

The host application never sees, reads, or buffers the private key bytes. Even if an attacker gains full root access, dumps memory, or extracts core files, the private key cannot be stolen or duplicated.

---

## 3. RFC 7512 `pkcs11:` URI Standard

Our platform eliminates hardcoded paths and plaintext key passwords entirely. Instead, components reference keys through **RFC 7512 standard PKCS#11 URIs**:

```text
pkcs11:model=SoftHSM%20v2;token=HumanoidSecToken;id=%01;object=KernelModuleSigningKey;type=private
```

This URI is an opaque pointer referencing a cryptographic handle within the secure token:
- Build scripts (`scripts/build_kernel.sh`, `scripts/build_rootfs.sh`) supply this URI string to OpenSSL and Linux kernel signing tools (`sign-file`).
- OpenSSL uses its `pkcs11-provider` to dispatch signature requests directly into SoftHSMv2 or OP-TEE Secure World.

---

## 4. Platform Three-Tier Key Hierarchy

[![Key Hierarchy](/humanoid-sec-platform/diagrams/key_hierarchy.svg)](/humanoid-sec-platform/diagrams/key_hierarchy.html)
> 💡 *Click to open the [Archify Interactive Viewer](/humanoid-sec-platform/diagrams/key_hierarchy.html) displaying Tier 1 offline build keys, Tier 2 device sealed keys, and Tier 3 public artifacts.*

1. **Tier 1: Offline Signing Environment (SoftHSMv2 / Enterprise HSM)**
   - `KernelModuleSigningKey` (RSA-3072): Enforces kernel ring-0 module integrity.
   - `DmVeritySigningKey` (RSA-3072): Signs rootfs block Merkle tree root hash.
   - `ImaSigningKey` (ECDSA P-384): Signs user binaries and runtime libraries.
   - `DeviceEnrollmentCaKey` (ECDSA P-256): Issues robot identity certificates.
2. **Tier 2: Device Hardware & Secure World (OP-TEE & fTPM)**
   - `HumanoidDeviceIdentityKey` (ECDSA P-256): Trapped in Secure SRAM for mTLS.
   - fTPM 2.0 Primary Seed & Attestation Key (AK): Measures software execution into PCRs.
3. **Tier 3: Public Verification Artifacts (Safe for Distribution)**
   - Built-in kernel keyring certificates (`certs/signing_key.x509`).
   - Device certificate (`humanoid_device.crt`).

---

## 5. Summary & Best Practices Matrix

| Category | Insecure Anti-Pattern | Our Hardened Platform Standard |
| :--- | :--- | :--- |
| **Key Storage** | Storing `.key`/`.pem` files on disk | Zero plaintext keys; SoftHSMv2 token isolation |
| **Access Control** | Relying on `chmod 600` file permissions | Hardware `CKA_EXTRACTABLE=FALSE` never-extractable policy |
| **Key Reference** | Hardcoded file paths in configs | RFC 7512 `pkcs11:` opaque URI pointers |
| **CI/CD Quality Gate** | Manual ad-hoc inspections | Automated git-tree scanner (`keys_hsm/audit_zero_keys.sh`) |