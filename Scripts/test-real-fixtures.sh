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

if [[ -z ${FIXTURE_DESTINATION:-} ]]; then
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
echo "Using fixture simulator: $FIXTURE_DESTINATION"
"$REPO_ROOT/Fixtures/XCResultFixture/generate.sh" "$FIXTURE_OUTPUT"

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
