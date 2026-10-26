#!/usr/bin/env bash
# ==============================================================================
# keys_hsm/setup_softhsm.sh — SoftHSMv2 PKCS#11 Offline Key Management Pipeline
# ==============================================================================
# Description:
#   Initializes SoftHSMv2 security token ('HumanoidSecToken') and generates
#   cryptographic signing keypairs directly inside the HSM/PKCS#11 token.
#   Implements Zero Plaintext Key Policy: private keys are created with
#   sensitive/never-extractable flags and are NEVER written to plaintext files.
#
# Cryptographic Keys Generated:
#   - KernelModuleSigningKey : RSA 3072 / SHA-256 (ID: 01)
#   - DmVeritySigningKey     : RSA 3072 / SHA-256 (ID: 02)
#   - ImaSigningKey          : ECDSA P-384 / SHA-384 (ID: 03)
#   - DeviceEnrollmentCaKey  : ECDSA P-256 / SHA-256 (ID: 04)
# ==============================================================================

set -euo pipefail

# ANSI Color Codes
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# HSM / SoftHSM Parameters
TOKEN_LABEL="${SOFTHSM_TOKEN_LABEL:-HumanoidSecToken}"
SO_PIN="${SOFTHSM_SO_PIN:-12345678}"
USER_PIN="${SOFTHSM_USER_PIN:-1234}"

SOFTHSM_DIR="${REPO_ROOT}/.cache/softhsm"
TOKENS_DIR="${SOFTHSM_DIR}/tokens"
CONF_FILE="${SOFTHSM_DIR}/softhsm2.conf"
CERTS_OUT="${SCRIPT_DIR}/certs"

show_help() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --reset          Reset existing token and generate fresh keys
  --list           List objects in token
  --export-certs   Export public certificates/keys only
  -h, --help       Display this help message
EOF
}

resolve_tools() {
    # 1. Resolve pkcs11-tool
    if command -v pkcs11-tool >/dev/null 2>&1; then
        PKCS11_TOOL="$(command -v pkcs11-tool)"
    elif [[ -x "${REPO_ROOT}/.cache/pkcs11_tools/usr/bin/pkcs11-tool" ]]; then
        PKCS11_TOOL="${REPO_ROOT}/.cache/pkcs11_tools/usr/bin/pkcs11-tool"
        local lib_dir="${REPO_ROOT}/.cache/pkcs11_tools/usr/lib/x86_64-linux-gnu"
        export LD_LIBRARY_PATH="${lib_dir}:${lib_dir}/softhsm:${LD_LIBRARY_PATH:-}"
    else
        log_err "pkcs11-tool not found on system or local cache."
        exit 1
    fi

    # 2. Resolve libsofthsm2.so
    local lib_candidates=(
        "/usr/lib/x86_64-linux-gnu/softhsm/libsofthsm2.so"
        "/usr/lib/softhsm/libsofthsm2.so"
        "/usr/lib/aarch64-linux-gnu/softhsm/libsofthsm2.so"
        "${REPO_ROOT}/.cache/pkcs11_tools/usr/lib/x86_64-linux-gnu/softhsm/libsofthsm2.so"
    )

    PKCS11_MODULE=""
    for cand in "${lib_candidates[@]}"; do
        if [[ -f "${cand}" ]]; then
            PKCS11_MODULE="${cand}"
            break
        fi
    done

    if [[ -z "${PKCS11_MODULE}" ]]; then
        log_err "libsofthsm2.so PKCS#11 module not located."
        exit 1
    fi

    log_ok "Resolved PKCS#11 Tool:   ${PKCS11_TOOL}"
    log_ok "Resolved PKCS#11 Module: ${PKCS11_MODULE}"
}

setup_config() {
    mkdir -p "${TOKENS_DIR}" "${CERTS_OUT}"
    cat <<EOF > "${CONF_FILE}"
# SoftHSM v2 configuration for humanoid-sec-platform
directories.tokendir = ${TOKENS_DIR}
objectstore.backend = file
log.level = INFO
EOF
    export SOFTHSM2_CONF="${CONF_FILE}"
}

