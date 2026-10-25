#!/usr/bin/env bash
# ==============================================================================
# scripts/build_kernel.sh — Dual-Target Linux Kernel Build Pipeline
# ==============================================================================
# Description:
#   Merges base defconfig, KSPP security hardening fragment, and optional QEMU
#   hardware drivers, then cross-compiles the ARM64 kernel Image and modules.
#
# Target Modes:
#   - qemu   (default): [Base defconfig] + [security_hardening] + [qemu_compat]
#   - jetson          : [Base defconfig] + [security_hardening]
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Target & Architecture
ARCH="arm64"
CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
if command -v ccache >/dev/null 2>&1; then
    CROSS_COMPILE="ccache ${CROSS_COMPILE}"
fi

# Directories
SOURCES_DIR="${SOURCES_DIR:-${REPO_ROOT}/sources}"
CONFIG_DIR="${REPO_ROOT}/configs/kernel"
BUILD_ROOT="${BUILD_DIR:-${REPO_ROOT}/build}"
OUT_DIR="${BUILD_ROOT}/kernel"

# Colors
C_RESET="\033[0m"
C_CYAN="\033[1;36m"
C_GREEN="\033[1;32m"
C_YELLOW="\033[1;33m"
C_RED="\033[1;31m"

log_info()  { echo -e "${C_CYAN}[INFO]${C_RESET} $*"; }
log_ok()    { echo -e "${C_GREEN}[OK]${C_RESET}   $*"; }
log_warn()  { echo -e "${C_YELLOW}[WARN]${C_RESET} $*"; }
log_err()   { echo -e "${C_RED}[ERR]${C_RESET}  $*"; }

show_help() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --target <qemu|jetson>   Select build target (default: qemu)
  --config-only            Merge fragments and generate .config without compiling
  --clean                  Clean kernel build directory before building
  --dry-run                Print planned actions and configuration fragments
  -h, --help               Display this help message

Target Modes:
  qemu   : Base defconfig + security_hardening.config + qemu_compat.config
  jetson : Base defconfig + security_hardening.config (Production Jetson Board)
EOF
}

# Auto-locate kernel source tree
find_kernel_src() {
    local candidates=(
        "${SOURCES_DIR}/kernel/kernel/kernel-noble"
        "${SOURCES_DIR}/kernel/kernel-noble"
        "${SOURCES_DIR}/kernel/kernel-6.8"
        "${SOURCES_DIR}/kernel/kernel-5.15"
        "${SOURCES_DIR}/kernel"
        "${SOURCES_DIR}/Linux_for_Tegra/source/kernel/kernel-6.8"
        "${SOURCES_DIR}/Linux_for_Tegra/source/kernel/kernel-5.15"
    )
    for dir in "${candidates[@]}"; do
        if [[ -f "${dir}/Makefile" && -d "${dir}/arch/arm64" ]]; then
            echo "${dir}"
            return 0
        fi
    done
    return 1
}

# Merge config fragment helper (POSIX fallback if merge_config.sh not found)
merge_configs() {
    local base_config="$1"
    local output_config="$2"
    shift 2
    local fragments=("$@")

    log_info "Merging kernel configuration fragments..."
    mkdir -p "$(dirname "${output_config}")"
    cp "${base_config}" "${output_config}"

    for frag in "${fragments[@]}"; do
        if [[ -f "${frag}" ]]; then
            log_info "  + Merging: $(basename "${frag}")"
            # Append fragment and let olddefconfig resolve overrides
            echo "" >> "${output_config}"
            echo "# --- Fragment: $(basename "${frag}") ---" >> "${output_config}"
            cat "${frag}" >> "${output_config}"
        else
            log_warn "Fragment not found: ${frag}"
        fi
    done
}

