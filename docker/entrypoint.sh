#!/usr/bin/env bash
set -e

# Initialize required persistent directories
mkdir -p /workspace/.cache/downloads
mkdir -p /workspace/.cache/ccache
mkdir -p /workspace/.cache/softhsm
mkdir -p /workspace/sources
mkdir -p /workspace/build

# Ensure SoftHSM2 points to persistent cache if mounted
if [ -d "/workspace/.cache/softhsm" ]; then
    mkdir -p /etc/softhsm
    echo "directories.tokendir = /workspace/.cache/softhsm" > /etc/softhsm/softhsm2.conf
    export SOFTHSM2_CONF=/etc/softhsm/softhsm2.conf
fi

# Configure ccache size limit
if command -v ccache >/dev/null 2>&1; then
    ccache -M 20G >/dev/null 2>&1 || true
fi

# If running as root but USER_UID and USER_GID are passed, optionally adjust
if [ -n "${USER_UID}" ] && [ -n "${USER_GID}" ] && [ "$(id -u)" = "0" ]; then
    groupadd -g "${USER_GID}" developer 2>/dev/null || true
    useradd -u "${USER_UID}" -g "${USER_GID}" -m -s /bin/bash developer 2>/dev/null || true
    echo "developer ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/developer
    chown -R "${USER_UID}:${USER_GID}" /workspace/.cache /workspace/build /workspace/sources 2>/dev/null || true
    exec gosu developer "$@"
fi

exec "$@"
