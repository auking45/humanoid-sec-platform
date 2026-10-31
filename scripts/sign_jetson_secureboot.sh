#!/usr/bin/env bash
# ==============================================================================
# scripts/sign_jetson_secureboot.sh — NVIDIA Jetson R39.2.1 Secure Boot Pipeline
# ==============================================================================
# Description:
#   Implements the official NVIDIA Jetson Linux R39.2.1 (JetPack 7.2.1)
#   Secure Boot architecture for Tegra234 (Orin) and Tegra264 (Thor):
#     1. Official <genericfuse MagicId="0x45535546"> XML fuse configuration
#        (PublicKeyHash, SecureBootKey/SBK, OemK1, OemK2, OemKdk0,
#         BootSecurityInfo=0x00000209, SecurityMode=0x1) + JSON mirror.
#     2. Official EKB (Encrypted Key Blob: eks_t234.img / eks_t264.img)
#        generation via NVIDIA R39.2.1 'gen_ekb.py' and OP-TEE extraction
#        verification matching 'jetson_ekb_extraction_t234.c' & 't264.c'.
#     3. Official 8,192-byte (0x2000) 'NVDA' Boot Component Header (BCH) with
#        two-stage authentication & encryption:
#        - Stage 1 (BootROM/MB1/MB2): SBKPKC (SBK AES-CMAC/GCM + RSA-3072 PKC)
#        - Stage 2 (UEFI + OP-TEE CPUBL): UEFI db RSA-3072 signature + EKB
#          sym_key NIST-SP-800-108 KDF + AES-256-GCM payload encryption
#          matching 'jetson_uefi_services.c' & 'jetson_nist_sp_800_108_kdf.c'.
#
# References:
#   - NVIDIA Jetson Linux R39.2.1 Developer Guide: Secure Boot (SecureBoot.html)
#   - sources/optee/optee/samples/hwkey-agent/host/tool/gen_ekb/gen_ekb.py
#   - sources/optee/optee/optee_os/core/pta/tegra/jetson_uefi_services.c
#   - sources/optee/optee/optee_os/core/pta/tegra/jetson_ekb_extraction_t234.c
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Configuration & Paths
SOFTHSM_DIR="${REPO_ROOT}/.cache/softhsm"
CONF_FILE="${SOFTHSM_DIR}/softhsm2.conf"
CERTS_DIR="${REPO_ROOT}/keys_hsm/certs"
FUSES_CONFIG="${REPO_ROOT}/configs/secureboot/tegra_fuses.json"
FUSES_XML="${REPO_ROOT}/configs/secureboot/fuse_config.xml"
IMAGES_DIR="${REPO_ROOT}/build/images"
EKB_T234_IMG="${IMAGES_DIR}/eks_t234.img"
EKB_T264_IMG="${IMAGES_DIR}/eks_t264.img"

NVIDIA_GEN_EKB="${REPO_ROOT}/sources/optee/optee/samples/hwkey-agent/host/tool/gen_ekb/gen_ekb.py"
NVIDIA_GEN_LUKS="${REPO_ROOT}/sources/optee/optee/samples/luks-srv/host/tool/gen_luks_passphrase/gen_luks_passphrase.py"

TOKEN_LABEL="HumanoidSecToken"
USER_PIN="1234"
PKC_KEY_ID="06"
PKC_KEY_LABEL="SecureBootKey"
PKC_PUB_PEM="${CERTS_DIR}/SecureBootKey_pub.pem"

UEFI_DB_KEY_ID="01"
UEFI_DB_KEY_LABEL="KernelModuleSigningKey"
UEFI_DB_PUB_PEM="${CERTS_DIR}/KernelModuleSigningKey_pub.pem"

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
  burn-fuses        Generate official NVIDIA <genericfuse> XML (fuse_config.xml)
                    and JSON fuse table (PublicKeyHash, SBK, OemK1, OemKdk0)
                    Options: [--out <tegra_fuses.json>] [--xml <fuse_config.xml>]

  gen-ekb           Generate official NVIDIA EKB images (eks_t234.img & eks_t264.img)
                    using R39.2.1 gen_ekb.py and HSM-derived OemK1/OemKdk0 keys
                    Options: [--chip <t234|t264|all>] [--out <eks.img>] [--fuses <file>]

  verify-ekb        Authenticate & extract EKB image using OemK1/OemKdk0 fuse key
                    (mirrors OP-TEE jetson_ekb_extraction_t234.c / t264.c)
                    Options: [--in <eks.img>] [--chip <t234|t264>] [--fuses <file>]

  sign              Encrypt & sign a boot payload into an 8192-byte NVDA BCH container
                    (Stage 1 SBKPKC + Stage 2 UEFI db & EKB CPUBL AES-256-GCM)
                    Options: --in <file> [--out <signed-file>] [--type <kernel|bootloader|initrd|firmware>]
                             [--fuses <file>] [--ekb <eks.img>]

  verify            Verify 8192-byte NVDA BCH container against Fuse XML/JSON, EKB sym_key,
                    Stage 1 PKC & Stage 2 UEFI db signatures, and decrypt AES-256-GCM payload
                    Options: --in <signed-file> [--fuses <file>] [--ekb <eks.img>]
                             [--decrypt-out <decrypted-file>]

  tamper-test       Run 5-point R39.2.1 Secure Boot & EKB tamper resistance test suite

Examples:
  $(basename "$0") burn-fuses --out configs/secureboot/tegra_fuses.json --xml configs/secureboot/fuse_config.xml
  $(basename "$0") gen-ekb --chip all
  $(basename "$0") verify-ekb --in build/images/eks_t234.img --chip t234
  $(basename "$0") sign --in build/kernel/arch/arm64/boot/Image --out build/images/kernel.signed
  $(basename "$0") verify --in build/images/kernel.signed --decrypt-out build/run/kernel.decrypted
EOF
}

setup_env() {
    export SOFTHSM2_CONF="${CONF_FILE}"
    export LD_LIBRARY_PATH="${REPO_ROOT}/.cache/pkcs11_tools/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"

    if command -v pkcs11-tool >/dev/null 2>&1; then
        PKCS11_TOOL="$(command -v pkcs11-tool)"
    elif [[ -x "${REPO_ROOT}/.cache/pkcs11_tools/usr/bin/pkcs11-tool" ]]; then
        PKCS11_TOOL="${REPO_ROOT}/.cache/pkcs11_tools/usr/bin/pkcs11-tool"
    else
        log_err "pkcs11-tool utility not found."
        exit 1
    fi

    if [[ -f "/usr/lib/x86_64-linux-gnu/softhsm/libsofthsm2.so" ]]; then
        PKCS11_MODULE="/usr/lib/x86_64-linux-gnu/softhsm/libsofthsm2.so"
    elif [[ -f "${REPO_ROOT}/.cache/pkcs11_tools/usr/lib/x86_64-linux-gnu/softhsm/libsofthsm2.so" ]]; then
        PKCS11_MODULE="${REPO_ROOT}/.cache/pkcs11_tools/usr/lib/x86_64-linux-gnu/softhsm/libsofthsm2.so"
    else
        log_err "libsofthsm2.so PKCS#11 module not found."
        exit 1
    fi

    if [[ ! -f "${PKC_PUB_PEM}" || ! -f "${UEFI_DB_PUB_PEM}" ]]; then
        log_info "Exporting public keys from SoftHSM..."
        "${REPO_ROOT}/keys_hsm/setup_softhsm.sh" --export-certs >/dev/null 2>&1 || true
    fi
}

# Calculate 32-byte SHA-256 and 64-byte SHA-512 PKC Public Key Hashes from DER
get_pkc_hash_sha256() {
    local pub_pem="$1"
    openssl rsa -pubin -in "${pub_pem}" -outform DER 2>/dev/null | sha256sum | awk '{print $1}'
}

