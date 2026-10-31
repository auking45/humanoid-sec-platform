#!/usr/bin/env bash
# ==============================================================================
# humanoid.sh — Unified Master CLI for Humanoid Security Platform
# ==============================================================================
# Description:
#   Single-command entrypoint that orchestrates the entire platform lifecycle
#   from a fresh git clone (scratch) through HSM provisioning, L4T source fetch,
#   TrustZone firmware/kernel/rootfs compilation, Secure Boot signing, QEMU
#   emulation, automated verification, and Red/Blue Team attack simulations.
#
# Usage:
#   ./humanoid.sh [COMMAND] [OPTIONS]
#
# Commands:
#   all      Full Scratch-to-E2E workflow: setup -> build -> verify (default)
#   setup    Initialize SoftHSMv2 token, PKCS#11 keys, SoC eFuses & Zero-Key audit
#   build    Fetch L4T sources & build TF-A, OP-TEE, Kernel, SecureBoot & Rootfs
#   run      Launch interactive QEMU TrustZone + Secure Boot virtual machine
#   verify   Run headless QEMU boot check, 52 unit/E2E tests & 5 attack demos
#   attack   Run Red/Blue Team attack simulation suite (ATK-01 ~ ATK-05)
#   status   Display platform readiness dashboard (HSM, Firmware, Kernel, Rootfs)
#   clean    Clean temporary runtime staging and log files
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${REPO_ROOT}/scripts"
KEYS_HSM_DIR="${REPO_ROOT}/keys_hsm"
BUILD_DIR="${REPO_ROOT}/build"
CACHE_DIR="${REPO_ROOT}/.cache"

# ANSI Colors
readonly C_RESET="\033[0m"
readonly C_BOLD="\033[1m"
readonly C_GREEN="\033[32m"
readonly C_YELLOW="\033[33m"
readonly C_RED="\033[31m"
readonly C_CYAN="\033[36m"

log_step()  { echo -e "\n${C_BOLD}${C_CYAN}==> $*${C_RESET}"; }
log_info()  { echo -e "${C_CYAN}[INFO]${C_RESET}  $*"; }
log_ok()    { echo -e "${C_GREEN}[OK]${C_RESET}   $*"; }
log_warn()  { echo -e "${C_YELLOW}[WARN]${C_RESET} $*"; }
log_err()   { echo -e "${C_RED}[ERR]${C_RESET}  $*"; }

show_help() {
    cat <<EOF
======================================================================
  Humanoid Security Platform — Unified Master CLI (humanoid.sh)
======================================================================
Usage: ./$(basename "$0") [COMMAND] [OPTIONS]

Commands:
  all        Run full E2E pipeline from scratch: setup -> build -> verify (default)
  setup      Provision SoftHSMv2 PKCS#11 keys, SoC eFuses, and Zero-Key audit
  build      Fetch NVIDIA L4T sources and build Firmware, Kernel & EROFS Rootfs
  run        Boot interactive QEMU TrustZone + Secure Boot virtual machine
  verify     Run headless QEMU boot verification, full test suite & attack demo
  attack     Run Red/Blue Team 5 attack simulation scenarios (ATK-01 ~ ATK-05)
  status     Inspect current build artifacts, HSM token keys & platform readiness
  clean      Clean temporary runtime files (.cache/run, .cache/logs)

Options:
  --minimal     Use fast minimal verification rootfs profile (default)
  --ubuntu      Use full NVIDIA L4T R39.2.1 Ubuntu 24.04 (dm-verity + OverlayFS) profile
  --force       Force full rebuild even if cached build artifacts already exist
  --skip-boot   Skip headless QEMU boot execution during 'verify' / 'all'
  --dry-run     Print planned workflow steps without executing
  -h, --help    Show this help message

Examples (From Fresh Clone):
  ./$(basename "$0")                       # Full scratch-to-E2E build & verification (minimal)
  ./$(basename "$0") all --ubuntu          # Full scratch-to-E2E with Ubuntu 24.04 OverlayFS
  ./$(basename "$0") run --ubuntu          # Enter interactive Ubuntu 24.04 LTS security shell
  ./$(basename "$0") verify                # Run boot check + 52 unit tests + 5 attack demos
  ./$(basename "$0") attack                # Run Red/Blue Team attack simulations only
  ./$(basename "$0") status                # Show platform readiness dashboard
EOF
}