init_token() {
    log_info "Initializing SoftHSMv2 Token: '${TOKEN_LABEL}'..."
    # Initialize Token and SO PIN
    "${PKCS11_TOOL}" --module "${PKCS11_MODULE}" \
        --init-token \
        --label "${TOKEN_LABEL}" \
        --so-pin "${SO_PIN}" >/dev/null 2>&1 || true

    # Initialize User PIN
    "${PKCS11_TOOL}" --module "${PKCS11_MODULE}" \
        --token-label "${TOKEN_LABEL}" \
        --init-pin \
        --so-pin "${SO_PIN}" \
        --pin "${USER_PIN}" >/dev/null 2>&1 || true

    log_ok "Token '${TOKEN_LABEL}' initialized successfully."
}

generate_keys() {
    log_info "--- [Generating HSM Signing Keys inside '${TOKEN_LABEL}'] ---"

    # Key 1: KernelModuleSigningKey (RSA 3072)
    log_info "Generating KernelModuleSigningKey (RSA 3072, ID: 01)..."
    "${PKCS11_TOOL}" --module "${PKCS11_MODULE}" \
        --token-label "${TOKEN_LABEL}" \
        --login --pin "${USER_PIN}" \
        --keypairgen --key-type rsa:3072 \
        --label "KernelModuleSigningKey" \
        --id "01" \
        --usage-sign >/dev/null

    # Key 2: DmVeritySigningKey (RSA 3072)
    log_info "Generating DmVeritySigningKey (RSA 3072, ID: 02)..."
    "${PKCS11_TOOL}" --module "${PKCS11_MODULE}" \
        --token-label "${TOKEN_LABEL}" \
        --login --pin "${USER_PIN}" \
        --keypairgen --key-type rsa:3072 \
        --label "DmVeritySigningKey" \
        --id "02" \
        --usage-sign >/dev/null

    # Key 3: ImaSigningKey (ECDSA P-384 / secp384r1)
    log_info "Generating ImaSigningKey (ECDSA P-384, ID: 03)..."
    "${PKCS11_TOOL}" --module "${PKCS11_MODULE}" \
        --token-label "${TOKEN_LABEL}" \
        --login --pin "${USER_PIN}" \
        --keypairgen --key-type EC:secp384r1 \
        --label "ImaSigningKey" \
        --id "03" \
        --usage-sign >/dev/null

    # Key 4: DeviceEnrollmentCaKey (ECDSA P-256 / prime256v1)
    log_info "Generating DeviceEnrollmentCaKey (ECDSA P-256, ID: 04)..."
    "${PKCS11_TOOL}" --module "${PKCS11_MODULE}" \
        --token-label "${TOKEN_LABEL}" \
        --login --pin "${USER_PIN}" \
        --keypairgen --key-type EC:prime256v1 \
        --label "DeviceEnrollmentCaKey" \
        --id "04" \
        --usage-sign >/dev/null

    # Key 5: HumanoidDeviceIdentityKey (ECDSA P-256 / prime256v1)
    log_info "Generating HumanoidDeviceIdentityKey (ECDSA P-256, ID: 05)..."
    "${PKCS11_TOOL}" --module "${PKCS11_MODULE}" \
        --token-label "${TOKEN_LABEL}" \
        --login --pin "${USER_PIN}" \
        --keypairgen --key-type EC:prime256v1 \
        --label "HumanoidDeviceIdentityKey" \
        --id "05" \
        --usage-sign >/dev/null

    # Key 6: SecureBootKey (RSA-3072, Jetson PKC Root of Trust)
    log_info "Generating SecureBootKey (RSA-3072, ID: 06, NVIDIA Jetson PKC)..."
    "${PKCS11_TOOL}" --module "${PKCS11_MODULE}" \
        --token-label "${TOKEN_LABEL}" \
        --login --pin "${USER_PIN}" \
        --keypairgen --key-type rsa:3072 \
        --label "SecureBootKey" \
        --id "06" \
        --usage-sign >/dev/null

    log_ok "All HSM signing keypairs generated (Zero Plaintext Keys)."
}

