#!/usr/bin/env swift

import Foundation
import ArgumentParser

// MARK: - Command-Line Interface

struct XCTestReport: ParsableCommand {
    @Argument(help: "Path to the .xcresult file.")
    var xcresultPath: String

    @Argument(help: "Output directory for the HTML report.")
    var outputDir: String

    struct RuntimeError: Error {
        let message: String
    }

    func run() throws {
        // Existing main logic goes here
        // You can move all existing code inside this run() method

        // MARK: - Structures (adjust as needed)
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

        // Additional structures
        struct TopLevel: Decodable {
            let testPlanRunSummaries: TestPlanRunSummaries?
            let issues: Issues?
        }

        struct TestPlanRunSummaries: Decodable {
            let summaries: [TestPlanRunSummary]
        }

        struct TestPlanRunSummary: Decodable {
            let testableSummaries: [TestableSummary]
        }

        struct TestableSummary: Decodable {
            let tests: [TestSummaryGroup]
        }

        struct TestSummaryGroup: Decodable {
            let name: String
            let subtests: [TestSummary]
        }

        struct TestSummary: Decodable {
            let name: String
            let identifier: String
            let testStatus: String
            let duration: Double?
            let subtests: [TestSummary]?
            let activitySummaries: [ActivitySummary]?
        }

        struct ActivitySummary: Decodable {
            let title: String?
            let attachments: [Attachment]?
        }

        struct Attachment: Decodable {
            let filename: String?
            let uniformTypeIdentifier: String?
            let payloadRef: PayloadRef?
        }

        struct PayloadRef: Decodable {
            let id: String
        }

        struct Issues: Decodable {
            let testFailureSummaries: [TestFailureSummary]?
        }

        struct TestFailureSummary: Decodable {
            let message: String
            let producingTarget: String?
            let fileName: String?
            let lineNumber: Int?
            let testCaseName: String?
        }

        // MARK: - Structures for full JSON

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
            var attachments: [TestAttachment] = []

            // CodingKeys to exclude 'attachments' from the Decodable protocol
            enum CodingKeys: String, CodingKey {
                case name
                case nodeType
                case nodeIdentifier
                case result
                case duration
                case details
                case children
                // Do not include 'attachments' here
            }
        }

        // Define TestPlanConfiguration struct
        struct TestPlanConfiguration: Decodable {
            let configurationId: String
            let configurationName: String
        }

        // Rename Attachment struct to TestAttachment to avoid conflict
        struct TestAttachment {
            let filename: String
            let uniformTypeIdentifier: String?
            let payloadId: String
        }

        // Define structures for decoding the activities JSON
        struct ActivitiesResponse: Decodable {
            let testIdentifier: String
            let testName: String
            let testRuns: [TestRun]
        }

        struct TestRun: Decodable {
            let activities: [Activity]
            let device: Device
            let testPlanConfiguration: TestPlanConfiguration
        }

        struct Activity: Decodable {
            let title: String
            let startTime: Double?
            let attachments: [ActivityAttachment]?
            let childActivities: [Activity]?
        }

        struct ActivityAttachment: Decodable {
            let name: String
            let payloadId: String
            let uniformTypeIdentifier: String?
            let timestamp: Double?
            let lifetime: String
            let uuid: String
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

        // MARK: - Helpers
        func shell(_ args: [String], outputFile: String? = nil, captureOutput: Bool = true) -> (String?, Int32) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            task.arguments = args