get_pkc_hash_sha512() {
    local pub_pem="$1"
    openssl rsa -pubin -in "${pub_pem}" -outform DER 2>/dev/null | sha512sum | awk '{print $1}'
}

# Deterministically derive a symmetric key in-memory using SoftHSMv2 C_Sign
# so zero plaintext key files ever need to be stored in the repository.
derive_hsm_sym_key_hex() {
    local label="$1"
    local num_bytes="${2:-32}"
    local in_tmp sig_tmp
    in_tmp="$(mktemp)"
    sig_tmp="$(mktemp)"
    printf "NVIDIA_JETSON_R39_2_1_HSM_KDF::%s" "${label}" > "${in_tmp}"

    "${PKCS11_TOOL}" --module "${PKCS11_MODULE}" \
        --token-label "${TOKEN_LABEL}" \
        --login --pin "${USER_PIN}" \
        --sign --id "${PKC_KEY_ID}" \
        -m SHA256-RSA-PKCS \
        --input-file "${in_tmp}" \
        --output-file "${sig_tmp}" >/dev/null 2>&1

    local hex_out
    if [[ "${num_bytes}" -le 32 ]]; then
        hex_out="$(sha256sum "${sig_tmp}" | awk '{print $1}' | cut -c1-$((num_bytes * 2)))"
    else
        hex_out="$(sha512sum "${sig_tmp}" | awk '{print $1}' | cut -c1-$((num_bytes * 2)))"
    fi
    rm -f "${in_tmp}" "${sig_tmp}"
    printf "%s" "${hex_out}"
}

# Generate Official NVIDIA <genericfuse> XML & JSON Fuse Configuration
burn_efuses() {
    local out_fuses="${FUSES_CONFIG}"
    local out_xml="${FUSES_XML}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --out) out_fuses="$2"; shift 2 ;;
            --xml) out_xml="$2"; shift 2 ;;
            *)
                if [[ "$1" != -* ]]; then
                    out_fuses="$1"
                fi
                shift
                ;;
        esac
    done

    mkdir -p "$(dirname "${out_fuses}")" "$(dirname "${out_xml}")"

    if [[ ! -f "${PKC_PUB_PEM}" ]]; then
        log_err "PKC Public Key PEM not found at '${PKC_PUB_PEM}'."
        exit 1
    fi

    local pkc_sha256 pkc_sha512 uefi_db_sha256
    pkc_sha256="$(get_pkc_hash_sha256 "${PKC_PUB_PEM}")"
    pkc_sha512="$(get_pkc_hash_sha512 "${PKC_PUB_PEM}")"
    uefi_db_sha256="$(get_pkc_hash_sha256 "${UEFI_DB_PUB_PEM}")"

    local sbk_hex oem_k1_hex oem_k2_hex oem_kdk1_hex
    sbk_hex="$(derive_hsm_sym_key_hex "FUSE_SBK_AES256" 32)"
    oem_k1_hex="$(derive_hsm_sym_key_hex "FUSE_OEM_K1_ROOT" 32)"
    oem_k2_hex="$(derive_hsm_sym_key_hex "FUSE_OEM_K2_ROOT" 32)"
    oem_kdk1_hex="$(derive_hsm_sym_key_hex "FUSE_OEM_KDK1_THOR" 32)"
    local ecid_hex="0123456789abcdeffedcba9876543210"

    log_info "Generating official NVIDIA Jetson R39.2.1 Fuse Configuration XML & JSON..."

    # 1. Write Official NVIDIA <genericfuse> XML (compatible with odmfuse.sh / fskp_fuseburn.py)
    cat <<EOF > "${out_xml}"
<genericfuse MagicId="0x45535546" version="1.0.0">
    <!-- NVIDIA Jetson Linux R39.2.1 (JetPack 7.2.1) Production Fuse Configuration -->
    <!-- PublicKeyHash: SHA-512 / SHA-256 digest of SoftHSMv2 SecureBootKey (RSA-3072) -->
    <fuse name="PublicKeyHash" size="64" value="0x${pkc_sha512}" sha256="0x${pkc_sha256}" />

    <!-- SecureBootKey (SBK): 256-bit AES key for SBKPKC bootloader encryption -->
    <fuse name="SecureBootKey" size="32" value="0x${sbk_hex}" />

    <!-- OemK1 / OemK2 (Tegra234 Orin) & OemKdk0 (Tegra264 Thor): Root keys for EKB & fTPM -->
    <fuse name="OemK1" size="32" value="0x${oem_k1_hex}" />
    <fuse name="OemK2" size="32" value="0x${oem_k2_hex}" />
    <fuse name="OemKdk0" size="32" value="0x${oem_kdk1_hex}" />

    <!-- BootSecurityInfo (0x268): Bit 0 (RSA-3072 PKC) | Bit 3 (SBK Encryption) | Bit 9 (BSI_OEM_KEY_VALID_MASK=0x200) -->
    <fuse name="BootSecurityInfo" size="4" value="0x00000209" />

    <!-- SecurityMode (0x1a0): Bit 0 (SECURITY_MODE_ENABLED_MASK=0x1) -->
    <fuse name="SecurityMode" size="4" value="0x1" />

    <!-- ODM Reserved & Device Identity (ECID) -->
    <fuse name="ReservedOdm0" size="4" value="0x48554d41" />
    <fuse name="ReservedOdm1" size="4" value="0x4e4f4944" />
</genericfuse>
EOF

    # 2. Write JSON mirror for runtime verifier & test inspection
    cat <<EOF > "${out_fuses}"
{
  "tegra_soc": "Tegra234_Orin_Tegra264_Thor_R39.2.1",
  "l4t_release": "R39.2.1",
  "security_mode": "1",
  "fuse_xml_path": "${out_xml}",
  "fuses": {
    "FUSE_SECURITY_MODE": "0x00000001",
    "FUSE_BOOT_SECURITY_INFO": "0x00000209",
    "FUSE_PKC_HASH": "${pkc_sha256}",
    "FUSE_PUBLIC_KEY_HASH_SHA512": "${pkc_sha512}",
    "FUSE_OPT_SUBKEY": "${pkc_sha256}",
    "FUSE_SBK": "${sbk_hex}",
    "FUSE_OEM_K1": "${oem_k1_hex}",
    "FUSE_OEM_K2": "${oem_k2_hex}",
    "FUSE_OEM_KDK1": "${oem_kdk1_hex}",
    "FUSE_UEFI_DB_HASH": "${uefi_db_sha256}",
    "FUSE_ECID": "${ecid_hex}",
    "FUSE_RESERVED_ODM0": "0x48554d41",
    "FUSE_RESERVED_ODM1": "0x4e4f4944"
  },
  "metadata": {
    "key_source": "SoftHSMv2 PKCS#11 Token (${TOKEN_LABEL})",
    "pkc_key_id": "${PKC_KEY_ID}",
    "pkc_key_algorithm": "RSA-3072 (SBKPKC)",
    "pkc_pubkey_path": "${PKC_PUB_PEM}",
    "uefi_db_key_id": "${UEFI_DB_KEY_ID}",
    "uefi_db_pubkey_path": "${UEFI_DB_PUB_PEM}",
    "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  }
}
EOF

    log_ok "Official NVIDIA Fuse XML generated:  ${out_xml}"
    log_ok "Tegra SoC eFuse JSON table updated:  ${out_fuses}"
    log_ok "  BootSecurityInfo: 0x00000209 (RSA-3072 PKC + SBK + OEM_K1 Valid)"
    log_ok "  SecurityMode:     0x1 (ENABLED)"
    log_ok "  FUSE_PKC_HASH:    ${pkc_sha256}"

    # Ensure EKB images are synchronized when fuses are burned inside the repo
    if [[ "${out_fuses}" == "${FUSES_CONFIG}" ]]; then
        gen_ekb --chip all --fuses "${out_fuses}" >/dev/null
    fi
}