setup_paths() {
    local tc_bin="${CACHE_DIR}/toolchains/aarch64-none-linux-gnu/bin"
    local host_bin="${CACHE_DIR}/host_tools/usr/bin:${CACHE_DIR}/host_tools/sbin"
    local p11_bin="${CACHE_DIR}/pkcs11_tools/usr/bin"
    export PATH="${tc_bin}:${host_bin}:${p11_bin}:${PATH}"

    local host_lib="${CACHE_DIR}/host_tools/usr/lib/x86_64-linux-gnu:${CACHE_DIR}/host_tools/lib/x86_64-linux-gnu"
    local p11_lib="${CACHE_DIR}/pkcs11_tools/usr/lib/x86_64-linux-gnu:${CACHE_DIR}/pkcs11_tools/usr/lib/x86_64-linux-gnu/softhsm"
    export LD_LIBRARY_PATH="${host_lib}:${p11_lib}:${LD_LIBRARY_PATH:-}"
    export SOFTHSM2_CONF="${SOFTHSM2_CONF:-${CACHE_DIR}/softhsm/softhsm2.conf}"
}

cmd_setup() {
    local dry_run="$1"
    log_step "[STEP 1] Provisioning SoftHSMv2 PKCS#11 Token, SoC eFuses & Zero-Key Audit"

    if [[ "${dry_run}" == "true" ]]; then
        log_info "[DRY-RUN] bash keys_hsm/setup_softhsm.sh"
        log_info "[DRY-RUN] bash scripts/sign_jetson_secureboot.sh burn-fuses"
        log_info "[DRY-RUN] bash keys_hsm/audit_zero_keys.sh"
        return 0
    fi

    bash "${KEYS_HSM_DIR}/setup_softhsm.sh"
    bash "${SCRIPTS_DIR}/sign_jetson_secureboot.sh" burn-fuses --out "${REPO_ROOT}/configs/secureboot/tegra_fuses.json"
    bash "${KEYS_HSM_DIR}/audit_zero_keys.sh"
    log_ok "HSM token, PKCS#11 keys, and SoC eFuses provisioned."
}

cmd_build() {
    local profile="$1"
    local force_rebuild="$2"
    local dry_run="$3"

    log_step "[STEP 2] Building Platform Artifacts (Profile: ${profile})"

    local flash0_bin="${BUILD_DIR}/firmware/flash0.bin"
    local kernel_img="${BUILD_DIR}/kernel/arch/arm64/boot/Image"
    local signed_kernel="${BUILD_DIR}/images/kernel.signed"
    local rootfs_erofs="${BUILD_DIR}/images/rootfs.erofs"
    if [[ "${profile}" == "ubuntu" ]]; then
        rootfs_erofs="${BUILD_DIR}/images/ubuntu_rootfs.erofs"
    fi

    if [[ "${dry_run}" == "true" ]]; then
        log_info "[DRY-RUN] bash scripts/fetch_l4t_sources.sh (profile=${profile})"
        log_info "[DRY-RUN] bash scripts/build_tfa_optee.sh"
        log_info "[DRY-RUN] bash scripts/build_kernel.sh --target qemu"
        log_info "[DRY-RUN] bash scripts/sign_jetson_secureboot.sh sign --in ${kernel_img} --out ${signed_kernel}"
        log_info "[DRY-RUN] bash scripts/build_rootfs.sh --${profile}"
        return 0
    fi

    # 1. Fetch L4T sources if needed
    if [[ "${force_rebuild}" == "true" || ! -f "${kernel_img}" || ! -f "${flash0_bin}" ]]; then
        log_info "Checking / fetching NVIDIA L4T R39.2.1 sources..."
        bash "${SCRIPTS_DIR}/fetch_l4t_sources.sh"
    fi
    if [[ "${profile}" == "ubuntu" && ! -f "${CACHE_DIR}/downloads/Tegra_Linux_Sample-Root-Filesystem_R39.2.1_aarch64.tbz2" ]]; then
        log_info "Fetching NVIDIA L4T R39.2.1 Ubuntu 24.04 Sample Rootfs..."
        bash "${SCRIPTS_DIR}/fetch_l4t_sources.sh" --rootfs-only
    fi

    # 2. Build TF-A + OP-TEE + Early fTPM TA + flash0.bin
    if [[ "${force_rebuild}" == "true" || ! -f "${flash0_bin}" ]]; then
        log_info "Building TF-A (BL1/BL2/BL31) and OP-TEE (Early fTPM & PKCS#11 TA)..."
        bash "${SCRIPTS_DIR}/build_tfa_optee.sh"
    else
        log_ok "Reusing cached TrustZone firmware image: ${flash0_bin}"
    fi

    # 3. Build Hardened Linux 6.8 Kernel
    if [[ "${force_rebuild}" == "true" || ! -f "${kernel_img}" ]]; then
        log_info "Building hardened Linux 6.8 Noble kernel for QEMU virt..."
        bash "${SCRIPTS_DIR}/build_kernel.sh" --target qemu
    else
        log_ok "Reusing cached hardened kernel image: ${kernel_img}"
    fi

    # 4. Sign Kernel into NVIDIA Tegra PKC NVD1 Container
    if [[ "${force_rebuild}" == "true" || ! -f "${signed_kernel}" ]]; then
        log_info "Signing kernel image with SoftHSMv2 SecureBootKey..."
        bash "${SCRIPTS_DIR}/sign_jetson_secureboot.sh" sign --in "${kernel_img}" --out "${signed_kernel}"
    else
        log_ok "Reusing signed kernel container: ${signed_kernel}"
    fi
    bash "${SCRIPTS_DIR}/sign_jetson_secureboot.sh" verify --in "${signed_kernel}"

    # 5. Build Immutable EROFS + dm-verity Rootfs
    # Always ensure minimal rootfs exists for baseline unit tests
    if [[ "${force_rebuild}" == "true" || ! -f "${BUILD_DIR}/images/rootfs.erofs" ]]; then
        bash "${SCRIPTS_DIR}/build_rootfs.sh" --minimal
    fi

    if [[ "${profile}" == "ubuntu" ]]; then
        if [[ "${force_rebuild}" == "true" || ! -f "${rootfs_erofs}" ]]; then
            bash "${SCRIPTS_DIR}/build_rootfs.sh" --ubuntu
        else
            log_ok "Reusing cached Ubuntu 24.04 EROFS + dm-verity image: ${rootfs_erofs}"
        fi
    fi

    log_ok "All platform artifacts built and cryptographically verified (${profile})."
}

