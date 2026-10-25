#!/usr/bin/env bash
# ==============================================================================
# scripts/fetch_l4t_sources.sh — NVIDIA JetPack (L4T) Official Source & BSP Fetcher
# ==============================================================================
# Description:
#   Downloads NVIDIA Jetson Linux (L4T) official public sources, BSP driver
#   package, and sample rootfs with persistent volume caching and auto-extraction.
#
# Default Target: JetPack 6.0 (L4T R36.3.0, Linux Kernel 5.15, OP-TEE 3.22)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Configurable versions & directories
L4T_VERSION="${L4T_VERSION:-36.3.0}"
L4T_RELEASE_TAG="${L4T_RELEASE_TAG:-r36_release_v3.0}"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-${REPO_ROOT}/.cache/downloads}"
SOURCES_DIR="${SOURCES_DIR:-${REPO_ROOT}/sources}"

# Upstream NVIDIA download URLs
NVIDIA_BASE_URL="https://developer.nvidia.com/downloads/embedded/l4t/${L4T_RELEASE_TAG}"
PUBLIC_SOURCES_URL="${NVIDIA_BASE_URL}/sources/public_sources.tbz2"
BSP_URL="${NVIDIA_BASE_URL}/release/Jetson_Linux_R${L4T_VERSION}_aarch64.tbz2"
ROOTFS_URL="${NVIDIA_BASE_URL}/release/Tegra_Linux_Sample-Root-Filesystem_R${L4T_VERSION}_aarch64.tbz2"

# Color helpers
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
  --all            Download Public Sources, BSP, and Sample Rootfs (default)
  --sources-only   Download only public_sources.tbz2 (Kernel, OP-TEE, TF-A)
  --bsp-only       Download only Jetson_Linux BSP driver package
  --rootfs-only    Download only Tegra Linux Sample Rootfs
  --extract        Extract downloaded tarballs into sources/ directory
  --dry-run        Print download URLs and destination paths without fetching
  -h, --help       Display this help message

Environment Variables:
  L4T_VERSION       L4T release version (default: "36.3.0")
  L4T_RELEASE_TAG   NVIDIA release URL tag (default: "r36_release_v3.0")
  DOWNLOAD_DIR      Directory to store tarballs (default: .cache/downloads)
  SOURCES_DIR       Directory to unpack source tree (default: sources)
EOF
}

# Download helper with resume and atomic write
download_tarball() {
    local url="$1"
    local dest_name="$2"
    local dest_path="${DOWNLOAD_DIR}/${dest_name}"
    local part_path="${dest_path}.part"

    if [[ -f "${dest_path}" && -s "${dest_path}" ]]; then
        local size
        size=$(stat -c%s "${dest_path}" 2>/dev/null || stat -f%z "${dest_path}" 2>/dev/null || echo "0")
        log_ok "Already cached: ${dest_name} ($(( size / 1024 / 1024 )) MB). Skipping download."
        return 0
    fi

    log_info "Fetching ${dest_name}..."
    log_info "Source: ${url}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] curl -fL -C - --retry 5 --retry-delay 3 -o '${dest_path}' '${url}'"
        return 0
    fi

    mkdir -p "${DOWNLOAD_DIR}"
    if curl -fL -C - --retry 5 --retry-delay 3 --progress-bar -o "${part_path}" "${url}"; then
        mv "${part_path}" "${dest_path}"
        local size
        size=$(stat -c%s "${dest_path}" 2>/dev/null || stat -f%z "${dest_path}" 2>/dev/null || echo "0")
        log_ok "Download complete: ${dest_name} ($(( size / 1024 / 1024 )) MB)"
    else
        log_err "Failed to download ${dest_name} from ${url}"
        rm -f "${part_path}"
        return 1
    fi
}

