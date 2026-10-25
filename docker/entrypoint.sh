#!/usr/bin/env bash
# ==============================================================================
# docker/entrypoint.sh — DevContainer & CI Container Entrypoint
# ==============================================================================

set -euo pipefail

init_persistent_dirs() {
    mkdir -p /workspace/.cache/downloads
    mkdir -p /workspace/.cache/ccache
    mkdir -p /workspace/.cache/softhsm
    mkdir -p /workspace/sources
    mkdir -p /workspace/build
}

configure_softhsm() {
    if [[ -d "/workspace/.cache/softhsm" ]]; then
        mkdir -p /etc/softhsm
        echo "directories.tokendir = /workspace/.cache/softhsm" > /etc/softhsm/softhsm2.conf
        export SOFTHSM2_CONF=/etc/softhsm/softhsm2.conf
    fi
}

configure_ccache() {
    if command -v ccache >/dev/null 2>&1; then
        ccache -M 20G >/dev/null 2>&1 || true
    fi
}

handle_user_permissions() {
    local uid="${USER_UID:-}"
    local gid="${USER_GID:-}"

    if [[ -n "${uid}" && -n "${gid}" && "$(id -u)" == "0" ]]; then
        groupadd -g "${gid}" developer 2>/dev/null || true
        useradd -u "${uid}" -g "${gid}" -m -s /bin/bash developer 2>/dev/null || true
        echo "developer ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/developer
        chown -R "${uid}:${gid}" /workspace/.cache /workspace/build /workspace/sources 2>/dev/null || true
        exec gosu developer "$@"
    fi
}

main() {
    init_persistent_dirs
    configure_softhsm
    configure_ccache
    handle_user_permissions "$@"

    exec "$@"
}

main "$@"