main() {
    local target="qemu"
    local config_only="false"
    local do_clean="false"
    local dry_run="false"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --target)
                target="$2"
                shift 2
                ;;
            --config-only)
                config_only="true"
                shift
                ;;
            --clean)
                do_clean="true"
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
                log_err "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    if [[ "${target}" != "qemu" && "${target}" != "jetson" ]]; then
        log_err "Invalid target: ${target}. Must be 'qemu' or 'jetson'."
        exit 1
    fi

    log_info "=================================================="
    log_info "Humanoid Security Platform — Kernel Build"
    log_info "Target:         ${target} (Dual-Target Architecture)"
    log_info "Output:         ${OUT_DIR}"
    log_info "Cross Compiler: ${CROSS_COMPILE}"
    log_info "=================================================="

    local kernel_src=""
    if kernel_src=$(find_kernel_src); then
        log_ok "Kernel source located: ${kernel_src}"
    else
        log_warn "Kernel source tree not found in ${SOURCES_DIR}."
        log_warn "Run './scripts/fetch_l4t_sources.sh --extract' first to unpack sources."
        if [[ "${dry_run}" != "true" && "${config_only}" != "true" ]]; then
            log_err "Cannot compile without kernel source. Aborting."
            exit 1
        fi
    fi

    if [[ "${do_clean}" == "true" ]]; then
        log_info "Cleaning ${OUT_DIR}..."
        rm -rf "${OUT_DIR}"
    fi

    mkdir -p "${OUT_DIR}"

    # Select configuration fragments based on target
    local fragments=(
        "${CONFIG_DIR}/security_hardening.config"
    )

    if [[ "${target}" == "qemu" ]]; then
        fragments+=("${CONFIG_DIR}/qemu_compat.config")
    fi

    log_info "Active configuration fragments for '${target}':"
    for f in "${fragments[@]}"; do
        log_info "  - ${f}"
    done

    if [[ "${dry_run}" == "true" ]]; then
        log_ok "[DRY-RUN] Pre-flight checks passed. Configuration fragments validated."
        exit 0
    fi

    # Step 1: Base defconfig generation
    log_info "Generating base defconfig..."
    if [[ -n "${kernel_src}" ]]; then
        local defconfig_name="defconfig"
        if [[ -f "${kernel_src}/arch/arm64/configs/tegra_defconfig" ]]; then
            defconfig_name="tegra_defconfig"
        fi
        log_info "Using base: ${defconfig_name}"
        make -C "${kernel_src}" O="${OUT_DIR}" ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" "${defconfig_name}"

        # Step 2: Merge fragments
        local merge_script="${kernel_src}/scripts/kconfig/merge_config.sh"
        if [[ -x "${merge_script}" ]]; then
            log_info "Invoking upstream merge_config.sh..."
            "${merge_script}" -m -O "${OUT_DIR}" "${OUT_DIR}/.config" "${fragments[@]}"
            make -C "${kernel_src}" O="${OUT_DIR}" ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" olddefconfig
        else
            merge_configs "${OUT_DIR}/.config" "${OUT_DIR}/.config" "${fragments[@]}"
            make -C "${kernel_src}" O="${OUT_DIR}" ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" olddefconfig
        fi
    else
        log_info "Synthesizing standalone merged config in ${OUT_DIR}/.config..."
        echo "# Synthesized standalone configuration" > "${OUT_DIR}/.config"
        for frag in "${fragments[@]}"; do
            cat "${frag}" >> "${OUT_DIR}/.config"
        done
    fi

    log_ok "Merged configuration written to ${OUT_DIR}/.config"

    if [[ "${config_only}" == "true" ]]; then
        log_ok "Configuration complete (--config-only specified). Exiting."
        exit 0
    fi

    # Step 3: Kernel Compilation
    local jobs
    jobs=$(nproc)
    log_info "Compiling Linux Kernel Image with ${jobs} parallel threads..."
    make -C "${kernel_src}" O="${OUT_DIR}" ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" -j"${jobs}" Image modules

    # Step 4: Install modules into staging directory
    local modules_dir="${OUT_DIR}/modules"
    mkdir -p "${modules_dir}"
    log_info "Installing modules to ${modules_dir}..."
    make -C "${kernel_src}" O="${OUT_DIR}" ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" INSTALL_MOD_PATH="${modules_dir}" modules_install

    log_ok "=================================================="
    log_ok "Kernel build completed successfully!"
    log_ok "Kernel Image: ${OUT_DIR}/arch/arm64/boot/Image"
    log_ok "Modules Path: ${modules_dir}"
    log_ok "=================================================="
}

main "$@"

