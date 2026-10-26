#!/usr/bin/env bash
# ==============================================================================
# scripts/sign_jetson_secureboot.sh — NVIDIA Jetson PKC Secure Boot Signing Pipeline
# ==============================================================================
# Description:
#   Emulates NVIDIA JetPack/L4T Tegra PKC (Public Key Cryptography) Secure Boot.
#   Uses SoftHSMv2 PKCS#11 token to sign bootloader, kernel, and initramfs binaries
#   producing authenticated NVD1 container headers and emulated eFuse hashes.
#
# References:
#   - SRD-SEC-001: Hardware Root of Trust & eFuse Verification
#   - SRD-SEC-002: Secure Boot Chain of Trust
#   - NVIDIA Tegra Linux Driver Package (L4T) Development Guide: Secure Boot
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Configuration & Paths
SOFTHSM_DIR="${REPO_ROOT}/.cache/softhsm"
CONF_FILE="${SOFTHSM_DIR}/softhsm2.conf"
CERTS_DIR="${REPO_ROOT}/keys_hsm/certs"
FUSES_CONFIG="${REPO_ROOT}/configs/secureboot/tegra_fuses.json"
SIGN_HELPER="${REPO_ROOT}/keys_hsm/sign_helper.sh"

TOKEN_LABEL="HumanoidSecToken"
USER_PIN="1234"
PKC_KEY_ID="06"
PKC_KEY_LABEL="SecureBootKey"
PKC_PUB_PEM="${CERTS_DIR}/SecureBootKey_pub.pem"

# ANSI Colors
readonly C_RESET="\033[0m"
readonly C_BOLD="\033[1m"
readonly C_GREEN="\033[32m"
readonly C_YELLOW="\033[33m"
readonly C_RED="\033[31m"
readonly C_CYAN="\033[36m"

log_info()  { echo -e "${C_CYAN}[INFO]${C_RESET}  $*"; }
log_ok()    { echo -e "${C_GREEN}[OK]${C_RESET}   $*"; }
log_warn()  { echo -e "${C_YELLOW}[WARN]${C_RESET} $*"; }
log_err()   { echo -e "${C_RED}[ERR]${C_RESET}  $*"; }

show_help() {
    cat <<EOF
Usage: $(basename "$0") <COMMAND> [OPTIONS]

Commands:
  sign              Sign a boot binary and create an authenticated container
                    Options: --in <file> [--out <signed-file>] [--type <kernel|initrd|firmware>]

  burn-fuses        Generate emulated Tegra eFuse table from HSM PKC key
                    Options: [--out <tegra_fuses.json>]

  verify            Verify signed container against eFuse PKC hash and SoftHSM signature
                    Options: --in <signed-file> [--fuses <tegra_fuses.json>]

  tamper-test       Run cryptographic tamper injection test verifying rejection

Examples:
  $(basename "$0") sign --in build/kernel/arch/arm64/boot/Image --out build/images/kernel.signed
  $(basename "$0") burn-fuses --out configs/secureboot/tegra_fuses.json
  $(basename "$0") verify --in build/images/kernel.signed
EOF
}

setup_env() {
    export SOFTHSM2_CONF="${CONF_FILE}"
    export LD_LIBRARY_PATH="${REPO_ROOT}/.cache/pkcs11_tools/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"

    # Resolve pkcs11-tool
    if command -v pkcs11-tool >/dev/null 2>&1; then
        PKCS11_TOOL="$(command -v pkcs11-tool)"
    elif [[ -x "${REPO_ROOT}/.cache/pkcs11_tools/usr/bin/pkcs11-tool" ]]; then
        PKCS11_TOOL="${REPO_ROOT}/.cache/pkcs11_tools/usr/bin/pkcs11-tool"
    else
        log_err "pkcs11-tool utility not found."
        exit 1
    fi

    # Resolve OpenSC module
    if [[ -f "/usr/lib/x86_64-linux-gnu/softhsm/libsofthsm2.so" ]]; then
        PKCS11_MODULE="/usr/lib/x86_64-linux-gnu/softhsm/libsofthsm2.so"
    elif [[ -f "${REPO_ROOT}/.cache/pkcs11_tools/usr/lib/x86_64-linux-gnu/softhsm/libsofthsm2.so" ]]; then
        PKCS11_MODULE="${REPO_ROOT}/.cache/pkcs11_tools/usr/lib/x86_64-linux-gnu/softhsm/libsofthsm2.so"
    else
        log_err "libsofthsm2.so PKCS#11 module not found."
        exit 1
    fi

    # Verify public key exists
    if [[ ! -f "${PKC_PUB_PEM}" ]]; then
        log_info "Exporting ${PKC_KEY_LABEL} public key from SoftHSM..."
        "${REPO_ROOT}/keys_hsm/setup_softhsm.sh" --export-certs >/dev/null 2>&1 || true
    fi
}

