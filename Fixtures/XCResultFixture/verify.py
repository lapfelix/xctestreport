#!/usr/bin/env python3
"""Check the semantic contract of a real fixture bundle with Apple's public CLI."""

import argparse
import json
import plistlib
import re
import struct
import subprocess
import sys
import tempfile
from pathlib import Path


EXPECTED_CASES = {
    "ActivityTests/testNestedActivitiesAndAttachments()",
    "ActivityTests/testPerformanceMeasurement()",
    "ActivityTests/testSlowPassingOperation()",
    "OutcomeTests/testPassingAssertion()",
    "OutcomeTests/testSkippedWithReason()",
    "OutcomeTests/testExpectedFailure()",
    "OutcomeTests/testMultipleFailuresInNestedStep()",
    "OutcomeTests/testThrownError()",
    "OutcomeTests/testFailsOnceThenPasses()",
    "SnapshotTests/testChangedCard()",
    "SnapshotTests/testResizedCard()",
    "SnapshotTests/testProvidedDifferenceAndAliases()",
    "SnapshotTests/testMatchingCardWithoutAttachments()",
    "ModernTests/fares(category:)",
    "ModernTests/modernAssertion()",
    "JourneyUITests/testPinRoute()",
    "JourneyUITests/testSearchRoutes()",
    "JourneyUITests/testFailureWithScreenshotAndHierarchy()",
}

MIXED_FAILURES = {
    "OutcomeTests/testMultipleFailuresInNestedStep()",
    "OutcomeTests/testThrownError()",
    "SnapshotTests/testChangedCard()",
    "SnapshotTests/testResizedCard()",
    "SnapshotTests/testProvidedDifferenceAndAliases()",
    "ModernTests/modernAssertion()",
    "JourneyUITests/testFailureWithScreenshotAndHierarchy()",
}

CUSTOM_ATTACHMENT_NAMES = {
    "journey.log", "response.json", "route-state.plist", "route-state-xml.plist",
    "duplicate-name.txt", "opaque.bin", "empty.txt", "timing.txt", "failure-context.txt",
    "response-context.txt", "service.log", "attempt.txt", "pin-state.json",
    "search-results.txt", "accessibility-hierarchy.txt",
}

