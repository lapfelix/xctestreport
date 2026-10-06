import XCTest

@testable import xctestreport

final class ReviewNotesTests: XCTestCase {
    func testReportIDIsStableForOneRunAndDiffersBetweenRuns() {
        let first = XCTestReport.reviewNotesReportID(title: "Run", startTime: 100, finishTime: 200)
        XCTAssertEqual(first, XCTestReport.reviewNotesReportID(title: "Run", startTime: 100, finishTime: 200))
        XCTAssertNotEqual(first, XCTestReport.reviewNotesReportID(title: "Run", startTime: 101, finishTime: 200))
        XCTAssertNotEqual(first, XCTestReport.reviewNotesReportID(title: "Other", startTime: 100, finishTime: 200))
    }

    func testPagesCarryEscapedNotesAttributesAndScript() {
        var report = XCTestReport()
        report.noNotes = false
        XCTAssertEqual(
            report.reviewNotesBodyAttributes(
                reportID: "abc", reportRoot: "../", extra: [("data-test-id", "Suite/test\"x\"()")]),
            " data-report-id=\"abc\" data-report-root=\"../\" data-test-id=\"Suite/test&quot;x&quot;()\"")
        XCTAssertEqual(
            report.reviewNotesScriptHTML(webDirectory: "../web"),
            "<script src=\"../web/notes.js\" defer></script>")
    }

    func testNoNotesLeavesPagesUntouched() {
        var report = XCTestReport()
        report.noNotes = true
        XCTAssertEqual(report.reviewNotesBodyAttributes(reportID: "abc", reportRoot: "./"), "")
        XCTAssertEqual(report.reviewNotesScriptHTML(webDirectory: "web"), "")
    }
}
