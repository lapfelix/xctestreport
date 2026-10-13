#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 1 || ${1:-} == --help || ${1:-} == -h ]]; then
  echo "Usage: $0 [install-prefix]"
  echo "Default prefix: \$HOME/.local. Set XCTESTREPORT_BUILD_PATH to use a custom build directory."
  [[ $# -le 1 ]] && exit 0
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_PREFIX="${1:-$HOME/.local}"
BUILD_PATH="${XCTESTREPORT_BUILD_PATH:-$REPO_ROOT/.build}"
SWIFT_OPTIONS=(--package-path "$REPO_ROOT" --scratch-path "$BUILD_PATH" -c release)

swift build "${SWIFT_OPTIONS[@]}"
BIN_PATH="$(swift build "${SWIFT_OPTIONS[@]}" --show-bin-path)"
shopt -s nullglob
RESOURCE_BUNDLES=("$BIN_PATH"/*.bundle)
if [[ ${#RESOURCE_BUNDLES[@]} -eq 0 ]]; then
  echo "No SwiftPM resource bundles found beside $BIN_PATH/xctestreport." >&2
  exit 1
fi

mkdir -p "$INSTALL_PREFIX/bin"
for RESOURCE_BUNDLE in "${RESOURCE_BUNDLES[@]}"; do
  BUNDLE_NAME="$(basename "$RESOURCE_BUNDLE")"
  rm -rf "$INSTALL_PREFIX/bin/$BUNDLE_NAME"
  cp -R "$RESOURCE_BUNDLE" "$INSTALL_PREFIX/bin/$BUNDLE_NAME"
done
install -m 755 "$BIN_PATH/xctestreport" "$INSTALL_PREFIX/bin/xctestreport"
echo "Installed xctestreport and its resources in $INSTALL_PREFIX/bin."
