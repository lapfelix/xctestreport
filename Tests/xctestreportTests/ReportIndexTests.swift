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
        let report = XCTestReport()
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

    private func makeRun(_ result: String) -> XCTestReport.TestRunDetail {
        return XCTestReport.TestRunDetail(
            children: nil, duration: "1s", name: "Run", nodeIdentifier: nil,
            nodeType: "Test Case Run", result: result)
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
