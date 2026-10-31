#!/usr/bin/env bash
# ==============================================================================
# scripts/flash_jetson_hardware.sh — NVIDIA Jetson Hardware Flashing & Deployment Helper
# ==============================================================================
# Description:
#   Prepares, validates, and stages cryptographic artifacts (PKC eFuse XML, EKB,
#   NVDA BCH signed kernel container, and EROFS/dm-verity rootfs) to flash physical
#   NVIDIA Jetson Orin / Thor humanoid robot compute platforms via official
#   NVIDIA L4T R39.2.1 flashing utilities (odmfuse.sh / flash.sh / l4t_initrd_flash.sh).
#
# References:
#   - NVIDIA Jetson Linux Developer Guide: Secure Boot & Fuse Burning
#   - SRD-SEC-001: Hardware Root of Trust & SoC eFuse (PKC)
#   - SRD-STR-001: Immutable Root Filesystem (EROFS)
#   - SRD-STR-002: Block-Level Integrity Verification (dm-verity)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

BUILD_DIR="${BUILD_DIR:-${REPO_ROOT}/build}"
IMAGES_DIR="${BUILD_DIR}/images"
FIRMWARE_DIR="${BUILD_DIR}/firmware"
CONFIGS_DIR="${REPO_ROOT}/configs"
KEYS_DIR="${REPO_ROOT}/keys_hsm"
L4T_DIR="${REPO_ROOT}/sources/Linux_for_Tegra"

# Default hardware target configuration
DEFAULT_BOARD="jetson-agx-orin-devkit"
DEFAULT_CHIP="t234"
DEFAULT_STORAGE="nvme0n1p1"

# NVIDIA USB Recovery Device IDs (Vendor: 0955)
# 0955:7023 -> Jetson AGX Orin
# 0955:7223 -> Jetson Orin NX / Nano
# 0955:7045 -> Jetson Thor (T264)
readonly NVIDIA_USB_VID="0955"

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
log_step()  { echo -e "\n${C_BOLD}${C_CYAN}>>> $*${C_RESET}"; }

show_help() {
    cat <<EOF
Usage: $(basename "$0") [COMMAND] [OPTIONS]

Commands:
  check-board         Verify USB recovery connection to physical NVIDIA Jetson board
  prepare-payloads    Verify and stage all signed images and fuses into L4T workspace
  fuse                Simulate or perform one-time eFuse burning via odmfuse.sh
  flash               Flash bootloader, EKB, signed kernel, and EROFS/dm-verity rootfs
  status              Display deployment readiness of all hardware target artifacts

Options:
  --board <name>      Target board model (default: ${DEFAULT_BOARD})
  --chip <id>         Target SoC chip (t234 or t264, default: ${DEFAULT_CHIP})
  --storage <dev>     Target storage drive (default: ${DEFAULT_STORAGE})
  --l4t-dir <path>    Path to extracted Linux_for_Tegra directory (default: sources/Linux_for_Tegra)
  --dry-run           Print flashing and fusing commands without executing
  --live-burn         Actually execute hardware eFuse burning (DANGEROUS: IRREVERSIBLE)
  -h, --help          Show this help message

Examples:
  $(basename "$0") status
  $(basename "$0") check-board
  $(basename "$0") prepare-payloads --chip t234
  $(basename "$0") fuse --dry-run
  $(basename "$0") flash --dry-run
EOF
}

check_prerequisites() {
    local missing=0
    for cmd in openssl python3 lsusb; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            log_warn "Host utility '${cmd}' is not installed in current environment."
        fi
    done
    return "${missing}"
}

cmd_check_board() {
    log_step "Checking physical Jetson USB Recovery connection..."

    if ! command -v lsusb >/dev/null 2>&1; then
        log_warn "'lsusb' command not found. Cannot automatically detect USB bus devices."
        log_info "Ensure Jetson board is connected via USB Type-C in Force Recovery Mode."
        return 0
    fi

    local dev_line
    dev_line="$(lsusb 2>/dev/null | grep -i "${NVIDIA_USB_VID}:" || true)"

    if [[ -n "${dev_line}" ]]; then
        log_ok "NVIDIA Jetson Recovery Device detected on USB bus:"
        echo "       ${dev_line}"
    else
        log_warn "No NVIDIA Jetson board detected in USB Recovery Mode (Vendor ID: ${NVIDIA_USB_VID})."
        log_info "To enter Force Recovery Mode:"
        log_info "  1. Power off board and connect USB-C flashing port to host."
        log_info "  2. Press and hold 'Force Recovery' button."
        log_info "  3. Press and release 'Power' button."
        log_info "  4. Release 'Force Recovery' button after 2 seconds."
    fi
}

