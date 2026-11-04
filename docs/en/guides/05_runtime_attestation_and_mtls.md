# Security Beginner's Guide to Runtime Attestation and mTLS

> **Purpose**: Demystifies Zero-Trust fleet security for autonomous humanoid robots, detailing how Linux IMA and fTPM 2.0 PCR measurements power hardware-backed Remote Attestation and how Secure World mTLS enforces TLS 1.3 mutual authentication without exposing private keys.  
> **Audience**: Security beginners, cloud/robotics networking engineers, backend infrastructure security architects  
> **Status**: Production Guide  

---

## 1. The Fleet Trust Dilemma: "Can We Trust This Robot?"

Humanoid robots operate autonomously in remote environments (warehouses, factories, hospitals), receiving trajectory paths and motor torque instructions from centralized cloud fleets.  
Fleet operators face a fundamental security dilemma:

> **"How do we know a connecting robot hasn't been compromised by malware or a stealth rootkit?"**

Traditional passwords, API tokens, or static certificate files cannot resolve this:
- If a robot is hacked, attackers copy certificate files to an external machine and masquerade as legitimate robots.
- A compromised control process could report "healthy telemetry" while executing malicious actuation scripts in the background.

Zero-Trust fleet security demands **Hardware Remote Attestation** coupled with **Secure World Mutual TLS (mTLS)**.

---

## 2. Runtime Execution Measurement: Linux IMA and fTPM PCR 10

The Linux kernel subsystem responsible for recording all executing software is the **Integrity Measurement Architecture (IMA)**:

[![fTPM PCR 10 Hash-Chain](../../diagrams/tpm_pcr_extend_flow.svg)](../../diagrams/tpm_pcr_extend_flow.html)
> 💡 *Click to open the [Archify Interactive Viewer](../../diagrams/tpm_pcr_extend_flow.html) tracing binary measurement hooks into fTPM PCR 10.*

### 2.1. Intercepting the `execve()` System Call
1. When a process launches (e.g., `./actuator_node`), the kernel intercepts the `execve()` system call.
2. The IMA subsystem reads the target executable bytes and computes its **SHA-256 cryptographic digest**.
3. IMA records this event into the kernel measurement log (`/sys/kernel/security/ima/ascii_runtime_measurements`).

### 2.2. fTPM PCR 10 Hardware Hash Extension
Crucially, the file digest does not stay purely in software RAM. The kernel dispatches an **Extend** command into the **hardware fTPM 2.0 PCR 10 register**:

$$\text{PCR 10}_{new} = \text{SHA-256}(\text{PCR 10}_{old} \parallel \text{File-SHA256})$$

- Even if an attacker gains root and tampers with the memory log, **the hardware PCR 10 register trapped in Secure World (OP-TEE) cannot be altered or rewritten**.
- If unapproved code runs even once, PCR 10 diverges irreversibly from the golden baseline.

---

## 3. Remote Attestation Challenge-Response

The cloud fleet manager authenticates robot health via a cryptographic **Challenge-Response** protocol:

```text
[Cloud Fleet Server]                                       [Humanoid Robot]
         |                                                         |
         |--1. Attestation Challenge (32-byte fresh Nonce)-------->|
         |                                                         |
         |                                                         +--2. Dispatches TPM2_Quote
         |                                                         |     (PCR 10, Nonce, Key=AK)
         |                                                         |
         |                                                         +--3. fTPM in Secure World
         |                                                         |     binds PCR 10 + Nonce,
         |                                                         |     signing via Attestation Key
         |                                                         |
         |<--4. Transmits TPM2_Quote Bundle + IMA Event Log--------|
         |
+--------+---------------------------------------------------------+
| Cloud Verification Logic:                                        |
| - Verify Signature: Validate Quote signature with enrolled AK cert|
| - Freshness Check: Does Quote Nonce match the challenge sent?    |
|   (Neutralizes Replay Attacks using stale valid quotes)          |
| - Baseline Comparison: Replay IMA event log against golden image  |
|   and compare calculated hash with signed PCR 10 value.          |
|   => Verdict: [TRUSTED: Grant RPC access] / [COMPROMISED: Quarantine]|
+------------------------------------------------------------------+
```

---

## 4. Why Standard HTTPS (Unidirectional TLS) is Insufficient

When browsers connect to websites, they use **Server-Only TLS**:
- The browser checks the website's certificate.
- The server does not check the client with an X.509 certificate; it accepts passwords or cookies.

In industrial robotics, this is dangerous: rogue nodes or spoofed proxies could inject malicious motion packets.  
Robotics fleets require **Mutual TLS (mTLS)**: both client and server cryptographically verify each other with X.509 certificates.

---

## 5. Secure World mTLS: Zero Plaintext Key Exposure

Traditional mTLS suffered from storing `client.key` as a plaintext file on disk.  
Our platform solves this via **OpenSSL 3.x pkcs11-provider integrated with OP-TEE**:

[![Secure World mTLS Sequence](../../diagrams/secure_mtls_sequence.svg)](../../diagrams/secure_mtls_sequence.html)
> 💡 *Click to open the [Archify Interactive Viewer](../../diagrams/secure_mtls_sequence.html) illustrating OpenSSL 3.x provider and OP-TEE in-token signing.*

1. **CertificateRequest**: The cloud server requests client identity authentication during TLS 1.3 handshake.
2. **Signing Delegation**: The client passes the TLS payload hash to OpenSSL's `pkcs11-provider`.
3. **In-Token Signature**: The robot private key (`HumanoidDeviceIdentityKey`, ECDSA P-256) **never leaves OP-TEE Secure SRAM**. OP-TEE generates the ECDSA signature inside hardware and returns only the final `(r, s)` signature values.
4. **Session Established**: Mutual TLS 1.3 session encryption activates without the robot's private key ever being read into Normal World user memory.

---

## 6. Summary

1. **Zero-Trust Verification**: Validates remote robot integrity on every connection before granting physical actuator authority.
2. **IMA + fTPM PCR 10**: Irreversibly chains all executed code into non-resettable hardware registers.
3. **Nonce Challenge**: Defeats replay attacks by binding freshly generated one-time random tokens into quotes.
4. **Secure World mTLS**: Enforces mutual TLS 1.3 authentication while keeping private keys locked inside ARM TrustZone Secure SRAM.
