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
            sourceLocationCandidateTexts: [test.details!],
            bundleFileName: "test_Suite_testFoo().zip"
        )

        XCTAssertEqual(summary, "Foo.swift:42: XCTAssertTrue failed - boom")
        XCTAssertTrue(markdown.contains("## Failure"))
        XCTAssertTrue(markdown.contains("XCTAssertTrue failed - boom"))
        XCTAssertTrue(markdown.contains("`Foo.swift:42`"), "Source location should be extracted")
        XCTAssertTrue(markdown.contains("- [0.000s] Start Test"))
        XCTAssertTrue(markdown.contains("  - [FAIL] [5.000s] Assertion Failure: boom"))
        XCTAssertTrue(markdown.allSatisfy { $0.isASCII }, "Markdown must be ASCII-only")
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
                markdownRelativePath: "agent-tests.md#Suite_testFoo__",
                markdown: "# testFoo()"),
            XCTestReport.AgentTestEntry(
                name: "testBar()", suite: "Suite", identifier: "Suite/testBar()",
                result: "Passed", duration: "1s", failureSummary: nil,
                markdownRelativePath: "agent-tests.md#Suite_testBar__",
                markdown: "# testBar()"),
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
        XCTAssertTrue(markdown.contains("[testFoo()](agent-tests.md#Suite_testFoo__)"))
        XCTAssertTrue(markdown.contains("boom failed"))
        XCTAssertTrue(markdown.contains("Suite - 1/2 passed"))
        XCTAssertTrue(markdown.allSatisfy { $0.isASCII }, "Report must be ASCII-only")
        XCTAssertFalse(
            markdown.contains("## Failed tests (1)\n\n| Test | Suite | Reason |\n| --- | --- | --- |\n|  |"),
            "Passed tests must not appear in the failed-tests table")
    }

    func testFailuresReportInlinesFailedTestsOnly() throws {
        let directory = try makeTempDirectory()
        let report = makeReport(outputDir: directory.path)
        let entries = [
            XCTestReport.AgentTestEntry(
                name: "testFoo()", suite: "Suite", identifier: "Suite/testFoo()",
                result: "Failed", duration: "5s", failureSummary: "boom failed",
                markdownRelativePath: "agent-tests.md#Suite_testFoo__",
                markdown: "# testFoo()\n\n## Failure\n\nboom\n\n- [shot](../attachments/foo.png)"),
            XCTestReport.AgentTestEntry(
                name: "testBar()", suite: "Suite", identifier: "Suite/testBar()",
                result: "Passed", duration: "1s", failureSummary: nil,
                markdownRelativePath: "agent-tests.md#Suite_testBar__",
                markdown: "# testBar()\n\nall good"),
        ]
        report.writeFailuresReport(
            summaryTitle: "My Suite",
            counts: XCTestReport.TestCounts(passedTests: 1, failedTests: 1, skippedTests: 0),
            result: "Failed",
            entries: entries,
            buildErrorCount: 0,
            buildWarningCount: 2,
            previousResultsDate: nil)

        let markdown = try String(
            contentsOf: directory.appendingPathComponent("failures.md"), encoding: .utf8)
        XCTAssertTrue(markdown.contains("# My Suite - Failed Tests"))
        XCTAssertTrue(markdown.contains("# testFoo()"), "Failed test detail must be inlined")
        XCTAssertTrue(markdown.contains("boom"))
        XCTAssertFalse(markdown.contains("all good"), "Passed tests must not appear")
        XCTAssertTrue(markdown.contains("[shot](attachments/foo.png)"),
            "Links must be rewritten relative to the output root")
        XCTAssertTrue(markdown.allSatisfy { $0.isASCII }, "Report must be ASCII-only")
    }

    func testFailuresReportZeroFailures() throws {
        let directory = try makeTempDirectory()
        let report = makeReport(outputDir: directory.path)
        let entries = [
            XCTestReport.AgentTestEntry(
                name: "testBar()", suite: "Suite", identifier: "Suite/testBar()",
                result: "Passed", duration: "1s", failureSummary: nil,
                markdownRelativePath: "agent-tests.md#Suite_testBar__",
                markdown: "# testBar()"),
        ]
        report.writeFailuresReport(
            summaryTitle: "My Suite",
            counts: XCTestReport.TestCounts(passedTests: 1, failedTests: 0, skippedTests: 0),
            result: "Passed",
            entries: entries,
            buildErrorCount: nil,
            buildWarningCount: nil,
            previousResultsDate: nil)

        let markdown = try String(
            contentsOf: directory.appendingPathComponent("failures.md"), encoding: .utf8)
        XCTAssertTrue(markdown.contains("No failed tests. 1 tests passed."))
    }

    func testNonAsciiContentIsFoldedToAscii() {
        let report = makeReport()
        let message = "XCTAssertEqual failed \u{2014} expected \u{201C}caf\u{00E9}\u{201D} but got \u{2018}x\u{2019}\u{2026}"
        let test = XCTestReport.TestNode(
            name: "testUnicode()",
            nodeType: "Test Case",
            nodeIdentifier: "Suite/testUnicode()",
            result: "Failed",
            duration: "1s",
            details: message,
            children: nil,
            startTime: nil
        )

        let (markdown, summary) = report.renderTestMarkdown(
            test: test,
            result: "Failed",
            suite: "Suite",
            testDetails: nil,
            testActivities: nil,
            attachmentsByTestIdentifier: [:],
            primaryFailureMessage: message,
            sourceLocationCandidateTexts: [],
            bundleFileName: "test_Suite_testUnicode().zip"
        )

        XCTAssertTrue(markdown.allSatisfy { $0.isASCII }, "Markdown must be ASCII-only")
        XCTAssertTrue(summary?.allSatisfy { $0.isASCII } ?? false)
        XCTAssertTrue(markdown.contains("expected \"caf?\" but got 'x'..."),
            "Typographic punctuation folds to ASCII; other non-ASCII becomes '?'")
    }

    func testAnchorLinkTargetsCombinedFile() {
        let report = makeReport()
        XCTAssertEqual(
            report.agentMarkdownAnchorLink(identifier: "Suite/testFoo()", name: "testFoo()"),
            "agent-tests.md#Suite_testFoo__")
        XCTAssertEqual(
            report.agentMarkdownAnchorLink(identifier: nil, name: "testFoo()"),
            "agent-tests.md#testFoo__")
        // Slashes and parentheses must not survive into the anchor.
        XCTAssertEqual(
            report.agentMarkdownAnchorLink(identifier: "A/B c-d.e()", name: "x"),
            "agent-tests.md#A_B_c-d.e__")
    }

    func testAgentTestsFileTableOfContentsPointsAtSectionMarkers() throws {
        let directory = try makeTempDirectory()
        let report = makeReport(outputDir: directory.path)
        let entries = (1...12).map { index -> XCTestReport.AgentTestEntry in
            let name = "test\(index)()"
            let suite = index % 2 == 0 ? "BetaSuite" : "AlphaSuite"
            let body = (0..<index).map { "line \($0)" }.joined(separator: "\n")
            return XCTestReport.AgentTestEntry(
                name: name, suite: suite, identifier: "\(suite)/\(name)",
                result: index % 3 == 0 ? "Failed" : (index % 3 == 1 ? "Passed" : "Skipped"),
                duration: "1s", failureSummary: nil,
                markdownRelativePath: report.agentMarkdownAnchorLink(
                    identifier: "\(suite)/\(name)", name: name),
                markdown: "# \(name)\n\n\(body)\n\n- [shot](../attachments/foo.png)")
        }

        report.writeAgentTestsFile(summaryTitle: "My Suite", entries: entries)

        let markdown = try String(
            contentsOf: directory.appendingPathComponent("agent-tests.md"), encoding: .utf8)
        let lines = markdown.components(separatedBy: "\n")
        XCTAssertTrue(markdown.hasPrefix("# My Suite - Per-test detail"))
        XCTAssertTrue(markdown.contains("## Tests (12)"))
        XCTAssertTrue(markdown.allSatisfy { $0.isASCII }, "File must be ASCII-only")
        XCTAssertTrue(
            markdown.contains("[shot](attachments/foo.png)"),
            "Links must be rewritten relative to the output root")

        let tocLines = lines.filter { $0.hasPrefix("- ") && $0.contains("Suite/test") }
        XCTAssertEqual(tocLines.count, 12)
        for tocLine in tocLines {
            let fields = tocLine.dropFirst(2).components(separatedBy: " ")
            let lineNumber = Int(fields[0])
            XCTAssertNotNil(lineNumber, "Table of contents must start with a line number")
            let status = fields[1]
            let identifier = fields[2]
            XCTAssertEqual(
                lines[lineNumber! - 1],
                "<!-- test:\(identifier) --><a id=\"\(identifier.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "(", with: "_").replacingOccurrences(of: ")", with: "_"))\"></a>",
                "Line \(lineNumber!) must be the marker for \(identifier)")
            XCTAssertEqual(lines[lineNumber! + 1], "## \(status) \(identifier)")
        }

        // Sections follow the "All suites" ordering: suite first, then test name.
        let order = tocLines.map { $0.components(separatedBy: " ").dropFirst(3).joined(separator: " ") }
        XCTAssertEqual(order, order.sorted())
    }

    func testBundledAttachmentsBecomeUnzipCommandsAndVideosStayLinks() {
        let report = makeReport()
        let test = XCTestReport.TestNode(
            name: "testFoo()",
            nodeType: "Test Case",
            nodeIdentifier: "Suite/testFoo()",
            result: "Passed",
            duration: "5s",
            details: nil,
            children: nil,
            startTime: nil
        )
        let attachments = [
            XCTestReport.AttachmentManifestItem(
                exportedFileName: "12.plist", isAssociatedWithFailure: nil,
                suggestedHumanReadableName: "UI Snapshot", timestamp: nil, payloadRefId: nil),
            XCTestReport.AttachmentManifestItem(
                exportedFileName: "13.mp4", isAssociatedWithFailure: nil,
                suggestedHumanReadableName: "Screen Recording", timestamp: nil, payloadRefId: nil),
        ]

        let (markdown, _) = report.renderTestMarkdown(
            test: test,
            result: "Passed",
            suite: "Suite",
            testDetails: nil,
            testActivities: nil,
            attachmentsByTestIdentifier: ["Suite/testFoo()": attachments],
            primaryFailureMessage: nil,
            sourceLocationCandidateTexts: [],
            bundleFileName: "test_Suite_testFoo().zip"
        )

        XCTAssertTrue(
            markdown.contains(
                "UI Snapshot - `unzip -p 'tests/test_Suite_testFoo().zip' attachments/12.plist`"),
            "Bundled attachments must carry an extraction command, not a dangling link")
        XCTAssertFalse(markdown.contains("](../attachments/12.plist)"))
        XCTAssertTrue(
            markdown.contains("[Screen Recording](../attachments/13.mp4)"),
            "Videos stay loose files, so they keep a plain link")
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