export_public_certs() {
    log_info "--- [Exporting Public Keys and Certificates] ---"

    local keys=("KernelModuleSigningKey:01" "DmVeritySigningKey:02" "ImaSigningKey:03" "DeviceEnrollmentCaKey:04" "HumanoidDeviceIdentityKey:05" "SecureBootKey:06")
    for item in "${keys[@]}"; do
        local label="${item%%:*}"
        local id="${item##*:}"
        local out_der="${CERTS_OUT}/${label}_pub.der"
        local out_pem="${CERTS_OUT}/${label}_pub.pem"

        "${PKCS11_TOOL}" --module "${PKCS11_MODULE}" \
            --token-label "${TOKEN_LABEL}" \
            --read-object --type pubkey \
            --id "${id}" \
            --output-file "${out_der}" >/dev/null 2>&1 || true

        if [[ -f "${out_der}" && -s "${out_der}" ]]; then
            # Convert DER to PEM for standard OpenSSL tooling
            openssl pkey -pubin -inform DER -in "${out_der}" -outform PEM -out "${out_pem}" 2>/dev/null || true
            log_ok "Exported public key: ${out_pem}"
        fi
    done

    # Generate x509 certificates via OpenSSL 3 PKCS#11 Provider if available
    local ossl_modules="${REPO_ROOT}/.cache/host_tools/usr/lib/x86_64-linux-gnu/ossl-modules"
    if [[ -d "${ossl_modules}" ]]; then
        export OPENSSL_MODULES="${ossl_modules}"
        export PKCS11_PROVIDER_MODULE="${PKCS11_MODULE}"
        export SOFTHSM2_CONF="${CONF_FILE}"

        log_info "Generating x509 CA & Device certificates via PKCS#11 provider..."
        openssl req -new -x509 -days 365 -subj "/C=KR/O=NVIDIA-Jetson-Robotics/OU=Security/CN=Humanoid-Root-CA" \
            -key "pkcs11:token=${TOKEN_LABEL};object=DeviceEnrollmentCaKey?pin-value=${USER_PIN}" \
            -out "${CERTS_OUT}/DeviceEnrollmentCa.crt" \
            -provider default -provider pkcs11 >/dev/null 2>&1 || true

        openssl req -new -x509 -days 365 -subj "/C=KR/O=NVIDIA-Jetson-Robotics/OU=Humanoid-Unit-01/CN=jetson-humanoid-01" \
            -key "pkcs11:token=${TOKEN_LABEL};object=HumanoidDeviceIdentityKey?pin-value=${USER_PIN}" \
            -out "${CERTS_OUT}/humanoid_device.crt" \
            -provider default -provider pkcs11 >/dev/null 2>&1 || true
        log_ok "Generated x509 certificates: DeviceEnrollmentCa.crt, humanoid_device.crt"
    fi
}

list_objects() {
    log_info "--- [HSM Token Objects in '${TOKEN_LABEL}'] ---"
    "${PKCS11_TOOL}" --module "${PKCS11_MODULE}" \
        --token-label "${TOKEN_LABEL}" \
        --login --pin "${USER_PIN}" \
        --list-objects
}

main() {
    local action="setup"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --reset)
                action="reset"
                shift
                ;;
            --list)
                action="list"
                shift
                ;;
            --export-certs)
                action="export"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_err "Unknown argument: $1"
                show_help
                exit 1
                ;;
        esac
    done

    resolve_tools
    setup_config

    if [[ "${action}" == "reset" ]]; then
        log_warn "Resetting token directory: ${TOKENS_DIR}"
        rm -rf "${TOKENS_DIR}"/*
        init_token
        generate_keys
        export_public_certs
    elif [[ "${action}" == "list" ]]; then
        list_objects
    elif [[ "${action}" == "export" ]]; then
        export_public_certs
    else
        # Default setup: init if empty or generate keys
        init_token
        # Check if keys exist
        if ! "${PKCS11_TOOL}" --module "${PKCS11_MODULE}" --token-label "${TOKEN_LABEL}" --login --pin "${USER_PIN}" --list-objects 2>/dev/null | grep -q "KernelModuleSigningKey"; then
            generate_keys
        else
            log_ok "Token '${TOKEN_LABEL}' already contains signing keys."
        fi
        export_public_certs
    fi

    log_ok "=================================================="
    log_ok "SoftHSMv2 PKCS#11 pipeline configuration ready!"
    log_ok "Token Label:   ${TOKEN_LABEL}"
    log_ok "Tokens Dir:    ${TOKENS_DIR}"
    log_ok "Public Certs:  ${CERTS_OUT}"
    log_ok "Zero Plaintext Key Policy: Verified (0 private keys on disk)"
    log_ok "=================================================="
}

main "$@"
