#!/usr/bin/env bash
# ==============================================================================
# scripts/build_rootfs.sh — Hardened EROFS & dm-verity Rootfs Generator
# ==============================================================================
# Description:
#   Constructs an immutable EROFS root filesystem, generates a SHA-256 dm-verity
#   Merkle hash tree, cryptographically signs the root hash via SoftHSM PKCS#11,
#   and validates cryptographic integrity and tamper-resistance.
#
# References:
#   - SRD-STR-001: Immutable Root Filesystem (EROFS)
#   - SRD-STR-002: Block-Level Integrity Verification (dm-verity)
#   - SRD-INT-001: IMA Runtime Measurement & Policy Configuration
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Configuration & Paths
BUILD_DIR="${BUILD_DIR:-${REPO_ROOT}/build}"
IMAGES_DIR="${BUILD_DIR}/images"
FIRMWARE_DIR="${BUILD_DIR}/firmware"
CACHE_DIR="${REPO_ROOT}/.cache"
HOST_TOOLS_DIR="${CACHE_DIR}/host_tools"
SIGN_HELPER="${REPO_ROOT}/keys_hsm/sign_helper.sh"

BLOCK_SIZE="${BLOCK_SIZE:-4096}"
HASH_ALGO="${HASH_ALGO:-sha256}"
ROOTFS_PROFILE="minimal"
DO_SIGN="true"
DO_VERIFY="true"
L4T_ROOTFS_TBZ2="${CACHE_DIR}/downloads/Tegra_Linux_Sample-Root-Filesystem_R39.2.1_aarch64.tbz2"
UBUNTU_ROOTFS_SRC="${REPO_ROOT}/sources/ubuntu_rootfs"

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

show_help() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --minimal             Build fast minimal verification EROFS rootfs (default)
  --ubuntu              Build full NVIDIA L4T R39.2.1 Ubuntu 24.04 LTS EROFS rootfs
  --source <dir>        Source rootfs directory (overrides profile source)
  --output-dir <dir>    Output directory for generated images (default: build/images)
  --block-size <bytes>  Block size for data and hash tree (default: 4096)
  --hash-algo <algo>    dm-verity hash algorithm (default: sha256)
  --no-sign             Skip SoftHSM PKCS#11 signing of dm-verity root hash
  --no-verify           Skip self-verification and tamper detection tests
  -h, --help            Show this help message
EOF
}

# Ensure tools and library paths
setup_tool_environment() {
    local custom_lib_path="${HOST_TOOLS_DIR}/usr/lib/x86_64-linux-gnu:${HOST_TOOLS_DIR}/lib/x86_64-linux-gnu"
    if [[ -d "${HOST_TOOLS_DIR}/usr/lib/x86_64-linux-gnu" ]]; then
        export LD_LIBRARY_PATH="${custom_lib_path}:${LD_LIBRARY_PATH:-}"
    fi

    # Resolve mkfs.erofs
    if command -v mkfs.erofs >/dev/null 2>&1; then
        MKFS_EROFS="$(command -v mkfs.erofs)"
    elif [[ -x "${HOST_TOOLS_DIR}/usr/bin/mkfs.erofs" ]]; then
        MKFS_EROFS="${HOST_TOOLS_DIR}/usr/bin/mkfs.erofs"
    else
        log_err "mkfs.erofs not found in PATH or ${HOST_TOOLS_DIR}."
        exit 1
    fi

    # Resolve veritysetup
    if command -v veritysetup >/dev/null 2>&1; then
        VERITYSETUP="$(command -v veritysetup)"
    elif [[ -x "${HOST_TOOLS_DIR}/sbin/veritysetup" ]]; then
        VERITYSETUP="${HOST_TOOLS_DIR}/sbin/veritysetup"
    else
        log_err "veritysetup not found in PATH or ${HOST_TOOLS_DIR}."
        exit 1
    fi

    log_info "Toolchain resolved:"
    log_info "  mkfs.erofs:  ${MKFS_EROFS}"
    log_info "  veritysetup: ${VERITYSETUP}"
}