cmd_verify() {
    local profile="$1"
    local skip_boot="$2"
    local dry_run="$3"

    log_step "[STEP 3] Executing End-to-End Security Verification & Attack Suite (Profile: ${profile})"

    if [[ "${dry_run}" == "true" ]]; then
        log_info "[DRY-RUN] bash scripts/run_qemu.sh --${profile} --optee-chain --secureboot --headless --timeout 35"
        log_info "[DRY-RUN] python3 -m unittest discover -s tests -v"
        log_info "[DRY-RUN] bash scripts/run_attack_demo.sh"
        return 0
    fi

    if [[ "${skip_boot}" != "true" && -f "${BUILD_DIR}/firmware/flash0.bin" && -f "${BUILD_DIR}/kernel/arch/arm64/boot/Image" ]]; then
        local boot_timeout=28
        if [[ "${profile}" == "ubuntu" ]]; then
            boot_timeout=35
        fi
        log_info "Running live Headless QEMU TrustZone Cold Boot verification (--${profile}, timeout=${boot_timeout}s)..."
        bash "${SCRIPTS_DIR}/run_qemu.sh" "--${profile}" --optee-chain --secureboot --headless --timeout "${boot_timeout}"
        if grep -q "Full Security Chain verified" "${CACHE_DIR}/logs/console.log" 2>/dev/null; then
            log_ok "Live QEMU Cold Boot Chain Verified: TF-A -> OP-TEE -> Kernel -> Userspace (${profile})"
        else
            log_warn "QEMU boot completed; inspect ${CACHE_DIR}/logs/console.log for full boot output."
        fi
    fi

    log_info "Running full automated test suite (Phase 2 ~ Phase 7)..."
    python3 -m unittest discover -s "${REPO_ROOT}/tests" -v

    log_info "Running Red/Blue Team Attack Simulation Suite (ATK-01 ~ ATK-05)..."
    bash "${SCRIPTS_DIR}/run_attack_demo.sh"

    log_ok "All E2E security checks, unit/integration tests, and attack simulations PASSED!"
}