# Calculate 32-byte SHA-256 PKC Hash from Public Key DER
get_pkc_hash() {
    local pub_pem="$1"
    openssl rsa -pubin -in "${pub_pem}" -outform DER 2>/dev/null | sha256sum | awk '{print $1}'
}

# Generate emulated Tegra eFuse configuration
burn_efuses() {
    local out_fuses="${FUSES_CONFIG}"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --out) out_fuses="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    mkdir -p "$(dirname "${out_fuses}")"

    if [[ ! -f "${PKC_PUB_PEM}" ]]; then
        log_err "PKC Public Key PEM not found at '${PKC_PUB_PEM}'."
        exit 1
    fi

    local pkc_hash
    pkc_hash="$(get_pkc_hash "${PKC_PUB_PEM}")"

    log_info "Burning emulated Tegra SoC eFuses from SoftHSM PKC key..."
    cat <<EOF > "${out_fuses}"
{
  "tegra_soc": "Tegra234_Orin_Virt",
  "security_mode": "1",
  "fuses": {
    "FUSE_BOOT_SECURITY_INFO": "0x00000001",
    "FUSE_OPT_SUBKEY": "${pkc_hash}",
    "FUSE_PKC_HASH": "${pkc_hash}",
    "FUSE_RESERVED_ODM0": "0x48554d41",
    "FUSE_RESERVED_ODM1": "0x4e4f4944"
  },
  "metadata": {
    "key_source": "SoftHSMv2 PKCS#11 Token (${TOKEN_LABEL})",
    "key_id": "${PKC_KEY_ID}",
    "key_algorithm": "RSA-3072",
    "pkc_pubkey_path": "${PKC_PUB_PEM}",
    "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  }
}
EOF

    log_ok "Tegra SoC eFuse table generated: ${out_fuses}"
    log_ok "  Security Mode:  ENABLED (1)"
    log_ok "  FUSE_PKC_HASH:  ${pkc_hash}"
}

# Construct NVIDIA-compliant signed container (NVD1 header + Payload)
sign_image() {
    local in_file=""
    local out_file=""
    local img_type="kernel"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --in)   in_file="$2"; shift 2 ;;
            --out)  out_file="$2"; shift 2 ;;
            --type) img_type="$2"; shift 2 ;;
            *) log_err "Unknown option: $1"; exit 1 ;;
        esac
    done

    if [[ -z "${in_file}" || ! -f "${in_file}" ]]; then
        log_err "Valid --in <file> required."
        exit 1
    fi

    out_file="${out_file:-${in_file}.signed}"
    mkdir -p "$(dirname "${out_file}")"

    log_info "Signing boot payload: ${in_file} (${img_type})"

    # 1. Compute payload metrics
    local payload_size
    payload_size="$(stat -c %s "${in_file}")"
    local payload_sha256
    payload_sha256="$(sha256sum "${in_file}" | awk '{print $1}')"

    # 2. Compute PKC public key hash
    local pkc_hash
    pkc_hash="$(get_pkc_hash "${PKC_PUB_PEM}")"

    # 3. Perform in-HSM RSA-SHA256 signature of the payload
    local sig_tmp
    sig_tmp="$(mktemp)"
    "${PKCS11_TOOL}" --module "${PKCS11_MODULE}" \
        --token-label "${TOKEN_LABEL}" \
        --login --pin "${USER_PIN}" \
        --sign --id "${PKC_KEY_ID}" \
        -m SHA256-RSA-PKCS \
        --input-file "${in_file}" \
        --output-file "${sig_tmp}"

    local sig_size
    sig_size="$(stat -c %s "${sig_tmp}")"

    # 4. Construct 512-byte NVD1 header
    # Magic (4): 'NVD1'
    # Version (4): 1
    # Payload Size (8): uint64
    # Payload SHA256 (32): raw bytes
    # PKC Public Key Hash (32): raw bytes
    # Header Checksum (32): SHA256 of preceding bytes
    # Signature (384): RSA-3072 signature
    # Padding: zero to 512-byte boundary
    local hdr_tmp
    hdr_tmp="$(mktemp)"

    python3 -c "
