#!/usr/bin/env bash
# ==============================================================================
# scripts/run_qemu.sh — QEMU ARM64 Secure Verification Runner
# ==============================================================================
# Description:
#   Launches QEMU 'virt' machine (secure=on, Cortex-A57/A72, GICv3, RPMB)
#   with TF-A BL31, OP-TEE OS, hardened Linux kernel Image, and minimal initramfs.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Configuration & Paths
BUILD_DIR="${BUILD_DIR:-${REPO_ROOT}/build}"
FIRMWARE_DIR="${BUILD_DIR}/firmware"
KERNEL_DIR="${BUILD_DIR}/kernel"
LOG_DIR="${REPO_ROOT}/.cache/logs"
RUN_DIR="${REPO_ROOT}/.cache/run"

QEMU_BIN="${QEMU_BIN:-qemu-system-aarch64}"
SMP_CORES="${SMP_CORES:-4}"
RAM_SIZE="${RAM_SIZE:-2048M}"
SSH_PORT="${SSH_PORT:-2222}"
MTLS_PORT="${MTLS_PORT:-8443}"

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
  --kernel <path>       Path to Linux kernel Image (default: build/kernel/arch/arm64/boot/Image)
  --initrd <path>       Path to Initramfs (default: auto-generates minimal baseline)
  --headless            Run without graphical display (-nographic)
  --daemon              Run in background and save PID to .cache/run/qemu.pid
  --timeout <sec>       Automatically kill QEMU after specified seconds
  --log-console <path>  Write serial console output to file (default: .cache/logs/console.log)
  --dry-run             Print the full QEMU invocation command line without starting
  -h, --help            Display this help message
EOF
}

# Kernel Release Display in Initramfs
KERNEL_RELEASE_LABEL="6.8-hardened"

# Generate a standalone baseline initramfs if none provided
generate_minimal_initramfs() {
    local target_cpio="$1"
    local stage_dir="${RUN_DIR}/initramfs_stage"

    log_info "Generating minimal verification initramfs..."
    rm -rf "${stage_dir}"
    mkdir -p "${stage_dir}"/{bin,sbin,dev,proc,sys,etc,mnt,root}

    # Write POSIX init script
    cat <<INIT_EOF > "${stage_dir}/init"
#!/bin/sh
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev 2>/dev/null || mdev -s 2>/dev/null || true

echo "=================================================="
echo " Humanoid Security Platform — Verification Node"
echo " Kernel Release: \$(uname -r 2>/dev/null || echo '${KERNEL_RELEASE_LABEL}')"
echo " Machine Arch:   \$(uname -m 2>/dev/null || echo 'aarch64')"
echo "=================================================="

# Check TEE devices
if [ -c /dev/tee0 ] || [ -c /dev/teepriv0 ]; then
    echo "[OK] OP-TEE device node recognized (/dev/tee0)"
else
    echo "[WARN] OP-TEE device node not detected yet"
fi

# Check TPM devices
if [ -c /dev/tpm0 ] || [ -c /dev/tpmrm0 ]; then
    echo "[OK] fTPM device node recognized (/dev/tpmrm0)"
else
    echo "[WARN] fTPM device node not detected yet"
fi

echo "[OK] Minimal verification initramfs booted successfully."
sleep 1
INIT_EOF

    chmod +x "${stage_dir}/init"
    (cd "${stage_dir}" && find . -print0 | cpio --null -ov --format=newc 2>/dev/null | gzip -9 > "${target_cpio}")
    rm -rf "${stage_dir}"
    log_ok "Initramfs generated: ${target_cpio}"
}

# CLI Argument Parsing
KERNEL_PATH="${KERNEL_DIR}/arch/arm64/boot/Image"
INITRD_PATH=""
HEADLESS="false"
IS_DAEMON="false"
TIMEOUT_SEC=0
CONSOLE_LOG="${LOG_DIR}/console.log"
DRY_RUN="false"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --kernel)
            KERNEL_PATH="$2"
            shift 2
            ;;
        --initrd)
            INITRD_PATH="$2"
            shift 2
            ;;
        --headless)
            HEADLESS="true"
            shift
            ;;
        --daemon)
            IS_DAEMON="true"
            HEADLESS="true"
            shift
            ;;
        --timeout)
            TIMEOUT_SEC="$2"
            shift 2
            ;;
        --log-console)
            CONSOLE_LOG="$2"
            shift 2
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

mkdir -p "${LOG_DIR}" "${RUN_DIR}"

# Locate or generate initramfs
if [[ -z "${INITRD_PATH}" ]]; then
    INITRD_PATH="${RUN_DIR}/initramfs_minimal.cpio.gz"
    if [[ ! -f "${INITRD_PATH}" && "${DRY_RUN}" != "true" ]]; then
        generate_minimal_initramfs "${INITRD_PATH}"
    fi
fi