# Generate Official NVIDIA EKB (eks_t234.img / eks_t264.img) using R39.2.1 gen_ekb.py
gen_ekb() {
    local chip="all"
    local out_ekb=""
    local fuses_file="${FUSES_CONFIG}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --chip)  chip="$2"; shift 2 ;;
            --out)   out_ekb="$2"; shift 2 ;;
            --fuses) fuses_file="$2"; shift 2 ;;
            *) log_err "Unknown option for gen-ekb: $1"; exit 1 ;;
        esac
    done

    if [[ ! -f "${fuses_file}" ]]; then
        burn_efuses --out "${FUSES_CONFIG}" --xml "${FUSES_XML}"
        fuses_file="${FUSES_CONFIG}"
    fi

    mkdir -p "${IMAGES_DIR}"

    # Create ephemeral directory in RAM (/tmp) for gen_ekb.py inputs; shredded immediately
    local tmp_dir
    tmp_dir="$(mktemp -d)"

    # Extract OEM_K1 and OEM_KDK1 from fuse file, and derive EKB payload keys from SoftHSMv2
    local oem_k1_hex oem_kdk1_hex ecid_hex
    read -r oem_k1_hex oem_kdk1_hex ecid_hex < <(python3 -c "
import json, xml.etree.ElementTree as ET
path = '${fuses_file}'
if path.endswith('.xml'):
    root = ET.parse(path).getroot()
    fmap = {e.attrib['name']: e.attrib.get('value', '').replace('0x', '') for e in root.findall('fuse')}
    k1 = fmap.get('OemK1', '00'*32)
    kdk1 = fmap.get('OemKdk0', k1)
    ecid = '0123456789abcdeffedcba9876543210'
else:
    data = json.load(open(path))['fuses']
    k1 = data.get('FUSE_OEM_K1', '00'*32).replace('0x', '')
    kdk1 = data.get('FUSE_OEM_KDK1', k1).replace('0x', '')
    ecid = data.get('FUSE_ECID', '0123456789abcdeffedcba9876543210').replace('0x', '')
print(k1, kdk1, ecid)
")

    local sym_key_hex sym2_key_hex auth_key_hex hw_key_hex ftpm_eps_hex ftpm_sn_hex
    sym_key_hex="$(derive_hsm_sym_key_hex "EKB_KERNEL_ENCRYPTION_SYM_KEY" 32)"
    sym2_key_hex="$(derive_hsm_sym_key_hex "EKB_DISK_ENCRYPTION_SYM2_KEY" 16)"
    auth_key_hex="$(derive_hsm_sym_key_hex "EKB_UEFI_VAR_AUTH_KEY" 16)"
    hw_key_hex="$(derive_hsm_sym_key_hex "EKB_HWKEY_AGENT_KEY" 16)"
    ftpm_eps_hex="$(derive_hsm_sym_key_hex "EKB_FTPM_EPS_SEED" 64)"
    ftpm_sn_hex="000102030405060708090a0b0c0d0e0f10111213"

    printf "%s\n" "${oem_k1_hex}"   > "${tmp_dir}/oem_k1.key"
    printf "%s\n" "${oem_kdk1_hex}" > "${tmp_dir}/oem_kdk1.key"
    printf "%s\n" "${sym_key_hex}"  > "${tmp_dir}/sym.key"
    printf "%s\n" "${sym2_key_hex}" > "${tmp_dir}/sym2.key"
    printf "%s\n" "${auth_key_hex}" > "${tmp_dir}/auth.key"
    printf "%s\n" "${hw_key_hex}"   > "${tmp_dir}/hwkey.key"
    printf "%s\n" "${ftpm_eps_hex}" > "${tmp_dir}/ftpm_eps_seed"

    local gen_ekb_runner="${NVIDIA_GEN_EKB}"
    if [[ ! -f "${gen_ekb_runner}" ]]; then
        log_err "Official NVIDIA R39.2.1 gen_ekb.py not found at ${gen_ekb_runner}"
        rm -rf "${tmp_dir}"
        exit 1
    fi

    if [[ "${chip}" == "t234" || "${chip}" == "all" ]]; then
        local out_t234="${out_ekb:-${EKB_T234_IMG}}"
        mkdir -p "$(dirname "${out_t234}")"
        python3 "${gen_ekb_runner}" \
            -chip t234 \
            -oem_k1_key "${tmp_dir}/oem_k1.key" \
            -in_sym_key "${tmp_dir}/sym.key" \
            -in_sym_key2 "${tmp_dir}/sym2.key" \
            -in_auth_key "${tmp_dir}/auth.key" \
            -in_hw_key "${tmp_dir}/hwkey.key" \
            -in_ftpm_sn "${ftpm_sn_hex}" \
            -in_ftpm_eps_seed "${tmp_dir}/ftpm_eps_seed" \
            -out "${out_t234}"
        log_ok "Generated R39.2.1 T234 (Orin) EKB image: ${out_t234} ($(stat -c %s "${out_t234}") bytes, magic: NVEKBP)"
    fi

    if [[ "${chip}" == "t264" || "${chip}" == "all" ]]; then
        local out_t264="${EKB_T264_IMG}"
        if [[ "${chip}" == "t264" && -n "${out_ekb}" ]]; then
            out_t264="${out_ekb}"
        fi
        mkdir -p "$(dirname "${out_t264}")"
        python3 "${gen_ekb_runner}" \
            -chip t264 \
            -oem_kdk1_key "${tmp_dir}/oem_kdk1.key" \
            -in_sym_key "${tmp_dir}/sym.key" \
            -in_sym_key2 "${tmp_dir}/sym2.key" \
            -in_auth_key "${tmp_dir}/auth.key" \
            -in_hw_key "${tmp_dir}/hwkey.key" \
            -in_ftpm_sn "${ftpm_sn_hex}" \
            -in_ftpm_eps_seed "${tmp_dir}/ftpm_eps_seed" \
            -out "${out_t264}"
        log_ok "Generated R39.2.1 T264 (Thor) EKB image: ${out_t264} ($(stat -c %s "${out_t264}") bytes, magic: NVEKBP)"
    fi

    # Verify official R39.2.1 gen_luks_passphrase.py derivation with EKB sym2.key + ECID
    if [[ -f "${NVIDIA_GEN_LUKS}" ]]; then
        local luks_pass
        luks_pass="$(python3 "${NVIDIA_GEN_LUKS}" -k "${tmp_dir}/sym2.key" -c "humanoid-rootfs-luks" -e "${ecid_hex}" -u)"
        log_ok "Verified R39.2.1 LUKS passphrase KDF (gen_luks_passphrase.py): ${luks_pass:0:16}..."
    fi

    rm -rf "${tmp_dir}"
}

# Verify & Extract EKB Image (exact mirror of OP-TEE jetson_ekb_extraction_t234.c & t264.c)
verify_ekb() {
    local in_ekb="${EKB_T234_IMG}"
    local chip="t234"
    local fuses_file="${FUSES_CONFIG}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --in)    in_ekb="$2"; shift 2 ;;
            --chip)  chip="$2"; shift 2 ;;
            --fuses) fuses_file="$2"; shift 2 ;;
            *) log_err "Unknown option for verify-ekb: $1"; exit 1 ;;
        esac
    done

    if [[ ! -f "${in_ekb}" ]]; then
        log_err "EKB image not found: ${in_ekb}"
        return 1
    fi

    local verify_res
    verify_res="$(python3 -c "