import struct, hashlib

magic = b'NVD1'
version = 1
payload_size = ${payload_size}
payload_hash = bytes.fromhex('${payload_sha256}')
pkc_hash = bytes.fromhex('${pkc_hash}')

# Pack pre-checksum header (80 bytes)
pre_hdr = struct.pack('<4sIQ32s32s', magic, version, payload_size, payload_hash, pkc_hash)
hdr_checksum = hashlib.sha256(pre_hdr).digest()

with open('${sig_tmp}', 'rb') as f:
    sig = f.read()

# Build full 512-byte container header
header = pre_hdr + hdr_checksum + sig
if len(header) < 512:
    header = header + b'\x00' * (512 - len(header))

with open('${hdr_tmp}', 'wb') as f:
    f.write(header)
"

    # 5. Concatenate Header + Payload into authenticated container
    cat "${hdr_tmp}" "${in_file}" > "${out_file}"
    # Keep detached sigheader alongside for UEFI/MB2 inspection
    cp "${hdr_tmp}" "${out_file}.sigheader"

    rm -f "${sig_tmp}" "${hdr_tmp}"

    log_ok "Signed NVIDIA container created: ${out_file}"
    log_ok "  Container Magic:  NVD1 (Tegra Secure Boot Container v1)"
    log_ok "  Payload Size:     ${payload_size} bytes"
    log_ok "  Payload SHA-256:  ${payload_sha256}"
    log_ok "  PKC Key Hash:     ${pkc_hash}"
    log_ok "  Signature Size:   ${sig_size} bytes (RSA-3072 PSS/PKCS)"
}

# Verify signed container against eFuse PKC hash and digital signature
verify_container() {
    local in_file=""
    local fuses_file="${FUSES_CONFIG}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --in)    in_file="$2"; shift 2 ;;
            --fuses) fuses_file="$2"; shift 2 ;;
            *) log_err "Unknown option: $1"; exit 1 ;;
        esac
    done

    if [[ -z "${in_file}" || ! -f "${in_file}" ]]; then
        log_err "Valid --in <signed-file> required."
        exit 1
    fi

    if [[ ! -f "${fuses_file}" ]]; then
        log_warn "eFuse file '${fuses_file}' not found. Generating default eFuse table..."
        burn_efuses "${fuses_file}"
    fi

    log_info "Verifying NVIDIA Secure Boot container: ${in_file}"

    # Verify container via python unpacker and OpenSSL
    local verify_res
    verify_res="$(python3 -c "
import struct, hashlib, json, sys, subprocess

with open('${fuses_file}', 'r') as f:
    fuse_data = json.load(f)
expected_pkc_hash = fuse_data['fuses'].get('FUSE_PKC_HASH', '').lower()

with open('${in_file}', 'rb') as f:
    hdr = f.read(512)
    payload = f.read()

if len(hdr) < 512:
    print('FAIL: Container shorter than 512-byte header boundary')
    sys.exit(1)

magic, version, payload_size, payload_hash, pkc_hash = struct.unpack('<4sIQ32s32s', hdr[:80])
hdr_checksum = hdr[80:112]
sig = hdr[112:112+384]

if magic != b'NVD1':
    print(f'FAIL: Invalid container magic: {magic}')
    sys.exit(1)

calc_hdr_checksum = hashlib.sha256(hdr[:80]).digest()
if hdr_checksum != calc_hdr_checksum:
    print('FAIL: Container header checksum mismatch (header corrupted)')
    sys.exit(1)

if len(payload) != payload_size:
    print(f'FAIL: Payload length mismatch (expected {payload_size}, got {len(payload)})')
    sys.exit(1)

calc_payload_hash = hashlib.sha256(payload).digest()
if payload_hash != calc_payload_hash:
    print('FAIL: Payload hash mismatch (tampered payload body)')
    sys.exit(1)

actual_pkc_hash = pkc_hash.hex().lower()
if actual_pkc_hash != expected_pkc_hash:
    print(f'FAIL: PKC hash mismatch with SoC eFuses! (Image: {actual_pkc_hash}, Fuse: {expected_pkc_hash})')
    sys.exit(1)

