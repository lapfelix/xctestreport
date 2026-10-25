#!/usr/bin/env python3
"""Compare shipping reports with the independently verified real xcresult fixture contract."""

import argparse
import hashlib
from html.parser import HTMLParser
import json
import math
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
from urllib.parse import unquote, urlsplit
import zipfile

from verify import EXPECTED_CASES, MIXED_FAILURES, attachment_name, canonical, require, walk


class Element:
    def __init__(self, tag, attributes=(), parent=None):
        self.tag, self.attributes, self.parent = tag, dict(attributes), parent
        self.children = []

    @property
    def classes(self):
        return set(self.attributes.get("class", "").split())

    @property
    def text(self):
        return "".join(child.text if isinstance(child, Element) else child for child in self.children)

    def elements(self):
        yield self
        for child in self.children:
            if isinstance(child, Element):
                yield from child.elements()


class Document(HTMLParser):
    VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"}

    def __init__(self, content):
        super().__init__(convert_charrefs=True)
        self.root = Element("document")
        self.stack = [self.root]
        self.feed(content)

    def handle_starttag(self, tag, attributes):
        node = Element(tag, attributes, self.stack[-1])
        self.stack[-1].children.append(node)
        if tag not in self.VOID:
            self.stack.append(node)

    def handle_endtag(self, tag):
        for index in range(len(self.stack) - 1, 0, -1):
            if self.stack[index].tag == tag:
                del self.stack[index:]
                break

    def handle_startendtag(self, tag, attributes):
        self.handle_starttag(tag, attributes)
        self.handle_endtag(tag)

    def handle_data(self, data):
        self.stack[-1].children.append(data)


def load_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def local_path(root, relative):
    require(not urlsplit(relative).scheme, f"External artifact path: {relative}")
    result = (root / unquote(urlsplit(relative).path)).resolve()
    require(result.is_relative_to(root.resolve()), f"Artifact escapes report: {relative}")
    return result


def by_identifier(entries, field="testIdentifier"):
    return {canonical(key): value for key, value in entries.items()} if isinstance(entries, dict) else {
        canonical(entry[field]): entry for entry in entries
    }


def report_pages(report):
    pages = {}
    for file in (report / "tests").glob("*.html"):
        document = Document(file.read_text(encoding="utf-8"))
        body = next(node for node in document.root.elements() if node.tag == "body")
        key = canonical(body.attributes["data-test-id"])
        require(key not in pages, f"Duplicate report page for {key}")
        archive = local_path(file.parent, body.attributes["data-report-bundle"])
        require(archive.is_file(), f"Missing archive for {key}")
        with zipfile.ZipFile(archive) as bundle:
            require(bundle.testzip() is None, f"Corrupt ZIP: {archive.name}")
            require("test.md" in bundle.namelist(), f"Missing bundled Markdown for {key}")
        pages[key] = {"file": file, "document": document, "archive": archive}
    require(set(pages) == EXPECTED_CASES, f"Report page inventory differs: {set(pages) ^ EXPECTED_CASES}")
    require(len(list((report / "tests").glob("*.zip"))) == len(pages), "Unexpected extra/missing test ZIPs")
    return pages


def payload(report, pages, manifest, key, name, all_matches=False):
    items = [item for item in manifest.get(key, {}).get("attachments", [])
             if attachment_name(item.get("suggestedHumanReadableName") or "") == name]
    require(items, f"{key}: missing attachment {name}")
    values = []
    for item in items:
        loose = local_path(report / "attachments", item["exportedFileName"])
        if loose.exists():
            data = loose.read_bytes()
        else:
            with zipfile.ZipFile(pages[key]["archive"]) as bundle:
                data = bundle.read("attachments/" + item["exportedFileName"])
        values.append((item, data))
    return values if all_matches else values[0]


def own_attachments(page, title):
    links = []
    for node in page["document"].root.elements():
        if "timeline-node" not in node.classes:
            continue
        container = next((child for child in node.children if isinstance(child, Element) and child.tag == "details"), node)
        children = [child for child in container.children if isinstance(child, Element)]
        row = next((element for child in children if child.tag in {"div", "summary"}
                    for element in child.elements() if "timeline-event" in element.classes), None)
        if row is None or not any("timeline-title" in child.classes and title in child.text for child in row.elements()):
            continue
        for child in children:
            if "timeline-attachments" in child.classes:
                links.extend(element for element in child.elements() if "timeline-attachment-link" in element.classes)
    return links


