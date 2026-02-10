#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <xcresult-path> <test-identifier> [output-dir]"
  exit 1
fi

XCR_PATH="$1"
TEST_ID="$2"
OUT_DIR="${3:-$(mktemp -d /tmp/xctestreport-compare.XXXXXX)}"

if [[ ! -d "$XCR_PATH" ]]; then
  echo "xcresult path not found: $XCR_PATH"
  exit 1
fi

if [[ ! -x .build/debug/xctestreport ]]; then
  echo "Building xctestreport..."
  swift build >/dev/null
fi

echo "Generating report to: $OUT_DIR"
.build/debug/xctestreport "$XCR_PATH" "$OUT_DIR" >/tmp/xctestreport-compare.log

python3 - <<'PY' "$XCR_PATH" "$TEST_ID" "$OUT_DIR"
import gzip
import json
import os
import subprocess
import sys

xcr_path, test_id, out_dir = sys.argv[1:4]
safe_id = test_id.replace("/", "_")
payload_path = os.path.join(out_dir, "timeline_payloads", f"test_{safe_id}.runstates.bin")

if not os.path.exists(payload_path):
    print(f"Missing payload: {payload_path}")
    sys.exit(2)

xc_cmd = [
    "xcrun", "xcresulttool", "get", "test-results", "activities",
    "--test-id", test_id,
    "--path", xcr_path,
    "--format", "json",
    "--compact",
]
xc_json = subprocess.check_output(xc_cmd, text=True)
xc_obj = json.loads(xc_json)

def walk_xc(node, out):
    title = node.get("title") or ""
    if node.get("isAssociatedWithFailure"):
        out.append(title)
    for child in node.get("childActivities") or []:
        walk_xc(child, out)

xc_failure_titles = []
for run in xc_obj.get("testRuns", []):
    for activity in run.get("activities", []):
        walk_xc(activity, xc_failure_titles)

with open(payload_path, "rb") as fh:
    runstates = json.loads(gzip.decompress(fh.read()).decode("utf-8"))

our_error_titles = []
for run in runstates:
    events = run[3] if len(run) > 3 else []
    for event in events:
        if len(event) >= 5 and event[4] == "error":
            our_error_titles.append(event[1])

xc_set = set(xc_failure_titles)
our_set = set(our_error_titles)

missing = sorted(xc_set - our_set)
extra = sorted(our_set - xc_set)

print("=== Activity Extraction Comparison ===")
print(f"Test: {test_id}")
print(f"xcresulttool failure events: {len(xc_failure_titles)}")
print(f"our timeline error events:   {len(our_error_titles)}")
print(f"missing from our output:     {len(missing)}")
print(f"extra in our output:         {len(extra)}")

if missing:
    print("\nMissing failure titles:")
    for title in missing[:20]:
        print(f" - {title}")

if extra:
    print("\nExtra error titles:")
    for title in extra[:20]:
        print(f" - {title}")

if missing:
    sys.exit(3)

print("\nOK: all xcresulttool failure titles are present in our timeline output.")
PY

echo
echo "Artifacts:"
echo " - report output: $OUT_DIR"
echo " - generation log: /tmp/xctestreport-compare.log"