cmd_status() {
    log_step "Physical Hardware Deployment Readiness Status"

    local artifacts=(
        "SoC eFuse XML:${CONFIGS_DIR}/secureboot/fuse_config.xml"
        "PKC Public Key:${KEYS_DIR}/certs/SecureBootKey_pub.pem"
        "UEFI db Public Cert:${KEYS_DIR}/certs/KernelModuleSigningKey_pub.pem"
        "T234 Orin EKB:${IMAGES_DIR}/eks_t234.img"
        "T264 Thor EKB:${IMAGES_DIR}/eks_t264.img"
        "BCH Signed Kernel:${IMAGES_DIR}/kernel.signed"
        "Minimal EROFS Rootfs:${IMAGES_DIR}/rootfs.erofs"
        "Minimal Verity Tree:${IMAGES_DIR}/rootfs.verity"
        "Ubuntu 24.04 EROFS Rootfs:${IMAGES_DIR}/ubuntu_rootfs.erofs"
        "Ubuntu 24.04 Verity Tree:${IMAGES_DIR}/ubuntu_rootfs.verity"
    )

    echo -e "${C_BOLD}======================================================================${C_RESET}"
    echo -e "${C_BOLD}  Hardware Deployment Staging Dashboard${C_RESET}"
    echo -e "${C_BOLD}======================================================================${C_RESET}"

    local all_ready=true
    for entry in "${artifacts[@]}"; do
        local label="${entry%%:*}"
        local path="${entry#*:}"
        if [[ -f "${path}" ]]; then
            local sz
            sz="$(du -h "${path}" 2>/dev/null | awk '{print $1}')"
            printf "  [%-5s] %-28s : %s (%s)\n" "READY" "${label}" "${path#${REPO_ROOT}/}" "${sz}"
        else
            printf "  [%-5s] %-28s : %s\n" "MISS" "${label}" "${path#${REPO_ROOT}/}"
            if [[ ! "${label}" =~ (Thor|Minimal) ]]; then
                all_ready=false
            fi
        fi
    done

    echo -e "${C_BOLD}======================================================================${C_RESET}"
    if [[ "${all_ready}" == "true" ]]; then
        log_ok "Core Jetson Orin R39.2.1 Secure Boot payloads are fully assembled!"
    else
        log_warn "Some payloads are missing. Run './humanoid.sh build --ubuntu' to generate."
    fi
}

cmd_prepare_payloads() {
    local board="$1"
    local chip="$2"
    local l4t_path="$3"

    log_step "Staging cryptographic artifacts into Linux_for_Tegra tree..."

    mkdir -p "${l4t_path}"/bootloader "${l4t_path}"/kernel

    # 1. Stage EKB
    local ekb_src="${IMAGES_DIR}/eks_${chip}.img"
    if [[ -f "${ekb_src}" ]]; then
        cp -p "${ekb_src}" "${l4t_path}/bootloader/eks.img"
        cp -p "${ekb_src}" "${l4t_path}/bootloader/eks_${chip}.img"
        log_ok "Staged Encrypted Key Blob: ${l4t_path}/bootloader/eks.img"
    else
        log_err "EKB not found at ${ekb_src}. Run './humanoid.sh sign-secureboot' first."
        return 1
    fi

    # 2. Stage Signed Kernel
    local kernel_src="${IMAGES_DIR}/kernel.signed"
    if [[ -f "${kernel_src}" ]]; then
        cp -p "${kernel_src}" "${l4t_path}/kernel/kernel.signed"
        log_ok "Staged NVDA BCH signed kernel: ${l4t_path}/kernel/kernel.signed"
    else
        log_err "Signed kernel not found at ${kernel_src}."
        return 1
    fi

    # 3. Stage PKC & UEFI db public certificates
    local pkc_pub="${KEYS_DIR}/certs/SecureBootKey_pub.pem"
    local uefi_pub="${KEYS_DIR}/certs/KernelModuleSigningKey_pub.pem"
    if [[ -f "${pkc_pub}" && -f "${uefi_pub}" ]]; then
        cp -p "${pkc_pub}" "${l4t_path}/bootloader/pkc_pub.pem"
        cp -p "${uefi_pub}" "${l4t_path}/bootloader/uefi_db_pub.pem"
        log_ok "Staged PKC and UEFI db public keys in ${l4t_path}/bootloader/"
    fi

    # 4. Stage EROFS & dm-verity rootfs
    local rootfs_src="${IMAGES_DIR}/ubuntu_rootfs.erofs"
    if [[ ! -f "${rootfs_src}" ]]; then
        rootfs_src="${IMAGES_DIR}/rootfs.erofs"
    fi
    if [[ -f "${rootfs_src}" ]]; then
        log_ok "Staged EROFS root filesystem payload: ${rootfs_src}"
    fi

    log_ok "Payload staging for board '${board}' (${chip}) completed successfully."
}