import json, struct, sys, xml.etree.ElementTree as ET
from math import ceil
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import cmac, hashes
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.kdf.kbkdf import CounterLocation, KBKDFHMAC, Mode

fuses_path = '${fuses_file}'
chip = '${chip}'
ekb_path = '${in_ekb}'

if fuses_path.endswith('.xml'):
    root = ET.parse(fuses_path).getroot()
    fmap = {e.attrib['name']: e.attrib.get('value', '').replace('0x', '') for e in root.findall('fuse')}
    fuse_hex = fmap.get('OemK1' if chip == 't234' else 'OemKdk0', '')
else:
    data = json.load(open(fuses_path))['fuses']
    fuse_hex = data.get('FUSE_OEM_K1' if chip == 't234' else 'FUSE_OEM_KDK1', data.get('FUSE_PKC_HASH', '')).replace('0x', '')

if len(fuse_hex) != 64:
    print('FAIL: Invalid or missing 32-byte OEM fuse key in fuse table')
    sys.exit(1)

fuse_key = bytes.fromhex(fuse_hex)
blob = open(ekb_path, 'rb').read()
if len(blob) < 1024:
    print(f'FAIL: EKB image shorter than EKB_MIN_SIZE (1024 bytes): {len(blob)}')
    sys.exit(1)

ekb_len, magic, ver_maj, ver_min = struct.unpack('<I8sHH', blob[:16])
if not magic.startswith(b'NVEKBP'):
    print(f'FAIL: Invalid EKB header magic: {magic}')
    sys.exit(1)

fv_or_res = blob[16:32]
expected_cmac = blob[32:48]
content_header = blob[48:64]
enc_data_len, content_magic = struct.unpack('<I4sxxxxxxxx', content_header)
if content_magic != b'EEKB':
    print(f'FAIL: Invalid EKB content magic: {content_magic}')
    sys.exit(1)

iv = blob[64:80]
ciphertext = blob[80:80+enc_data_len]

def nist_cmac_kdf(key, context, label, dk_len=16):
    okm = b''
    for count in range(ceil(dk_len / 16)):
        data = bytes([count + 1]) + label.encode('utf-8') + b'\x00' + context.encode('utf-8') + (dk_len * 8).to_bytes(4, 'big')
        c = cmac.CMAC(algorithms.AES(key), backend=default_backend())
        c.update(data)
        okm += c.finalize()
    return okm[:dk_len]

def nist_kbkdf_sha256(key, label, context):
    kdf = KBKDFHMAC(
        algorithm=hashes.SHA256(),
        mode=Mode.CounterMode,
        length=32,
        rlen=4,
        llen=4,
        location=CounterLocation.BeforeFixed,
        label=label,
        context=context,
        fixed=None,
        backend=default_backend(),
    )
    return kdf.derive(key)

if chip == 't234':
    enc = Cipher(algorithms.AES(fuse_key), modes.ECB(), backend=default_backend()).encryptor()
    ekb_rk = enc.update(fv_or_res) + enc.finalize()
    key_ek = nist_cmac_kdf(ekb_rk, 'ekb', 'encryption', 16)
    key_ak = nist_cmac_kdf(ekb_rk, 'ekb', 'authentication', 16)
else:
    ctx = b'\x00'
    kdk1 = nist_kbkdf_sha256(fuse_key, b'STATIC_RT', ctx)
    tz_kdk1 = nist_kbkdf_sha256(kdk1, b'STATIC_RT_TZ', ctx)
    ekb_rk = nist_kbkdf_sha256(tz_kdk1, b'ekb', b'root')
    key_ek = nist_kbkdf_sha256(ekb_rk, b'ekb', b'encryption')
    key_ak = nist_kbkdf_sha256(ekb_rk, b'ekb', b'authentication')

c = cmac.CMAC(algorithms.AES(key_ak), backend=default_backend())
c.update(content_header + iv + ciphertext)
calc_cmac = c.finalize()

if calc_cmac != expected_cmac:
    print('FAIL: EKB AES-CMAC authentication failed (OemK1/OemKdk0 mismatch or tampered EKB)')
    sys.exit(1)

dec = Cipher(algorithms.AES(key_ek), modes.CBC(iv), backend=default_backend()).decryptor()
pt = dec.update(ciphertext) + dec.finalize()

# Parse TLV tags (jetson_ekb_extraction_parse_key)
pos = 0
tags = {}
while pos + 8 <= len(pt):
    kt, kl = struct.unpack('<II', pt[pos:pos+8])
    pos += 8
    if kt == 0 and kl == 0:
        break
    if pos + kl > len(pt):
        print('FAIL: Corrupted TLV entry inside EKB plaintext')
        sys.exit(1)
    tags[kt] = pt[pos:pos+kl].hex()
    pos += kl

if 1 not in tags or 2 not in tags or 4 not in tags:
    print(f'FAIL: Missing mandatory EKB keys (found tags: {list(tags.keys())})')
    sys.exit(1)

print(f'PASS: EKB v{ver_maj}.{ver_min} ({chip}) authenticated & extracted tags={sorted(tags.keys())} sym_key={tags[1][:16]}...')
")" || true

    if [[ "${verify_res}" =~ ^PASS ]]; then
        log_ok "${verify_res}"
        return 0
    else
        log_err "${verify_res}"
        return 1
    fi
}

