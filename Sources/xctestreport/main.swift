#!/usr/bin/env swift

import Foundation
import ArgumentParser
import Dispatch

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
            // Remove testNodes field as it's not part of the summary
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
            let startTime: Double?

            enum CodingKeys: String, CodingKey {
                case name
                case nodeType
                case nodeIdentifier
                case result
                case duration
                case details
                case children
                case startTime
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

        struct TestHistory {
            let date: Date
            let results: [String: TestResult]  // nodeIdentifier -> result
        }

        struct TestResult {
            let name: String
            let status: String
            let duration: String?
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
            // Save test details JSON to test_details folder
            let testDetailsDir = (outputDir as NSString).appendingPathComponent("test_details")
            try? FileManager.default.createDirectory(atPath: testDetailsDir, withIntermediateDirectories: true)
            let safeTestIdentifier = testIdentifier.replacingOccurrences(of: "/", with: "_")
            let testDetailsPath = (testDetailsDir as NSString).appendingPathComponent("\(safeTestIdentifier).json")
            try? testDetailsJSON?.write(toFile: testDetailsPath, atomically: true, encoding: .utf8)
            let decoder = JSONDecoder()
            return try? decoder.decode(TestDetails.self, from: data)
        }

        func findFirstValidStartTime(_ nodes: [TestNode]) -> Double {
            for node in nodes {
                if let startTime = node.startTime, startTime > 0 {
                    return startTime
                }
                if let children = node.children {
                    let childStartTime = findFirstValidStartTime(children)
                    if childStartTime > 0 {
                        return childStartTime
                    }
                }
            }
            return Date().timeIntervalSince1970 // fallback to current time if no valid startTime found
        }

        func findPreviousResults() -> TestHistory? {
            let fileManager = FileManager.default
            let parentDir = (outputDir as NSString).deletingLastPathComponent
            let currentDirName = (outputDir as NSString).lastPathComponent
            print("\nLooking for previous results...")
            print("Current directory: \(currentDirName)")
            print("Parent directory: \(parentDir)")
            
            // Get all directories and check each for tests_full.json
            if let contents = try? fileManager.contentsOfDirectory(atPath: parentDir) {
                let previousDirs = contents
                    .filter { $0 != currentDirName && $0 != ".DS_Store" }
                    .sorted()
                    .reversed()
                
                print("Found \(previousDirs.count) potential previous directories:")
                previousDirs.forEach { print("- \($0)") }
                
                for dir in previousDirs {
                    let fullTestsPath = (parentDir as NSString).appendingPathComponent("\(dir)/tests_full.json")
                    print("\nChecking directory: \(dir)")
                    print("Looking for: \(fullTestsPath)")
                    
                    if FileManager.default.fileExists(atPath: fullTestsPath) {
                        print("Found tests_full.json")
                        if let fullData = try? Data(contentsOf: URL(fileURLWithPath: fullTestsPath)) {
                            print("Loaded \(fullData.count) bytes")
                            do {
                                let previousResults = try JSONDecoder().decode(FullTestResults.self, from: fullData)
                                print("Successfully decoded results with \(previousResults.testNodes.count) test nodes")
                                
                                // Convert to our simplified format
                                var testResults = [String: TestResult]()
                                func processNodes(_ nodes: [TestNode]) {
                                    for node in nodes {
                                        if node.nodeType == "Test Case", let identifier = node.nodeIdentifier {
                                            testResults[identifier] = TestResult(
                                                name: node.name,
                                                status: node.result,
                                                duration: node.duration
                                            )
                                        }
                                        if let children = node.children {
                                            processNodes(children)
                                        }
                                    }
                                }
                                processNodes(previousResults.testNodes)
                                print("Processed \(testResults.count) individual test results")
                                
                                let startTime = findFirstValidStartTime(previousResults.testNodes)
                                print("Found start time: \(startTime)")
                                
                                return TestHistory(
                                    date: Date(timeIntervalSince1970: startTime),
                                    results: testResults
                                )
                            } catch {
                                print("Failed to decode results: \(error)")
                                continue
                            }
                        } else {
                            print("Could not read file data")
                        }
                    } else {
                        print("No tests_full.json found")
                    }
                }
                print("\nNo valid previous results found in any directory")
            } else {
                print("Could not read parent directory contents")
            }
            return nil
        }

        try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

        // Get summary
        let summaryCmd = ["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", xcresultPath, "--format", "json", "--compact"]
        print("Running summary command: \(summaryCmd.joined(separator: " "))")
        let (summaryJSON, summaryExit) = shell(summaryCmd)
        guard summaryExit == 0, let summaryData = summaryJSON?.data(using: .utf8) else {
            print("Failed to get test summary.")
            throw RuntimeError(message: "Failed to get test summary.")
        }

        //print("Summary JSON content:")
        //print(summaryJSON ?? "nil")

        let summaryJSONPath = (outputDir as NSString).appendingPathComponent("summary.json")
        print("Writing summary to: \(summaryJSONPath)")
        try summaryJSON?.write(toFile: summaryJSONPath, atomically: true, encoding: .utf8)

        let decoder = JSONDecoder()
        let summary: Summary
        do {
            summary = try decoder.decode(Summary.self, from: summaryData)
        } catch {
            print("Decode summary error: \(error)")
            if let jsonObject = try? JSONSerialization.jsonObject(with: summaryData, options: []),
               let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                print("JSON structure:")
                print(prettyString)
            }
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
        
        let totalTests = allTests.count
        var processedTests = Array<Int32>(repeating: 0, count: 1)
        let processedTestsQueue = DispatchQueue(label: "processedTests")
        let group = DispatchGroup()
        let concurrentQueue = DispatchQueue(label: "testProcessing", attributes: .concurrent)
        let maxConcurrent = ProcessInfo.processInfo.processorCount
        
        // Split tests into chunks for concurrent processing
        let testsPerCore = (allTests.count + maxConcurrent - 1) / maxConcurrent
        let testChunks = stride(from: 0, to: allTests.count, by: testsPerCore).map {
            Array(allTests[$0..<min($0 + testsPerCore, allTests.count)])
        }
        
        print("Processing \(allTests.count) tests using \(maxConcurrent) cores...")
        
        for chunk in testChunks {
            group.enter()
            concurrentQueue.async {
                for test in chunk {
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
                    <meta charset="UTF-8">
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
                    try? testDetailHTML.write(toFile: testPagePath, atomically: true, encoding: .utf8)

                    processedTestsQueue.sync {
                        processedTests[0] += 1
                        let progress = Double(processedTests[0]) / Double(totalTests) * 100
                        print(String(format: "\rProgress: %.2f%% (%d/%d)", progress, processedTests[0], totalTests), terminator: "")
                        fflush(stdout)
                    }
                }
                group.leave()
            }
        }
        
        group.wait()
        print("\n")

        let previousResults = findPreviousResults()

        var indexHTML = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
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
        .new-failure {
            color: #856404;
            background-color: #fff3cd;
            padding: 2px 6px;
            border-radius: 3px;
            font-size: 0.9em;
        }
        .fixed {
            color: #155724;
            background-color: #d4edda;
            padding: 2px 6px;
            border-radius: 3px;
            font-size: 0.9em;
        }
        [title] {
            position: relative;
            cursor: help;
        }
        .emoji-status {
            text-decoration: none;
            margin-left: 4px;
        }
        </style>
        </head>
        <body>
        <h1>Test Report: \(summary.title)</h1>
        <p>Total: \(summary.totalTestCount), Passed: \(summary.passedTests), Failed: \(summary.failedTests), Skipped: \(summary.skippedTests)</p>
        """

        if let previousResults = previousResults {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .short
            dateFormatter.timeZone = TimeZone.current
            dateFormatter.locale = Locale(identifier: "en_US")
            let dateString = dateFormatter.string(from: previousResults.date)
                .replacingOccurrences(of: ":", with: "&#58;")
                .replacingOccurrences(of: " ", with: "&#32;")
            indexHTML += "<p>Compared with previous run from: \(dateString)</p>"
        }

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
                
                var statusEmoji = ""
                if let previousResults = previousResults,
                   let testId = test.nodeIdentifier,
                   let previousResult = previousResults.results[testId] {
                    if test.result == "Failed" && previousResult.status == "Passed" {
                        statusEmoji = """
                         <span class="emoji-status" title="Newly failed test">⭕️</span>
                        """
                    } else if test.result == "Passed" && previousResult.status == "Failed" {
                        statusEmoji = """
                         <span class="emoji-status" title="Fixed test">✨</span>
                        """
                    }
                }
                
                // Add warning emoji only if first run failed but eventually succeeded
                if test.result == "Passed",
                   let testDetails = getTestDetails(for: test.nodeIdentifier ?? ""),
                   testDetails.testRuns.count > 1,
                   let firstRun = testDetails.testRuns.first,
                   firstRun.result != "Passed" {
                    statusEmoji += """
                     <span class="emoji-status" title="Failed first attempt, succeeded on run #\(testDetails.testRuns.count)">⚠️</span>
                    """
                }
                
                indexHTML += "<tr\(rowClass)><td><a href=\"\(testPageName)\">\(test.name)</a></td><td class=\"\(statusClass)\">\(test.result)\(statusEmoji)</td><td>\(duration)</td></tr>"
            }
            indexHTML += "</table>"
        }

        indexHTML += "</body></html>"

        let indexPath = (outputDir as NSString).appendingPathComponent("index.html")
        try indexHTML.write(toFile: indexPath, atomically: true, encoding: .utf8)

        print("HTML report generated at \(indexPath)")
    }
}

XCTestReport.main()