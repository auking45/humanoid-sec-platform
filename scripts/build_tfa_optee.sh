#!/usr/bin/env bash
# ==============================================================================
# scripts/build_tfa_optee.sh — Arm Trusted Firmware & OP-TEE Build Pipeline
# ==============================================================================
# Description:
#   Cross-compiles OP-TEE Core (with PKCS#11 TA, RPMB, and fTPM support) and
#   Arm Trusted Firmware (TF-A BL31/FIP) targeting QEMU aarch64 virt platform.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Cross-compilers
CROSS_COMPILE_64="${CROSS_COMPILE:-aarch64-linux-gnu-}"
if command -v ccache >/dev/null 2>&1; then
    CROSS_COMPILE_64="ccache ${CROSS_COMPILE_64}"
fi

# Directories
SOURCES_DIR="${SOURCES_DIR:-${REPO_ROOT}/sources}"
CONFIG_DIR="${REPO_ROOT}/configs/optee"
BUILD_ROOT="${BUILD_DIR:-${REPO_ROOT}/build}"
OPTEE_OUT="${BUILD_ROOT}/optee"
TFA_OUT="${BUILD_ROOT}/tfa"
BIN_OUT="${BUILD_ROOT}/firmware"

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
  --all            Build both OP-TEE OS and TF-A (default)
  --optee-only     Build only OP-TEE OS (tee-header_v2.bin, tee-pager_v2.bin)
  --tfa-only       Build only TF-A (bl31.bin, fip.bin)
  --clean          Clean build directories before compiling
  --dry-run        Validate configuration and display build commands
  -h, --help       Display this help message
EOF
}

# Locate source trees
find_src_dir() {
    local target="$1"
    local candidates=()
    if [[ "${target}" == "optee" ]]; then
        candidates=(
            "${SOURCES_DIR}/optee/optee_os"
            "${SOURCES_DIR}/optee"
            "${SOURCES_DIR}/Linux_for_Tegra/source/optee"
        )
    elif [[ "${target}" == "tfa" ]]; then
        candidates=(
            "${SOURCES_DIR}/tfa/arm-trusted-firmware"
            "${SOURCES_DIR}/tfa"
            "${SOURCES_DIR}/atf"
            "${SOURCES_DIR}/Linux_for_Tegra/source/atf"
        )
    fi

    for dir in "${candidates[@]}"; do
        if [[ -f "${dir}/Makefile" ]]; then
            echo "${dir}"
            return 0
        fi
    done
    return 1
}

MODE="all"
DO_CLEAN="false"
DRY_RUN="false"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)
            MODE="all"
            shift
            ;;
        --optee-only)
            MODE="optee"
            shift
            ;;
        --tfa-only)
            MODE="tfa"
            shift
            ;;
        --clean)
            DO_CLEAN="true"
            shift
            ;;
        --dry-run)
            DRY_RUN="true"
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

log_info "=================================================="
log_info "Humanoid Security Platform — TF-A & OP-TEE Build"
log_info "Mode:           ${MODE}"
log_info "Target Platform: QEMU ARMv8-A virt (secure=on)"
log_info "Cross Compiler:  ${CROSS_COMPILE_64}"
log_info "Firmware Output: ${BIN_OUT}"
log_info "=================================================="

if [[ "${DO_CLEAN}" == "true" ]]; then
    log_info "Cleaning firmware build directories..."
    rm -rf "${OPTEE_OUT}" "${TFA_OUT}" "${BIN_OUT}"
fi

mkdir -p "${OPTEE_OUT}" "${TFA_OUT}" "${BIN_OUT}"

