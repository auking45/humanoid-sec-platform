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
    local toolchain_libc="${REPO_ROOT}/.cache/toolchains/aarch64-none-linux-gnu/aarch64-none-linux-gnu/libc"

    log_info "Generating minimal verification initramfs..."
    rm -rf "${stage_dir}"
    mkdir -p "${stage_dir}"/{bin,sbin,dev,proc,sys,etc,mnt,root,lib,lib64}

    # Bundle OP-TEE client and supplicant if compiled
    if [[ -x "${FIRMWARE_DIR}/client/sbin/tee-supplicant" ]]; then
        log_info "Bundling tee-supplicant and client libraries into initramfs..."
        cp "${FIRMWARE_DIR}/client/sbin/tee-supplicant" "${stage_dir}/sbin/"
        cp -d "${FIRMWARE_DIR}/client/lib"/libteec* "${stage_dir}/lib/" 2>/dev/null || true
        cp -d "${FIRMWARE_DIR}/client/lib"/libckteec* "${stage_dir}/lib/" 2>/dev/null || true
        mkdir -p "${stage_dir}/lib/optee_arm64"
        if [[ -d "${FIRMWARE_DIR}/ta" ]]; then
            cp "${FIRMWARE_DIR}/ta"/*.ta "${stage_dir}/lib/optee_arm64/" 2>/dev/null || true
        fi
        if [[ -d "${toolchain_libc}" ]]; then
            cp -d "${toolchain_libc}/lib/ld-linux-aarch64.so.1" "${stage_dir}/lib/" 2>/dev/null || true
            cp -d "${toolchain_libc}/lib64/libc.so.6" "${stage_dir}/lib64/" 2>/dev/null || true
            ln -sf /lib/ld-linux-aarch64.so.1 "${stage_dir}/lib64/ld-linux-aarch64.so.1" 2>/dev/null || true
        fi
    fi

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

# Start OP-TEE Supplicant if present
if [ -x /sbin/tee-supplicant ]; then
    echo "[INFO] Launching OP-TEE Supplicant daemon (RPMB storage support)..."
    export LD_LIBRARY_PATH=/lib:/lib64
    /sbin/tee-supplicant &
    sleep 1
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

main() {
    local kernel_path="${KERNEL_DIR}/arch/arm64/boot/Image"
    local initrd_path=""
    local headless="false"
    local is_daemon="false"
    local timeout_sec=0
    local console_log="${LOG_DIR}/console.log"
    local dry_run="false"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --kernel)
                kernel_path="$2"
                shift 2
                ;;
            --initrd)
                initrd_path="$2"
                shift 2
                ;;
            --headless)
                headless="true"
                shift
                ;;
            --daemon)
                is_daemon="true"
                headless="true"
                shift
                ;;
            --timeout)
                timeout_sec="$2"
                shift 2
                ;;
            --log-console)
                console_log="$2"
                shift 2
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

    mkdir -p "${LOG_DIR}" "${RUN_DIR}"

    # Locate or generate initramfs
    if [[ -z "${initrd_path}" ]]; then
        initrd_path="${RUN_DIR}/initramfs_minimal.cpio.gz"
        if [[ ! -f "${initrd_path}" && "${dry_run}" != "true" ]]; then
            generate_minimal_initramfs "${initrd_path}"
        fi
    fi

    # Kernel Command Line
    local cmdline="console=ttyAMA0 earlycon=pl011,0x09000000 rdinit=/init init=/init"
    cmdline="${cmdline} ima_policy=tcb ima_hash=sha256"

    # Pre-flight checks (only enforced when actually executing QEMU)
    if [[ "${dry_run}" != "true" ]]; then
        # Pre-flight check 1: Verify QEMU emulator binary is in PATH
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

        # Pre-flight check 2: Validate Kernel Image presence before boot
        if [[ ! -f "${kernel_path}" ]]; then
            log_err "Kernel Image not found at '${kernel_path}'."
            echo ""
            log_info "To boot the platform, a Linux kernel Image must first be compiled or provided."
            log_info "Recommended build steps:"
            log_info "  1. Download NVIDIA L4T R39.2.1 sources (~295MB):"
            log_info "     ./scripts/fetch_l4t_sources.sh --sources-only --extract"
            log_info "  2. Compile the hardened kernel Image:"
            log_info "     ./scripts/build_kernel.sh --target qemu"
            log_info "  3. Launch QEMU:"
            log_info "     ./scripts/run_qemu.sh"
            echo ""
            log_info "Or specify an existing ARM64 kernel Image:"
            log_info "  ./scripts/run_qemu.sh --kernel /path/to/Image"
            echo ""
            exit 1
        fi
    fi

    # Assemble QEMU options
    local qemu_args=(
        "-M" "virt,secure=on,gic-version=3"
        "-cpu" "cortex-a57"
        "-smp" "${SMP_CORES}"
        "-m" "${RAM_SIZE}"
        "-kernel" "${kernel_path}"
        "-append" "${cmdline}"
        "-initrd" "${initrd_path}"
        "-netdev" "user,id=net0,hostfwd=tcp::${SSH_PORT}-:22,hostfwd=tcp::${MTLS_PORT}-:8443"
        "-device" "virtio-net-pci,netdev=net0"
        "-device" "virtio-rng-pci"
    )

    # Attach OP-TEE secure payload if built
    if [[ -f "${FIRMWARE_DIR}/tee-pager_v2.bin" ]]; then
        log_ok "Attaching OP-TEE Secure Payload: ${FIRMWARE_DIR}/tee-pager_v2.bin"
        qemu_args+=("-device" "loader,file=${FIRMWARE_DIR}/tee-pager_v2.bin,addr=0x0e100000")
    fi

    # Console and Serial Port Mapping
    if [[ "${headless}" == "true" ]]; then
        qemu_args+=("-nographic")
        qemu_args+=("-serial" "mon:stdio")
        qemu_args+=("-serial" "file:${console_log%/*}/optee.log")
    else
        qemu_args+=("-serial" "stdio")
        qemu_args+=("-serial" "file:${console_log%/*}/optee.log")
    fi

    log_info "=================================================="
    log_info "Launching QEMU ARM64 Security Verification Platform"
    log_info "Machine:        virt,secure=on,gic-version=3"
    log_info "CPUs:           ${SMP_CORES} cores (${RAM_SIZE} RAM)"
    log_info "Forward Ports:  SSH (localhost:${SSH_PORT}), mTLS (localhost:${MTLS_PORT})"
    log_info "Console Log:    ${console_log}"
    log_info "=================================================="

    if [[ "${dry_run}" == "true" ]]; then
        log_ok "[DRY-RUN] Executable command:"
        echo "${QEMU_BIN} ${qemu_args[*]}"
        exit 0
    fi

    # Execution with timeout wrapper if requested
    if [[ "${timeout_sec}" -gt 0 ]]; then
        log_info "Execution timeout set to ${timeout_sec} seconds."
        if [[ "${headless}" == "true" ]]; then
            timeout --preserve-status "${timeout_sec}" "${QEMU_BIN}" "${qemu_args[@]}" 2>&1 | tee "${console_log}" || true
        else
            timeout --preserve-status "${timeout_sec}" "${QEMU_BIN}" "${qemu_args[@]}" || true
        fi
        log_ok "QEMU execution finished."
        exit 0
    fi

    if [[ "${is_daemon}" == "true" ]]; then
        log_info "Starting QEMU daemon in background..."
        "${QEMU_BIN}" "${qemu_args[@]}" > "${console_log}" 2>&1 &
        local qemu_pid=$!
        echo "${qemu_pid}" > "${RUN_DIR}/qemu.pid"
        log_ok "QEMU running in background (PID: ${qemu_pid}). Log: ${console_log}"
        exit 0
    fi

    # Direct interactive foreground execution
    exec "${QEMU_BIN}" "${qemu_args[@]}"
}

main "$@"

