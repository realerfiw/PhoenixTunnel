#!/bin/sh
set -eu

OWNER="realerfiw"
REPOSITORY="PhoenixTunnel"
VERSION="${PHOENIX_VERSION:-v0.1.0-dev.69}"
INSTALL_DIR="${PHOENIX_INSTALL_DIR:-/opt/phoenix-tunnel}"
BASE_URL="https://github.com/${OWNER}/${REPOSITORY}/releases/download/${VERSION}"
INSTALLER_URL="https://raw.githubusercontent.com/${OWNER}/${REPOSITORY}/main/install.sh"

if [ "$(id -u)" -ne 0 ]; then
    echo "Phoenix installer must run as root." >&2
    echo "Run: curl -fsSL https://raw.githubusercontent.com/${OWNER}/${REPOSITORY}/main/install.sh | sudo sh" >&2
    exit 1
fi

for command_name in curl uname mktemp awk install; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "Missing required command: $command_name" >&2
        exit 1
    fi
done

case "$(uname -m)" in
    x86_64|amd64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *)
        echo "Unsupported Linux architecture: $(uname -m)" >&2
        exit 1
        ;;
esac

if command -v sha256sum >/dev/null 2>&1; then
    CHECKSUM_TOOL="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
    CHECKSUM_TOOL="shasum"
else
    echo "Missing checksum command: install sha256sum or shasum." >&2
    exit 1
fi

ASSET="phoenix-linux-${ARCH}"
TEMP_DIR="$(mktemp -d)"
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT INT TERM

echo "Downloading Phoenix Tunnel ${VERSION} (${ARCH})..."
curl --fail --location --silent --show-error \
    "${BASE_URL}/${ASSET}" --output "${TEMP_DIR}/${ASSET}"
curl --fail --location --silent --show-error \
    "${BASE_URL}/SHA256SUMS" --output "${TEMP_DIR}/SHA256SUMS"
curl --fail --location --silent --show-error \
    "$INSTALLER_URL" --output "${TEMP_DIR}/install.sh"

EXPECTED_SHA="$(awk -v asset="$ASSET" '$2 == asset { print $1; exit }' "${TEMP_DIR}/SHA256SUMS")"
if [ -z "$EXPECTED_SHA" ]; then
    echo "No checksum found for ${ASSET}." >&2
    exit 1
fi

echo "Verifying SHA-256..."
if [ "$CHECKSUM_TOOL" = "sha256sum" ]; then
    printf '%s  %s\n' "$EXPECTED_SHA" "${TEMP_DIR}/${ASSET}" | sha256sum -c -
else
    printf '%s  %s\n' "$EXPECTED_SHA" "${TEMP_DIR}/${ASSET}" | shasum -a 256 -c -
fi

mkdir -p "$INSTALL_DIR"
install -m 0755 "${TEMP_DIR}/${ASSET}" "${INSTALL_DIR}/phoenix"
install -m 0755 "${TEMP_DIR}/install.sh" "${INSTALL_DIR}/install.sh"

echo "Installed: ${INSTALL_DIR}/phoenix"
echo "Installer saved: ${INSTALL_DIR}/install.sh"
"${INSTALL_DIR}/phoenix" version
echo "Existing Phoenix services are not started or restarted by this installer."
