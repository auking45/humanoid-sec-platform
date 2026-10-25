#!/usr/bin/env bash
# ==============================================================================
# scripts/env_container.sh — Execute commands inside humanoid-sec-platform container
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${REPO_ROOT}/docker/docker-compose.yml"
SERVICE_NAME="humanoid-sec-platform"
CONTAINER_NAME="humanoid-sec-platform-dev"

detect_docker_compose() {
    if docker compose version >/dev/null 2>&1; then
        echo "docker compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        echo "docker-compose"
    else
        echo "[-] Error: Neither 'docker compose' nor 'docker-compose' found on host." >&2
        return 1
    fi
}

show_help() {
    cat <<EOF
Usage: $(basename "$0") [COMMAND] [ARGS...]

Execute commands inside the humanoid-sec-platform container environment.
If no command is provided, opens an interactive bash shell.

Examples:
  $(basename "$0")                      # Launch interactive bash shell
  $(basename "$0") bash                 # Launch interactive bash shell
  $(basename "$0") make help            # Run make inside container
  $(basename "$0") pytest tests/        # Run test suite inside container
  $(basename "$0") build                # Build the Docker image
  $(basename "$0") down                 # Stop container services
EOF
}

ensure_cache_dirs() {
    mkdir -p "${REPO_ROOT}/.cache/downloads"
    mkdir -p "${REPO_ROOT}/.cache/ccache"
    mkdir -p "${REPO_ROOT}/.cache/softhsm"
    mkdir -p "${REPO_ROOT}/sources"
    mkdir -p "${REPO_ROOT}/build"
}

main() {
    local docker_compose
    if ! docker_compose=$(detect_docker_compose); then
        exit 1
    fi

    if [[ $# -gt 0 ]]; then
        case "$1" in
            help|--help|-h)
                show_help
                exit 0
                ;;
            build)
                echo "[+] Building docker image for ${SERVICE_NAME}..."
                ${docker_compose} -f "${COMPOSE_FILE}" build
                exit 0
                ;;
            down)
                echo "[+] Stopping docker container services..."
                ${docker_compose} -f "${COMPOSE_FILE}" down
                exit 0
                ;;
        esac
    fi

    ensure_cache_dirs

    # Check if container is already running
    if command -v docker >/dev/null 2>&1 && docker ps --filter "name=^/${CONTAINER_NAME}$" --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "[*] Connecting to already running container '${CONTAINER_NAME}'..."
        if [[ $# -eq 0 ]]; then
            exec docker exec -it "${CONTAINER_NAME}" /bin/bash
        else
            exec docker exec -it "${CONTAINER_NAME}" "$@"
        fi
    else
        echo "[*] Running command in ephemeral container via compose..."
        if [[ $# -eq 0 ]]; then
            exec ${docker_compose} -f "${COMPOSE_FILE}" run --rm "${SERVICE_NAME}" /bin/bash
        else
            exec ${docker_compose} -f "${COMPOSE_FILE}" run --rm "${SERVICE_NAME}" "$@"
        fi
    fi
}

main "$@"