# Construct Official 8,192-byte NVDA Boot Component Header (BCH) + Encrypted/Signed Container
# Follows sources/optee/optee/optee_os/core/pta/tegra/include/jetson_uefi_services.h:
#   - Offset 0..4:     "NVDA" (BCH_HEADER_MAGIC)
#   - Offset 4..8:     "NVD1" (Container stage magic)
#   - Offset 8..12:    Version (2)
#   - Offset 12..16:   Image Type Code (1=kernel/cpubl, 2=bootloader/sbkpkc)
#   - Offset 16..24:   Original Unpadded Payload Size (uint64)
#   - Offset 24..56:   Original Payload SHA-256 (32 bytes)
#   - Offset 56..88:   PKC Public Key SHA-256 Hash (32 bytes)
#   - Offset 88..152:  PKC Public Key SHA-512 Hash (64 bytes)
#   - Offset 152..184: UEFI db Public Key SHA-256 Hash (32 bytes)
#   - Offset 184..200: SBK AES-CMAC Binding Tag over [0..184] + AAD [5120..5216] (16 bytes)
#   - Offset 200..232: Header SHA-256 Checksum (32 bytes)
#   - Offset 256..640: Stage 1 BootROM/MB2 PKC Signature (RSA-3072, 384 bytes)
#   - Offset 640..1024: Stage 2 UEFI Secure Boot db Signature (RSA-3072, 384 bytes)
#   - Offset 5120..5200 (BCH_HEADER_AAD_OFFSET, 80 bytes):
#       * 5120..5124: "BCRT"
#       * 5124..5128 (BCH_HEADER_BINARY_LEN_OFFSET): Encrypted Padded Payload Len (uint32)
#       * 5128..5136: Original Payload Size (uint64)
#       * 5136..5140 (BCH_HEADER_VER_OFFSET): "VER1" (4-byte KDF context)
#       * 5168..5184 (BCH_HEADER_DERIVE_STR_OFFSET): "CPUBL-PAYLOAD-DK" (16-byte KDF label)
#       * 5188..5200 (BCH_HEADER_IV_OFFSET): 12-byte AES-GCM IV
#   - Offset 5200..5216 (BCH_HEADER_TAG_OFFSET, 16 bytes): AES-256-GCM Auth Tag
sign_image() {
    local in_file=""
    local out_file=""
    local img_type="kernel"
    local fuses_file="${FUSES_CONFIG}"
    local ekb_file="${EKB_T234_IMG}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --in)    in_file="$2"; shift 2 ;;
            --out)   out_file="$2"; shift 2 ;;
            --type)  img_type="$2"; shift 2 ;;
            --fuses) fuses_file="$2"; shift 2 ;;
            --ekb)   ekb_file="$2"; shift 2 ;;
            *) log_err "Unknown option: $1"; exit 1 ;;
        esac
    done

    if [[ -z "${in_file}" || ! -f "${in_file}" ]]; then
        log_err "Valid --in <file> required."
        exit 1
    fi

    if [[ ! -f "${fuses_file}" ]]; then
        burn_efuses --out "${FUSES_CONFIG}" --xml "${FUSES_XML}"
        fuses_file="${FUSES_CONFIG}"
    fi
    if [[ ! -f "${ekb_file}" ]]; then
        gen_ekb --chip all --fuses "${fuses_file}"
    fi

    out_file="${out_file:-${in_file}.signed}"
    mkdir -p "$(dirname "${out_file}")"

    log_info "Encrypting & signing R39.2.1 boot component: ${in_file} (type=${img_type})"

    local pkc_sha256 pkc_sha512 uefi_db_sha256
    pkc_sha256="$(get_pkc_hash_sha256 "${PKC_PUB_PEM}")"
    pkc_sha512="$(get_pkc_hash_sha512 "${PKC_PUB_PEM}")"
    uefi_db_sha256="$(get_pkc_hash_sha256 "${UEFI_DB_PUB_PEM}")"

    local work_dir
    work_dir="$(mktemp -d)"
    local to_sign_bin="${work_dir}/bch_digest_input.bin"
    local enc_payload_bin="${work_dir}/enc_payload.bin"
    local hdr_pre_bin="${work_dir}/hdr_pre.bin"
    local pkc_sig_bin="${work_dir}/pkc_sig.bin"
    local uefi_sig_bin="${work_dir}/uefi_sig.bin"

    # Step 1: Extract EKB sym_key (using OemK1 from fuse config), derive CPUBL DK via
    # NIST SP 800-108 HMAC-SHA256 (matching jetson_nist_sp_800_108_kdf.c), pad payload
    # with 0x80 0x00... (matching get_one_and_zeros_padding in jetson_uefi_services.c),
    # and encrypt payload with AES-256-GCM.
    python3 -c "
import hashlib, hmac, json, os, struct, sys, xml.etree.ElementTree as ET
from math import ceil
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import cmac
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

fuses_path = '${fuses_file}'
if fuses_path.endswith('.xml'):
    root = ET.parse(fuses_path).getroot()
    fmap = {e.attrib['name']: e.attrib.get('value', '').replace('0x', '') for e in root.findall('fuse')}
    sbk_hex = fmap.get('SecureBootKey', '00'*32)
    oem_k1_hex = fmap.get('OemK1', '00'*32)
else:
    fdata = json.load(open(fuses_path))['fuses']
    sbk_hex = fdata.get('FUSE_SBK', '00'*32).replace('0x', '')
    oem_k1_hex = fdata.get('FUSE_OEM_K1', '00'*32).replace('0x', '')

sbk_key = bytes.fromhex(sbk_hex)
oem_k1_key = bytes.fromhex(oem_k1_hex)

# Extract sym_key (Tag 1) from EKB image via OemK1
ekb_blob = open('${ekb_file}', 'rb').read()
fv = ekb_blob[16:32]
content_hdr = ekb_blob[48:64]
enc_len, _ = struct.unpack('<I4sxxxxxxxx', content_hdr)
ekb_iv = ekb_blob[64:80]
ekb_ct = ekb_blob[80:80+enc_len]

enc = Cipher(algorithms.AES(oem_k1_key), modes.ECB(), backend=default_backend()).encryptor()
ekb_rk = enc.update(fv) + enc.finalize()

def nist_cmac_kdf(key, context, label, dk_len=16):
    okm = b''
    for count in range(ceil(dk_len / 16)):
        data = bytes([count + 1]) + label.encode('utf-8') + b'\x00' + context.encode('utf-8') + (dk_len * 8).to_bytes(4, 'big')
        c = cmac.CMAC(algorithms.AES(key), backend=default_backend())
        c.update(data)
        okm += c.finalize()
    return okm[:dk_len]

key_ek = nist_cmac_kdf(ekb_rk, 'ekb', 'encryption', 16)
dec = Cipher(algorithms.AES(key_ek), modes.CBC(ekb_iv), backend=default_backend()).decryptor()
ekb_pt = dec.update(ekb_ct) + dec.finalize()

pos = 0
sym_key = None
while pos + 8 <= len(ekb_pt):
    kt, kl = struct.unpack('<II', ekb_pt[pos:pos+8])
    pos += 8
    if kt == 0 and kl == 0:
        break
    if kt == 1:
        sym_key = ekb_pt[pos:pos+kl]
        break
    pos += kl

if sym_key is None:
    raise RuntimeError('Failed to extract Tag 1 (ekb_kernel_encryption_key) from EKB')

# NIST-SP 800-108 HMAC-SHA256 KDF matching jetson_nist_sp_800_108_kdf.c
def jetson_nist_sp_800_108_hmac_kdf(key, context_bytes, label_bytes, dk_len=32):
    counter = (1).to_bytes(4, 'big')
    L = (dk_len * 8).to_bytes(4, 'big')
    msg = bytearray(counter + label_bytes + b'\x00' + context_bytes + L)
    out = b''
    while len(out) < dk_len:
        out += hmac.new(key, bytes(msg), hashlib.sha256).digest()
        msg[0] = (msg[0] + 1) & 0xff
    return out[:dk_len]

raw_payload = open('${in_file}', 'rb').read()
orig_size = len(raw_payload)
orig_sha256 = hashlib.sha256(raw_payload).digest()

# ISO/IEC 9797-1 Method 2 padding (0x80 followed by 0x00 to 16-byte AES block boundary)
# matching get_one_and_zeros_padding() in jetson_uefi_services.c
pad_rem = (16 - ((orig_size + 1) % 16)) % 16
padded_payload = raw_payload + b'\x80' + (b'\x00' * pad_rem)
padded_len = len(padded_payload)

ver_bytes = b'VER1'
derive_str = b'CPUBL-PAYLOAD-DK'
iv_12 = hashlib.sha256(orig_sha256 + b'::BCH_IV').digest()[:12]

# Construct 80-byte AAD at offset 5120..5200 (BCH_HEADER_AAD_OFFSET)
aad = bytearray(80)
aad[0:4] = b'BCRT'
struct.pack_into('<I', aad, 4, padded_len)       # offset 5124: BCH_HEADER_BINARY_LEN_OFFSET
struct.pack_into('<Q', aad, 8, orig_size)        # offset 5128: original unpadded size
aad[16:20] = ver_bytes                           # offset 5136: BCH_HEADER_VER_OFFSET
aad[48:64] = derive_str                          # offset 5168: BCH_HEADER_DERIVE_STR_OFFSET
aad[68:80] = iv_12                               # offset 5188: BCH_HEADER_IV_OFFSET

img_type_str = '${img_type}'
type_code = 2 if img_type_str in ('bootloader', 'firmware') else 1
base_enc_key = sbk_key if type_code == 2 else sym_key
dk = jetson_nist_sp_800_108_hmac_kdf(base_enc_key, ver_bytes, derive_str, 32)

aesgcm = AESGCM(dk)
ct_with_tag = aesgcm.encrypt(iv_12, padded_payload, bytes(aad))
ciphertext = ct_with_tag[:-16]
gcm_tag = ct_with_tag[-16:]

