import Foundation
import XCTest

@testable import xctestreport

final class ReportIndexTests: XCTestCase {
    func testCompactDurationFormatting() {
        XCTAssertEqual(formatCompactDuration(0), "0s")
        XCTAssertEqual(formatCompactDuration(0.0004), "<1ms")
        XCTAssertEqual(formatCompactDuration(0.00057), "1ms")
        XCTAssertEqual(formatCompactDuration(0.026), "26ms")
        XCTAssertEqual(formatCompactDuration(0.9996), "1s")
        XCTAssertEqual(formatCompactDuration(12.34), "12.3s")
        XCTAssertEqual(formatCompactDuration(22), "22s")
        XCTAssertEqual(formatCompactDuration(219), "3m 39s")
        XCTAssertEqual(formatCompactDuration(600), "10m")
        XCTAssertEqual(formatCompactDuration(3605), "1h 0m 5s")
        XCTAssertEqual(formatCompactDuration(7200), "2h")
    }

    func testCompactDurationNeverShowsSixtySeconds() {
        XCTAssertEqual(formatCompactDuration(59.96), "1m")
        XCTAssertEqual(formatCompactDuration(119.6), "2m")
        XCTAssertEqual(formatCompactDuration(3599.7), "1h")
    }

    func testFlakyTestPassedAfterFailedAttempt() {
        let retried = [makeRun("Failed"), makeRun("Passed")]
        XCTAssertTrue(XCTestReport.isFlakyTest(result: "Passed", testRuns: retried))
        XCTAssertFalse(XCTestReport.isFlakyTest(result: "Failed", testRuns: retried))
        XCTAssertFalse(
            XCTestReport.isFlakyTest(result: "Passed", testRuns: [makeRun("Passed"), makeRun("Passed")]))
        XCTAssertFalse(XCTestReport.isFlakyTest(result: "Passed", testRuns: [makeRun("Failed")]))
        XCTAssertFalse(XCTestReport.isFlakyTest(result: "Passed", testRuns: nil))
    }

    func testMultiDestinationRunsFlattenToLabeledAttempts() throws {
        let details = try JSONDecoder().decode(
            XCTestReport.TestDetails.self,
            from: Data(
                """
                {"devices": [], "duration": "Average duration 4 minutes", "hasMediaAttachments": false,
                 "hasPerformanceMetrics": false, "testDescription": "Test case with 3 runs",
                 "testIdentifier": "Suite/testFoo()", "testName": "testFoo()",
                 "testPlanConfigurations": [], "testResult": "Passed",
                 "testRuns": [
                   {"name": "iPhone 16 Pro", "nodeType": "Device", "result": "Passed", "children": [
                     {"name": "Configuration 1", "duration": "13min", "nodeType": "Test Plan Configuration",
                      "result": "Passed", "children": [
                        {"name": "First Run", "duration": "10min", "nodeType": "Repetition", "result": "Failed",
                         "children": [{"name": "Timed out", "nodeType": "Test Case Run", "result": "Failed"}]},
                        {"name": "Retry 1", "duration": "3min", "nodeType": "Repetition", "result": "Passed"}
                     ]}
                   ]},
                   {"name": "iPhone 18 Pro", "nodeType": "Device", "result": "Passed", "children": [
                     {"name": "Configuration 1", "duration": "2min", "nodeType": "Test Plan Configuration",
                      "result": "Passed"}
                   ]}
                 ]}
                """.utf8))
        let runs = try XCTUnwrap(details.testRuns)

        XCTAssertEqual(runs.map(\.name), [
            "iPhone 16 Pro · Configuration 1 · First Run",
            "iPhone 16 Pro · Configuration 1 · Retry 1",
            "iPhone 18 Pro · Configuration 1",
        ])
        XCTAssertEqual(runs.map(\.duration), ["10min", "3min", "2min"])
        XCTAssertEqual(runs.first?.children?.first?.name, "Timed out")
        XCTAssertTrue(XCTestReport.isFlakyTest(result: "Passed", testRuns: runs))
    }

    func testFailureOnOneDestinationIsNotARetry() {
        let runs = [
            makeRun("Failed", destination: "iPhone 16 Pro"),
            makeRun("Passed", destination: "iPhone 18 Pro"),
        ]
        XCTAssertFalse(XCTestReport.isFlakyTest(result: "Passed", testRuns: runs))
    }

    func testPreviousRunDeltaListsNewlyFailingAndFixed() {
        let current = [
            makeTestNode("Suite/testBroke", result: "Failed"),
            makeTestNode("Suite/testFixed", result: "Passed"),
            makeTestNode("Suite/testStillFailing", result: "Failed"),
            makeTestNode("Suite/testNew", result: "Failed"),
            makeTestNode("Suite/testNowSkipped", result: "Skipped"),
        ]
        let previous: [String: XCTestReport.TestResult] = [
            "Suite/testBroke": .init(name: "testBroke", status: "Passed", duration: nil),
            "Suite/testFixed": .init(name: "testFixed", status: "Failed", duration: nil),
            "Suite/testStillFailing": .init(name: "testStillFailing", status: "Failed", duration: nil),
            "Suite/testNowSkipped": .init(name: "testNowSkipped", status: "Passed", duration: nil),
        ]

        let delta = XCTestReport.previousRunDelta(
            current: current, previous: previous, pagePath: { "tests/\($0.name).html" })

        XCTAssertEqual(delta.newlyFailing.map(\.identifier), ["Suite/testBroke"])
        XCTAssertEqual(delta.fixed.map(\.identifier), ["Suite/testFixed"])
        XCTAssertEqual(delta.newlyFailing.first?.pagePath, "tests/testBroke.html")
    }

    func testPreviousRunDeltaHTMLEscapesAndLinks() {
        let report = makeTestReport()
        let change = XCTestReport.PreviousRunChange(
            identifier: "Suite/test<A>", name: "test<A>", pagePath: "tests/a.html")
        let html = report.renderPreviousRunDeltaHTML(
            .init(newlyFailing: [change], fixed: []), dateHTML: "today")
        XCTAssertTrue(html.contains("<a href=\"tests/a.html\">test&lt;A&gt;</a>"))
        XCTAssertTrue(html.contains("Newly failing (1)"))
        XCTAssertFalse(html.contains("Fixed ("))

        let empty = report.renderPreviousRunDeltaHTML(.init(), dateHTML: "today")
        XCTAssertTrue(empty.contains("no status changes"))
    }

    private func makeRun(_ result: String, destination: String? = nil) -> XCTestReport.TestRunDetail {
        return XCTestReport.TestRunDetail(
            children: nil, duration: "1s", name: "Run", nodeIdentifier: nil,
            nodeType: "Test Case Run", result: result, destination: destination)
    }

    private func makeTestNode(_ identifier: String, result: String) -> XCTestReport.TestNode {
        return XCTestReport.TestNode(
            name: String(identifier.split(separator: "/").last ?? ""),
            nodeType: "Test Case",
            nodeIdentifier: identifier,
            result: result,
            duration: nil,
            details: nil,
            children: nil,
            startTime: nil
        )
    }
}