# Verify RSA signature with PKC Public Key
with open('/tmp/_verify_sig.bin', 'wb') as f:
    f.write(sig)
with open('/tmp/_verify_payload.bin', 'wb') as f:
    f.write(payload)

res = subprocess.run([
    'openssl', 'dgst', '-sha256',
    '-verify', '${PKC_PUB_PEM}',
    '-signature', '/tmp/_verify_sig.bin',
    '/tmp/_verify_payload.bin'
], capture_output=True, text=True)

if res.returncode != 0:
    print('FAIL: Cryptographic signature verification failed (invalid key or forged signature)')
    sys.exit(1)

print(f'PASS: Container authenticated successfully. PKC Hash: {actual_pkc_hash}')
")"

    if [[ "${verify_res}" =~ ^PASS ]]; then
        log_ok "${verify_res}"
        return 0
    else
        log_err "${verify_res}"
        return 1
    fi
}

# Tamper Resistance Test
run_tamper_test() {
    log_info "--- [NVIDIA Secure Boot Tamper Resistance Test] ---"

    local test_dir
    test_dir="$(mktemp -d)"
    local test_payload="${test_dir}/boot_payload.bin"
    local signed_container="${test_dir}/boot_payload.bin.signed"
    local tampered_container="${test_dir}/boot_payload_tampered.bin.signed"

    echo "HUMANOID_SECURITY_PLATFORM_KERNEL_PAYLOAD_V1" > "${test_payload}"

    # Sign legitimate payload
    sign_image --in "${test_payload}" --out "${signed_container}"

    # Test 1: Verify legitimate payload passes
    log_info "[TEST 1] Verifying legitimate signed container..."
    if verify_container --in "${signed_container}"; then
        log_ok "Test 1 PASSED: Legitimate container accepted."
    else
        log_err "Test 1 FAILED: Legitimate container was rejected."
        rm -rf "${test_dir}"
        return 1
    fi

    # Test 2: Modify 1 byte of payload and verify rejection
    log_info "[TEST 2] Injecting 1-byte tamper in payload body..."
    cp "${signed_container}" "${tampered_container}"
    # Flip byte at offset 520 (inside payload body)
    python3 -c "
with open('${tampered_container}', 'r+b') as f:
    f.seek(520)
    b = f.read(1)
    f.seek(520)
    f.write(bytes([b[0] ^ 0xFF]))
"
    if verify_container --in "${tampered_container}" 2>/dev/null; then
        log_err "Test 2 FAILED: Tampered payload was unexpectedly ACCEPTED!"
        rm -rf "${test_dir}"
        return 1
    else
        log_ok "Test 2 PASSED: Tampered payload body correctly REJECTED (Boot Aborted)."
    fi

    # Test 3: Modify eFuse PKC hash and verify rejection
    log_info "[TEST 3] Simulating unauthenticated image (eFuse hash mismatch)..."
    local fake_fuses="${test_dir}/fake_fuses.json"
    cat <<EOF > "${fake_fuses}"
{
  "security_mode": "1",
  "fuses": {
    "FUSE_PKC_HASH": "0000000000000000000000000000000000000000000000000000000000000000"
  }
}
EOF
    if verify_container --in "${signed_container}" --fuses "${fake_fuses}" 2>/dev/null; then
        log_err "Test 3 FAILED: Image with mismatched eFuses was unexpectedly ACCEPTED!"
        rm -rf "${test_dir}"
        return 1
    else
        log_ok "Test 3 PASSED: SoC eFuse hash mismatch correctly REJECTED (Boot Aborted)."
    fi

    rm -rf "${test_dir}" /tmp/_verify_sig.bin /tmp/_verify_payload.bin 2>/dev/null || true
    log_ok "All NVIDIA Secure Boot tamper resistance tests passed successfully!"
}

main() {
    if [[ $# -eq 0 ]]; then
        show_help
        exit 1
    fi

    setup_env

    local cmd="$1"
    shift

    case "${cmd}" in
        sign)
            sign_image "$@"
            ;;
        burn-fuses)
            burn_efuses "$@"
            ;;
        verify)
            verify_container "$@"
            ;;
        tamper-test)
            run_tamper_test
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_err "Unknown command: ${cmd}"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