# Construct minimal verified rootfs tree if custom source not provided
generate_base_rootfs_tree() {
    local target_dir="$1"
    local toolchain_libc="${REPO_ROOT}/.cache/toolchains/aarch64-none-linux-gnu/aarch64-none-linux-gnu/libc"

    log_info "Generating base rootfs directory structure: ${target_dir}"
    rm -rf "${target_dir}"
    mkdir -p "${target_dir}"/{bin,sbin,usr/bin,usr/sbin,usr/lib,usr/lib64,lib,lib64,etc/ima,dev,proc,sys,mnt,root,var/log,run}

    # /etc/os-release
    cat <<EOF > "${target_dir}/etc/os-release"
NAME="Ubuntu"
VERSION="24.04 LTS (Noble Numbat)"
ID=ubuntu
ID_LIKE=debian
PRETTY_NAME="Ubuntu 24.04 LTS / NVIDIA Jetson Linux R39.2.1 Hardened"
VERSION_ID="24.04"
HOME_URL="https://www.ubuntu.com/"
SUPPORT_URL="https://help.ubuntu.com/"
BUG_REPORT_URL="https://bugs.launchpad.net/ubuntu/"
PRIVACY_POLICY_URL="https://www.ubuntu.com/legal/terms-and-policies/privacy-policy"
UBUNTU_CODENAME=noble
PLATFORM="Jetson-Humanoid-Sec-Platform"
EOF

    # /etc/fstab
    cat <<EOF > "${target_dir}/etc/fstab"
# /etc/fstab: static file system information.
# <file system>             <mount point>   <type>  <options>       <dump>  <pass>
/dev/mapper/dm-root         /               erofs   ro,defaults     0       0
devtmpfs                    /dev            devtmpfs defaults       0       0
proc                        /proc           proc    defaults        0       0
sysfs                       /sys            sysfs   defaults        0       0
tmpfs                       /run            tmpfs   defaults,nodev,nosuid,noexec 0 0
tmpfs                       /tmp            tmpfs   defaults,nodev,nosuid 0 0
EOF

    # /etc/ima/ima-policy (SRD-INT-001)
    cat <<EOF > "${target_dir}/etc/ima/ima-policy"
# IMA Measurement & Appraisal Policy for NVIDIA Jetson Humanoid Platform
# Measure all executables and shared libraries into PCR 10
measure func=BPRM_CHECK mask=MAY_EXEC
measure func=MMAP_CHECK mask=MAY_EXEC
measure func=MODULE_CHECK
measure func=FIRMWARE_CHECK
measure func=POLICY_CHECK
# Appraise root-owned executables
appraise func=BPRM_CHECK fowner=0 appraise_type=imasig
appraise func=MODULE_CHECK appraise_type=imasig
EOF

    # Populate OP-TEE client binaries & libraries
    if [[ -x "${FIRMWARE_DIR}/client/sbin/tee-supplicant" ]]; then
        log_info "Integrating OP-TEE client tools and TAs into rootfs..."
        cp "${FIRMWARE_DIR}/client/sbin/tee-supplicant" "${target_dir}/usr/sbin/"
        cp -d "${FIRMWARE_DIR}/client/lib"/libteec* "${target_dir}/usr/lib/" 2>/dev/null || true
        cp -d "${FIRMWARE_DIR}/client/lib"/libckteec* "${target_dir}/usr/lib/" 2>/dev/null || true
        mkdir -p "${target_dir}/lib/optee_arm64"
        if [[ -d "${FIRMWARE_DIR}/ta" ]]; then
            cp "${FIRMWARE_DIR}/ta"/*.ta "${target_dir}/lib/optee_arm64/" 2>/dev/null || true
        fi
        if [[ -d "${toolchain_libc}" ]]; then
            cp -d "${toolchain_libc}/lib/ld-linux-aarch64.so.1" "${target_dir}/lib/" 2>/dev/null || true
            cp -d "${toolchain_libc}/lib64/libc.so.6" "${target_dir}/usr/lib64/" 2>/dev/null || true
            ln -sf /lib/ld-linux-aarch64.so.1 "${target_dir}/lib64/ld-linux-aarch64.so.1" 2>/dev/null || true
            ln -sf /usr/lib64/libc.so.6 "${target_dir}/lib/libc.so.6" 2>/dev/null || true
        fi
    fi

    # Minimal init script for direct rootfs testing
    cat <<'INIT_EOF' > "${target_dir}/sbin/init"
#!/bin/sh
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev 2>/dev/null || true

echo "=================================================="
echo " Humanoid Security Platform — EROFS Rootfs Loaded"
echo " Filesystem State: Read-Only (dm-verity Protected)"
echo "=================================================="
exec /bin/sh
INIT_EOF
    chmod +x "${target_dir}/sbin/init"

    log_ok "Base rootfs tree created successfully: ${target_dir}"
}

# Extract and provision official NVIDIA L4T R39.2.1 Ubuntu 24.04 Sample Rootfs
prepare_ubuntu_rootfs_tree() {
    local target_dir="$1"
    local marker_file="${target_dir}/.l4t_r39_2_1_extracted"

    if [[ ! -f "${L4T_ROOTFS_TBZ2}" ]]; then
        log_info "NVIDIA L4T Sample Rootfs archive not found locally. Fetching via fetch_l4t_sources.sh..."
        bash "${SCRIPT_DIR}/fetch_l4t_sources.sh" --rootfs-only
    fi

    if [[ ! -f "${marker_file}" ]]; then
        log_info "Extracting NVIDIA L4T R39.2.1 Ubuntu 24.04 Sample Rootfs into ${target_dir}..."
        rm -rf "${target_dir}"
        mkdir -p "${target_dir}"

        # Extract excluding special /dev device nodes (devtmpfs is mounted at runtime)
        # mkfs.erofs --all-root enforces uid=0/gid=0 across all inodes in the EROFS image
        tar -xjf "${L4T_ROOTFS_TBZ2}" \
            -C "${target_dir}" \
            --exclude='dev/*' \
            --no-same-owner \
            --no-same-permissions

        touch "${marker_file}"
        log_ok "Ubuntu 24.04 Sample Rootfs extracted successfully."
    else
        log_info "Reusing cached extracted Ubuntu 24.04 rootfs tree: ${target_dir}"
    fi

    # Ensure all extracted directories/files have user read/traverse permissions for rootless mkfs.erofs
    chmod -R u+rX "${target_dir}" 2>/dev/null || true

    log_info "Provisioning security policies, OP-TEE runtime, and OverlayFS mount points..."
    mkdir -p "${target_dir}"/{dev,proc,sys,run,tmp,mnt,etc/ima,lib/optee_arm64,usr/local/bin}

    echo "jetson-virt" > "${target_dir}/etc/hostname"
    rm -f "${target_dir}/etc/resolv.conf"
    cat <<EOF > "${target_dir}/etc/resolv.conf"
# QEMU SLIRP User Networking DNS & Fallback Public DNS
nameserver 10.0.2.3
nameserver 8.8.8.8
EOF

    # /etc/ima/ima-policy (SRD-INT-001)
    cat <<EOF > "${target_dir}/etc/ima/ima-policy"
# IMA Measurement & Appraisal Policy for NVIDIA Jetson Humanoid Platform
measure func=BPRM_CHECK mask=MAY_EXEC
measure func=MMAP_CHECK mask=MAY_EXEC
measure func=MODULE_CHECK
measure func=FIRMWARE_CHECK
measure func=POLICY_CHECK
appraise func=BPRM_CHECK fowner=0 appraise_type=imasig
appraise func=MODULE_CHECK appraise_type=imasig
EOF

    # Populate OP-TEE client binaries & TAs
    if [[ -x "${FIRMWARE_DIR}/client/sbin/tee-supplicant" ]]; then
        cp -f "${FIRMWARE_DIR}/client/sbin/tee-supplicant" "${target_dir}/usr/sbin/"
        cp -fd "${FIRMWARE_DIR}/client/lib"/libteec* "${target_dir}/usr/lib/" 2>/dev/null || true
        cp -fd "${FIRMWARE_DIR}/client/lib"/libckteec* "${target_dir}/usr/lib/" 2>/dev/null || true
        if [[ -d "${target_dir}/usr/lib/aarch64-linux-gnu" ]]; then
            cp -fd "${FIRMWARE_DIR}/client/lib"/libteec* "${target_dir}/usr/lib/aarch64-linux-gnu/" 2>/dev/null || true
            cp -fd "${FIRMWARE_DIR}/client/lib"/libckteec* "${target_dir}/usr/lib/aarch64-linux-gnu/" 2>/dev/null || true
        fi
        if [[ -d "${FIRMWARE_DIR}/ta" ]]; then
            cp -f "${FIRMWARE_DIR}/ta"/*.ta "${target_dir}/lib/optee_arm64/" 2>/dev/null || true
        fi
    fi

    # Install security status helper utility inside Ubuntu 24.04 userspace
    cat <<'SEC_EOF' > "${target_dir}/usr/local/bin/sec-status"
#!/bin/bash
echo "=================================================================="
echo "  Humanoid Security Platform — Ubuntu 24.04 LTS Runtime Status"
echo "=================================================================="
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    echo "[OS]        ${PRETTY_NAME}"
fi
if [[ -f /proc/version ]]; then
    read -r _ _ kver _ < /proc/version
    echo "[Kernel]    Linux ${kver} aarch64"
fi
while read -r dev mp fstype opts _; do
    if [[ "${mp}" == "/" && "${fstype}" == "overlay" ]]; then
        echo "[Rootfs]    ${dev} on ${mp} type ${fstype} (${opts})"
    elif [[ "${fstype}" == "erofs" ]]; then
        echo "[dm-verity] ${dev} on ${mp} type ${fstype} (${opts})"
    fi
done < /proc/mounts
for dev in /dev/tee0 /dev/teepriv0 /dev/tpmrm0 /dev/mapper/dm-root; do
    if [[ -e "${dev}" ]]; then
        echo "[Device]    ${dev} -> PRESENT"
    else
        echo "[Device]    ${dev} -> NOT FOUND"
    fi
done
if [[ -d /sys/kernel/security/ima ]]; then
    echo "[IMA]       Active (/sys/kernel/security/ima)"
fi
if [[ -x /usr/bin/dpkg ]]; then
    echo "[PkgMgr]    /usr/bin/dpkg & /usr/bin/apt READY (Ubuntu 24.04 arm64)"
fi
if echo "overlay-rw-ok" > /etc/.overlay_probe 2>/dev/null && ! touch /mnt/lower/.ro_probe 2>/dev/null; then
    rm -f /etc/.overlay_probe
    echo "[OverlayFS] RW upperdir (/etc writable) + RO lowerdir (/mnt/lower EROFS immutable) VERIFIED"
fi
echo "=================================================================="
SEC_EOF
    chmod +x "${target_dir}/usr/local/bin/sec-status"

    log_ok "Ubuntu 24.04 rootfs tree provisioned: ${target_dir}"
}

build_erofs_image() {
    local src_dir="$1"
    local erofs_img="$2"

    log_info "Building immutable EROFS filesystem image..."
    log_info "  Source:      ${src_dir}"
    log_info "  Destination: ${erofs_img}"
    log_info "  Block size:  ${BLOCK_SIZE} bytes"

    mkdir -p "$(dirname "${erofs_img}")"
    rm -f "${erofs_img}"

    "${MKFS_EROFS}" \
        -b "${BLOCK_SIZE}" \
        -x 2 \
        --all-root \
        "${erofs_img}" \
        "${src_dir}"

    local img_size
    img_size="$(stat -c %s "${erofs_img}")"
    log_ok "EROFS image generated: ${erofs_img} (${img_size} bytes)"
}

generate_dm_verity() {
    local data_img="$1"
    local hash_img="$2"
    local roothash_file="$3"
    local params_env="$4"

    log_info "Generating dm-verity Merkle hash tree..."
    log_info "  Data device: ${data_img}"
    log_info "  Hash device: ${hash_img}"
    log_info "  Algorithm:   ${HASH_ALGO}"

    rm -f "${hash_img}" "${roothash_file}" "${params_env}"

    local format_output
    format_output="$("${VERITYSETUP}" format \
        --data-block-size="${BLOCK_SIZE}" \
        --hash-block-size="${BLOCK_SIZE}" \
        --hash="${HASH_ALGO}" \
        --root-hash-file="${roothash_file}" \
        "${data_img}" "${hash_img}")"

    echo "${format_output}"

    # Extract parameters for environment file
    local uuid roothash salt data_blocks hash_blocks
    uuid="$(echo "${format_output}" | grep -E '^UUID:' | awk '{print $2}')"
    data_blocks="$(echo "${format_output}" | grep -E '^Data blocks:' | awk '{print $3}')"
    hash_blocks="$(echo "${format_output}" | grep -E '^Hash blocks:' | awk '{print $3}')"
    salt="$(echo "${format_output}" | grep -E '^Salt:' | awk '{print $2}')"
    roothash="$(cat "${roothash_file}" | tr -d ' \n\r')"

    cat <<EOF > "${params_env}"
# dm-verity Runtime Parameters
VERITY_UUID="${uuid}"
VERITY_ROOTHASH="${roothash}"
VERITY_SALT="${salt}"
VERITY_DATA_BLOCKS="${data_blocks}"
VERITY_HASH_BLOCKS="${hash_blocks}"
VERITY_DATA_BLOCK_SIZE="${BLOCK_SIZE}"
VERITY_HASH_BLOCK_SIZE="${BLOCK_SIZE}"
VERITY_HASH_ALGO="${HASH_ALGO}"
EOF

    log_ok "dm-verity hash tree generated: ${hash_img}"
    log_ok "Root Hash:   ${roothash}"
    log_ok "Salt:        ${salt}"
    log_ok "Params Env:  ${params_env}"
}

sign_verity_roothash() {
    local roothash_file="$1"
    local sig_file="$2"

    log_info "Signing dm-verity root hash via SoftHSM PKCS#11 pipeline..."
    if [[ ! -x "${SIGN_HELPER}" ]]; then
        log_err "Signing helper not found: ${SIGN_HELPER}"
        exit 1
    fi

    bash "${SIGN_HELPER}" verity \
        --hash-file "${roothash_file}" \
        --out "${sig_file}"

    log_ok "Root hash signature generated: ${sig_file}"

    log_info "Verifying signature against DmVeritySigningKey..."
    bash "${SIGN_HELPER}" verify \
        --in "${roothash_file}" \
        --sig "${sig_file}" \
        --type verity

    log_ok "Cryptographic verification of root hash: PASSED"
}

verify_integrity_and_tampering() {
    local data_img="$1"
    local hash_img="$2"
    local roothash_file="$3"
    local roothash
    roothash="$(cat "${roothash_file}" | tr -d ' \n\r')"

    log_info "Executing dm-verity integrity verification self-test..."
    "${VERITYSETUP}" verify "${data_img}" "${hash_img}" "${roothash}"
    log_ok "Baseline dm-verity verification: PASSED (Data device matches hash tree)"

    log_info "Executing tamper-resistance test (simulating 1-byte unauthorized modification)..."
    local orig_byte="${IMAGES_DIR}/orig_byte.tmp"
    dd if="${data_img}" of="${orig_byte}" bs=1 skip=128 count=1 status=none

    # Flip 1 byte inside data block (XOR with 0xFF via Python for guaranteed diff)
    python3 -c '
with open("'"${data_img}"'", "r+b") as f:
    f.seek(128)
    b = f.read(1)
    f.seek(128)
    f.write(bytes([b[0] ^ 0xFF]))
'

    local tamper_detected="false"
    if "${VERITYSETUP}" verify "${data_img}" "${hash_img}" "${roothash}" >/dev/null 2>&1; then
        tamper_detected="false"
    else
        tamper_detected="true"
    fi

    # Restore original byte immediately
    dd if="${orig_byte}" of="${data_img}" bs=1 seek=128 count=1 conv=notrunc status=none
    rm -f "${orig_byte}"

    if [[ "${tamper_detected}" != "true" ]]; then
        log_err "CRITICAL FAILURE: dm-verity failed to detect unauthorized data corruption!"
        exit 1
    fi

    # Confirm restored image verifies cleanly
    "${VERITYSETUP}" verify "${data_img}" "${hash_img}" "${roothash}"
    log_ok "Tamper-resistance verification: PASSED (Corrupted data rejected by dm-verity)"
}

main() {
    local src_dir=""
    local output_dir="${IMAGES_DIR}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --minimal)
                ROOTFS_PROFILE="minimal"
                shift
                ;;
            --ubuntu)
                ROOTFS_PROFILE="ubuntu"
                shift
                ;;
            --source)
                src_dir="$2"
                shift 2
                ;;
            --output-dir)
                output_dir="$2"
                shift 2
                ;;
            --block-size)
                BLOCK_SIZE="$2"
                shift 2
                ;;
            --hash-algo)
                HASH_ALGO="$2"
                shift 2
                ;;
            --no-sign)
                DO_SIGN="false"
                shift
                ;;
            --no-verify)
                DO_VERIFY="false"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_err "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    mkdir -p "${output_dir}"
    setup_tool_environment

    local temp_stage=""
    local erofs_img verity_img roothash_file roothash_sig params_env

    if [[ "${ROOTFS_PROFILE}" == "ubuntu" ]]; then
        if [[ -z "${src_dir}" ]]; then
            prepare_ubuntu_rootfs_tree "${UBUNTU_ROOTFS_SRC}"
            src_dir="${UBUNTU_ROOTFS_SRC}"
        fi
        erofs_img="${output_dir}/ubuntu_rootfs.erofs"
        verity_img="${output_dir}/ubuntu_rootfs.verity"
        roothash_file="${output_dir}/ubuntu_verity.roothash"
        roothash_sig="${output_dir}/ubuntu_verity.roothash.sig"
        params_env="${output_dir}/ubuntu_verity_params.env"
    else
        if [[ -z "${src_dir}" ]]; then
            temp_stage="${CACHE_DIR}/run/rootfs_stage"
            generate_base_rootfs_tree "${temp_stage}"
            src_dir="${temp_stage}"
        fi
        erofs_img="${output_dir}/rootfs.erofs"
        verity_img="${output_dir}/rootfs.verity"
        roothash_file="${output_dir}/verity.roothash"
        roothash_sig="${output_dir}/verity.roothash.sig"
        params_env="${output_dir}/verity_params.env"
    fi

    build_erofs_image "${src_dir}" "${erofs_img}"
    generate_dm_verity "${erofs_img}" "${verity_img}" "${roothash_file}" "${params_env}"

    if [[ "${DO_SIGN}" == "true" ]]; then
        sign_verity_roothash "${roothash_file}" "${roothash_sig}"
    fi

    if [[ "${DO_VERIFY}" == "true" ]]; then
        verify_integrity_and_tampering "${erofs_img}" "${verity_img}" "${roothash_file}"
    fi

    if [[ -n "${temp_stage}" && -d "${temp_stage}" ]]; then
        rm -rf "${temp_stage}"
    fi

    log_info "=================================================="
    log_ok   "Phase 5 Rootfs & dm-verity Artifacts Built Successfully (${ROOTFS_PROFILE}):"
    log_info "  Profile:      ${ROOTFS_PROFILE}"
    log_info "  EROFS Image:  ${erofs_img}"
    log_info "  Hash Tree:    ${verity_img}"
    log_info "  Root Hash:    $(cat "${roothash_file}")"
    log_info "  Signature:    ${roothash_sig}"
    log_info "  Environment:  ${params_env}"
    log_info "=================================================="
}

main "$@"
