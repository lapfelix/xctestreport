#!/usr/bin/env python3
"""Point a project's committed performance baselines at this Mac and a simulator destination.

Xcode applies an .xcbaseline only when its run destination matches the host Mac and the
target device model exactly; otherwise the test silently runs without a baseline.
"""

import argparse
import json
import plistlib
import subprocess
import sys
from pathlib import Path


def sysctl(name):
    result = subprocess.run(["sysctl", "-n", name], capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else ""


def sysctl_int(name):
    value = sysctl(name)
    return int(value) if value.isdigit() else 0


def host():
    # Apple silicon reports no bus/CPU frequency; Xcode records 0 for both.
    return {
        "busSpeedInMHz": sysctl_int("hw.busfrequency") // 1_000_000,
        "cpuCount": sysctl_int("hw.packages") or 1,
        "cpuKind": sysctl("machdep.cpu.brand_string"),
        "cpuSpeedInMHz": sysctl_int("hw.cpufrequency") // 1_000_000,
        "logicalCPUCoresPerPackage": sysctl_int("hw.logicalcpu"),
        "modelCode": sysctl("hw.model"),
        "physicalCPUCoresPerPackage": sysctl_int("hw.physicalcpu"),
        "platformIdentifier": "com.apple.platform.macosx",
    }


def simulator_model(destination):
    fields = dict(part.split("=", 1) for part in destination.split(",") if "=" in part)
    simctl = lambda *args: json.loads(subprocess.run(["xcrun", "simctl", "list", *args, "-j"],
                                                     capture_output=True, text=True, check=True).stdout)
    types = simctl("devicetypes")["devicetypes"]
    type_id = None
    if "id" in fields:
        devices = [device for runtime in simctl("devices", "available")["devices"].values() for device in runtime]
        type_id = next((d["deviceTypeIdentifier"] for d in devices if d["udid"] == fields["id"]), None)
    elif "name" in fields:
        type_id = next((t["identifier"] for t in types if t["name"] == fields["name"]), None)
    model = next((t.get("modelIdentifier") for t in types if t["identifier"] == type_id), None)
    if not model:
        raise ValueError(f"Cannot resolve a simulator model for destination {destination!r}")
    return model


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path, help="path to the .xcodeproj to modify in place")
    parser.add_argument("destination", help="xcodebuild -destination string (name= or id=)")
    args = parser.parse_args()
    target = {
        "localComputer": host(),
        "targetArchitecture": "arm64" if sysctl("hw.optional.arm64") == "1" else "x86_64",
        "targetDevice": {
            "modelCode": simulator_model(args.destination),
            "platformIdentifier": "com.apple.platform.iphonesimulator",
        },
    }
    infos = sorted((args.project / "xcshareddata" / "xcbaselines").glob("*.xcbaseline/Info.plist"))
    if not infos:
        raise ValueError(f"No baselines found in {args.project}")
    for info in infos:
        plist = plistlib.loads(info.read_bytes())
        plist["runDestinationsByUUID"] = {uuid: target for uuid in plist["runDestinationsByUUID"]}
        info.write_bytes(plistlib.dumps(plist))
    print(f"Baselines target {target['localComputer']['modelCode']} ({target['localComputer']['cpuKind']}) "
          f"with {target['targetDevice']['modelCode']}")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, subprocess.CalledProcessError) as error:
        print(f"Cannot retarget baselines: {error}", file=sys.stderr)
        sys.exit(1)
