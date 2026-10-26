#!/usr/bin/env bash
# ==============================================================================
# scripts/build_tfa_optee.sh — Arm Trusted Firmware & OP-TEE Build Pipeline
# ==============================================================================
# Description:
#   Cross-compiles OP-TEE Core (with PKCS#11 TA, RPMB, and early fTPM TA support),
#   OP-TEE Client libraries (libteec, libckteec, tee-supplicant), and
#   Arm Trusted Firmware (TF-A BL1/BL2/BL31/FIP) targeting QEMU aarch64 virt platform.
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
FTPM_OUT="${BUILD_ROOT}/ftpm"
CLIENT_OUT="${BUILD_ROOT}/optee_client"
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
  --all            Build OP-TEE OS, fTPM TA, OP-TEE Client, and TF-A (default)
  --optee-only     Build only OP-TEE OS & fTPM TA
  --client-only    Build only OP-TEE Client libraries & tee-supplicant
  --tfa-only       Build only TF-A (bl1.bin, bl2.bin, bl31.bin, fip.bin)
  --clean          Clean build directories before compiling
  --dry-run        Validate configuration and display build commands
  -h, --help       Display this help message
EOF
}

resolve_environment() {
    # Set Python Path if cached wheels exist
    if [[ -d "${REPO_ROOT}/.cache/python-packages" ]]; then
        export PYTHONPATH="${REPO_ROOT}/.cache/python-packages:${PYTHONPATH:-}"
    fi

    # Auto-resolve cross compiler if system one is missing
    local raw_cc="${CROSS_COMPILE_64#ccache }"
    if ! command -v "${raw_cc}gcc" >/dev/null 2>&1; then
        local local_toolchain="${REPO_ROOT}/.cache/toolchains/aarch64-none-linux-gnu/bin"
        if [[ -f "${local_toolchain}/aarch64-none-linux-gnu-gcc" ]]; then
            export PATH="${local_toolchain}:${PATH}"
            CROSS_COMPILE_64="aarch64-none-linux-gnu-"
            if command -v ccache >/dev/null 2>&1; then
                CROSS_COMPILE_64="ccache ${CROSS_COMPILE_64}"
            fi
            log_ok "Using resolved cross-compiler: ${local_toolchain}/aarch64-none-linux-gnu-gcc"
        fi
    fi
}

find_src_dir() {
    local target="$1"
    local candidates=()
    if [[ "${target}" == "optee" ]]; then
        candidates=(
            "${SOURCES_DIR}/optee/optee/optee_os"
            "${SOURCES_DIR}/optee/optee_os"
            "${SOURCES_DIR}/optee/optee"
            "${SOURCES_DIR}/optee"
            "${SOURCES_DIR}/Linux_for_Tegra/source/optee"
        )
    elif [[ "${target}" == "ftpm" ]]; then
        candidates=(
            "${SOURCES_DIR}/optee/optee/optee_ftpm"
            "${SOURCES_DIR}/optee/optee_ftpm"
        )
    elif [[ "${target}" == "ms-tpm" ]]; then
        candidates=(
            "${SOURCES_DIR}/optee/optee/samples/ms-tpm-20-ref"
            "${SOURCES_DIR}/optee/samples/ms-tpm-20-ref"
        )
    elif [[ "${target}" == "client" ]]; then
        candidates=(
            "${SOURCES_DIR}/optee/optee/optee_client"
            "${SOURCES_DIR}/optee/optee_client"
        )
    elif [[ "${target}" == "tfa" ]]; then
        candidates=(
            "${SOURCES_DIR}/tfa/arm-trusted-firmware.t264"
            "${SOURCES_DIR}/tfa/arm-trusted-firmware.t234"
            "${SOURCES_DIR}/tfa/arm-trusted-firmware"
            "${SOURCES_DIR}/tfa"
            "${SOURCES_DIR}/atf"
            "${SOURCES_DIR}/Linux_for_Tegra/source/atf"
        )
    fi

    for dir in "${candidates[@]}"; do
        if [[ -f "${dir}/Makefile" || -d "${dir}/TPMCmd" ]]; then
            echo "${dir}"
            return 0
        fi
    done
    return 1
}

