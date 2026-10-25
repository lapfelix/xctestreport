#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || $1 != /* ]]; then
  echo "Usage: $0 /absolute/path/to/empty/fixture-output" >&2
  exit 1
fi
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE_OUTPUT="$1"
mkdir -p "$FIXTURE_OUTPUT"
if [[ -n "$(ls -A "$FIXTURE_OUTPUT")" ]]; then
  echo "Fixture output must be empty: $FIXTURE_OUTPUT" >&2
  exit 1
fi
FIXTURE_OUTPUT="$(cd "$FIXTURE_OUTPUT" && pwd)"
BUNDLE="$FIXTURE_OUTPUT/Performance.xcresult"
VERIFY=(env PYTHONDONTWRITEBYTECODE=1 python3 "$REPO_ROOT/Fixtures/XCResultFixture/verify.py")

# A verified bundle is reusable across runs: its baselines and measurements are recorded in it.
RAW_CACHE="${XCTESTREPORT_RAW_PERFORMANCE_CACHE:-}"
REUSED_RAW=false
if [[ -n "$RAW_CACHE" ]]; then
  mkdir -p "$RAW_CACHE"
  RAW_CACHE="$(cd "$RAW_CACHE" && pwd)"
  if [[ "$RAW_CACHE" == "$FIXTURE_OUTPUT" || "$RAW_CACHE" == "$FIXTURE_OUTPUT/"* || "$FIXTURE_OUTPUT" == "$RAW_CACHE/"* ]]; then
    echo "Raw fixture cache and fresh fixture output must be separate directories." >&2
    exit 1
  fi
  if [[ -d "$RAW_CACHE/Performance.xcresult" && -f "$RAW_CACHE/verified.json" ]]; then
    echo "Revalidating the cached Performance.xcresult with the current fixture oracle."
    cp -R "$RAW_CACHE/Performance.xcresult" "$BUNDLE"
    if "${VERIFY[@]}" "$BUNDLE" Performance; then
      REUSED_RAW=true
    else
      echo "The cached bundle failed validation; generating it again."
      rm -rf "$BUNDLE"
      rm -f "$RAW_CACHE/verified.json"
    fi
  else
    rm -f "$RAW_CACHE/verified.json"
  fi
fi

if [[ "$REUSED_RAW" != true ]]; then
  if [[ -z ${FIXTURE_DESTINATION:-} ]]; then
    FIXTURE_DESTINATION="$("$REPO_ROOT/Scripts/fixture-destination.sh")"
    export FIXTURE_DESTINATION
  fi
  echo "Using fixture simulator: $FIXTURE_DESTINATION"
  "$REPO_ROOT/Fixtures/XCResultFixture/generate.sh" --performance "$FIXTURE_OUTPUT"
  if [[ -n "$RAW_CACHE" ]]; then
    # The marker is written last, so an interrupted copy is never reused.
    rm -rf "$RAW_CACHE/Performance.xcresult"
    cp -R "$BUNDLE" "$RAW_CACHE/Performance.xcresult"
    echo '{"schemaVersion":1,"verifiedPlans":["Performance"]}' > "$RAW_CACHE/verified.json"
  fi
fi

cd "$REPO_ROOT"
swift build
PYTHONDONTWRITEBYTECODE=1 python3 "$REPO_ROOT/Fixtures/XCResultFixture/validate_performance_report.py" \
  "$BUNDLE" "$(swift build --show-bin-path)/xctestreport"