build_optee() {
    log_info "--- [Building OP-TEE OS] ---"
    local optee_src=""
    if optee_src=$(find_src_dir "optee"); then
        log_ok "OP-TEE source located: ${optee_src}"
    else
        log_warn "OP-TEE source tree not found in ${SOURCES_DIR}."
        log_warn "Run './scripts/fetch_l4t_sources.sh --extract' first."
        if [[ "${DRY_RUN}" != "true" ]]; then
            log_err "Cannot compile OP-TEE without sources. Aborting."
            return 1
        fi
    fi

    local conf_file="${CONFIG_DIR}/ftpm_pkcs11.conf"
    local conf_flags=()
    if [[ -f "${conf_file}" ]]; then
        log_info "Loading OP-TEE config: ${conf_file}"
        while IFS='=' read -r key val || [[ -n "$key" ]]; do
            [[ -z "$key" || "$key" =~ ^# ]] && continue
            key=$(echo "$key" | xargs)
            val=$(echo "$val" | xargs)
            conf_flags+=("${key}=${val}")
        done < "${conf_file}"
    fi

    local jobs
    jobs=$(nproc)

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] make -C '${optee_src:-sources/optee}' PLATFORM=vexpress-qemu_armv8a O='${OPTEE_OUT}' CROSS_COMPILE_core='${CROSS_COMPILE_64}' ${conf_flags[*]}"
        return 0
    fi

    make -C "${optee_src}" \
        PLATFORM=vexpress-qemu_armv8a \
        O="${OPTEE_OUT}" \
        CROSS_COMPILE_core="${CROSS_COMPILE_64}" \
        CROSS_COMPILE_ta_arm64="${CROSS_COMPILE_64}" \
        -j"${jobs}" \
        "${conf_flags[@]}"

    # Stage OP-TEE binaries
    if [[ -f "${OPTEE_OUT}/core/tee-header_v2.bin" ]]; then
        cp "${OPTEE_OUT}/core/tee-header_v2.bin" "${BIN_OUT}/"
        cp "${OPTEE_OUT}/core/tee-pager_v2.bin" "${BIN_OUT}/"
        cp "${OPTEE_OUT}/core/tee-pageable_v2.bin" "${BIN_OUT}/"
        log_ok "OP-TEE binaries staged in ${BIN_OUT}/"
    fi
}

build_tfa() {
    log_info "--- [Building Arm Trusted Firmware (TF-A)] ---"
    local tfa_src=""
    if tfa_src=$(find_src_dir "tfa"); then
        log_ok "TF-A source located: ${tfa_src}"
    else
        log_warn "TF-A source tree not found in ${SOURCES_DIR}."
        log_warn "Run './scripts/fetch_l4t_sources.sh --extract' first."
        if [[ "${DRY_RUN}" != "true" ]]; then
            log_err "Cannot compile TF-A without sources. Aborting."
            return 1
        fi
    fi

    local jobs
    jobs=$(nproc)

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] make -C '${tfa_src:-sources/tfa}' PLAT=qemu SPD=opteed BL32='${BIN_OUT}/tee-header_v2.bin' CROSS_COMPILE='${CROSS_COMPILE_64}' all fip"
        return 0
    fi

    make -C "${tfa_src}" \
        PLAT=qemu \
        SPD=opteed \
        BL32="${BIN_OUT}/tee-header_v2.bin" \
        BL32_EXTRA1="${BIN_OUT}/tee-pager_v2.bin" \
        BL32_EXTRA2="${BIN_OUT}/tee-pageable_v2.bin" \
        CROSS_COMPILE="${CROSS_COMPILE_64}" \
        BUILD_BASE="${TFA_OUT}" \
        DEBUG=1 \
        LOG_LEVEL=40 \
        -j"${jobs}" \
        all fip

    # Stage TF-A binaries
    local tfa_build="${TFA_OUT}/qemu/debug"
    if [[ -d "${tfa_build}" ]]; then
        cp "${tfa_build}"/bl*.bin "${BIN_OUT}/" 2>/dev/null || true
        cp "${tfa_build}"/fip.bin "${BIN_OUT}/" 2>/dev/null || true
        log_ok "TF-A binaries staged in ${BIN_OUT}/"
    fi
}

case "${MODE}" in
    all)
        build_optee
        build_tfa
        ;;
    optee)
        build_optee
        ;;
    tfa)
        build_tfa
        ;;
esac

log_ok "=================================================="
log_ok "TF-A & OP-TEE build process finished successfully!"
log_ok "Output Directory: ${BIN_OUT}"
log_ok "=================================================="

