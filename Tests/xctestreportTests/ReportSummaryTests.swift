import Foundation
import XCTest

@testable import xctestreport

final class ReportSummaryTests: XCTestCase {
    func testTestCountsExcludeSkippedFromTotalAndPassRate() {
        let counts = XCTestReport.testCounts(for: [
            makeTestNode(name: "testPassedOne", result: "Passed"),
            makeTestNode(name: "testPassedTwo", result: "Passed"),
            makeTestNode(name: "testFailed", result: "Failed"),
            makeTestNode(name: "testSkippedOne", result: "Skipped"),
            makeTestNode(name: "testSkippedTwo", result: "Skipped"),
        ])

        XCTAssertEqual(counts.passedTests, 2)
        XCTAssertEqual(counts.failedTests, 1)
        XCTAssertEqual(counts.skippedTests, 2)
        XCTAssertEqual(counts.totalTests, 3)
        XCTAssertEqual(counts.rawTotalTests, 5)
        XCTAssertEqual(counts.percentagePassed, 66.6667, accuracy: 0.001)
    }

    func testSkippedResultsAreNotTreatedAsFailures() {
        XCTAssertFalse(XCTestReport.isFailureTestResult("Passed"))
        XCTAssertFalse(XCTestReport.isFailureTestResult("Skipped"))
        XCTAssertTrue(XCTestReport.isFailureTestResult("Failed"))
        XCTAssertTrue(XCTestReport.isFailureTestResult(nil))
    }

    func testIndexTemplateClarifiesTotalExcludesSkippedTests() throws {
        let template = try loadProjectFile("Sources/xctestreport/Resources/Web/templates/index.html")

        XCTAssertTrue(
            template.contains("Total (excl. skipped): <span class=\"stat-number\">{{total_tests}}</span>"),
            "Index summary should explain that the displayed total excludes skipped tests."
        )
    }

    func testSkippedStylesUseAmberPresentation() throws {
        let css = try loadProjectFile("Sources/xctestreport/Resources/Web/report.css")

        XCTAssertTrue(
            ruleBodies(for: ".status-skipped", in: css).contains(where: {
                $0.contains("background-color: #fff3cd;") && $0.contains("color: #8d6e00;")
            }),
            "Skipped badge should use amber styling instead of failure styling."
        )
        XCTAssertTrue(
            ruleBodies(for: "tr.skipped", in: css).contains(where: {
                $0.contains("background-color: #fff8e1;")
            }),
            "Skipped rows should use a non-failure background."
        )
    }

    private func makeTestNode(name: String, result: String?) -> XCTestReport.TestNode {
        return XCTestReport.TestNode(
            name: name,
            nodeType: "Test Case",
            nodeIdentifier: "Suite/\(name)",
            result: result,
            duration: nil,
            details: nil,
            children: nil,
            startTime: nil
        )
    }

    private func loadProjectFile(_ relativePath: String) throws -> String {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fileURL = projectRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private func ruleBodies(for selector: String, in css: String) -> [String] {
        let escapedSelector = NSRegularExpression.escapedPattern(for: selector)
        let pattern = "(?s)" + escapedSelector + "\\s*\\{(.*?)\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(location: 0, length: css.utf16.count)
        let nsCSS = css as NSString
        return regex.matches(in: css, options: [], range: range).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            return nsCSS.substring(with: match.range(at: 1))
        }
    }
}
