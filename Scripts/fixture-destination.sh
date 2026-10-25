#!/usr/bin/env bash
# Prints an xcodebuild destination for the newest available iPhone simulator (iOS 17+).
set -euo pipefail
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
echo "platform=iOS Simulator,id=$SIMULATOR_ID"