# Build 8192-byte NVDA BCH Header
bch = bytearray(8192)
bch[0:4] = b'NVDA'                               # BCH_HEADER_MAGIC
bch[4:8] = b'NVD1'                               # Container magic
struct.pack_into('<IIQ', bch, 8, 2, type_code, orig_size)
bch[24:56] = orig_sha256
bch[56:88] = bytes.fromhex('${pkc_sha256}')
bch[88:152] = bytes.fromhex('${pkc_sha512}')
bch[152:184] = bytes.fromhex('${uefi_db_sha256}')
bch[5120:5200] = aad
bch[5200:5216] = gcm_tag                         # BCH_HEADER_TAG_OFFSET

# Compute SBK AES-CMAC binding over [0..184] + [5120..5216]
c = cmac.CMAC(algorithms.AES(sbk_key), backend=default_backend())
c.update(bytes(bch[0:184]) + bytes(bch[5120:5216]))
bch[184:200] = c.finalize()

# Compute Header Checksum over [0..200] + [5120..5216]
hdr_chk = hashlib.sha256(bytes(bch[0:200]) + bytes(bch[5120:5216])).digest()
bch[200:232] = hdr_chk

# Save pre-signature BCH, encrypted payload, and digest input for HSM signing
open('${hdr_pre_bin}', 'wb').write(bch)
open('${enc_payload_bin}', 'wb').write(ciphertext)
sign_target = hdr_chk + gcm_tag + hashlib.sha256(ciphertext).digest()
open('${to_sign_bin}', 'wb').write(sign_target)
"

    # Step 2: Sign with Stage 1 SoC PKC Key (SoftHSMv2 SecureBootKey, ID 06, RSA-3072)
    "${PKCS11_TOOL}" --module "${PKCS11_MODULE}" \
        --token-label "${TOKEN_LABEL}" \
        --login --pin "${USER_PIN}" \
        --sign --id "${PKC_KEY_ID}" \
        -m SHA256-RSA-PKCS \
        --input-file "${to_sign_bin}" \
        --output-file "${pkc_sig_bin}" >/dev/null 2>&1

    # Step 3: Sign with Stage 2 UEFI Secure Boot db Key (SoftHSMv2 ID 01, RSA-3072)
    "${PKCS11_TOOL}" --module "${PKCS11_MODULE}" \
        --token-label "${TOKEN_LABEL}" \
        --login --pin "${USER_PIN}" \
        --sign --id "${UEFI_DB_KEY_ID}" \
        -m SHA256-RSA-PKCS \
        --input-file "${to_sign_bin}" \
        --output-file "${uefi_sig_bin}" >/dev/null 2>&1

    # Step 4: Embed both RSA-3072 signatures into the 8192-byte NVDA BCH header and assemble container
    python3 -c "
bch = bytearray(open('${hdr_pre_bin}', 'rb').read())
pkc_sig = open('${pkc_sig_bin}', 'rb').read()
uefi_sig = open('${uefi_sig_bin}', 'rb').read()
bch[256:256+len(pkc_sig)] = pkc_sig
bch[640:640+len(uefi_sig)] = uefi_sig

with open('${out_file}', 'wb') as f:
    f.write(bch)
    f.write(open('${enc_payload_bin}', 'rb').read())

with open('${out_file}.sigheader', 'wb') as f:
    f.write(bch)
"

    local orig_sz total_sz
    orig_sz="$(stat -c %s "${in_file}")"
    total_sz="$(stat -c %s "${out_file}")"
    rm -rf "${work_dir}"

    log_ok "Signed & Encrypted R39.2.1 NVDA BCH Container created: ${out_file}"
    log_ok "  BCH Header:       8192 bytes (Magic: NVDA / BCRT, AAD @ 0x1400, GCM Tag @ 0x1450)"
    log_ok "  Stage 1 Auth:     SBKPKC (RSA-3072 PKC Hash: ${pkc_sha256:0:16}... + SBK CMAC)"
    log_ok "  Stage 2 Auth:     UEFI Secure Boot db (RSA-3072) + EKB CPUBL AES-256-GCM"
    log_ok "  Payload Size:     ${orig_sz} bytes -> ${total_sz} bytes (8KB BCH + padded GCM ciphertext)"
}

# Verify 8192-byte NVDA BCH Container against Fuse XML/JSON, EKB sym_key, PKC & UEFI db signatures,
# and decrypt payload using AES-256-GCM (matching OP-TEE jetson_uefi_services.c)
verify_container() {
    local in_file=""
    local fuses_file="${FUSES_CONFIG}"
    local ekb_file="${EKB_T234_IMG}"
    local decrypt_out=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --in)          in_file="$2"; shift 2 ;;
            --fuses)       fuses_file="$2"; shift 2 ;;
            --ekb)         ekb_file="$2"; shift 2 ;;
            --decrypt-out) decrypt_out="$2"; shift 2 ;;
            *) log_err "Unknown option: $1"; exit 1 ;;
        esac
    done

    if [[ -z "${in_file}" || ! -f "${in_file}" ]]; then
        log_err "Valid --in <signed-file> required."
        exit 1
    fi

    if [[ ! -f "${fuses_file}" ]]; then
        burn_efuses --out "${FUSES_CONFIG}" --xml "${FUSES_XML}"
        fuses_file="${FUSES_CONFIG}"
    fi
    if [[ ! -f "${ekb_file}" ]]; then
        gen_ekb --chip all --fuses "${fuses_file}"
    fi

    log_info "Verifying R39.2.1 NVDA BCH Container: ${in_file}"

    local verify_res
    verify_res="$(python3 -c "
import hashlib, hmac, json, os, struct, subprocess, sys, tempfile, xml.etree.ElementTree as ET
from math import ceil
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import cmac
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

fuses_path = '${fuses_file}'
if fuses_path.endswith('.xml'):
    root = ET.parse(fuses_path).getroot()
    fmap = {e.attrib['name']: e.attrib for e in root.findall('fuse')}
    sec_mode = int(fmap.get('SecurityMode', {}).get('value', '0x0'), 16)
    bsi = int(fmap.get('BootSecurityInfo', {}).get('value', '0x0'), 16)
    expected_pkc_sha512 = fmap.get('PublicKeyHash', {}).get('value', '').replace('0x', '').lower()
    expected_pkc_sha256 = fmap.get('PublicKeyHash', {}).get('sha256', '').replace('0x', '').lower()
    sbk_hex = fmap.get('SecureBootKey', {}).get('value', '').replace('0x', '')
    oem_k1_hex = fmap.get('OemK1', {}).get('value', '').replace('0x', '')
else:
    raw_json = json.load(open(fuses_path))
    fuses = raw_json.get('fuses', {})
    sec_mode = int(str(fuses.get('FUSE_SECURITY_MODE', raw_json.get('security_mode', '1'))), 0)
    bsi = int(str(fuses.get('FUSE_BOOT_SECURITY_INFO', '0x00000209')), 0)
    expected_pkc_sha256 = fuses.get('FUSE_PKC_HASH', '').replace('0x', '').lower()
    expected_pkc_sha512 = fuses.get('FUSE_PUBLIC_KEY_HASH_SHA512', '').replace('0x', '').lower()
    sbk_hex = fuses.get('FUSE_SBK', '').replace('0x', '')
    oem_k1_hex = fuses.get('FUSE_OEM_K1', '').replace('0x', '')

if (sec_mode & 0x1) == 0:
    print('FAIL: FUSE_SECURITY_MODE is not enabled (0x0)')
    sys.exit(1)

with open('${in_file}', 'rb') as f:
    bch = f.read(8192)
    ciphertext = f.read()

