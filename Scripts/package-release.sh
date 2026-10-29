#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <version> <output-dir>" >&2
  echo "Set XCTESTREPORT_CODESIGN_IDENTITY to sign the executable with a Developer ID." >&2
  exit 1
fi

VERSION="$1"
OUTPUT_DIR="$2"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_PATH="${XCTESTREPORT_BUILD_PATH:-$REPO_ROOT/.build/release-universal}"
SWIFT_OPTIONS=(--package-path "$REPO_ROOT" --scratch-path "$BUILD_PATH" -c release --arch arm64 --arch x86_64)
ARCHIVE_NAME="xctestreport-macos-universal.tar.gz"

swift build "${SWIFT_OPTIONS[@]}"
BIN_PATH="$(swift build "${SWIFT_OPTIONS[@]}" --show-bin-path)"

STAGING="$(mktemp -d "${TMPDIR:-/tmp}/xctestreport-package.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
PACKAGE_DIR="$STAGING/xctestreport"
mkdir -p "$PACKAGE_DIR"

install -m 755 "$BIN_PATH/xctestreport" "$PACKAGE_DIR/xctestreport"
shopt -s nullglob
RESOURCE_BUNDLES=("$BIN_PATH"/*.bundle)
if [[ ${#RESOURCE_BUNDLES[@]} -eq 0 ]]; then
  echo "No SwiftPM resource bundles found beside $BIN_PATH/xctestreport." >&2
  exit 1
fi
for RESOURCE_BUNDLE in "${RESOURCE_BUNDLES[@]}"; do
  cp -R "$RESOURCE_BUNDLE" "$PACKAGE_DIR/"
done
cp "$REPO_ROOT/COPYING" "$REPO_ROOT/README.md" "$PACKAGE_DIR/"
printf '%s\n' "$VERSION" > "$PACKAGE_DIR/VERSION"

if [[ -n "${XCTESTREPORT_CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --options runtime \
    --sign "$XCTESTREPORT_CODESIGN_IDENTITY" "$PACKAGE_DIR/xctestreport"
  codesign --verify --strict --verbose=2 "$PACKAGE_DIR/xctestreport"
fi

REPORTED_VERSION="$("$PACKAGE_DIR/xctestreport" --version)"
if [[ "$REPORTED_VERSION" != "$VERSION" ]]; then
  echo "Packaged executable reports version '$REPORTED_VERSION', expected '$VERSION'." >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
# Fixed owner and ordering keep the archive independent of the build machine's account.
COPYFILE_DISABLE=1 tar -C "$STAGING" --uid 0 --gid 0 --uname root --gname wheel \
  -czf "$OUTPUT_DIR/$ARCHIVE_NAME" xctestreport
echo "$OUTPUT_DIR/$ARCHIVE_NAME"