# Extract sources into modular hierarchy
extract_sources() {
    local public_sources="${DOWNLOAD_DIR}/public_sources.tbz2"

    if [[ ! -f "${public_sources}" ]]; then
        log_err "Cannot extract: ${public_sources} does not exist. Run with download first."
        return 1
    fi

    log_info "Extracting L4T public sources into ${SOURCES_DIR}..."
    mkdir -p "${SOURCES_DIR}"

    local marker_file="${SOURCES_DIR}/.l4t_${L4T_VERSION}_extracted"
    if [[ -f "${marker_file}" ]]; then
        log_ok "Sources already extracted (${marker_file} exists). Skipping."
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] tar -xjf '${public_sources}' -C '${SOURCES_DIR}'"
        return 0
    fi

    # Unpack outer archive
    log_info "Unpacking outer public_sources.tbz2..."
    tar -xjf "${public_sources}" -C "${SOURCES_DIR}"

    local tegra_src="${SOURCES_DIR}/Linux_for_Tegra/source"

    # Unpack Kernel tree
    if [[ -f "${tegra_src}/kernel_src.tbz2" ]]; then
        log_info "Unpacking kernel_src.tbz2 into ${SOURCES_DIR}/kernel..."
        mkdir -p "${SOURCES_DIR}/kernel"
        tar -xjf "${tegra_src}/kernel_src.tbz2" -C "${SOURCES_DIR}/kernel"
    fi

    # Unpack OP-TEE tree
    if [[ -f "${tegra_src}/nvidia-jetson-optee-source.tbz2" ]]; then
        log_info "Unpacking nvidia-jetson-optee-source.tbz2 into ${SOURCES_DIR}/optee..."
        mkdir -p "${SOURCES_DIR}/optee"
        tar -xjf "${tegra_src}/nvidia-jetson-optee-source.tbz2" -C "${SOURCES_DIR}/optee"
    fi

    # Unpack TF-A (ATF) tree
    if [[ -f "${tegra_src}/atf_src.tbz2" ]]; then
        log_info "Unpacking atf_src.tbz2 into ${SOURCES_DIR}/tfa..."
        mkdir -p "${SOURCES_DIR}/tfa"
        tar -xjf "${tegra_src}/atf_src.tbz2" -C "${SOURCES_DIR}/tfa"
    fi

    touch "${marker_file}"
    log_ok "All L4T sources unpacked successfully."
}

# Parse command line arguments
MODE="all"
DO_EXTRACT="false"
DRY_RUN="false"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)
            MODE="all"
            shift
            ;;
        --sources-only)
            MODE="sources"
            shift
            ;;
        --bsp-only)
            MODE="bsp"
            shift
            ;;
        --rootfs-only)
            MODE="rootfs"
            shift
            ;;
        --extract)
            DO_EXTRACT="true"
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
log_info "NVIDIA L4T Source Fetcher (JetPack 6 / L4T R${L4T_VERSION})"
log_info "Download Cache: ${DOWNLOAD_DIR}"
log_info "Source Tree:    ${SOURCES_DIR}"
log_info "=================================================="

case "${MODE}" in
    all)
        download_tarball "${PUBLIC_SOURCES_URL}" "public_sources.tbz2"
        download_tarball "${BSP_URL}" "Jetson_Linux_R${L4T_VERSION}_aarch64.tbz2"
        download_tarball "${ROOTFS_URL}" "Tegra_Linux_Sample-Root-Filesystem_R${L4T_VERSION}_aarch64.tbz2"
        ;;
    sources)
        download_tarball "${PUBLIC_SOURCES_URL}" "public_sources.tbz2"
        ;;
    bsp)
        download_tarball "${BSP_URL}" "Jetson_Linux_R${L4T_VERSION}_aarch64.tbz2"
        ;;
    rootfs)
        download_tarball "${ROOTFS_URL}" "Tegra_Linux_Sample-Root-Filesystem_R${L4T_VERSION}_aarch64.tbz2"
        ;;
esac

if [[ "${DO_EXTRACT}" == "true" ]]; then
    extract_sources
fi

log_ok "Source fetch process completed successfully."
