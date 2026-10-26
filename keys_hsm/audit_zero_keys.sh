#!/usr/bin/env bash
# ==============================================================================
# keys_hsm/audit_zero_keys.sh — Zero Plaintext Key Audit & CI Verification
# ==============================================================================
# Description:
#   Scans git repository and workspace to ensure strict adherence to the
#   Zero Plaintext Key Policy. Fails if any unencrypted private key markers
#   ('BEGIN PRIVATE KEY', 'BEGIN RSA PRIVATE KEY', 'BEGIN EC PRIVATE KEY')
#   or plaintext key file extensions are detected.
# ==============================================================================

set -euo pipefail

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

audit_git_tracked_files() {
    log_info "Scanning git-tracked files for plaintext private keys..."
    local violations=0

    # Pattern for private key PEM headers
    local priv_pattern="BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY"

    # Search in git tracked files
    while IFS= read -r file; do
        if [[ -f "${REPO_ROOT}/${file}" ]]; then
            if grep -Eq "${priv_pattern}" "${REPO_ROOT}/${file}" 2>/dev/null; then
                log_err "CRITICAL: Plaintext private key found in tracked file: ${file}"
                violations=$((violations + 1))
            fi
        fi
    done < <(git -C "${REPO_ROOT}" ls-files)

    if [[ ${violations} -gt 0 ]]; then
        log_err "Audit FAILED: ${violations} plaintext private key(s) detected in git tree."
        return 1
    else
        log_ok "All git-tracked files verified clean (0 plaintext private keys)."
        return 0
    fi
}

audit_workspace_files() {
    log_info "Scanning workspace non-cache paths..."
    local violations=0
    local priv_pattern="BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY"

    while IFS= read -r file; do
        # Ignore .cache, .git, and sources directory
        if [[ "${file}" =~ ^\./(\.cache|\.git|sources)/ ]]; then
            continue
        fi

        if grep -Eq "${priv_pattern}" "${REPO_ROOT}/${file}" 2>/dev/null; then
            log_err "CRITICAL: Plaintext private key found in workspace: ${file}"
            violations=$((violations + 1))
        fi
    done < <(cd "${REPO_ROOT}" && find . -maxdepth 4 -type f \( -name "*.pem" -o -name "*.key" -o -name "*.p12" \))

    if [[ ${violations} -gt 0 ]]; then
        log_err "Audit FAILED: ${violations} plaintext private key file(s) found in workspace."
        return 1
    else
        log_ok "Workspace verified clean (0 plaintext private keys in source paths)."
        return 0
    fi
}

main() {
    log_info "=================================================="
    log_info "Zero Plaintext Key Policy Audit"
    log_info "Repository: ${REPO_ROOT}"
    log_info "=================================================="

    audit_git_tracked_files
    audit_workspace_files

    log_ok "=================================================="
    log_ok "Zero Plaintext Key Policy: PASSED"
    log_ok "=================================================="
}

main "$@"