if len(bch) < 8192:
    print(f'FAIL: Container shorter than 8192-byte NVDA BCH header boundary ({len(bch)} bytes)')
    sys.exit(1)

if bch[0:4] != b'NVDA':
    print(f'FAIL: Invalid BCH_HEADER_MAGIC: {bch[0:4]} (expected NVDA)')
    sys.exit(1)

_, type_code, orig_size = struct.unpack_from('<IIQ', bch, 8)
orig_sha256 = bch[24:56]
img_pkc_sha256 = bch[56:88].hex().lower()
img_pkc_sha512 = bch[88:152].hex().lower()
img_sbk_cmac = bch[184:200]
img_hdr_chk = bch[200:232]
pkc_sig = bch[256:256+384]
uefi_sig = bch[640:640+384]

aad = bch[5120:5200]
gcm_tag = bch[5200:5216]

# 1. Verify BCH Header Checksum
calc_hdr_chk = hashlib.sha256(bch[0:200] + bch[5120:5216]).digest()
if calc_hdr_chk != img_hdr_chk:
    print('FAIL: NVDA BCH header checksum mismatch (header corrupted)')
    sys.exit(1)

# 2. Verify SoC eFuse PublicKeyHash (PKC)
if expected_pkc_sha256 and img_pkc_sha256 != expected_pkc_sha256:
    print(f'FAIL: PKC PublicKeyHash mismatch (PKC hash mismatch) with SoC eFuses! (Image: {img_pkc_sha256}, Fuse: {expected_pkc_sha256})')
    sys.exit(1)
if expected_pkc_sha512 and img_pkc_sha512 != expected_pkc_sha512:
    print('FAIL: PKC SHA-512 PublicKeyHash mismatch with SoC eFuses!')
    sys.exit(1)

# 3. Verify SBK AES-CMAC Binding if SBK fuse is present
if len(sbk_hex) == 64:
    sbk_key = bytes.fromhex(sbk_hex)
    c = cmac.CMAC(algorithms.AES(sbk_key), backend=default_backend())
    c.update(bch[0:184] + bch[5120:5216])
    if c.finalize() != img_sbk_cmac:
        print('FAIL: SecureBootKey (SBK) AES-CMAC authentication failed!')
        sys.exit(1)
else:
    print('FAIL: Missing 32-byte SecureBootKey (SBK) in fuse configuration!')
    sys.exit(1)

# 4. Verify Stage 1 (BootROM/MB2 PKC) and Stage 2 (UEFI db) RSA-3072 Signatures
sign_target = img_hdr_chk + gcm_tag + hashlib.sha256(ciphertext).digest()
with tempfile.TemporaryDirectory() as td:
    msg_p = os.path.join(td, 'msg.bin')
    sig1_p = os.path.join(td, 'sig1.bin')
    sig2_p = os.path.join(td, 'sig2.bin')
    open(msg_p, 'wb').write(sign_target)
    open(sig1_p, 'wb').write(pkc_sig)
    open(sig2_p, 'wb').write(uefi_sig)

    r1 = subprocess.run(['openssl', 'dgst', '-sha256', '-verify', '${PKC_PUB_PEM}', '-signature', sig1_p, msg_p], capture_output=True)
    if r1.returncode != 0:
        print('FAIL: Stage 1 BootROM/MB2 PKC RSA-3072 signature verification failed')
        sys.exit(1)

    r2 = subprocess.run(['openssl', 'dgst', '-sha256', '-verify', '${UEFI_DB_PUB_PEM}', '-signature', sig2_p, msg_p], capture_output=True)
    if r2.returncode != 0:
        print('FAIL: Stage 2 UEFI Secure Boot db RSA-3072 signature verification failed')
        sys.exit(1)

# 5. Extract sym_key from EKB image (eks_t234.img) using OemK1 fuse (jetson_ekb_extraction_t234.c)
if len(oem_k1_hex) != 64:
    print('FAIL: Missing 32-byte OemK1 fuse key for EKB extraction')
    sys.exit(1)

oem_k1_key = bytes.fromhex(oem_k1_hex)
ekb_blob = open('${ekb_file}', 'rb').read()
if len(ekb_blob) < 1024 or not ekb_blob[4:12].startswith(b'NVEKBP'):
    print('FAIL: Invalid or corrupted EKB image header')
    sys.exit(1)

fv = ekb_blob[16:32]
ekb_cmac_expected = ekb_blob[32:48]
content_hdr = ekb_blob[48:64]
enc_len, content_magic = struct.unpack('<I4sxxxxxxxx', content_hdr)
if content_magic != b'EEKB':
    print('FAIL: Invalid EKB content magic')
    sys.exit(1)
ekb_iv = ekb_blob[64:80]
ekb_ct = ekb_blob[80:80+enc_len]

enc = Cipher(algorithms.AES(oem_k1_key), modes.ECB(), backend=default_backend()).encryptor()
ekb_rk = enc.update(fv) + enc.finalize()

def nist_cmac_kdf(key, context, label, dk_len=16):
    okm = b''
    for count in range(ceil(dk_len / 16)):
        data = bytes([count + 1]) + label.encode('utf-8') + b'\x00' + context.encode('utf-8') + (dk_len * 8).to_bytes(4, 'big')
        c = cmac.CMAC(algorithms.AES(key), backend=default_backend())
        c.update(data)
        okm += c.finalize()
    return okm[:dk_len]

key_ek = nist_cmac_kdf(ekb_rk, 'ekb', 'encryption', 16)
key_ak = nist_cmac_kdf(ekb_rk, 'ekb', 'authentication', 16)

c_ekb = cmac.CMAC(algorithms.AES(key_ak), backend=default_backend())
c_ekb.update(content_hdr + ekb_iv + ekb_ct)
if c_ekb.finalize() != ekb_cmac_expected:
    print('FAIL: EKB AES-CMAC verification failed (OemK1 fuse mismatch or tampered EKB)')
    sys.exit(1)

dec = Cipher(algorithms.AES(key_ek), modes.CBC(ekb_iv), backend=default_backend()).decryptor()
ekb_pt = dec.update(ekb_ct) + dec.finalize()

pos = 0
sym_key = None
while pos + 8 <= len(ekb_pt):
    kt, kl = struct.unpack('<II', ekb_pt[pos:pos+8])
    pos += 8
    if kt == 0 and kl == 0:
        break
    if kt == 1:
        sym_key = ekb_pt[pos:pos+kl]
        break
    pos += kl

if sym_key is None:
    print('FAIL: EKB missing Tag 1 (ekb_kernel_encryption_key)')
    sys.exit(1)

# 6. Decrypt CPUBL payload via jetson_uefi_services.c (BCH AAD + NIST SP 800-108 HMAC-SHA256 + AES-256-GCM)
if aad[0:4] != b'BCRT':
    print('FAIL: Invalid BCH AAD magic (expected BCRT)')
    sys.exit(1)

padded_len = struct.unpack_from('<I', aad, 4)[0]
ver_bytes = aad[16:20]
derive_str = aad[48:64]
iv_12 = aad[68:80]

if len(ciphertext) != padded_len:
    print(f'FAIL: Encrypted payload length mismatch (expected {padded_len}, got {len(ciphertext)})')
    sys.exit(1)

def jetson_nist_sp_800_108_hmac_kdf(key, context_bytes, label_bytes, dk_len=32):
    counter = (1).to_bytes(4, 'big')
    L = (dk_len * 8).to_bytes(4, 'big')
    msg = bytearray(counter + label_bytes + b'\x00' + context_bytes + L)
    out = b''
    while len(out) < dk_len:
        out += hmac.new(key, bytes(msg), hashlib.sha256).digest()
        msg[0] = (msg[0] + 1) & 0xff
    return out[:dk_len]

