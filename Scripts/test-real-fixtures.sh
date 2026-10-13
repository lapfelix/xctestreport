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

RAW_CACHE="${XCTESTREPORT_RAW_FIXTURE_CACHE:-}"
REUSED_RAW=false
if [[ -n "$RAW_CACHE" ]]; then
  mkdir -p "$RAW_CACHE"
  RAW_CACHE="$(cd "$RAW_CACHE" && pwd)"
  FIXTURE_OUTPUT="$(cd "$FIXTURE_OUTPUT" && pwd)"
  if [[ "$RAW_CACHE" == "$FIXTURE_OUTPUT" || "$RAW_CACHE" == "$FIXTURE_OUTPUT/"* || "$FIXTURE_OUTPUT" == "$RAW_CACHE/"* ]]; then
    echo "Raw fixture cache and fresh fixture output must be separate directories." >&2
    exit 1
  fi
  if [[ -d "$RAW_CACHE/Baseline.xcresult" && -d "$RAW_CACHE/Mixed.xcresult" && -f "$RAW_CACHE/verified.json" ]] &&
    python3 -c 'import json,sys; value=json.load(open(sys.argv[1])); sys.exit(0 if value.get("schemaVersion")==1 and value.get("verifiedPlans")==["Baseline","Mixed"] else 1)' "$RAW_CACHE/verified.json"; then
    echo "Revalidating cached raw xcresults with the current fixture oracle."
    cp -R "$RAW_CACHE/Baseline.xcresult" "$FIXTURE_OUTPUT/Baseline.xcresult"
    cp -R "$RAW_CACHE/Mixed.xcresult" "$FIXTURE_OUTPUT/Mixed.xcresult"
    if PYTHONDONTWRITEBYTECODE=1 python3 "$REPO_ROOT/Fixtures/XCResultFixture/verify.py" "$FIXTURE_OUTPUT/Baseline.xcresult" Baseline > "$FIXTURE_OUTPUT/cache-verification.log" 2>&1 &&
      PYTHONDONTWRITEBYTECODE=1 python3 "$REPO_ROOT/Fixtures/XCResultFixture/verify.py" "$FIXTURE_OUTPUT/Mixed.xcresult" Mixed >> "$FIXTURE_OUTPUT/cache-verification.log" 2>&1; then
      REUSED_RAW=true
      cat "$FIXTURE_OUTPUT/cache-verification.log"
    else
      echo "Cached raw fixtures failed validation; generating both bundles again."
      for plan in Baseline Mixed; do
        rm -rf "$FIXTURE_OUTPUT/$plan.xcresult"
        rm -f "$FIXTURE_OUTPUT/$plan.summary.json" "$FIXTURE_OUTPUT/$plan.tests.json" "$FIXTURE_OUTPUT/$plan.media.json"
      done
      rm -f "$RAW_CACHE/verified.json"
    fi
  else
    # A marker is published last; anything incomplete must not be reused or saved.
    rm -f "$RAW_CACHE/verified.json"
  fi
fi

if [[ "$REUSED_RAW" != true && -z ${FIXTURE_DESTINATION:-} ]]; then
  SIMULATOR_ID="$(xcrun simctl list devices available --json | python3 -c '
import json, re, sys
choices = []
for runtime, devices in json.load(sys.stdin)["devices"].items():
    version = re.search(r"iOS-(\d+(?:-\d+)*)$", runtime)
    if not version or int(version.group(1).split("-")[0]) < 17:
        continue
    parts = tuple(map(int, version.group(1).split("-")))
    for device in devices:
        if device.get("isAvailable", False) and ("iPhone" in device.get("deviceTypeIdentifier", "") or device["name"].startswith("iPhone")):
            choices.append((parts, device.get("state") == "Booted", device["name"], device["udid"]))
if not choices:
    sys.exit("No available iPhone simulator with an iOS 17+ runtime. Install one or set FIXTURE_DESTINATION.")
print(sorted(choices, reverse=True)[0][3])')"
  export FIXTURE_DESTINATION="platform=iOS Simulator,id=$SIMULATOR_ID"
