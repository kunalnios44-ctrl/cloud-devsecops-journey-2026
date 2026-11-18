#!/usr/bin/env bash
set -euo pipefail

# 1. Ensure target directory exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "${SCRIPT_DIR}"

# 2. Check all core required utilities
for cmd in curl tr dirname mkdir rm mv mktemp grep awk head; do
    if ! command -v "${cmd}" &> /dev/null; then
        echo "[ERROR] Required system utility '${cmd}' is missing."
        exit 1
    fi
done

# 3. Enforce pinned version of Syft with strict binary & supply-chain security
DESIRED_VERSION="1.18.1"
TAGGED_VERSION="v${DESIRED_VERSION}"
INSTALL_DIR="/usr/local/bin"
SYFT_BIN=""
NEEDS_INSTALL=false

if command -v syft &> /dev/null; then
    SYFT_BIN="$(command -v syft)"
    CURRENT_RAW=$("${SYFT_BIN}" version 2>/dev/null || echo "unknown")
    CURRENT_VERSION=$(echo "${CURRENT_RAW}" | grep -oiE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || echo "unknown")
    
    if [ "${CURRENT_VERSION}" != "${DESIRED_VERSION}" ]; then
        echo "[INFO] Installed Syft version (${CURRENT_VERSION}) does not match required (${DESIRED_VERSION}). Upgrading..."
        NEEDS_INSTALL=true
    fi
else
    NEEDS_INSTALL=true
fi

# Track temporary files for automatic cleanup
TEMP_INSTALLER=""
TEMP_FILE=""
cleanup() {
    [ -n "${TEMP_INSTALLER}" ] && rm -f "${TEMP_INSTALLER}"
    [ -n "${TEMP_FILE}" ] && rm -f "${TEMP_FILE}"
}
trap cleanup EXIT

if [ "${NEEDS_INSTALL}" = true ]; then
    if [ ! -w "${INSTALL_DIR}" ]; then
        if [ -n "${CI:-}" ] || [ ! -t 0 ] || ! command -v sudo &> /dev/null; then
            INSTALL_DIR="${HOME}/.local/bin"
            mkdir -p "${INSTALL_DIR}"
        fi
    fi

    echo "[INFO] Downloading pinned Syft installer (${TAGGED_VERSION})..."
    INSTALLER_URL="https://raw.githubusercontent.com/anchore/syft/${TAGGED_VERSION}/install.sh"
    TEMP_INSTALLER=$(mktemp "${SCRIPT_DIR}/.syft-install.XXXXXX.sh")

    # Download installer to disk first instead of piping directly to shell
    if ! curl -fsSL "${INSTALLER_URL}" -o "${TEMP_INSTALLER}"; then
        echo "[ERROR] Failed to download Syft installer from ${INSTALLER_URL}"
        exit 1
    fi

    # Verify downloaded installer is non-empty and a valid shell script
    if [ ! -s "${TEMP_INSTALLER}" ] || ! head -n 1 "${TEMP_INSTALLER}" | grep -q "^#!/bin/sh"; then
        echo "[ERROR] Downloaded installer failed basic integrity check."
        exit 1
    fi

    # Enable cryptographic signature verification automatically if cosign is present
    VERIFY_FLAG=""
    if command -v cosign &> /dev/null; then
        echo "[INFO] Cosign detected. Enabling cryptographic signature verification..."
        VERIFY_FLAG="-v"
    fi

    if [ "${INSTALL_DIR}" = "/usr/local/bin" ] && command -v sudo &> /dev/null; then
        sudo sh "${TEMP_INSTALLER}" ${VERIFY_FLAG} -b "${INSTALL_DIR}" "${TAGGED_VERSION}"
    else
        sh "${TEMP_INSTALLER}" ${VERIFY_FLAG} -b "${INSTALL_DIR}" "${TAGGED_VERSION}"
    fi

    # Strictly verify the newly installed binary without falling back to old PATH binaries
    SYFT_BIN="${INSTALL_DIR}/syft"
    if [ ! -x "${SYFT_BIN}" ]; then
        echo "[ERROR] Syft executable missing at ${SYFT_BIN}."
        exit 1
    fi

    VERIFIED_RAW=$("${SYFT_BIN}" version 2>/dev/null || echo "unknown")
    if ! echo "${VERIFIED_RAW}" | grep -q "${DESIRED_VERSION}"; then
        echo "[ERROR] Syft version verification failed at ${SYFT_BIN}. Expected ${DESIRED_VERSION}."
        exit 1
    fi
fi

IMAGE_TARGET="${1:-alpine:3.20}"
SANITIZED_NAME=$(echo "${IMAGE_TARGET}" | tr '/:' '__')
OUTPUT_FILE="${SCRIPT_DIR}/sbom-report-${SANITIZED_NAME}.spdx.json"

# 4. Secure temporary file creation using mktemp
TEMP_FILE=$(mktemp "${SCRIPT_DIR}/.sbom.XXXXXX")

echo "[INFO] Generating SPDX JSON SBOM for target: ${IMAGE_TARGET} using ${SYFT_BIN}"

# 5. Execute exact verified Syft binary and validate JSON output
if "${SYFT_BIN}" "${IMAGE_TARGET}" -o spdx-json > "${TEMP_FILE}"; then
    if command -v python3 &> /dev/null; then
        python3 -m json.tool "${TEMP_FILE}" > /dev/null
        VALIDATION_STATUS="[Validated via Python3 JSON Lint]"
    else
        VALIDATION_STATUS="[Generated (Python lint skipped)]"
    fi
    mv "${TEMP_FILE}" "${OUTPUT_FILE}"
    echo "[SUCCESS] SBOM generated at: ${OUTPUT_FILE} ${VALIDATION_STATUS}"
else
    echo "[ERROR] SBOM generation failed for target: ${IMAGE_TARGET}. Verify target source or network connectivity."
    exit 1
fi