def require_ownership(page, title, name):
    require(any(name in link.text for link in own_attachments(page, title)),
            f"{name} is not attached directly to step {title}")


def markdown_identifiers(content):
    return {canonical(value) for value in re.findall(r"^- \*\*Identifier:\*\* `([^`]+)`$", content, re.M)}


# The fixture app logs when it actually received each touch and shows a magenta bar while a
# finger is down. Overlay gestures must match the log, and the video must show the bar where
# the overlay says the touch is; the video lags by a frame or two of render/capture latency.
GESTURE_KEY = "JourneyUITests/testGestureTiming()"
GESTURE_TOLERANCE = 0.08
VIDEO_LAG = (-0.03, 0.15)
FRAME_STEP = 0.02


def sample_frames(video, times):
    script = Path(__file__).with_name("sample_frames.swift")
    with tempfile.TemporaryDirectory(prefix="xctestreport-frames-") as module_cache:
        result = subprocess.run(
            ["xcrun", "swift", "-module-cache-path", module_cache, str(script), str(video)]
            + [f"{time:.3f}" for time in times],
            capture_output=True, text=True, check=True)
    samples = {}
    for line in result.stdout.splitlines():
        time, *rgb = line.split()
        if rgb[0] != "none":
            red, green, blue = map(int, rgb)
            samples[round(float(time), 3)] = red > 180 and green < 90 and blue > 180
    return samples


def verify_gesture_timing(report, pages, manifest, mixed):
    touches = json.loads(payload(report, pages, manifest, GESTURE_KEY, "touch-log.json")[1])
    require(len(touches) == 5 and all("up" in touch for touch in touches), "Fixture touch log is incomplete")
    page = pages[GESTURE_KEY]
    with zipfile.ZipFile(page["archive"]) as bundle:
        run_states = json.loads(bundle.read("timeline/runstates.json"))
    # Compact run state: [base, label, failure index, events, gestures, hierarchy].
    gestures = [{"start": g[0], "end": g[1], "first": g[4][0][1:], "last": g[4][-1][1:]} for g in run_states[0][4]]
    require(len(gestures) == len(touches), f"Expected {len(touches)} overlay gestures, found {len(gestures)}")

    matched = []
    remaining = list(gestures)
    for touch in touches:
        gesture = min(remaining, key=lambda g: math.dist(g["first"], touch["downPoint"]) + math.dist(g["last"], touch["upPoint"]))
        remaining.remove(gesture)
        require(math.dist(gesture["first"], touch["downPoint"]) < 12 and math.dist(gesture["last"], touch["upPoint"]) < 12,
                f"Overlay gesture at {gesture['first']} does not match the touch at {touch['downPoint']}")
        start_error, end_error = gesture["start"] - touch["down"], gesture["end"] - touch["up"]
        require(abs(start_error) <= GESTURE_TOLERANCE and abs(end_error) <= GESTURE_TOLERANCE,
                f"Overlay gesture at {touch['downPoint']} is off by {start_error:+.3f}s (start) / {end_error:+.3f}s (end)")
        matched.append(gesture)
    if not mixed:
        return

    video = next(node for node in page["document"].root.elements() if node.tag == "video")
    video_start = float(video.attributes["data-video-start"])
    source = next(node for node in video.elements() if node.tag == "source")
    recording = local_path(report / "attachments", Path(unquote(source.attributes["src"])).name)
    # Look just around each gesture: the fixture's gestures are about 0.3s apart.
    windows = [(g["start"] - video_start, g["end"] - video_start) for g in matched]
    ranges = [(start - 0.1, end + VIDEO_LAG[1] + FRAME_STEP) for start, end in windows]
    times = sorted({round(low + index * FRAME_STEP, 3) for low, high in ranges
                    for index in range(int((high - low) / FRAME_STEP) + 1)})
    samples = sample_frames(recording, times)
    for (start, end), (low, high) in zip(windows, ranges):
        lit = [time for time, on in samples.items() if on and low <= time <= high]
        require(lit, f"Video never shows the touch the overlay places at {start:.3f}s")
        first_lag, last_lag = min(lit) - start, max(lit) - end
        require(VIDEO_LAG[0] <= first_lag <= VIDEO_LAG[1] and VIDEO_LAG[0] <= last_lag <= VIDEO_LAG[1] + FRAME_STEP,
                f"Video shows the touch at {min(lit):.3f}-{max(lit):.3f}s; the overlay places it at {start:.3f}-{end:.3f}s")


