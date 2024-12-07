#!/usr/bin/env swift

import Foundation
import ArgumentParser

// MARK: - Command-Line Interface

struct XCTestReport: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xctestreport",
        abstract: "A utility to generate simple HTML reports from XCTest results."
    )

    @Argument(help: "Path to the .xcresult file.")
    var xcresultPath: String

    @Argument(help: "Output directory for the HTML report.")
    var outputDir: String

    struct RuntimeError: Error {
        let message: String
    }

    func run() throws {
        // MARK: - Structures
        struct Summary: Decodable {
            let title: String
            let startTime: Double
            let finishTime: Double
            let environmentDescription: String
            let topInsights: [InsightSummary]
            let result: String
            let totalTestCount: Int
            let passedTests: Int
            let failedTests: Int
            let skippedTests: Int
            let expectedFailures: Int
            let statistics: [Statistic]
            let devicesAndConfigurations: [DeviceAndConfigurationSummary]
            let testFailures: [TestFailure]
        }

        struct InsightSummary: Decodable {
            let impact: String
            let category: String
            let text: String
        }

        struct Statistic: Decodable {
            let title: String
            let subtitle: String
        }

        struct DeviceAndConfigurationSummary: Decodable {
            let device: Device
            let testPlanConfiguration: Configuration
            let passedTests: Int
            let failedTests: Int
            let skippedTests: Int
            let expectedFailures: Int
        }

        struct Device: Decodable {
            let deviceId: String?
            let deviceName: String
            let architecture: String
            let modelName: String
            let platform: String?
            let osVersion: String
        }

        struct Configuration: Decodable {
            let configurationId: String
            let configurationName: String
        }

        struct TestFailure: Decodable {
            let testName: String
            let targetName: String
            let failureText: String
            let testIdentifier: Int
        }

        struct FullTestResults: Decodable {
            let devices: [Device]
            let testNodes: [TestNode]
            let testPlanConfigurations: [TestPlanConfiguration]
        }

        struct TestNode: Decodable {
            let name: String
            let nodeType: String
            let nodeIdentifier: String?
            let result: String
            let duration: String?
            let details: String?
            let children: [TestNode]?

            enum CodingKeys: String, CodingKey {
                case name
                case nodeType
                case nodeIdentifier
                case result
                case duration
                case details
                case children
            }
        }

        struct TestPlanConfiguration: Decodable {
            let configurationId: String
            let configurationName: String
        }

        struct TestDetails: Decodable {
            let devices: [Device]
            let duration: String
            let hasMediaAttachments: Bool
            let hasPerformanceMetrics: Bool
            let startTime: Double
            let testDescription: String
            let testIdentifier: String
            let testName: String
            let testPlanConfigurations: [TestPlanConfiguration]
            let testResult: String
            let testRuns: [TestRunDetail]
        }

        struct TestRunDetail: Decodable {
            let children: [TestRunChild]?
            let duration: String
            let name: String
            let nodeIdentifier: String
            let nodeType: String
            let result: String
        }

        struct TestRunChild: Decodable {
            let children: [TestRunChildDetail]?
            let name: String
            let nodeType: String
            let result: String
        }

        struct TestRunChildDetail: Decodable {
            let name: String
            let nodeType: String
        }

        func shell(_ args: [String], outputFile: String? = nil, captureOutput: Bool = true) -> (String?, Int32) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            task.arguments = args

            if let outputFile = outputFile {
                let outputURL = URL(fileURLWithPath: outputFile)
                if FileManager.default.fileExists(atPath: outputFile) {
                    try? FileManager.default.removeItem(at: outputURL)
                }
                FileManager.default.createFile(atPath: outputFile, contents: nil, attributes: nil)
                if let fileHandle = try? FileHandle(forWritingTo: outputURL) {
                    task.standardOutput = fileHandle
                    task.standardError = fileHandle
                } else {
                    print("Failed to open file for writing: \(outputFile)")
                    return (nil, 1)
                }
            } else if captureOutput {
                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = pipe
            } else {
                task.standardOutput = nil
                task.standardError = nil
            }

            do { try task.run() } catch { return (nil, 1) }
            task.waitUntilExit()

            var output: String? = nil
            if captureOutput, let pipe = task.standardOutput as? Pipe {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                output = String(data: data, encoding: .utf8)
            }
            return (output, task.terminationStatus)
        }

        func getTestDetails(for testIdentifier: String) -> TestDetails? {
            let testDetailsCmd = ["xcrun", "xcresulttool", "get", "test-results", "test-details", "--test-id", testIdentifier, "--path", xcresultPath, "--format", "json", "--compact"]
            let (testDetailsJSON, exitCode) = shell(testDetailsCmd)
            guard exitCode == 0, let data = testDetailsJSON?.data(using: .utf8) else {
                return nil
            }
            let decoder = JSONDecoder()
            return try? decoder.decode(TestDetails.self, from: data)
        }

        try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

        // Get summary
        let summaryCmd = ["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", xcresultPath, "--compact"]
        let (summaryJSON, summaryExit) = shell(summaryCmd)
        guard summaryExit == 0, let summaryData = summaryJSON?.data(using: .utf8) else {
            print("Failed to get test summary.")
            throw RuntimeError(message: "Failed to get test summary.")
        }

        let decoder = JSONDecoder()
        let summary: Summary
        do {
            summary = try decoder.decode(Summary.self, from: summaryData)
        } catch {
            print("Decode summary error: \(error)")
            throw RuntimeError(message: "Failed to decode test summary.")
        }

        // Get full JSON
        print("Getting full results...")
        let fullJSONPath = (outputDir as NSString).appendingPathComponent("tests_full.json")
        try? FileManager.default.removeItem(atPath: fullJSONPath)
        let fullCmd = ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", xcresultPath]
        print("Running: \(fullCmd.joined(separator: " "))")
        let (_, fullExit) = shell(fullCmd, outputFile: fullJSONPath, captureOutput: false)
        print("Full results exit code: \(fullExit)")

        guard fullExit == 0 else {
            print("Failed to get full results. Exit code: \(fullExit)")
            throw RuntimeError(message: "Failed to get full results.")
        }

        let fullData = try Data(contentsOf: URL(fileURLWithPath: fullJSONPath))
        print("Parsing full results...")
        print("Full JSON size: \(fullData.count) bytes")

        let fullResults: FullTestResults
        do {
            fullResults = try decoder.decode(FullTestResults.self, from: fullData)
        } catch {
            print("Decode full JSON error: \(error)")
            throw RuntimeError(message: "Failed to decode full results.")
        }

        var allTests = [TestNode]()

        func collectTestNodes(_ nodes: [TestNode]) {
            for node in nodes {
                if node.nodeType == "Test Case" {
                    allTests.append(node)
                }
                if let childNodes = node.children {
                    collectTestNodes(childNodes)
                }
            }
        }

        collectTestNodes(fullResults.testNodes)

        let groupedTests = Dictionary(grouping: allTests) { test -> String in
            if let identifier = test.nodeIdentifier, let suite = identifier.split(separator: "/").first {
                return String(suite)
            }
            return "Unknown Suite"
        }

        print("Generating HTML report...")

        var indexHTML = """
        <!DOCTYPE html>
        <html>
        <head>
        <title>Test Report</title>
        <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "San Francisco", "Helvetica Neue", Helvetica, Arial, sans-serif;
            color: #333;
            margin: 20px;
            background: #F9F9F9;
        }
        h1, h2, h3 {
            font-weight: 600;
            color: #000;
        }
        table {
            border-collapse: collapse;
            width: 100%;
            margin-top: 20px;
            background: #FFF;
            border: 1px solid #DDD;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
            table-layout: fixed;
        }
        th, td {
            text-align: left;
            padding: 12px;
            border-bottom: 1px solid #EEE;
            word-wrap: break-word;
        }
        th {
            background: #F2F2F2;
            font-weight: 600;
        }
        th:nth-child(1), td:nth-child(1) {
            width: 60%;
        }
        th:nth-child(2), td:nth-child(2) {
            width: 20%;
        }
        th:nth-child(3), td:nth-child(3) {
            width: 20%;
        }
        tr.failed {
            background-color: #f8d7da;
        }
        a {
            color: #0077EE;
            text-decoration: none;
        }
        a:hover {
            text-decoration: underline;
        }
        .passed {
            color: #28A745;
            font-weight: 600;
        }
        .failed {
            color: #DC3545;
            font-weight: 600;
        }
        </style>
        </head>
        <body>
        <h1>Test Report: \(summary.title)</h1>
        <p>Total: \(summary.totalTestCount), Passed: \(summary.passedTests), Failed: \(summary.failedTests), Skipped: \(summary.skippedTests)</p>
        """

        for suite in groupedTests.keys.sorted() {
            let tests = groupedTests[suite]!
            let succeeded = tests.filter { $0.result == "Passed" }.count
            let total = tests.count
            indexHTML += "<h2 class=\"collapsible\">\(suite) (\(succeeded)/\(total) Passed)</h2>"
            indexHTML += """
            <table>
            <tr><th>Test Name</th><th>Status</th><th>Duration</th></tr>
            """
            for test in tests {
                let testPageName = "test_\(test.nodeIdentifier ?? test.name).html".replacingOccurrences(of: "/", with: "_")
                let statusClass = test.result == "Passed" ? "passed" : "failed"
                let duration = test.duration ?? "0s"
                let rowClass = test.result == "Passed" ? "" : " class=\"failed\""
                indexHTML += "<tr\(rowClass)><td><a href=\"\(testPageName)\">\(test.name)</a></td><td class=\"\(statusClass)\">\(test.result)</td><td>\(duration)</td></tr>"
            }
            indexHTML += "</table>"
        }

        indexHTML += "</body></html>"

        for test in allTests {
            let testPageName = "test_\(test.nodeIdentifier ?? test.name).html".replacingOccurrences(of: "/", with: "_")
            let statusClass = test.result == "Passed" ? "passed" : "failed"
            let duration = test.duration ?? "0s"

            var failureInfo = ""
            if test.result != "Passed", let details = test.details {
                failureInfo = "<p><strong>Details:</strong> \(details)</p>"
            }

            var testDetails: TestDetails?
            if let testIdentifier = test.nodeIdentifier {
                testDetails = getTestDetails(for: testIdentifier)
            }

            if let testDetails = testDetails {
                let testDescription = testDetails.testDescription
                let testResult = testDetails.testResult
                let testRuns = testDetails.testRuns.map { run in
                    let runDetails = run.children?.map { child in
                        let childDetails = child.children?.map { detail in
                            return "<li><code>\(detail.name)</code></li>"
                        }.joined(separator: "") ?? ""
                        return "<li>\(child.name) (\(child.nodeType)): \(child.result)<ul>\(childDetails)</ul></li>"
                    }.joined(separator: "") ?? ""
                    return "<li>\(run.name) (\(run.nodeType)): \(run.result)<ul>\(runDetails)</ul></li>"
                }.joined(separator: "")

                failureInfo += """
                <p><strong>Test Description:</strong> \(testDescription)<br>
                <strong>Test Result:</strong> \(testResult)</p>
                <ul>\(testRuns)</ul>
                """
            }

            let testDetailHTML = """
            <!DOCTYPE html>
            <html>
            <head>
            <title>Test Detail: \(test.name)</title>
            <style>
            body {
                font-family: -apple-system, BlinkMacSystemFont, "San Francisco", "Helvetica Neue", Helvetica, Arial, sans-serif;
                color: #333;
                margin: 20px;
                background: #F9F9F9;
            }
            h1, h2, h3 {
                font-weight: 600;
                color: #000;
            }
            a {
                color: #0077EE;
                text-decoration: none;
            }
            a:hover {
                text-decoration: underline;
            }
            .passed {
                color: #28A745;
                font-weight: 600;
            }
            .failed {
                color: #DC3545;
                font-weight: 600;
            }
            </style>
            </head>
            <body>
            <h1>\(test.name)</h1>
            <p>Status: <span class="\(statusClass)">\(test.result)</span><br>Duration: \(duration)</p>
            \(failureInfo)
            <p><a href="index.html">Back to index</a></p>
            </body>
            </html>
            """
            let testPagePath = (outputDir as NSString).appendingPathComponent(testPageName)
            try testDetailHTML.write(toFile: testPagePath, atomically: true, encoding: .utf8)
        }

        let indexPath = (outputDir as NSString).appendingPathComponent("index.html")
        try indexHTML.write(toFile: indexPath, atomically: true, encoding: .utf8)

        print("HTML report generated at \(indexPath)")
    }
}

XCTestReport.main()