fi
if [[ "$REUSED_RAW" != true ]]; then
  echo "Using fixture simulator: $FIXTURE_DESTINATION"
  "$REPO_ROOT/Fixtures/XCResultFixture/generate.sh" "$FIXTURE_OUTPUT"
fi

# generate.sh verifies both plans. Cache only those source bundles, before report generation
# can fail. The workflow saves this marker even when a downstream report/browser check fails.
if [[ -n "$RAW_CACHE" && "$REUSED_RAW" != true ]]; then
  CACHE_STAGE="$(mktemp -d "${RAW_CACHE}.staging.XXXXXX")"
  trap 'rm -rf "$CACHE_STAGE"' EXIT
  cp -R "$FIXTURE_OUTPUT/Baseline.xcresult" "$CACHE_STAGE/Baseline.xcresult"
  cp -R "$FIXTURE_OUTPUT/Mixed.xcresult" "$CACHE_STAGE/Mixed.xcresult"
  rm -f "$RAW_CACHE/verified.json"
  for plan in Baseline Mixed; do
    rm -rf "$RAW_CACHE/$plan.xcresult"
    mv "$CACHE_STAGE/$plan.xcresult" "$RAW_CACHE/$plan.xcresult"
  done
  printf '{"schemaVersion":1,"verifiedPlans":["Baseline","Mixed"]}\n' > "$RAW_CACHE/verified.json"
  rm -rf "$CACHE_STAGE"
  trap - EXIT
fi

if [[ -n ${XCTESTREPORT_EXECUTABLE:-} ]]; then
  REPORT_EXECUTABLE="$XCTESTREPORT_EXECUTABLE"
else
  swift build --package-path "$REPO_ROOT" -c release
  REPORT_BIN_PATH="$(swift build --package-path "$REPO_ROOT" -c release --show-bin-path)"
  REPORT_EXECUTABLE="$REPORT_BIN_PATH/xctestreport"
fi
REPORT_ROOT="$FIXTURE_OUTPUT/reports"
mkdir -p "$REPORT_ROOT"
run_report() {
  local plan="$1"
  local report="$2"
  shift 2
  local log="$FIXTURE_OUTPUT/$report-generation.log"
  if [[ ${1:-} == --html-only ]]; then log="$FIXTURE_OUTPUT/$report-regeneration.log"; fi
  if ! "$REPORT_EXECUTABLE" "$FIXTURE_OUTPUT/$plan.xcresult" "$REPORT_ROOT/$report" "$@" > "$log" 2>&1; then
    tail -n 60 "$log" >&2
    return 1
  fi
}
run_report Baseline baseline
run_report Mixed mixed --baseline "$REPORT_ROOT/baseline"
PYTHONDONTWRITEBYTECODE=1 python3 "$REPO_ROOT/Fixtures/XCResultFixture/validate_reports.py" "$FIXTURE_OUTPUT"

ARCHIVED_SOURCES="$FIXTURE_OUTPUT/archived-xcresults"
mkdir -p "$ARCHIVED_SOURCES"
restore_sources() {
  for plan in Baseline Mixed; do
    if [[ -d "$ARCHIVED_SOURCES/$plan.xcresult" && ! -e "$FIXTURE_OUTPUT/$plan.xcresult" ]]; then
      mv "$ARCHIVED_SOURCES/$plan.xcresult" "$FIXTURE_OUTPUT/$plan.xcresult"
    fi
  done
}
trap restore_sources EXIT
for plan in Baseline Mixed; do
  mv "$FIXTURE_OUTPUT/$plan.xcresult" "$ARCHIVED_SOURCES/$plan.xcresult"
done
run_report Baseline baseline --html-only
run_report Mixed mixed --html-only --baseline "$REPORT_ROOT/baseline"
PYTHONDONTWRITEBYTECODE=1 python3 "$REPO_ROOT/Fixtures/XCResultFixture/validate_reports.py" "$FIXTURE_OUTPUT" --check-failure-preservation "$REPORT_EXECUTABLE"
echo "Verified actual xcresult reports, packed regeneration without sources, and failed-generation preservation."