def verify_report(fixture, plan):
    mixed = plan == "Mixed"
    report = fixture / "reports" / plan.lower()
    summary = load_json(fixture / f"{plan}.summary.json")
    source_cases = {canonical(node["nodeIdentifier"]): node for node in walk(load_json(fixture / f"{plan}.tests.json")["testNodes"])
                    if node["nodeType"] == "Test Case"}
    inventory = load_json(report / "tests_inventory.json")
    require(inventory["schemaVersion"] == 1, "Unsupported report inventory schema")
    cases = {canonical(node["nodeIdentifier"]): node for node in walk(inventory["tests"]) if node["nodeType"] == "Test Case"}
    require(set(cases) == EXPECTED_CASES == set(source_cases), "Source/report test inventories differ")
    require(all(cases[key]["result"] == source_cases[key]["result"] for key in cases), "Report altered source outcomes")
    expected_failures = MIXED_FAILURES if mixed else set()
    require({key for key, case in cases.items() if case.get("result") == "Failed"} == expected_failures, "Wrong real failure identities")
    require(summary["failedTests"] == len(expected_failures) and summary["skippedTests"] == int(mixed)
            and summary["expectedFailures"] == int(mixed), "Fixture summary contract changed")
    pages = report_pages(report)
    details = by_identifier(load_json(report / "test_details.json"))
    activities = by_identifier(load_json(report / "test_activities.json"))
    require(set(details) == set(activities) == EXPECTED_CASES, "Missing cached details/activities")
    parameter_key = "ModernTests/fares(category:)"
    require([run["result"] for run in details[parameter_key]["testRuns"]] == ["Passed"] * 3, "Missing parameterized runs")
    if mixed:
        require(all([child.get("result") for child in run.get("children", []) if child["nodeType"] == "Repetition"] == ["Passed", "Passed"]
                    for run in details[parameter_key]["testRuns"]), "Missing grouped parameter repetitions")
        require("Retry 1 (Repetition): Passed" in pages[parameter_key]["document"].root.text,
                "Grouped parameter repetitions were dropped from the rendered details")
    retry_key = "OutcomeTests/testFailsOnceThenPasses()"
    require([run["result"] for run in details[retry_key]["testRuns"]] == (["Failed", "Passed"] if mixed else ["Passed"]), "Wrong retry runs")
    require(details["ActivityTests/testPerformanceMeasurement()"]["hasPerformanceMetrics"], "Lost performance metric flag")

    index = Document((report / "index.html").read_text(encoding="utf-8"))
    rows = {canonical(node.attributes["data-test-id"]): node for node in index.root.elements() if node.tag == "tr" and "data-test-id" in node.attributes}
    require(set(rows) == EXPECTED_CASES, "Missing index rows")
    for key, row in rows.items():
        expected_status = "failed" if key in expected_failures else "skipped" if mixed and key == "OutcomeTests/testSkippedWithReason()" else "passed"
        require(row.attributes["data-status"] == expected_status, f"{key}: wrong index status (expected failures must pass)")
        link = next(node for node in row.elements() if node.tag == "a" and node.attributes.get("href", "").startswith("tests/"))
        require(local_path(report, link.attributes["href"]) == pages[key]["file"], f"{key}: index links to another test")
    require(rows[parameter_key].attributes.get("data-flaky") != "true", "Parameterized test incorrectly marked flaky")
    require((rows[retry_key].attributes.get("data-flaky") == "true") == mixed, "Recovering retry missing flaky status")
    require(markdown_identifiers((report / "failures.md").read_text(encoding="utf-8")) == expected_failures, "Failures Markdown includes an expected failure or omits a real failure")
    require(markdown_identifiers((report / "agent-tests.md").read_text(encoding="utf-8")) == EXPECTED_CASES, "Agent Markdown lost cases")

    manifest = by_identifier(load_json(report / "attachments" / "manifest.json"))
    nested_key = "ActivityTests/testNestedActivitiesAndAttachments()"
    nested = pages[nested_key]
    for name in ["response.json", "route-state.plist", "route-state-xml.plist"]:
        require_ownership(nested, "Load offline response", name)
    require_ownership(nested, "Decode → validate → render", "duplicate-name.txt")
    require_ownership(nested, "Finish journey", "duplicate-name.txt")
    duplicates = payload(report, pages, manifest, nested_key, "duplicate-name.txt", all_matches=True)
    require({data for _, data in duplicates} == {b"nested payload one", b"nested payload two"}, "Duplicate names overwrote a distinct payload")
    require(len({item["exportedFileName"] for item, _ in duplicates}) == 2, "Duplicate payloads share a filename")
    for title, expected in [("Decode → validate → render", b"nested payload one"), ("Finish journey", b"nested payload two")]:
        names = {link.attributes.get("data-attachment-name") for link in own_attachments(nested, title)}
        require(any(item["exportedFileName"] in names and data == expected for item, data in duplicates), f"Duplicate payload is assigned to the wrong step: {title}")
    require(payload(report, pages, manifest, nested_key, "empty.txt")[1] == b"", "Empty payload changed")
    require(payload(report, pages, manifest, nested_key, "opaque.bin")[1] == bytes([0, 1, 2, 127, 128, 254, 255]), "Opaque bytes changed")
    for name, binary in [("route-state.plist", True), ("route-state-xml.plist", False)]:
        item, data = payload(report, pages, manifest, nested_key, name)
        require(item["exportedFileName"].endswith(".plist"), f"Plist UTI exported with wrong extension: {name}")
        require(data.startswith(b"bplist00") == binary, f"Wrong plist encoding: {name}")
        state = plistlib.loads(data)
        require(state["selectedRoute"] == "Green" and state["pinned"] and len(state["rows"]) == 100, "Plist content changed")
    require(json.loads(payload(report, pages, manifest, nested_key, "response.json")[1])["city"] == "Montréal", "Unicode JSON changed")
    nested_titles = {node["title"] for run in activities[nested_key]["testRuns"] for node in walk(run["activities"], "childActivities")}
    require({"Plan a journey: Montréal → Downtown", "Load offline response", "Decode → validate → render"} <= nested_titles, "Cached nested activities lost Unicode/hierarchy")
    pin_key, search_key = "JourneyUITests/testPinRoute()", "JourneyUITests/testSearchRoutes()"
    require_ownership(pages[pin_key], "Verify and capture pin state", "pin-state.json")
    require_ownership(pages[search_key], "Verify filtered routes", "search-results.txt")
    pin_state = json.loads(payload(report, pages, manifest, pin_key, "pin-state.json")[1])
    require(pin_state["pinned"] and pin_state["city"] == "Montréal", "UI state JSON changed")
    require(b"Visible: Orange line" in payload(report, pages, manifest, search_key, "search-results.txt")[1], "UI search log changed")
    require_ownership(pages[GESTURE_KEY], "Attach the app's touch log", "touch-log.json")
    verify_gesture_timing(report, pages, manifest, mixed)
    if mixed:
        require_ownership(pages["OutcomeTests/testMultipleFailuresInNestedStep()"], "Validate status & route name <rail>", "failure-context.txt")
        failure_steps = [node for run in activities["OutcomeTests/testMultipleFailuresInNestedStep()"]["testRuns"] for node in walk(run["activities"], "childActivities")]
        require(any(node["title"] == "Validate status & route name <rail>" and node.get("isAssociatedWithFailure") for node in failure_steps), "Lost failure-associated nested step")
        modern_markdown = zipfile.ZipFile(pages["ModernTests/modernAssertion()"]["archive"]).read("test.md").decode("utf-8")
        require("Montréal → Downtown <rail> & bus" in modern_markdown, "Modern failure Unicode/markup changed")

    media = {"videoOnly": set(), "imageOnly": set(), "videoAndImage": set(), "noMedia": set()}
    for key in EXPECTED_CASES:
        items = manifest.get(key, {}).get("attachments", [])
        video = any(Path(item["exportedFileName"]).suffix.lower() in {".mp4", ".mov", ".m4v"} for item in items)
        image = any(Path(item["exportedFileName"]).suffix.lower() in {".png", ".jpg", ".jpeg", ".heic", ".gif", ".tif", ".tiff"} for item in items)
        media["videoAndImage" if video and image else "videoOnly" if video else "imageOnly" if image else "noMedia"].add(key)
        if video:
            require(any(node.tag == "video" for node in pages[key]["document"].root.elements()), f"{key}: missing video element")
            for item in items:
                if Path(item["exportedFileName"]).suffix.lower() in {".mp4", ".mov", ".m4v"}:
                    require(local_path(report / "attachments", item["exportedFileName"]).stat().st_size > 0, "Recording must remain a nonempty streaming file")
    expected_media = load_json(fixture / f"{plan}.media.json")["categories"]
    require(media == {key: set(value) for key, value in expected_media.items()}, "Report changed actual media ownership/distribution")

    snapshots = load_json(report / "snapshots.json")
    comparisons = {comparison["name"]: (entry, comparison) for entry in snapshots["tests"] for comparison in entry["comparisons"]}
    require(snapshots["totalComparisons"] == 3 and set(comparisons) == {"RouteCard", "WideCard", "AliasedCard"}, "Missing snapshot role aliases/groups")
    require(snapshots["failedComparisons"] == (3 if mixed else 0), "Wrong matched/changed snapshot count")
    for name, (entry, comparison) in comparisons.items():
        require(canonical(entry["testIdentifier"]) in EXPECTED_CASES, "Comparison attached to unknown case")
        require(comparison["diffSynthesized"] == (name != "AliasedCard" or not mixed), "Supplied/synthesized diff classification changed")
        for role in ["expected", "actual", "diff"]:
            require(comparison[role] and local_path(report, comparison[role]["rootSrc"]).is_file(), f"Missing {role} snapshot image")
        require((comparison["changedPixels"] > 0) == mixed, "Unexpected snapshot pixel result")
    wide = comparisons["WideCard"][1]
    require((wide["actual"]["width"], wide["actual"]["height"]) == ((192, 112) if mixed else (160, 96)), "Resized snapshot dimensions lost")
    require(wide["sizeMismatch"] == mixed and wide["widthDelta"] == (32 if mixed else 0) and wide["heightDelta"] == (16 if mixed else 0), "Snapshot size deltas lost")
    if mixed:
        aliased_entry, aliased = comparisons["AliasedCard"]
        supplied = payload(report, pages, manifest, canonical(aliased_entry["testIdentifier"]), "AliasedCard.difference.png")[1]
        require(local_path(report, aliased["diff"]["rootSrc"]).read_bytes() == supplied, "Provided difference image was replaced")
        require("Newly failing (7)" in index.root.text, "Missing baseline comparison delta")
        require(all(any("previous-runs-table" in node.classes for node in page["document"].root.elements()) for page in pages.values()), "Missing prior runs in real detail pages")
        baseline_metadata = load_json(fixture / "reports" / "baseline" / "report_metadata.json")
        require(baseline_metadata["startTime"] < load_json(report / "report_metadata.json")["startTime"], "Fixture timestamps are not ordered")
    print(f"Verified {plan} report: {len(EXPECTED_CASES)} cases/pages/ZIPs; outcomes, retries, payload ownership, media, "
          "snapshots, history and touch-overlay timing.")


