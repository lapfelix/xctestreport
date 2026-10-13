#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /absolute/path/to/generated-report-output" >&2
  exit 1
fi
case "$1" in
  /*) ;;
  *) echo "The generated-report output path must be absolute." >&2; exit 1 ;;
esac

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/xctestreport-install.XXXXXX")"
trap 'rm -rf "$SMOKE_ROOT"' EXIT

XCTESTREPORT_BUILD_PATH="$SMOKE_ROOT/build" "$REPO_ROOT/Scripts/install.sh" "$SMOKE_ROOT/install"
# Bundle.module must resolve the installed bundle after its embedded build path disappears.
rm -rf "$SMOKE_ROOT/build"
cd "$SMOKE_ROOT"
node "$REPO_ROOT/ui-tests/scripts/generate-report.js" "$SMOKE_ROOT/install/bin/xctestreport" "$1"
