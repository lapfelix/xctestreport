import Foundation
import XCTest

@testable import xctestreport

final class AgentMarkdownTests: XCTestCase {
    func testFailedTestMarkdownContainsFailureSourceAndSteps() {
        let report = makeReport()
        let test = XCTestReport.TestNode(
            name: "testFoo()",
            nodeType: "Test Case",
            nodeIdentifier: "Suite/testFoo()",
            result: "Failed",
            duration: "5s",
            details: "Foo.swift:42: XCTAssertTrue failed - boom",
            children: nil,
            startTime: nil
        )
        let activities = XCTestReport.TestActivities(
            testIdentifier: "Suite/testFoo()",
            testRuns: [
                XCTestReport.TestActivityRun(activities: [
                    activity(title: "Start Test", start: 100.0, children: [
                        activity(title: "Assertion Failure: boom", start: 105.0, failure: true)
                    ])
                ])
            ]
        )

        let (markdown, summary) = report.renderTestMarkdown(
            test: test,
            result: "Failed",
            suite: "Suite",
            testDetails: nil,
            testActivities: activities,
            attachmentsByTestIdentifier: [:],
            primaryFailureMessage: test.details,
            sourceLocationCandidateTexts: [test.details!]
        )

        XCTAssertEqual(summary, "Foo.swift:42: XCTAssertTrue failed - boom")
        XCTAssertTrue(markdown.contains("## Failure"))
        XCTAssertTrue(markdown.contains("XCTAssertTrue failed - boom"))
        XCTAssertTrue(markdown.contains("`Foo.swift:42`"), "Source location should be extracted")
        XCTAssertTrue(markdown.contains("- [0.000s] Start Test"))
        XCTAssertTrue(markdown.contains("  - ❌ [5.000s] Assertion Failure: boom"))
        // Parens in the HTML detail filename must be angle-bracketed so the link parses.
        XCTAssertTrue(markdown.contains("[HTML detail](<../tests/test_Suite_testFoo().html>)"))
    }

    func testIndexListsFailedTestsWithReasons() throws {
        let directory = try makeTempDirectory()
        let report = makeReport(outputDir: directory.path)
        let entries = [
            XCTestReport.AgentTestEntry(
                name: "testFoo()", suite: "Suite", identifier: "Suite/testFoo()",
                result: "Failed", duration: "5s", failureSummary: "boom failed",
                markdownRelativePath: "agent-tests/Suite_testFoo__.md"),
            XCTestReport.AgentTestEntry(
                name: "testBar()", suite: "Suite", identifier: "Suite/testBar()",
                result: "Passed", duration: "1s", failureSummary: nil,
                markdownRelativePath: "agent-tests/Suite_testBar__.md"),
        ]
        report.writeAgentReport(
            summaryTitle: "My Suite",
            counts: XCTestReport.TestCounts(passedTests: 1, failedTests: 1, skippedTests: 0),
            result: "Failed",
            entries: entries,
            buildErrorCount: 0,
            buildWarningCount: 2,
            previousResultsDate: nil)

        let markdown = try String(
            contentsOf: directory.appendingPathComponent("report.md"), encoding: .utf8)
        XCTAssertTrue(markdown.contains("## Failed tests (1)"))
        XCTAssertTrue(markdown.contains("[testFoo()](agent-tests/Suite_testFoo__.md)"))
        XCTAssertTrue(markdown.contains("boom failed"))
        XCTAssertTrue(markdown.contains("Suite — 1/2 passed"))
        XCTAssertFalse(
            markdown.contains("## Failed tests (1)\n\n| Test | Suite | Reason |\n| --- | --- | --- |\n|  |"),
            "Passed tests must not appear in the failed-tests table")
    }

    func testMarkdownFileNameIsFilesystemSafe() {
        let report = makeReport()
        let name = report.agentMarkdownFileName(
            identifier: "Suite/testFoo()", name: "testFoo()")
        XCTAssertEqual(name, "Suite_testFoo__.md")
    }

    // MARK: - Helpers

    private func activity(
        title: String, start: Double, failure: Bool = false,
        children: [XCTestReport.TestActivity] = []
    ) -> XCTestReport.TestActivity {
        XCTestReport.TestActivity(
            title: title,
            startTime: start,
            isAssociatedWithFailure: failure ? true : nil,
            attachments: nil,
            childActivities: children.isEmpty ? nil : children,
            failureBranchStyle: nil)
    }

    private func makeReport(outputDir: String = NSTemporaryDirectory()) -> XCTestReport {
        var report = XCTestReport()
        report.xcresultPath = ""
        report.outputDir = outputDir
        return report
    }

    private func makeTempDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("agentmd-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