build_ftpm_ta() {
    local dry_run="${1:-false}"
    log_info "--- [Building fTPM Trusted Application (ms-tpm-20-ref)] ---"

    local ftpm_src=""
    local ms_tpm_src=""
    local optee_src=""
    ftpm_src=$(find_src_dir "ftpm" || true)
    ms_tpm_src=$(find_src_dir "ms-tpm" || true)
    optee_src=$(find_src_dir "optee" || true)

    if [[ -z "${ftpm_src}" || -z "${ms_tpm_src}" || -z "${optee_src}" ]]; then
        log_warn "fTPM or ms-tpm-20-ref or optee_os source not located."
        if [[ "${dry_run}" != "true" ]]; then
            log_err "Cannot compile fTPM without sources. Aborting."
            return 1
        fi
    else
        log_ok "fTPM source located: ${ftpm_src}"
    fi

    local jobs
    jobs=$(nproc)
    mkdir -p "${FTPM_OUT}"

    if [[ "${dry_run}" == "true" ]]; then
        log_info "[DRY-RUN] make -C '${ftpm_src:-sources/optee_ftpm}' TA_DEV_KIT_DIR='${OPTEE_OUT}/export-ta_arm64' O='${FTPM_OUT}'"
        return 0
    fi

    make -C "${ftpm_src}" \
        CROSS_COMPILE="${CROSS_COMPILE_64}" \
        PYTHON3="python3" \
        TA_DEV_KIT_DIR="${OPTEE_OUT}/export-ta_arm64" \
        OPTEE_OS_DIR="${optee_src}" \
        CFG_TA_MEASURED_BOOT=y \
        CFG_USE_PLATFORM_EPS=y \
        CFG_MS_TPM_20_REF="${ms_tpm_src}" \
        O="${FTPM_OUT}" \
        -j"${jobs}"

    mkdir -p "${BIN_OUT}/ta"
    if [[ -f "${FTPM_OUT}/bc50d971-d4c9-42c4-82cb-343fb7f37896.ta" ]]; then
        cp "${FTPM_OUT}/bc50d971-d4c9-42c4-82cb-343fb7f37896.ta" "${BIN_OUT}/ta/"
        log_ok "fTPM TA staged in ${BIN_OUT}/ta/bc50d971-d4c9-42c4-82cb-343fb7f37896.ta"
    fi
}