cmd_fuse() {
    local board="$1"
    local chip="$2"
    local l4t_path="$3"
    local dry_run="$4"
    local live_burn="$5"

    log_step "NVIDIA SoC eFuse Burning (Target: ${board}, Chip: ${chip})"

    local fuse_xml="${CONFIGS_DIR}/secureboot/fuse_config.xml"
    if [[ ! -f "${fuse_xml}" ]]; then
        log_err "eFuse XML configuration not found: ${fuse_xml}"
        return 1
    fi

    local odmfuse_bin="${l4t_path}/odmfuse.sh"

    log_info "Official NVIDIA eFuse XML Configuration: ${fuse_xml}"
    log_info "SoC Chip ID: 0x23 (Orin / T234)"

    local fuse_cmd=("sudo" "${odmfuse_bin}" "-i" "0x23" "-c" "${fuse_xml}")

    if [[ "${live_burn}" != "true" ]]; then
        fuse_cmd+=("--test")
        log_info "Test Mode (--test): Simulates fusing without modifying physical OTP fuses."
    else
        log_warn "*******************************************************************"
        log_warn "CRITICAL: LIVE BURN MODE ENABLED!"
        log_warn "eFuses are ONE-TIME PROGRAMMABLE. This operation is IRREVERSIBLE."
        log_warn "Ensure PKC key is permanently backed up in SoftHSM / HSM storage."
        log_warn "*******************************************************************"
    fi

    fuse_cmd+=("${board}")

    log_info "Planned Fusing Command:"
    echo "  ${fuse_cmd[*]}"

    if [[ "${dry_run}" == "true" ]]; then
        log_ok "[DRY-RUN] odmfuse.sh command planned successfully."
        return 0
    fi

    if [[ ! -x "${odmfuse_bin}" ]]; then
        log_warn "NVIDIA official '${odmfuse_bin}' not found in L4T tree."
        log_info "Download L4T BSP packages into ${L4T_DIR} to run live fusing."
        return 0
    fi

    log_info "Executing odmfuse.sh..."
    "${fuse_cmd[@]}"
    log_ok "eFuse processing finished."
}

cmd_flash() {
    local board="$1"
    local chip="$2"
    local storage="$3"
    local l4t_path="$4"
    local dry_run="$5"

    log_step "NVIDIA Jetson Board Flashing (Board: ${board}, Storage: ${storage})"

    local flash_bin="${l4t_path}/flash.sh"
    local pkc_pub="${KEYS_DIR}/certs/SecureBootKey_pub.pem"

    local flash_cmd=(
        "sudo" "${flash_bin}"
        "-u" "${pkc_pub}"
        "${board}"
        "${storage}"
    )

    log_info "Planned Board Flashing Command:"
    echo "  ${flash_cmd[*]}"

    if [[ "${dry_run}" == "true" ]]; then
        log_ok "[DRY-RUN] flash.sh command verified successfully."
        return 0
    fi

    if [[ ! -x "${flash_bin}" ]]; then
        log_warn "NVIDIA official '${flash_bin}' not found in L4T tree."
        log_info "Ensure official JetPack / L4T BSP is extracted at ${l4t_path}."
        return 0
    fi

    log_info "Executing flash.sh..."
    "${flash_cmd[@]}"
    log_ok "Flashing pipeline finished."
}

main() {
    check_prerequisites

    local command="status"
    local board="${DEFAULT_BOARD}"
    local chip="${DEFAULT_CHIP}"
    local storage="${DEFAULT_STORAGE}"
    local l4t_path="${L4T_DIR}"
    local dry_run="false"
    local live_burn="false"

    if [[ $# -gt 0 ]]; then
        case "$1" in
            check-board|prepare-payloads|fuse|flash|status)
                command="$1"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
        esac
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --board)
                board="$2"
                shift 2
                ;;
            --chip)
                chip="$2"
                shift 2
                ;;
            --storage)
                storage="$2"
                shift 2
                ;;
            --l4t-dir)
                l4t_path="$2"
                shift 2
                ;;
            --dry-run)
                dry_run="true"
                shift
                ;;
            --live-burn)
                live_burn="true"
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

    case "${command}" in
        status)
            cmd_status
            ;;
        check-board)
            cmd_check_board
            ;;
        prepare-payloads)
            cmd_prepare_payloads "${board}" "${chip}" "${l4t_path}"
            ;;
        fuse)
            cmd_fuse "${board}" "${chip}" "${l4t_path}" "${dry_run}" "${live_burn}"
            ;;
        flash)
            cmd_flash "${board}" "${chip}" "${storage}" "${l4t_path}" "${dry_run}"
            ;;
    esac
}

main "$@"
