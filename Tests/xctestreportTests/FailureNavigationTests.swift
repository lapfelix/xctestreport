import Foundation
import XCTest

@testable import xctestreport

final class FailureNavigationTests: XCTestCase {

    func testFailuresAreOrderedBySuiteNameThenRunOrder() {
        let tests = [
            node("ZetaTests/testOne()", result: "Failed"),
            node("AlphaTests/testTwo()", result: "Failed"),
            node("AlphaTests/testPasses()", result: "Passed"),
            node("AlphaTests/testOne()", result: "Failed"),
            node("AlphaTests/testSkipped()", result: "Skipped"),
        ]
        let navigation = XCTestReport.failureNavigation(for: tests)

        XCTAssertEqual(navigation.count, 3)
        let first = navigation["test_AlphaTests_testTwo().html"]
        XCTAssertNil(first?.previous)
        XCTAssertEqual(first?.next?.pageName, "test_AlphaTests_testOne().html")
        XCTAssertEqual(first?.position, 1)
        XCTAssertEqual(first?.total, 3)

        let middle = navigation["test_AlphaTests_testOne().html"]
        XCTAssertEqual(middle?.previous?.pageName, "test_AlphaTests_testTwo().html")
        XCTAssertEqual(middle?.next?.pageName, "test_ZetaTests_testOne().html")

        let last = navigation["test_ZetaTests_testOne().html"]
        XCTAssertEqual(last?.previous?.testName, "testOne()")
        XCTAssertNil(last?.next)
        XCTAssertNil(navigation["test_AlphaTests_testPasses().html"])
    }

    func testRenderedLinksAreEscapedAndOmittedForASingleFailure() {
        let report = XCTestReport()
        let single = XCTestReport.failureNavigation(for: [node("A/testA()", result: "Failed")])
        XCTAssertEqual(report.renderFailureNavigation(single["test_A_testA().html"]), "")

        let navigation = XCTestReport.failureNavigation(for: [
            node("A/testA()", result: "Failed"), node("A/test<B>()", result: "Failed"),
        ])
        let html = report.renderFailureNavigation(navigation["test_A_testA().html"])
        XCTAssertTrue(html.contains("Failure 1 of 2"), html)
        XCTAssertTrue(html.contains("href=\"test_A_test&lt;B&gt;().html\""), html)
        XCTAssertTrue(html.contains("rel=\"next\""), html)
        XCTAssertFalse(html.contains("rel=\"prev\""), html)
    }

    private func node(_ identifier: String, result: String) -> XCTestReport.TestNode {
        XCTestReport.TestNode(
            name: (identifier as NSString).lastPathComponent, nodeType: "Test Case",
            nodeIdentifier: identifier, result: result, duration: "1s", details: nil,
            children: nil, startTime: nil)
    }
}