# Kernel Command Line
CMDLINE="console=ttyAMA0 earlycon=pl011,0x09000000 rdinit=/init init=/init"
CMDLINE="${CMDLINE} ima_policy=tcb ima_hash=sha256"

# Assemble QEMU options
QEMU_ARGS=(
    "-M" "virt,secure=on,gic-version=3"
    "-cpu" "cortex-a57"
    "-smp" "${SMP_CORES}"
    "-m" "${RAM_SIZE}"
    "-append" "${CMDLINE}"
    "-netdev" "user,id=net0,hostfwd=tcp::${SSH_PORT}-:22,hostfwd=tcp::${MTLS_PORT}-:8443"
    "-device" "virtio-net-pci,netdev=net0"
    "-device" "virtio-rng-pci"
)

# Attach OP-TEE secure payload if built
if [[ -f "${FIRMWARE_DIR}/tee-pager_v2.bin" ]]; then
    log_ok "Attaching OP-TEE Secure Payload: ${FIRMWARE_DIR}/tee-pager_v2.bin"
    QEMU_ARGS+=("-device" "loader,file=${FIRMWARE_DIR}/tee-pager_v2.bin,addr=0x0e100000")
fi

# Attach kernel and initramfs
if [[ -f "${KERNEL_PATH}" || "${DRY_RUN}" == "true" ]]; then
    QEMU_ARGS+=("-kernel" "${KERNEL_PATH}")
else
    log_warn "Kernel Image not found at ${KERNEL_PATH}."
    log_warn "To compile, run './scripts/build_kernel.sh'."
fi

if [[ -f "${INITRD_PATH}" || "${DRY_RUN}" == "true" ]]; then
    QEMU_ARGS+=("-initrd" "${INITRD_PATH}")
fi

# Console and Serial Port Mapping
if [[ "${HEADLESS}" == "true" ]]; then
    QEMU_ARGS+=("-nographic")
    QEMU_ARGS+=("-serial" "mon:stdio")
    QEMU_ARGS+=("-serial" "file:${LOG_DIR}/optee.log")
else
    QEMU_ARGS+=("-serial" "stdio")
    QEMU_ARGS+=("-serial" "file:${LOG_DIR}/optee.log")
fi

log_info "=================================================="
log_info "Launching QEMU ARM64 Security Verification Platform"
log_info "Machine:        virt,secure=on,gic-version=3"
log_info "CPUs:           ${SMP_CORES} cores (${RAM_SIZE} RAM)"
log_info "Forward Ports:  SSH (localhost:${SSH_PORT}), mTLS (localhost:${MTLS_PORT})"
log_info "Console Log:    ${CONSOLE_LOG}"
log_info "=================================================="

if [[ "${DRY_RUN}" == "true" ]]; then
    log_ok "[DRY-RUN] Executable command:"
    echo "${QEMU_BIN} ${QEMU_ARGS[*]}"
    exit 0
fi

# Verify QEMU binary is present in PATH
if ! command -v "${QEMU_BIN}" >/dev/null 2>&1; then
    log_err "QEMU emulator '${QEMU_BIN}' was not found in PATH."
    echo ""
    log_warn "Notice: This platform follows a DevContainer / Container-First architecture."
    log_info "To run QEMU without manual host package management:"
    log_info "  1. [VS Code Dev Containers] (Recommended):"
    log_info "     Open Command Palette (F1) -> 'Dev Containers: Reopen in Container'"
    log_info "  2. [Host CLI Container Wrapper]:"
    log_info "     ./scripts/env_container.sh ./scripts/run_qemu.sh"
    log_info "  3. [Native Host Installation] (Ubuntu/Debian):"
    log_info "     sudo apt-get update && sudo apt-get install -y qemu-system-arm"
    echo ""
    exit 127
fi

# Execution with timeout wrapper if requested
if [[ "${TIMEOUT_SEC}" -gt 0 ]]; then
    log_info "Execution timeout set to ${TIMEOUT_SEC} seconds."
    if [[ "${HEADLESS}" == "true" ]]; then
        timeout --preserve-status "${TIMEOUT_SEC}" "${QEMU_BIN}" "${QEMU_ARGS[@]}" 2>&1 | tee "${CONSOLE_LOG}" || true
    else
        timeout --preserve-status "${TIMEOUT_SEC}" "${QEMU_BIN}" "${QEMU_ARGS[@]}" || true
    fi
    log_ok "QEMU execution finished."
    exit 0
fi

if [[ "${IS_DAEMON}" == "true" ]]; then
    log_info "Starting QEMU daemon in background..."
    "${QEMU_BIN}" "${QEMU_ARGS[@]}" > "${CONSOLE_LOG}" 2>&1 &
    QEMU_PID=$!
    echo "${QEMU_PID}" > "${RUN_DIR}/qemu.pid"
    log_ok "QEMU running in background (PID: ${QEMU_PID}). Log: ${CONSOLE_LOG}"
    exit 0
fi

# Direct interactive foreground execution
exec "${QEMU_BIN}" "${QEMU_ARGS[@]}"

