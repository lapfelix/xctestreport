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
        let first = navigation[XCTestReport.testPageName(for: node("AlphaTests/testTwo()", result: "Failed"))]
        XCTAssertNil(first?.previous)
        XCTAssertEqual(first?.next?.pageName, XCTestReport.testPageName(for: node("AlphaTests/testOne()", result: "Failed")))
        XCTAssertEqual(first?.position, 1)
        XCTAssertEqual(first?.total, 3)

        let middle = navigation[XCTestReport.testPageName(for: node("AlphaTests/testOne()", result: "Failed"))]
        XCTAssertEqual(middle?.previous?.pageName, XCTestReport.testPageName(for: node("AlphaTests/testTwo()", result: "Failed")))
        XCTAssertEqual(middle?.next?.pageName, XCTestReport.testPageName(for: node("ZetaTests/testOne()", result: "Failed")))

        let last = navigation[XCTestReport.testPageName(for: node("ZetaTests/testOne()", result: "Failed"))]
        XCTAssertEqual(last?.previous?.testName, "testOne()")
        XCTAssertNil(last?.next)
        XCTAssertNil(navigation[XCTestReport.testPageName(for: node("AlphaTests/testPasses()", result: "Failed"))])
    }

    func testRenderedLinksAreEscapedAndOmittedForASingleFailure() {
        let report = XCTestReport()
        let single = XCTestReport.failureNavigation(for: [node("A/testA()", result: "Failed")])
        XCTAssertEqual(report.renderFailureNavigation(single[XCTestReport.testPageName(for: node("A/testA()", result: "Failed"))]), "")

        let navigation = XCTestReport.failureNavigation(for: [
            node("A/testA()", result: "Failed"), node("A/test<B>()", result: "Failed"),
        ])
        let html = report.renderFailureNavigation(navigation[XCTestReport.testPageName(for: node("A/testA()", result: "Failed"))])
        XCTAssertTrue(html.contains("Failure 1 of 2"), html)
        XCTAssertTrue(html.contains("href=\"\(XCTestReport.testPageName(for: node("A/test<B>()", result: "Failed")))\""), html)
        XCTAssertTrue(html.contains("Next failure: test&lt;B&gt;()"), html)
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