            if let outputFile = outputFile {
                let outputURL = URL(fileURLWithPath: outputFile)
                // Ensure the output file does not exist
                if FileManager.default.fileExists(atPath: outputFile) {
                    try? FileManager.default.removeItem(at: outputURL)
                }
                // Create the file
                FileManager.default.createFile(atPath: outputFile, contents: nil, attributes: nil)
                // Open the file for writing
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

        func collectTestSummaries(_ tests: [TestSummary]) -> [TestSummary] {
            var all = [TestSummary]()
            for t in tests {
                if let subs = t.subtests, !subs.isEmpty {
                    all.append(contentsOf: collectTestSummaries(subs))
                } else {
                    all.append(t)
                }
            }
            return all
        }

        func exportAttachment(xcresultPath: String, payloadId: String, outDir: String, filename: String?) -> String? {
            let fname = filename ?? payloadId
            let outPath = (outDir as NSString).appendingPathComponent(fname)
            let exportCmd = ["xcrun", "xcresulttool", "export", "--type", "file", "--path", xcresultPath, "--id", payloadId, "--output", outPath]
            print("Exporting attachment: \(exportCmd.joined(separator: " "))")
            let (data, exitCode) = shell(exportCmd)
            print("Export exit code: \(exitCode)")
            print("Export output: \(data ?? "")")
            return exitCode == 0 ? fname : nil
        }

        // Update the getActivities function to retrieve activities for a test case
        func getActivities(for testIdentifier: String) -> [Activity]? {
            let activitiesCmd = ["xcrun", "xcresulttool", "get", "test-results", "activities", "--test-id", testIdentifier, "--path", xcresultPath, "--format", "json", "--compact"]
            let (activitiesJSON, exitCode) = shell(activitiesCmd)
            guard exitCode == 0, let data = activitiesJSON?.data(using: .utf8) else {
                print("Failed to get activities for test \(testIdentifier)")
                return nil
            }
            let decoder = JSONDecoder()
            do {
                let activitiesResponse = try decoder.decode(ActivitiesResponse.self, from: data)
                return activitiesResponse.testRuns.first?.activities
            } catch {
                print("Error decoding activities for test \(testIdentifier): \(error)")
                return nil
            }
        }

        // Implement collectAttachments function
        func collectAttachments(from activities: [Activity]) -> [TestAttachment] {
            var attachments = [TestAttachment]()
            for activity in activities {
                // Collect attachments at this level
                if let activityAttachments = activity.attachments {
                    for att in activityAttachments {
                        let attachment = TestAttachment(filename: att.name, uniformTypeIdentifier: att.uniformTypeIdentifier, payloadId: att.payloadId)
                        attachments.append(attachment)
                    }
                }
                // Recursively collect attachments from child activities
                if let childActivities = activity.childActivities {
                    attachments.append(contentsOf: collectAttachments(from: childActivities))
                }
            }
            return attachments
        }

        func getTestDetails(for testIdentifier: String) -> TestDetails? {
            let testDetailsCmd = ["xcrun", "xcresulttool", "get", "test-results", "test-details", "--test-id", testIdentifier, "--path", xcresultPath, "--format", "json", "--compact"]

            let (testDetailsJSON, exitCode) = shell(testDetailsCmd)
            guard exitCode == 0, let data = testDetailsJSON?.data(using: .utf8) else {
                print("Failed to get test details for test \(testIdentifier)")
                return nil
            }
            let decoder = JSONDecoder()
            do {
                let testDetails = try decoder.decode(TestDetails.self, from: data)
                return testDetails
            } catch {
                print("Error decoding test details for test \(testIdentifier): \(error)")
                return nil
            }
        }

        // MARK: - Main
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

        // Remove if it exists
        try? FileManager.default.removeItem(atPath: fullJSONPath)

        let fullCmd = ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", xcresultPath]
        print("Running: \(fullCmd.joined(separator: " "))")
        let (_, fullExit) = shell(fullCmd, outputFile: fullJSONPath, captureOutput: false)
        print("Full results exit code: \(fullExit)")

        guard fullExit == 0 else {
            print("Failed to get full results. Exit code: \(fullExit)")
            throw RuntimeError(message: "Failed to get full results.")
        }

        // Now read the data from the file
        let fullData = try Data(contentsOf: URL(fileURLWithPath: fullJSONPath))

        print("Parsing full results...")

        print("Full JSON size: \(fullData.count) bytes")

        //let fullJsonAsDict = try JSONSerialization.jsonObject(with: fullData, options: []) as? [String: Any]
        //print ("Full JSON:\n\(fullJsonAsDict)")

        let fullResults: FullTestResults
        do {
            fullResults = try decoder.decode(FullTestResults.self, from: fullData)
        } catch {
            print("Decode full JSON error: \(error)")
            throw RuntimeError(message: "Failed to decode full results.")
        }

        // Update the processing logic to use the recursive 'TestNode' structure

        var allTests = [TestNode]()

        func collectTestNodes(_ nodes: [TestNode]) {
            for node in nodes {
                if node.nodeType == "Test Case" {
                    var testNode = node
                    // Collect attachments for the test case
                    collectAttachments(from: &testNode)
                    allTests.append(testNode)
                }
                if let childNodes = node.children {
                    collectTestNodes(childNodes)
                }
            }
        }

        // New function to collect attachments from a test node
        func collectAttachments(from node: inout TestNode) {
            if let children = node.children {
                for child in children {
                    if child.nodeType == "Failure Message" {
                        // Handle failure messages if needed
                    } else if child.nodeType == "Activity" {
                        // Collect attachments from activities
                        if let activityAttachments = collectAttachmentsFromActivity(child) {
                            node.attachments.append(contentsOf: activityAttachments)
                        }
                    } else {
                        // Recursively collect attachments from child nodes
                        var mutableChild = child
                        collectAttachments(from: &mutableChild)
                    }
                }
            }
        }

        // Helper function to collect attachments from an activity node
        func collectAttachmentsFromActivity(_ node: TestNode) -> [TestAttachment]? {
            var attachments = [TestAttachment]()
            if let children = node.children {
                for child in children {
                    if child.nodeType == "Attachment" {
                        if let payloadId = child.nodeIdentifier,
                           let uti = child.details {
                            // 'child.name' is non-optional, so we can access it directly
                            let filename = child.name
                            let attachment = TestAttachment(filename: filename, uniformTypeIdentifier: uti, payloadId: payloadId)
                            attachments.append(attachment)
                        }
                    } else if child.nodeType == "Activity" {
                        // Recursively collect attachments from nested activities
                        if let nestedAttachments = collectAttachmentsFromActivity(child) {
                            attachments.append(contentsOf: nestedAttachments)
                        }
                    }
                }
            }
            return attachments.isEmpty ? nil : attachments
        }

        // Start traversal from the root test nodes
        collectTestNodes(fullResults.testNodes)

        // Now 'allTests' contains all the test cases to generate reports for

        // After collecting allTests, group them by suite
        let groupedTests = Dictionary(grouping: allTests) { test -> String in
            if let identifier = test.nodeIdentifier, let suite = identifier.split(separator: "/").first {
                return String(suite)
            }
            return "Unknown Suite"
        }

        print("Generating HTML report...")

        // Prepare attachments dir (if needed)
        let attachmentsDir = (outputDir as NSString).appendingPathComponent("attachments")
        try? FileManager.default.createDirectory(atPath: attachmentsDir, withIntermediateDirectories: true)

        print("Generating HTML pages...")

        // Generate index.html with grouped tests
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
            word-wrap: break-word; /* Ensure text wraps within fixed width */
        }
        th {
            background: #F2F2F2;
            font-weight: 600;
        }
        th:nth-child(1), td:nth-child(1) {
            width: 60%; /* Set width for Test Name column */
        }
        th:nth-child(2), td:nth-child(2) {
            width: 20%; /* Set width for Status column */
        }
        th:nth-child(3), td:nth-child(3) {
            width: 20%; /* Set width for Duration column */
        }

        tr.failed {
            background-color: #f8d7da; /* Light red background */
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

        for (suite, tests) in groupedTests {
            indexHTML += "<h2>Suite: \(suite)</h2>"
            indexHTML += """
            <table>
            <tr><th>Test Name</th><th>Status</th><th>Duration</th></tr>
            """
            for test in tests {
                let testPageName = "test_\(test.nodeIdentifier ?? test.name).html".replacingOccurrences(of: "/", with: "_")
                let statusClass = test.result == "Passed" ? "passed" : "failed"
                let duration = test.duration ?? "0s"
                
                // Determine if the row should be tinted based on test result
                let rowClass = test.result == "Passed" ? "" : " class=\"failed\""
                
                indexHTML += "<tr\(rowClass)><td><a href=\"\(testPageName)\">\(test.name)</a></td><td class=\"\(statusClass)\">\(test.result)</td><td>\(duration)</td></tr>"
            }
            indexHTML += "</table>"
        }

        indexHTML += "</body></html>"

        // Generate individual test pages
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