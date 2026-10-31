#!/usr/bin/env bash
# ==============================================================================
# scripts/run_attack_demo.sh — Red/Blue Team Attack Simulation & Defense Runner
# ==============================================================================
# Description:
#   Executes end-to-end attack simulations (ATK-01 through ATK-05) comparing a
#   Vulnerable Baseline (security feature disabled/absent -> COMPROMISED)
#   against the Hardened Humanoid Security Platform (-> BLOCKED / DETECTED).
#
# Scenarios:
#   - ATK-01: Malicious Kernel Injection & Rogue Key Signing Bypass (Secure Boot)
#   - ATK-02: Unsigned / Tampered Rootkit Kernel Module (.ko) Injection (KSPP)
#   - ATK-03: Offline Rootfs Sector Tampering & Root Hash Forgery (dm-verity)
#   - ATK-04: Stealth Malware Execution & Quote Replay (IMA + fTPM PCR 10)
#   - ATK-05: Filesystem Key Exfiltration & Rogue Client mTLS Intrusion (PKCS#11)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ANSI Colors
readonly C_RESET="\033[0m"
readonly C_BOLD="\033[1m"
readonly C_GREEN="\033[32m"
readonly C_YELLOW="\033[33m"
readonly C_RED="\033[31m"
readonly C_CYAN="\033[36m"

log_info()  { echo -e "${C_CYAN}[INFO]${C_RESET}  $*"; }
log_ok()    { echo -e "${C_GREEN}[DEFENDED]${C_RESET} $*"; }
log_vuln()  { echo -e "${C_RED}[VULN-SIM]${C_RESET} $*"; }
log_err()   { echo -e "${C_RED}[ERR]${C_RESET}   $*"; }

show_help() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --dry-run   Print planned attack simulation scenarios without executing
  -h, --help  Show this help message
EOF
}

run_scenario() {
    local atk_id="$1"
    local title="$2"
    local vuln_desc="$3"
    local hard_desc="$4"
    local test_method="$5"

    echo -e "\n${C_BOLD}----------------------------------------------------------------------${C_RESET}"
    echo -e "${C_BOLD}[${atk_id}] ${title}${C_RESET}"
    echo -e "${C_BOLD}----------------------------------------------------------------------${C_RESET}"
    log_vuln "Without Control: ${vuln_desc} -> ${C_RED}COMPROMISED${C_RESET}"
    log_info "Executing live attack against Hardened Platform (${test_method})..."

    if python3 -m unittest "tests.test_attack_scenarios.TestRedBlueAttackScenarios.${test_method}" >/dev/null 2>&1; then
        log_ok "With Control:    ${hard_desc} -> ${C_GREEN}BLOCKED & DETECTED${C_RESET}"
    else
        log_err "Hardened defense check failed for ${atk_id}!"
        python3 -m unittest "tests.test_attack_scenarios.TestRedBlueAttackScenarios.${test_method}" -v
        exit 1
    fi
}

main() {
    local dry_run="false"

    while [[ $# -gt 0 ]]; do
        case "$1" in
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

    cd "${REPO_ROOT}"

    echo -e "${C_BOLD}======================================================================${C_RESET}"
    echo -e "${C_BOLD}  Humanoid Security Platform — Red/Blue Team Attack Simulation Suite${C_RESET}"
    echo -e "${C_BOLD}  Target: NVIDIA JetPack 7.2.1 (L4T R39.2.1 / Ubuntu 24.04 / OP-TEE)${C_RESET}"
    echo -e "${C_BOLD}======================================================================${C_RESET}"

    if [[ "${dry_run}" == "true" ]]; then
        log_info "[DRY-RUN] Planned Red/Blue Team Scenarios: ATK-01, ATK-02, ATK-03, ATK-04, ATK-05"
        exit 0
    fi

    run_scenario \
        "ATK-01" \
        "Malicious Kernel Injection & Rogue Signing Key Bypass (Secure Boot)" \
        "Unverified boot loads modified kernel or rogue-signed image" \
        "Tegra PKC RSA-3072 + SoC eFuse hash check rejects payload & rogue key" \
        "test_atk01_secureboot_rogue_key_and_kernel_tamper"

    run_scenario \
        "ATK-02" \
        "Unsigned / Tampered Rootkit Kernel Module (.ko) Load (Kernel Hardening)" \
        "Unsigned or hooked .ko module loads into ring-0 kernel space" \
        "CONFIG_MODULE_SIG_FORCE=y + KernelModuleSigningKey rejects tampered .ko" \
        "test_atk02_unsigned_and_tampered_kernel_module"

    run_scenario \
        "ATK-03" \
        "Offline Rootfs Binary Tampering & Root Hash Forgery (Storage Integrity)" \
        "1-byte binary backdoor on standard rw filesystem persists across boots" \
        "dm-verity Merkle tree + SoftHSM DmVeritySigningKey rejects corruption" \
        "test_atk03_dm_verity_offline_corruption_and_ro_enforcement"

    run_scenario \
        "ATK-04" \
        "Stealth Malware Execution & Attestation Quote Replay (Runtime Integrity)" \
        "Static telemetry hides malware execution and accepts replayed quotes" \
        "fTPM PCR 10 IMA hash-chain replay & single-use Nonce block forgery" \
        "test_atk04_runtime_ima_tamper_and_attestation_replay"

    run_scenario \
        "ATK-05" \
        "Filesystem Key Exfiltration & Rogue Certificate mTLS Intrusion (HSM/mTLS)" \
        "Plaintext .key files stolen from disk; rogue client connects to server" \
        "Zero-Plaintext PKCS#11 HSM + TLS 1.3 Mutual Auth rejects rogue cert" \
        "test_atk05_key_exfiltration_and_rogue_mtls_client"

    echo -e "\n${C_BOLD}======================================================================${C_RESET}"
    echo -e "${C_BOLD}  Red/Blue Team Comparative Summary Matrix (5 / 5 Attacks Blocked)${C_RESET}"
    echo -e "${C_BOLD}======================================================================${C_RESET}"
    printf "  %-8s | %-28s | %-13s | %-13s\n" "ID" "Security Layer" "Without Ctrl" "Hardened"
    echo "  ---------+------------------------------+---------------+--------------"
    printf "  %-8s | %-28s | ${C_RED}%-13s${C_RESET} | ${C_GREEN}%-13s${C_RESET}\n" "ATK-01" "Tegra PKC Secure Boot" "COMPROMISED" "BLOCKED"
    printf "  %-8s | %-28s | ${C_RED}%-13s${C_RESET} | ${C_GREEN}%-13s${C_RESET}\n" "ATK-02" "Kernel Module Signing (.ko)" "COMPROMISED" "BLOCKED"
    printf "  %-8s | %-28s | ${C_RED}%-13s${C_RESET} | ${C_GREEN}%-13s${C_RESET}\n" "ATK-03" "EROFS + dm-verity + Overlay" "COMPROMISED" "BLOCKED"
    printf "  %-8s | %-28s | ${C_RED}%-13s${C_RESET} | ${C_GREEN}%-13s${C_RESET}\n" "ATK-04" "IMA PCR 10 & Attestation" "COMPROMISED" "BLOCKED"
    printf "  %-8s | %-28s | ${C_RED}%-13s${C_RESET} | ${C_GREEN}%-13s${C_RESET}\n" "ATK-05" "PKCS#11 HSM & TLS 1.3 mTLS" "COMPROMISED" "BLOCKED"
    echo -e "${C_BOLD}======================================================================${C_RESET}"
}

main "$@"

