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
            return Date().timeIntervalSince1970 // fallback
        }

        func findPreviousResults() -> TestHistory? {
            let fileManager = FileManager.default
            let parentDir = (outputDir as NSString).deletingLastPathComponent
            let currentDirName = (outputDir as NSString).lastPathComponent
            print("\nLooking for previous results...")
            print("Current directory: \(currentDirName)")
            print("Parent directory: \(parentDir)")

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

                                // Convert to simplified format
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

        // Preprocessing step (parallelized)
        let totalTests = allTests.count
        var processedTests = 0
        let processedTestsQueue = DispatchQueue(label: "processedTests")
        let preprocessingGroup = DispatchGroup()
        let concurrentQueue = DispatchQueue(label: "testPreprocessing", attributes: .concurrent)
        let maxConcurrent = ProcessInfo.processInfo.processorCount

        let testsPerCore = (allTests.count + maxConcurrent - 1) / maxConcurrent
        let testChunks = stride(from: 0, through: allTests.count - 1, by: testsPerCore).map {
            Array(allTests[$0..<min($0 + testsPerCore, allTests.count)])
        }

        print("Preprocessing \(allTests.count) tests using \(maxConcurrent) cores...")

        for chunk in testChunks {
            preprocessingGroup.enter()
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
                        processedTests += 1
                        let progress = Double(processedTests) / Double(totalTests) * 100
                        print(String(format: "\rPreprocessing Progress: %.2f%% (%d/%d)", progress, processedTests, totalTests), terminator: "")
                        fflush(stdout)
                    }
                }
                preprocessingGroup.leave()
            }
        }

        preprocessingGroup.wait()
        print("\n")

        let previousResults = findPreviousResults()

        // Parallelize test HTML generation for suites
        print("Processing \(totalTests) tests for suite generation using \(maxConcurrent) cores...")
        
        let suiteHTMLQueue = DispatchQueue(label: "suiteHTML")
        var suiteSections = [String: [String]](minimumCapacity: groupedTests.count)
        var processedSuiteTests = 0
        
        // Initialize suite sections with headers
        for (suite, tests) in groupedTests {
            let succeeded = tests.filter { $0.result == "Passed" }.count
            let total = tests.count
            let percentagePassed = Double(succeeded) / Double(total) * 100.0
            
            // Calculate total duration for the suite
            let totalDuration = tests.compactMap { test -> TimeInterval? in
                guard let durationStr = test.duration?.lowercased() else { return nil }
                // Remove 's' suffix and handle potential subseconds with '.'
                let numberStr = durationStr.replacingOccurrences(of: "s", with: "")
                return Double(numberStr)
            }.reduce(0, +)
            
            let durationText: String
            if totalDuration >= 60 {
                let minutes = floor(totalDuration / 60)
                let seconds = totalDuration.truncatingRemainder(dividingBy: 60)
                if seconds > 0 {
                    durationText = String(format: "%.0f min %.0f sec", minutes, seconds)
                } else {
                    durationText = String(format: "%.0f min", minutes)
                }
            } else {
                durationText = String(format: "%.1f sec", totalDuration)
            }
            
            suiteHTMLQueue.sync {
                suiteSections[suite] = []
                suiteSections[suite]?.append("""
                    <div class="suite"><h2 class="collapsible">
                        <span class="suite-name">\(suite)</span>
                        <span class="suite-stats">
                            <span class="stats-number">\(succeeded)/\(total)</span> Passed
                            <span class="stats-percent">(\(String(format: "%.1f", percentagePassed))%)</span>
                            <span class="suite-duration">\(durationText)</span>
                        </span>
                    </h2><div class="content">
                    <table style="margin-top:0px">
                    <tr><th>Test Name</th><th>Status</th><th>Duration</th></tr>
                    """)
            }
        }
        
        let suiteGroup = DispatchGroup()
        for chunk in testChunks {
            suiteGroup.enter()
            concurrentQueue.async {
                for test in chunk {
                    let suite = test.nodeIdentifier?.split(separator: "/").first.map(String.init) ?? "Unknown Suite"
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

                    if test.result == "Passed",
                       let testDetails = getTestDetails(for: test.nodeIdentifier ?? ""),
                       testDetails.testRuns.count > 1,
                       let firstRun = testDetails.testRuns.first,
                       firstRun.result != "Passed" {
                        statusEmoji += """
                         <span class="emoji-status" title="Failed first attempt, succeeded on run #\(testDetails.testRuns.count)">⚠️</span>
                        """
                    }

                    let testRow = "<tr\(rowClass)><td><a href=\"\(testPageName)\">\(test.name)</a></td><td class=\"\(statusClass)\">\(test.result)\(statusEmoji)</td><td>\(duration)</td></tr>"
                    
                    suiteHTMLQueue.sync {
                        suiteSections[suite]?.append(testRow)
                    }

                    processedTestsQueue.sync {
                        processedSuiteTests += 1
                        let progress = Double(processedSuiteTests) / Double(totalTests) * 100
                        print(String(format: "\rSuite Generation Progress: %.2f%% (%d/%d)", progress, processedSuiteTests, totalTests), terminator: "")
                        fflush(stdout)
                    }
                }
                suiteGroup.leave()
            }
        }

        suiteGroup.wait()
        print("\n")

        // Close all suite sections
        for suite in groupedTests.keys {
            suiteSections[suite]?.append("</table></div></div>")
        }

        // Initialize the HTML template first
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
        h2 {
            padding: 8px 12px;
            border-radius: 6px 6px 0 0;
            background: lightgrey;
            margin-bottom: 0px;
            transition: border-radius 0.2s;
        }
        
        .collapsible {
            display: flex;
            flex-direction: column;
            gap: 4px;
            padding-right: 25px; /* Space for arrow */
            position: relative;
        }
        
        .suite-name {
            font-size: 1.1em;
            font-weight: 600;
            margin-right: 8px;
        }
        
        .suite-stats {
            display: flex;
            align-items: center;
            flex-wrap: wrap;
            gap: 4px 8px;
            font-size: 0.9em;
            font-weight: normal;
            color: #666;
            padding-right: 15px;
        }
        
        @media (min-width: 768px) {
            .collapsible {
                flex-direction: row;
                align-items: center;
                justify-content: space-between;
            }
            
            .suite-name {
                margin-right: 0;
            }
        }
        
        .stats-number {
            font-weight: 600;
            color: #333;
        }
        
        .stats-percent {
            color: #666;
            font-weight: normal;
        }
        
        .suite-duration {
            color: #666;
        }

        .collapsible::after {
            content: "\\25BC";
            position: absolute;
            right: 10px;
            top: 50%;
            transform: translateY(-50%);
            font-size: 0.8em;
            transition: transform 0.2s;
        }
        .collapsed + .content {
            display: none;
        }
        .collapsible.collapsed {
            border-radius: 6px;
        }
        table {
            border-collapse: collapse;
            width: 100%;
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
        .collapsible {
            cursor: pointer;
            user-select: none;
            position: relative;
            padding-right: 20px;
        }
        .collapsible::after {
            content: "\\25BC"; /* Down arrow */
            position: absolute;
            right: 10px;
            font-size: 0.8em;
            transition: transform 0.2s;
        }
        .collapsed::after {
            content: "\\25B6"; /* Right arrow */
        }
        .content {
            max-height: 2000px; /* Should be larger than any potential content */
            opacity: 1;
            transition: max-height 0.3s ease-in-out, opacity 0.2s ease-in-out;
            overflow: hidden;
        }
        
        .collapsed + .content {
            max-height: 0;
            opacity: 0;
            transition: max-height 0.3s ease-in-out, opacity 0.2s ease-in-out;
        }

        .suite {
            margin-bottom: 1px; /* Prevent margin collapse during animation */
        }
        .summary-stats {
            font-size: 1.2em;
            margin: 20px 0;
            padding: 15px;
            background: white;
            border-radius: 8px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
            display: flex;
            flex-direction: column;
            gap: 20px;
        }
        
        .stat-number {
            font-size: 1.3em;
            font-weight: 600;
            font-feature-settings: "tnum";
            font-variant-numeric: tabular-nums;
        }
        
        .passed-number {
            color: #28A745;
        }
        
        .failed-number {
            color: #DC3545;
        }
        
        .skipped-number {
            color: #6c757d;
        }
        
        button#toggle-all {
            padding: 8px 16px;
            font-size: 14px;
            font-weight: 500;
            color: #24292e;
            background-color: #fafbfc;
            border: 1px solid rgba(27,31,35,0.15);
            border-radius: 6px;
            box-shadow: 0 1px 0 rgba(27,31,35,0.04);
            cursor: pointer;
            user-select: none;
            transition: all 0.2s ease;
            width: 100%;
        }
        
        @media (min-width: 768px) {
            .summary-stats {
                flex-direction: row;
                align-items: center;
                justify-content: space-between;
            }
            
            button#toggle-all {
                width: auto;
                white-space: nowrap;
            }
        }
        </style>
        </head>
        <body>
        <h1>Test Report: \(summary.title)</h1>
        <div class="summary-stats">
            <div>
                Total: <span class="stat-number">\(summary.totalTestCount)</span>, 
                Passed: <span class="stat-number passed-number">\(summary.passedTests)</span>, 
                Failed: <span class="stat-number failed-number">\(summary.failedTests)</span>, 
                Skipped: <span class="stat-number skipped-number">\(summary.skippedTests)</span>
            </div>
            <button id="toggle-all">Collapse All</button>
        </div>
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
            indexHTML += "<p class=\"comparison-info\">Compared with previous run from: \(dateString)</p>"
        }

        // Add suite sections to HTML in sorted order
        for suite in groupedTests.keys.sorted() {
            if let section = suiteSections[suite] {
                indexHTML += section.joined()
            }
        }

        indexHTML += """
        <script>
        var coll = document.getElementsByClassName("collapsible");
        var i;

        // Initialize sections as expanded
        for (i = 0; i < coll.length; i++) {
          var content = coll[i].nextElementSibling;
          content.style.display = "block";
          // Don't add collapsed class initially since we're expanded
        }

        // Add click handlers
        for (i = 0; i < coll.length; i++) {
          coll[i].addEventListener("click", function() {
            this.classList.toggle("collapsed");
            // Remove display manipulation - CSS transitions will handle it
          });
        }

        var toggleAllBtn = document.getElementById("toggle-all");
        toggleAllBtn.textContent = "Collapse All";

        toggleAllBtn.addEventListener("click", function() {
          var expanded = toggleAllBtn.textContent === "Collapse All";
          for (i = 0; i < coll.length; i++) {
            if (expanded) {
                coll[i].classList.add("collapsed");
            } else {
                coll[i].classList.remove("collapsed");
            }
          }
          toggleAllBtn.textContent = expanded ? "Expand All" : "Collapse All";
        });
        </script>
        </body></html>
        """

        let indexPath = (outputDir as NSString).appendingPathComponent("index.html")
        try indexHTML.write(toFile: indexPath, atomically: true, encoding: .utf8)

        print("HTML report generated at \(indexPath)")
    }
}

XCTestReport.main()