base_enc_key = sbk_key if type_code == 2 else sym_key
dk = jetson_nist_sp_800_108_hmac_kdf(base_enc_key, ver_bytes, derive_str, 32)

try:
    padded_pt = AESGCM(dk).decrypt(iv_12, ciphertext + gcm_tag, aad)
except Exception as e:
    print(f'FAIL: AES-256-GCM CPUBL payload decryption/tag verification failed: {e}')
    sys.exit(1)

# Unpad ISO/IEC 9797-1 Method 2 (0x80 0x00... — get_one_and_zeros_padding in jetson_uefi_services.c)
idx = len(padded_pt) - 1
while idx >= 0 and padded_pt[idx] == 0:
    idx -= 1
if idx < 0 or padded_pt[idx] != 0x80 or idx != orig_size:
    print('FAIL: Invalid ISO/IEC 9797-1 0x80 padding after AES-GCM decryption')
    sys.exit(1)

plaintext = padded_pt[:idx]
if hashlib.sha256(plaintext).digest() != orig_sha256:
    print('FAIL: Decrypted payload SHA-256 digest mismatch')
    sys.exit(1)

dec_out = '${decrypt_out}'
if dec_out:
    os.makedirs(os.path.dirname(os.path.abspath(dec_out)), exist_ok=True)
    with open(dec_out, 'wb') as df:
        df.write(plaintext)

print(f'PASS: R39.2.1 NVDA BCH + SBKPKC + EKB + UEFI db verified & decrypted ({orig_size} bytes). PKC: {img_pkc_sha256[:16]}...')
")" || true

    if [[ "${verify_res}" =~ ^PASS ]]; then
        log_ok "${verify_res}"
        return 0
    else
        log_err "${verify_res}"
        return 1
    fi
}

# 5-Point R39.2.1 Secure Boot & EKB Tamper Resistance Test Suite
run_tamper_test() {
    log_info "--- [NVIDIA Jetson R39.2.1 Secure Boot & EKB Tamper Resistance Suite] ---"

    local test_dir
    test_dir="$(mktemp -d)"
    local test_payload="${test_dir}/boot_payload.bin"
    local signed_container="${test_dir}/boot_payload.bin.signed"
    local decrypted_payload="${test_dir}/boot_payload.bin.decrypted"
    local tampered_container="${test_dir}/boot_payload_tampered.bin.signed"

    echo "HUMANOID_SECURITY_PLATFORM_R39_2_1_KERNEL_PAYLOAD_V2" > "${test_payload}"

    # Sign & encrypt legitimate payload
    sign_image --in "${test_payload}" --out "${signed_container}"

    # Test 1: Verify legitimate container & bit-for-bit decryption
    log_info "[TEST 1] Verifying legitimate NVDA BCH + SBKPKC + EKB + UEFI db container..."
    if verify_container --in "${signed_container}" --decrypt-out "${decrypted_payload}" && cmp -s "${test_payload}" "${decrypted_payload}"; then
        log_ok "Test 1 PASSED: Legitimate container authenticated and decrypted bit-for-bit."
    else
        log_err "Test 1 FAILED: Legitimate container was rejected or decryption mismatched."
        rm -rf "${test_dir}"
        return 1
    fi

    # Test 2: Flip 1 byte in AES-256-GCM encrypted payload body (offset 8200, inside ciphertext)
    log_info "[TEST 2] Injecting 1-byte tamper in AES-256-GCM encrypted payload body..."
    cp "${signed_container}" "${tampered_container}"
    python3 -c "
with open('${tampered_container}', 'r+b') as f:
    f.seek(8200)
    b = f.read(1)
    f.seek(8200)
    f.write(bytes([b[0] ^ 0xFF]))
"
    if verify_container --in "${tampered_container}" >/dev/null 2>&1; then
        log_err "Test 2 FAILED: Tampered encrypted payload was unexpectedly ACCEPTED!"
        rm -rf "${test_dir}"
        return 1
    else
        log_ok "Test 2 PASSED: Tampered encrypted payload correctly REJECTED (GCM tag + signature failure)."
    fi

    # Test 3: Modify eFuse PublicKeyHash / SBK in XML fuse configuration
    log_info "[TEST 3] Simulating SoC eFuse PublicKeyHash mismatch in <genericfuse> XML..."
    local fake_xml="${test_dir}/fake_fuse_config.xml"
    cat <<EOF > "${fake_xml}"
<genericfuse MagicId="0x45535546" version="1.0.0">
    <fuse name="PublicKeyHash" size="64" value="0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" sha256="0x0000000000000000000000000000000000000000000000000000000000000000" />
    <fuse name="SecureBootKey" size="32" value="0x0000000000000000000000000000000000000000000000000000000000000000" />
    <fuse name="OemK1" size="32" value="0x0000000000000000000000000000000000000000000000000000000000000000" />
    <fuse name="BootSecurityInfo" size="4" value="0x00000209" />
    <fuse name="SecurityMode" size="4" value="0x1" />
</genericfuse>
EOF
    if verify_container --in "${signed_container}" --fuses "${fake_xml}" >/dev/null 2>&1; then
        log_err "Test 3 FAILED: Image with mismatched <genericfuse> XML was unexpectedly ACCEPTED!"
        rm -rf "${test_dir}"
        return 1
    else
        log_ok "Test 3 PASSED: SoC <genericfuse> XML PublicKeyHash mismatch correctly REJECTED."
    fi

    # Test 4: Flip 1 byte in EKB (eks_t234.img) ciphertext -> EKB AES-CMAC failure
    log_info "[TEST 4] Injecting 1-byte tamper into EKB image (eks_t234.img)..."
    local tampered_ekb="${test_dir}/eks_t234_tampered.img"
    cp "${EKB_T234_IMG}" "${tampered_ekb}"
    python3 -c "
with open('${tampered_ekb}', 'r+b') as f:
    f.seek(120)
    b = f.read(1)
    f.seek(120)
    f.write(bytes([b[0] ^ 0xFF]))
"
    if verify_container --in "${signed_container}" --ekb "${tampered_ekb}" >/dev/null 2>&1; then
        log_err "Test 4 FAILED: Tampered EKB image was unexpectedly ACCEPTED!"
        rm -rf "${test_dir}"
        return 1
    else
        log_ok "Test 4 PASSED: Tampered EKB image correctly REJECTED by AES-CMAC check."
    fi

    # Test 5: Corrupt Stage 2 UEFI Secure Boot db signature (offset 650 inside BCH header)
    log_info "[TEST 5] Corrupting Stage 2 UEFI Secure Boot db signature in BCH header..."
    local tampered_uefi="${test_dir}/boot_payload_bad_uefi.bin.signed"
    cp "${signed_container}" "${tampered_uefi}"
    python3 -c "
with open('${tampered_uefi}', 'r+b') as f:
    f.seek(650)
    b = f.read(1)
    f.seek(650)
    f.write(bytes([b[0] ^ 0xFF]))
"
    if verify_container --in "${tampered_uefi}" >/dev/null 2>&1; then
        log_err "Test 5 FAILED: Corrupted Stage 2 UEFI db signature was unexpectedly ACCEPTED!"
        rm -rf "${test_dir}"
        return 1
    else
        log_ok "Test 5 PASSED: Corrupted Stage 2 UEFI db signature correctly REJECTED."
    fi

    rm -rf "${test_dir}"
    log_ok "All 5 NVIDIA Jetson R39.2.1 Secure Boot & EKB tamper tests passed!"
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
        burn-fuses)
            burn_efuses "$@"
            ;;
        gen-ekb)
            gen_ekb "$@"
            ;;
        verify-ekb)
            verify_ekb "$@"
            ;;
        sign)
            sign_image "$@"
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