def check_failure_preservation(fixture, executable):
    for plan in ["Baseline", "Mixed"]:
        report = fixture / "reports" / plan.lower()
        source = fixture / f"{plan}.xcresult"
        require(not source.exists(), "Preservation check must run without the original xcresult")
        cache = report / "test_details.json"
        saved_cache = cache.read_bytes()
        fingerprints = {file.relative_to(report): hashlib.sha256(file.read_bytes()).digest()
                        for file in report.rglob("*") if file.is_file() and file != cache}
        try:
            cache.write_text("{", encoding="utf-8")
            args = [str(executable.resolve()), str(source), str(report), "--html-only"]
            if plan == "Mixed":
                args += ["--baseline", str(fixture / "reports" / "baseline")]
            result = subprocess.run(args, capture_output=True, text=True)
            (fixture / f"{plan.lower()}-failed-regeneration.log").write_text(result.stdout + result.stderr, encoding="utf-8")
            require(result.returncode != 0, f"{plan}: corrupt cache was accepted")
            current = {file.relative_to(report): hashlib.sha256(file.read_bytes()).digest()
                       for file in report.rglob("*") if file.is_file() and file != cache}
            require(current == fingerprints, f"{plan}: failed generation changed published artifacts")
        finally:
            cache.write_bytes(saved_cache)
    print("Verified corrupt-cache failures preserve every published report artifact.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixture_directory", type=Path)
    parser.add_argument("--check-failure-preservation", type=Path, metavar="EXECUTABLE")
    args = parser.parse_args()
    fixture = args.fixture_directory.resolve()
    try:
        for plan in ["Baseline", "Mixed"]:
            verify_report(fixture, plan)
        if args.check_failure_preservation:
            check_failure_preservation(fixture, args.check_failure_preservation)
    except (ValueError, KeyError, OSError, StopIteration, zipfile.BadZipFile, subprocess.SubprocessError) as error:
        print(f"Report fixture verification failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