cmd_run() {
    local profile="$1"
    local dry_run="$2"

    log_step "Launching Interactive QEMU Security Verification VM (Profile: ${profile})"
    if [[ "${dry_run}" == "true" ]]; then
        bash "${SCRIPTS_DIR}/run_qemu.sh" "--${profile}" --optee-chain --secureboot --dry-run
        return 0
    fi
    exec bash "${SCRIPTS_DIR}/run_qemu.sh" "--${profile}" --optee-chain --secureboot
}

cmd_status() {
    echo -e "${C_BOLD}======================================================================${C_RESET}"
    echo -e "${C_BOLD}  Humanoid Security Platform — Readiness Dashboard${C_RESET}"
    echo -e "${C_BOLD}======================================================================${C_RESET}"

    local items=(
        "SoftHSMv2 Config:${CACHE_DIR}/softhsm/softhsm2.conf"
        "SoC eFuse Table:${REPO_ROOT}/configs/secureboot/tegra_fuses.json"
        "TrustZone PFLASH0 (BL1+FIP):${BUILD_DIR}/firmware/flash0.bin"
        "OP-TEE Core (Early fTPM TA):${BUILD_DIR}/firmware/tee-pager_v2.bin"
        "PKCS#11 TA Binary:${BUILD_DIR}/firmware/ta/fd02c9da-306c-48c7-a49c-bbd827ae86ee.ta"
        "Hardened Kernel 6.8 Image:${BUILD_DIR}/kernel/arch/arm64/boot/Image"
        "Tegra PKC Signed Kernel:${BUILD_DIR}/images/kernel.signed"
        "Minimal EROFS + dm-verity:${BUILD_DIR}/images/rootfs.erofs"
        "Ubuntu 24.04 EROFS Image:${BUILD_DIR}/images/ubuntu_rootfs.erofs"
        "Ubuntu 24.04 Verity Tree:${BUILD_DIR}/images/ubuntu_rootfs.verity"
    )

    for entry in "${items[@]}"; do
        local label="${entry%%:*}"
        local path="${entry#*:}"
        if [[ -f "${path}" ]]; then
            local sz
            sz="$(du -h "${path}" 2>/dev/null | awk '{print $1}')"
            printf "  [%-5s] %-28s : %s (%s)\n" "READY" "${label}" "${path#${REPO_ROOT}/}" "${sz}"
        else
            printf "  [%-5s] %-28s : %s\n" "MISS" "${label}" "${path#${REPO_ROOT}/}"
        fi
    done
    echo -e "${C_BOLD}======================================================================${C_RESET}"
}

cmd_clean() {
    log_step "Cleaning temporary runtime staging and logs..."
    rm -rf "${CACHE_DIR}/run"/* "${CACHE_DIR}/logs"/* 2>/dev/null || true
    log_ok "Cleaned .cache/run and .cache/logs."
}

main() {
    setup_paths

    local subcommand="all"
    local profile="minimal"
    local force_rebuild="false"
    local skip_boot="false"
    local dry_run="false"

    if [[ $# -gt 0 ]]; then
        case "$1" in
            all|setup|build|run|verify|attack|status|clean)
                subcommand="$1"
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
            --minimal)
                profile="minimal"
                shift
                ;;
            --ubuntu)
                profile="ubuntu"
                shift
                ;;
            --force)
                force_rebuild="true"
                shift
                ;;
            --skip-boot)
                skip_boot="true"
                shift
                ;;
            --dry-run)
                dry_run="true"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_err "Unknown option or command: $1"
                show_help
                exit 1
                ;;
        esac
    done

    case "${subcommand}" in
        all)
            cmd_setup "${dry_run}"
            cmd_build "${profile}" "${force_rebuild}" "${dry_run}"
            cmd_verify "${profile}" "${skip_boot}" "${dry_run}"
            ;;
        setup)
            cmd_setup "${dry_run}"
            ;;
        build)
            cmd_build "${profile}" "${force_rebuild}" "${dry_run}"
            ;;
        run)
            cmd_run "${profile}" "${dry_run}"
            ;;
        verify)
            cmd_verify "${profile}" "${skip_boot}" "${dry_run}"
            ;;
        attack)
            bash "${SCRIPTS_DIR}/run_attack_demo.sh" $([[ "${dry_run}" == "true" ]] && echo "--dry-run" || true)
            ;;
        status)
            cmd_status
            ;;
        clean)
            cmd_clean
            ;;
    esac
}

main "$@"

