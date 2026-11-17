#!/usr/bin/env bash
set -euo pipefail

# 1. Ensure target directory exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE}")" && pwd)"
mkdir -p "${SCRIPT_DIR}"

# 2. Check all core required utilities including head and uname
for cmd in curl tr dirname mkdir rm mv mktemp grep awk head uname; do
    if ! command -v "${cmd}" &> /dev/null; then
        echo "[ERROR] Required system utility '${cmd}' is missing."
        exit 1
    fi
done

# 3. Enforce pinned version of Cosign with OS/Arch detection & SHA-256 verification
DESIRED_VERSION="2.4.1"
TAGGED_VERSION="v${DESIRED_VERSION}"
INSTALL_DIR="/usr/local/bin"
COSIGN_BIN=""
NEEDS_INSTALL=false

if command -v cosign &> /dev/null; then
    COSIGN_BIN="$(command -v cosign)"
    CURRENT_RAW=$("${COSIGN_BIN}" version 2>/dev/null || echo "unknown")
    CURRENT_VERSION=$(echo "${CURRENT_RAW}" | grep -oiE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || echo "unknown")
    
    if [ "${CURRENT_VERSION}" != "${DESIRED_VERSION}" ]; then
        echo "[INFO] Installed Cosign version (${CURRENT_VERSION}) does not match required (${DESIRED_VERSION}). Upgrading..."
        NEEDS_INSTALL=true
    fi
else
    NEEDS_INSTALL=true
fi

TEMP_DIR=""
cleanup() {
    [ -n "${TEMP_DIR}" ] && rm -rf "${TEMP_DIR}"
}
trap cleanup EXIT

if [ "${NEEDS_INSTALL}" = true ]; then
    if [ ! -w "${INSTALL_DIR}" ]; then
        if [ -n "${CI:-}" ] || [ ! -t 0 ] || ! command -v sudo &> /dev/null; then
            INSTALL_DIR="${HOME}/.local/bin"
            mkdir -p "${INSTALL_DIR}"
        fi
    fi

    # Detect OS and Architecture dynamically
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    case "${ARCH}" in
        x86_64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        *) echo "[ERROR] Unsupported architecture: ${ARCH}"; exit 1 ;;
    esac

    BINARY_NAME="cosign-${OS}-${ARCH}"
    BASE_URL="https://github.com/sigstore/cosign/releases/download/${TAGGED_VERSION}"
    TEMP_DIR=$(mktemp -d "${SCRIPT_DIR}/.cosign-tmp.XXXXXX")

    echo "[INFO] Downloading Cosign ${TAGGED_VERSION} (${OS}/${ARCH}) and checksums..."
    curl -fsSL "${BASE_URL}/${BINARY_NAME}" -o "${TEMP_DIR}/${BINARY_NAME}"
    curl -fsSL "${BASE_URL}/cosign_checksums.txt" -o "${TEMP_DIR}/cosign_checksums.txt"

    # Verify SHA-256 checksum
    EXPECTED_HASH=$(grep " ${BINARY_NAME}\$" "${TEMP_DIR}/cosign_checksums.txt" | awk '{print $1}')
    if [ -z "${EXPECTED_HASH}" ]; then
        echo "[ERROR] Could not find checksum for ${BINARY_NAME}."
        exit 1
    fi

    if command -v sha256sum &> /dev/null; then
        ACTUAL_HASH=$(sha256sum "${TEMP_DIR}/${BINARY_NAME}" | awk '{print $1}')
    elif command -v shasum &> /dev/null; then
        ACTUAL_HASH=$(shasum -a 256 "${TEMP_DIR}/${BINARY_NAME}" | awk '{print $1}')
    else
        echo "[ERROR] Neither sha256sum nor shasum is available for verification."
        exit 1
    fi

    if [ "${EXPECTED_HASH}" != "${ACTUAL_HASH}" ]; then
        echo "[ERROR] SHA-256 checksum mismatch for ${BINARY_NAME}!"
        exit 1
    fi
    echo "[INFO] SHA-256 checksum verified successfully."

    chmod +x "${TEMP_DIR}/${BINARY_NAME}"
    if [ "${INSTALL_DIR}" = "/usr/local/bin" ] && command -v sudo &> /dev/null; then
        sudo mv "${TEMP_DIR}/${BINARY_NAME}" "${INSTALL_DIR}/cosign"
    else
        mv "${TEMP_DIR}/${BINARY_NAME}" "${INSTALL_DIR}/cosign"
    fi

    COSIGN_BIN="${INSTALL_DIR}/cosign"
    if [ ! -x "${COSIGN_BIN}" ]; then
        echo "[ERROR] Cosign executable missing at ${COSIGN_BIN}."
        exit 1
    fi
fi

IMAGE_REF="${1:-ghcr.io/kunalnios44-ctrl/devsecops-app:latest}"

echo "[INFO] Verifying Cosign binary and cryptographic readiness for image: ${IMAGE_REF}"

if "${COSIGN_BIN}" version; then
    echo "[SUCCESS] Verified Cosign (${COSIGN_BIN}) is ready for keyless OIDC supply-chain signing."
else
    echo "[ERROR] Cosign verification failed."
    exit 1
fi