EXPECTED_ACTIVITY_TITLES = {
    "ActivityTests/testNestedActivitiesAndAttachments()": "Plan a journey: Montréal → Downtown",
    "ActivityTests/testPerformanceMeasurement()": "Measure local route serialization",
    "ActivityTests/testSlowPassingOperation()": "Wait for a deliberately slow local operation",
    "OutcomeTests/testPassingAssertion()": "Verify a plain assertion without attachments",
    "OutcomeTests/testSkippedWithReason()": "Check subscription eligibility",
    "OutcomeTests/testExpectedFailure()": "Verify fare rounding",
    "OutcomeTests/testMultipleFailuresInNestedStep()": "Verify response",
    "OutcomeTests/testThrownError()": "Request route service",
    "OutcomeTests/testFailsOnceThenPasses()": "Connect to route service",
    "SnapshotTests/testChangedCard()": "Compare route card without a supplied diff",
    "SnapshotTests/testResizedCard()": "Compare images of different sizes",
    "SnapshotTests/testProvidedDifferenceAndAliases()": "Compare reference/failure aliases with supplied difference",
    "SnapshotTests/testMatchingCardWithoutAttachments()": "Verify matching card without retaining images",
    "JourneyUITests/testPinRoute()": "Open journey",
    "JourneyUITests/testSearchRoutes()": "Search for Orange line",
    "JourneyUITests/testFailureWithScreenshotAndHierarchy()": "Verify pin state after tapping",
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def run(*args):
    result = subprocess.run(args, capture_output=True, text=True, check=True)
    return result.stdout


def canonical(identifier):
    # Some Xcode versions include the target/module in the identifier.
    suite, method = identifier.split("/")[-2:]
    return f"{suite.rsplit('.', 1)[-1]}/{method}"


def attachment_name(name):
    return re.sub(r"_\d+_[0-9A-Fa-f-]{36}(?=\.[^.]+$|$)", "", name)


def walk(nodes, child_key="children"):
    for node in nodes:
        yield node
        yield from walk(node.get(child_key) or [], child_key)


def verify(bundle, plan):
    mixed = plan == "Mixed"
    detail_exports = {}
    activity_exports = {}

    def save(topic, value):
        bundle.with_suffix(f".{topic}.json").write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")

    def result(topic, test_id=None):
        args = ["xcrun", "xcresulttool", "get", "test-results", topic,
                "--path", str(bundle), "--compact"]
        if test_id:
            args.extend(["--test-id", test_id])
        return json.loads(run(*args))

    summary = result("summary")
    tree = result("tests")
    save("summary", summary)
    save("tests", tree)
    cases = {canonical(node["nodeIdentifier"]): node
             for node in walk(tree["testNodes"]) if node["nodeType"] == "Test Case"}
    require(set(cases) == EXPECTED_CASES,
            f"Case set changed: missing {EXPECTED_CASES - set(cases)}, extra {set(cases) - EXPECTED_CASES}")
    failures = {key for key, node in cases.items() if node.get("result") == "Failed"}
    require(failures == (MIXED_FAILURES if mixed else set()), f"Unexpected failures: {sorted(failures)}")
    require(summary["failedTests"] == (7 if mixed else 0), "Unexpected failure count")
    require(summary["skippedTests"] == (1 if mixed else 0), "Unexpected skip count")
    require(summary["expectedFailures"] == (1 if mixed else 0), "Missing/unexpected expected failure")
    require(summary["totalTestCount"] == 18, "Unexpected total test-function count")
    require(summary["passedTests"] == (9 if mixed else 18), "Unexpected passing-test count")

    for key, node in cases.items():
        expected = "Failed" if mixed and key in MIXED_FAILURES else "Passed"
        if mixed and key == "OutcomeTests/testSkippedWithReason()":
            expected = "Skipped"
        if mixed and key == "OutcomeTests/testExpectedFailure()":
            # Xcode versions represent known issues either on the case or on its children.
            require(node.get("result") in {"Passed", "Expected Failure"}, "Known issue became a failure")
        else:
            require(node.get("result") == expected, f"{key}: expected {expected}, got {node.get('result')}")

    def details(key):
        detail_exports[key] = result("test-details", cases[key]["nodeIdentifier"])
        save("details", detail_exports)
        return detail_exports[key]

    def activities(key):
        activity_exports[key] = result("activities", cases[key]["nodeIdentifier"])["testRuns"]
        save("activities", activity_exports)
        return activity_exports[key]

    metric = details("ActivityTests/testPerformanceMeasurement()")
    require(metric["hasPerformanceMetrics"], "Missing XCTest performance measurement")
    parameter_runs = details("ModernTests/fares(category:)")["testRuns"]
    require(len(parameter_runs) == 3, "Expected three Swift Testing arguments")
    retry_runs = activities("OutcomeTests/testFailsOnceThenPasses()")
    require(len(retry_runs) == (2 if mixed else 1), "Missing deterministic retry / extra attempts")
    retry_results = [run["result"] for run in details("OutcomeTests/testFailsOnceThenPasses()")["testRuns"]]
    require(retry_results == (["Failed", "Passed"] if mixed else ["Passed"]),
            f"Unexpected retry outcomes: {retry_results}")

    nested_runs = activities("ActivityTests/testNestedActivitiesAndAttachments()")
    nested = list(walk(nested_runs[0]["activities"], "childActivities"))
    titles = {node["title"] for node in nested}
    require("Decode → validate → render" in titles, "Missing nested activity")
    # xcresulttool repeats a descendant's attachments on each ancestor activity.
    exported_names = {attachment["name"] for node in nested for attachment in node.get("attachments", [])}
    names = [attachment_name(name) for name in exported_names]
    require(names.count("duplicate-name.txt") == 2, "Missing duplicate names in separate steps")
    required_names = {"journey.log", "response.json", "route-state.plist", "route-state-xml.plist",
                      "route-preview.png", "empty.txt", "opaque.bin"}
    require(required_names <= set(names), f"Missing nested attachments: {required_names - set(names)}")
    nested_steps = {node["title"]: node for node in nested}
    require(any(child["title"] == "Decode → validate → render"
                for child in nested_steps["Load offline response"].get("childActivities", [])),
            "Activity hierarchy was flattened")
    # Public activity exports omit the private SQLite activityType. Check the fixture's
    # exact named user steps instead of treating missing optional metadata as missing steps.
    for key, title in sorted(EXPECTED_ACTIVITY_TITLES.items()):
        runs = activities(key)
        require(all(any(node.get("title") == title
                        for node in walk(run["activities"], "childActivities")) for run in runs),
                f"Missing XCTContext.runActivity step {title!r} for {key}")

    if mixed:
        issue_steps = [node for run in activities("OutcomeTests/testMultipleFailuresInNestedStep()")
                       for node in walk(run["activities"], "childActivities")]
        require(any(node["title"] == "Validate status & route name <rail>" and node["isAssociatedWithFailure"]
                    for node in issue_steps), "Missing failure-associated nested activity")

    # Export with the public tool so validation does not depend on Xcode's private
    # SQLite schema or the on-disk compression used for attachment payloads.
    with tempfile.TemporaryDirectory(prefix="xcresult-fixture-verify-") as temp:
        run("xcrun", "xcresulttool", "export", "attachments", "--path", str(bundle), "--output-path", temp)
        manifest = json.loads((Path(temp) / "manifest.json").read_text())
        save("attachments", manifest)
        attachments = {}
        videos_by_test = set()
        images_by_test = set()
        media_by_test = {key: {"images": [], "videos": [], "customAttachments": [], "diagnosticAttachments": []}
                         for key in sorted(EXPECTED_CASES)}
        for entry in manifest:
            key = canonical(entry["testIdentifier"])
            for item in entry["attachments"]:
                name = attachment_name(item["suggestedHumanReadableName"])
                path = Path(temp) / item["exportedFileName"]
                attachments.setdefault(name, path)
                if path.suffix.lower() in {".mp4", ".mov", ".m4v"}:
                    require(path.stat().st_size > 0, "Empty UI recording")
                    videos_by_test.add(key)
                    media_by_test[key]["videos"].append(name)
                elif path.suffix.lower() in {".png", ".jpg", ".jpeg", ".heic", ".gif", ".tif", ".tiff"}:
                    images_by_test.add(key)
                    media_by_test[key]["images"].append(name)
                elif name in CUSTOM_ATTACHMENT_NAMES:
                    media_by_test[key]["customAttachments"].append(name)
                else:
                    media_by_test[key]["diagnosticAttachments"].append(name)
        ui_tests = {key for key in EXPECTED_CASES if key.startswith("JourneyUITests/")}
        expected_video_tests = ui_tests if mixed else set()
        require(expected_video_tests == videos_by_test, f"Wrong video distribution: {sorted(videos_by_test)}")
        search_key = "JourneyUITests/testSearchRoutes()"
        pin_key = "JourneyUITests/testPinRoute()"
        if mixed:
            require(search_key not in images_by_test, "Video-only search test unexpectedly has a still image")
            require(pin_key in images_by_test, "Combined video/screenshot test has no screenshots")
        else:
            require(ui_tests <= images_by_test, "Missing baseline UI screenshots")
        image_only = images_by_test - videos_by_test
        no_media = EXPECTED_CASES - images_by_test - videos_by_test
        require("SnapshotTests/testChangedCard()" in image_only, "Missing image-only snapshot test")
        require("OutcomeTests/testPassingAssertion()" in no_media, "Plain test unexpectedly has media")
        require("SnapshotTests/testMatchingCardWithoutAttachments()" in no_media,
                "Matching snapshot test unexpectedly has media")
        media = {
            "categories": {
                "videoOnly": sorted(videos_by_test - images_by_test),
                "imageOnly": sorted(image_only),
                "videoAndImage": sorted(videos_by_test & images_by_test),
                "noMedia": sorted(no_media),
            },
            "tests": media_by_test,
        }

        def payload(name):
            require(name in attachments, f"Missing exported attachment: {name}")
            return attachments[name].read_bytes()

        binary = payload("route-state.plist")
        require(binary.startswith(b"bplist00"), "Binary plist is not binary")
        require(plistlib.loads(binary)["selectedRoute"] == "Green", "Unexpected plist content")
        require(plistlib.loads(payload("route-state-xml.plist"))["pinned"], "XML plist changed")
        require(json.loads(payload("response.json"))["city"] == "Montréal", "JSON payload changed")
        require(payload("opaque.bin") == bytes([0, 1, 2, 127, 128, 254, 255]), "Opaque payload changed")
        require(payload("empty.txt") == b"", "Empty payload changed")
        pin_state = json.loads(payload("pin-state.json"))
        require(pin_state["pinned"] and pin_state["city"] == "Montréal", "Custom UI state JSON changed")
        require("pin-state.json" in media_by_test[pin_key]["customAttachments"], "UI JSON attached to the wrong test")
        require("Visible: Orange line" in payload("search-results.txt").decode(), "Missing custom UI search log")

        for name in ["RouteCard.expected.png", "RouteCard.actual.png", "WideCard.expected.png",
                     "WideCard.actual.png", "AliasedCard.reference.png", "AliasedCard.failure.png"]:
            require(payload(name).startswith(b"\x89PNG\r\n\x1a\n"), f"Invalid PNG: {name}")
        expected_size = (192, 112) if mixed else (160, 96)
        require(struct.unpack(">II", payload("WideCard.actual.png")[16:24]) == expected_size,
                "Wrong resized snapshot dimensions")
        if mixed:
            require(payload("AliasedCard.difference.png").startswith(b"\x89PNG"), "Missing supplied diff")
            require(payload("RouteCard.expected.png") != payload("RouteCard.actual.png"), "Snapshot did not change")
            require("accessibility-hierarchy.txt" in attachments, "Missing UI hierarchy text")
        else:
            require(payload("RouteCard.expected.png") == payload("RouteCard.actual.png"), "Baseline snapshot differs")

    bundle.with_suffix(".summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    bundle.with_suffix(".tests.json").write_text(json.dumps(tree, indent=2) + "\n")
    bundle.with_suffix(".media.json").write_text(json.dumps(media, indent=2) + "\n")
    print(f"Verified {plan}: {len(cases)} test functions, {summary['failedTests']} failures, "
          f"{summary['skippedTests']} skips, {summary['expectedFailures']} expected failures; "
          "custom attachments, nested activities, snapshots, metrics, parameters, retries, and media mix intact.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path)
    parser.add_argument("plan", choices=["Baseline", "Mixed"])
    args = parser.parse_args()
    try:
        verify(args.bundle.resolve(), args.plan)
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        print(f"Fixture verification failed: {error}", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError):
            print(error.stderr, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