build_optee_client() {
    local dry_run="${1:-false}"
    log_info "--- [Building OP-TEE Client (libteec, libckteec, tee-supplicant)] ---"

    local client_src=""
    if client_src=$(find_src_dir "client"); then
        log_ok "OP-TEE client source located: ${client_src}"
    else
        log_warn "OP-TEE client source not located."
        if [[ "${dry_run}" != "true" ]]; then
            log_err "Cannot compile optee_client without sources. Aborting."
            return 1
        fi
    fi

    local jobs
    jobs=$(nproc)
    mkdir -p "${CLIENT_OUT}"

    if [[ "${dry_run}" == "true" ]]; then
        log_info "[DRY-RUN] make -C '${client_src:-sources/optee_client}' WITH_TEEACL=0 O='${CLIENT_OUT}'"
        return 0
    fi

    make -C "${client_src}" \
        CROSS_COMPILE="${CROSS_COMPILE_64}" \
        PKG_CONFIG="pkg-config" \
        WITH_TEEACL=0 \
        O="${CLIENT_OUT}" \
        -j"${jobs}"

    mkdir -p "${BIN_OUT}/client"
    if [[ -d "${CLIENT_OUT}/export/usr" ]]; then
        cp -r "${CLIENT_OUT}/export/usr"/* "${BIN_OUT}/client/"
        log_ok "OP-TEE client binaries staged in ${BIN_OUT}/client/"
    fi
}

build_optee() {
    local dry_run="${1:-false}"
    log_info "--- [Building OP-TEE OS (PKCS#11 TA + Early fTPM TA)] ---"
    local optee_src=""
    if optee_src=$(find_src_dir "optee"); then
        log_ok "OP-TEE source located: ${optee_src}"
    else
        log_warn "OP-TEE source tree not found in ${SOURCES_DIR}."
        if [[ "${dry_run}" != "true" ]]; then
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

    if [[ "${dry_run}" == "true" ]]; then
        log_info "[DRY-RUN] Phase 1: make -C '${optee_src:-sources/optee}' PLATFORM=vexpress-qemu_armv8a O='${OPTEE_OUT}' ${conf_flags[*]}"
        build_ftpm_ta "true"
        log_info "[DRY-RUN] Phase 2: make -C '${optee_src:-sources/optee}' PLATFORM=vexpress-qemu_armv8a EARLY_TA_PATHS=... ${conf_flags[*]}"
        return 0
    fi

    # Step 1: Build OP-TEE Core, TA DevKit, and PKCS#11 TA
    make -C "${optee_src}" \
        PLATFORM=vexpress-qemu_armv8a \
        O="${OPTEE_OUT}" \
        CROSS_COMPILE_core="${CROSS_COMPILE_64}" \
        CROSS_COMPILE_ta_arm64="${CROSS_COMPILE_64}" \
        -j"${jobs}" \
        "${conf_flags[@]}"

    mkdir -p "${BIN_OUT}/ta"
    if [[ -f "${OPTEE_OUT}/ta/pkcs11/fd02c9da-306c-48c7-a49c-bbd827ae86ee.ta" ]]; then
        cp "${OPTEE_OUT}/ta/pkcs11/fd02c9da-306c-48c7-a49c-bbd827ae86ee.ta" "${BIN_OUT}/ta/"
        log_ok "PKCS#11 TA staged in ${BIN_OUT}/ta/fd02c9da-306c-48c7-a49c-bbd827ae86ee.ta"
    fi

    # Step 2: Build fTPM TA
    build_ftpm_ta "false"

    # Step 3: Embed fTPM TA as Early TA inside OP-TEE Core
    local ftpm_elf="${FTPM_OUT}/bc50d971-d4c9-42c4-82cb-343fb7f37896.stripped.elf"
    if [[ -f "${ftpm_elf}" ]]; then
        log_info "Embedding fTPM TA into OP-TEE Core (Early TA)..."
        make -C "${optee_src}" \
            PLATFORM=vexpress-qemu_armv8a \
            O="${OPTEE_OUT}" \
            CROSS_COMPILE_core="${CROSS_COMPILE_64}" \
            CROSS_COMPILE_ta_arm64="${CROSS_COMPILE_64}" \
            CFG_EARLY_TA=y \
            EARLY_TA_PATHS="${ftpm_elf}" \
            -j"${jobs}" \
            "${conf_flags[@]}"
        log_ok "OP-TEE Core re-linked with embedded Early fTPM TA."
    fi

    # Stage OP-TEE binaries
    if [[ -f "${OPTEE_OUT}/core/tee-header_v2.bin" ]]; then
        cp "${OPTEE_OUT}/core/tee-header_v2.bin" "${BIN_OUT}/"
        cp "${OPTEE_OUT}/core/tee-pager_v2.bin" "${BIN_OUT}/"
        cp "${OPTEE_OUT}/core/tee-pageable_v2.bin" "${BIN_OUT}/"
        log_ok "OP-TEE firmware binaries staged in ${BIN_OUT}/"
    fi
}

build_tfa() {
    local dry_run="${1:-false}"
    log_info "--- [Building Arm Trusted Firmware (TF-A)] ---"
    local tfa_src=""
    if tfa_src=$(find_src_dir "tfa"); then
        log_ok "TF-A source located: ${tfa_src}"
    else
        log_warn "TF-A source tree not found in ${SOURCES_DIR}."
        if [[ "${dry_run}" != "true" ]]; then
            log_err "Cannot compile TF-A without sources. Aborting."
            return 1
        fi
    fi

    local jobs
    jobs=$(nproc)

    if [[ "${dry_run}" == "true" ]]; then
        log_info "[DRY-RUN] make -C '${tfa_src:-sources/tfa}' PLAT=qemu SPD=opteed BL32='${BIN_OUT}/tee-header_v2.bin' CROSS_COMPILE='${CROSS_COMPILE_64}' all fip"
        return 0
    fi

    local dummy_bl33="${BUILD_ROOT}/dummy_bl33.bin"
    touch "${dummy_bl33}"

    make -C "${tfa_src}" \
        PLAT=qemu \
        SPD=opteed \
        BL32="${BIN_OUT}/tee-header_v2.bin" \
        BL32_EXTRA1="${BIN_OUT}/tee-pager_v2.bin" \
        BL32_EXTRA2="${BIN_OUT}/tee-pageable_v2.bin" \
        BL33="${dummy_bl33}" \
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

main() {
    local mode="all"
    local do_clean="false"
    local dry_run="false"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all)
                mode="all"
                shift
                ;;
            --optee-only)
                mode="optee"
                shift
                ;;
            --client-only)
                mode="client"
                shift
                ;;
            --tfa-only)
                mode="tfa"
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

    resolve_environment

    log_info "=================================================="
    log_info "Humanoid Security Platform — TF-A & OP-TEE Build"
    log_info "Mode:            ${mode}"
    log_info "Target Platform: QEMU ARMv8-A virt (secure=on)"
    log_info "Cross Compiler:  ${CROSS_COMPILE_64}"
    log_info "Firmware Output: ${BIN_OUT}"
    log_info "=================================================="

    if [[ "${do_clean}" == "true" ]]; then
        log_info "Cleaning firmware build directories..."
        rm -rf "${OPTEE_OUT}" "${FTPM_OUT}" "${CLIENT_OUT}" "${TFA_OUT}" "${BIN_OUT}"
    fi

    mkdir -p "${OPTEE_OUT}" "${FTPM_OUT}" "${CLIENT_OUT}" "${TFA_OUT}" "${BIN_OUT}"

    case "${mode}" in
        all)
            build_optee "${dry_run}"
            build_optee_client "${dry_run}"
            build_tfa "${dry_run}"
            ;;
        optee)
            build_optee "${dry_run}"
            ;;
        client)
            build_optee_client "${dry_run}"
            ;;
        tfa)
            build_tfa "${dry_run}"
            ;;
    esac

    log_ok "=================================================="
    log_ok "Build process completed successfully!"
    log_ok "Output Directory: ${BIN_OUT}"
    log_ok "=================================================="
}

main "$@"
