#!/usr/bin/env python3
"""Check a shipping report of Performance.xcresult against xcresulttool's own metrics export."""

import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile

from validate_reports import Document
from verify import PERFORMANCE_CASES, canonical, require

# Baseline checks XCTest failed, which the report must flag: test -> row class on the test page.
FLAGGED = {
    "PerformanceTests/testBaselineRegression()": "perf-row-regressed",
    "PerformanceTests/testOutlierMeasurement()": "perf-row-regressed",
    "PerformanceTests/testHighRelativeStandardDeviation()": "perf-row-noisy",
}
UNFLAGGED = {
    "PerformanceTests/testBaselineImprovement()",
    "PerformanceTests/testLegacyBaselineWithinTolerance()",
}


def run_report(executable, bundle, output, *extra):
    result = subprocess.run([str(executable), str(bundle), str(output), *extra], capture_output=True, text=True)
    require(result.returncode == 0, f"Report generation failed:\n{result.stdout[-2000:]}\n{result.stderr[-2000:]}")


def expected_metrics(bundle):
    exported = json.loads(subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", "metrics", "--path", str(bundle)],
        capture_output=True, text=True, check=True).stdout)
    return {canonical(test["testIdentifier"]): test for test in exported
            if any(run["metrics"] for run in test["testRuns"])}


def performance_section(document):
    sections = [node for node in document.root.elements() if node.attributes.get("id") == "performance"]
    require(len(sections) == 1, "Expected exactly one performance section")
    return sections[0]


def section_rows(section):
    """Rows of each per-run metric table, in order."""
    tables = [node for node in section.elements() if node.tag == "table" and "perf-table" in node.classes]
    return [[row for row in table.elements() if row.tag == "tr" and row.parent.tag == "tbody"] for table in tables]


def verify_report(report, expected):
    cached = {canonical(test["testIdentifier"]): test
              for test in json.loads((report / "performance_metrics.json").read_text(encoding="utf-8"))}
    require(cached == expected, "performance_metrics.json differs from xcresulttool's metrics export")
    require(set(expected) == set(PERFORMANCE_CASES), f"Unexpected metric tests: {set(expected) ^ set(PERFORMANCE_CASES)}")

    index = Document((report / "index.html").read_text(encoding="utf-8"))
    rows = {canonical(node.attributes["data-test-id"]): node for node in index.root.elements()
            if node.tag == "tr" and "data-test-id" in node.attributes}
    for key in expected:
        require(rows[key].attributes.get("data-performance") == "true", f"{key} lacks the performance marker")
    overview = [node for node in index.root.elements() if node.attributes.get("id") == "performance-overview"]
    require(len(overview) == 1, "Missing index performance overview")
    overview_rows = [node for node in overview[0].elements() if node.tag == "tr" and node.parent.tag == "tbody"]
    require(len(overview_rows) == sum(len(test["testRuns"]) for test in expected.values()),
            "The overview needs one row per test run")

    pages = {}
    for file in (report / "tests").glob("*.html"):
        document = Document(file.read_text(encoding="utf-8"))
        body = next(node for node in document.root.elements() if node.tag == "body")
        pages[canonical(body.attributes["data-test-id"])] = document

    for key, test in expected.items():
        section = performance_section(pages[key])
        tables = section_rows(section)
        runs = test["testRuns"]
        require(len(tables) == len(runs), f"{key}: expected {len(runs)} run tables, found {len(tables)}")
        for run, table in zip(runs, tables):
            names = [next(node for node in row.elements() if "perf-metric-name" in node.classes).text for row in table]
            require(names == [metric["displayName"] for metric in run["metrics"]], f"{key}: metric rows differ: {names}")
            for metric, row in zip(run["metrics"], table):
                dots = [node for node in row.elements() if node.tag == "circle" and "perf-chart-dot" in node.classes]
                require(len(dots) == len(metric["measurements"]), f"{key}: {metric['displayName']} chart lacks iterations")
        classes = {cls for table in tables for row in table for cls in row.classes}
        if key in FLAGGED:
            require(FLAGGED[key] in classes, f"{key}: XCTest failed a baseline check the report does not flag")
        if key in UNFLAGGED:
            require("perf-row-regressed" not in classes, f"{key}: flagged although XCTest accepted it")

    agent = (report / "agent-tests.md").read_text(encoding="utf-8")
    require(agent.count("\n## Performance\n") == len(expected), "Every metric test needs a Markdown performance section")
    summary = (report / "report.md").read_text(encoding="utf-8")
    require(f"## Performance ({len(expected)} tests)" in summary, "report.md lacks the performance summary")
    return {key: str(performance_section(document).text) for key, document in pages.items() if key in expected}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path, help="Performance.xcresult from generate.sh --performance")
    parser.add_argument("executable", type=Path, help="xctestreport executable")
    arguments = parser.parse_args()

    expected = expected_metrics(arguments.bundle)
    with tempfile.TemporaryDirectory(prefix="xctestreport-performance-") as temporary:
        root = Path(temporary)
        report = root / "report"
        run_report(arguments.executable, arguments.bundle, report)
        sections = verify_report(report, expected)

        # Regeneration must not need the source bundle: the metrics come from the report's cache.
        run_report(arguments.executable, root / "missing.xcresult", report, "--html-only")
        require(verify_report(report, expected) == sections, "HTML-only regeneration changed the performance sections")
    print(f"Verified performance report for {len(expected)} tests")


if __name__ == "__main__":
    try:
        main()
    except ValueError as error:
        print(f"Performance report validation failed: {error}", file=sys.stderr)
        sys.exit(1)
