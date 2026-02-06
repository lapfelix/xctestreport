import Dispatch
import Foundation

extension XCTestReport {
    func generateHTMLReport() throws {

        try? FileManager.default.createDirectory(
            atPath: outputDir, withIntermediateDirectories: true)
        let webTemplates = try loadWebTemplates()
        try copyWebAssets(to: outputDir)

        // Check xcresult file size
        let fileManager = FileManager.default
        var sizeInGB: Double = 0
        if let attributes = try? fileManager.attributesOfItem(atPath: xcresultPath),
           let fileSize = attributes[.size] as? Int64 {
            sizeInGB = Double(fileSize) / 1_073_741_824
            print("XCResult file size: \(String(format: "%.2f", sizeInGB)) GB")
            if sizeInGB > 5.0 {
                print("WARNING: Large xcresult file detected (\(String(format: "%.2f", sizeInGB)) GB)")
                print("This may take a very long time to process...")
                print("Consider using smaller test batches or filtering tests")
            }
        }

        let attachmentsByTestIdentifier = exportAttachments()

        // Get summary
        let summaryCmd = [
            "xcrun", "xcresulttool", "get", "test-results", "summary", "--path", xcresultPath,
            "--format", "json", "--compact",
        ]
        print("Running summary command: \(summaryCmd.joined(separator: " "))")
        let startTime = Date()
        let (summaryJSON, summaryExit) = shell(summaryCmd)
        let summaryDuration = Date().timeIntervalSince(startTime)
        print("Summary command completed in \(String(format: "%.2f", summaryDuration)) seconds")
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
                let prettyData = try? JSONSerialization.data(
                    withJSONObject: jsonObject, options: .prettyPrinted),
                let prettyString = String(data: prettyData, encoding: .utf8)
            {
                print("JSON structure:")
                print(prettyString)
            }
            throw RuntimeError(message: "Failed to decode test summary.")
        }

        let summaryFailureTextsByTestName = Dictionary(grouping: summary.testFailures) { failure in
            failure.testName
        }.mapValues { failures in
            failures.map { $0.failureText }
        }

        // Get full JSON
        print("Getting full results...")
        let fullJSONPath = (outputDir as NSString).appendingPathComponent("tests_full.json")
        try? FileManager.default.removeItem(atPath: fullJSONPath)
        let fullCmd = [
            "xcrun", "xcresulttool", "get", "test-results", "tests", "--path", xcresultPath,
        ]
        print("Running: \(fullCmd.joined(separator: " "))")
        let fullStartTime = Date()
        let (_, fullExit) = shell(fullCmd, outputFile: fullJSONPath, captureOutput: false)
        let fullDuration = Date().timeIntervalSince(fullStartTime)
        print("Full results command completed in \(String(format: "%.2f", fullDuration)) seconds")
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
            if let identifier = test.nodeIdentifier,
                let suite = identifier.split(separator: "/").first
            {
                return String(suite)
            }
            return "Unknown Suite"
        }
        let testDetailTemplate = webTemplates.testDetailTemplate
        let indexTemplate = webTemplates.indexTemplate
        let timelineTemplate = webTemplates.timelineSectionTemplate

        // Preprocessing step (parallelized)
        let totalTests = allTests.count
        var processedTests = 0
        let processedTestsQueue = DispatchQueue(label: "processedTests")
        let preprocessingGroup = DispatchGroup()
        let concurrentQueue = DispatchQueue(label: "testPreprocessing", attributes: .concurrent)
        let maxConcurrent = 1  //ProcessInfo.processInfo.processorCount

        let testsPerCore = (allTests.count + maxConcurrent - 1) / maxConcurrent
        let testChunks = stride(from: 0, through: allTests.count - 1, by: testsPerCore).map {
            Array(allTests[$0..<min($0 + testsPerCore, allTests.count)])
        }

        print("Preprocessing \(allTests.count) tests using \(maxConcurrent) cores...")

        for chunk in testChunks {
            preprocessingGroup.enter()
            concurrentQueue.async {
                for test in chunk {
                    let testPageName = "test_\(test.nodeIdentifier ?? test.name).html"
                        .replacingOccurrences(of: "/", with: "_")
                    let result = test.result ?? "Unknown"
                    let statusBadgeClass = result == "Passed" ? "status-passed" : "status-failed"
                    let duration = test.duration ?? "0s"

                    var failureInfo = ""
                    var primaryFailureMessage: String?
                    var sourceLocationCandidateTexts = [String]()
                    if result != "Passed", let details = test.details {
                        primaryFailureMessage = details
                        sourceLocationCandidateTexts.append(details)
                    }
                    sourceLocationCandidateTexts.append(contentsOf: summaryFailureTextsByTestName[test.name] ?? [])
                    if primaryFailureMessage == nil {
                        primaryFailureMessage = summaryFailureTextsByTestName[test.name]?.first
                    }

                    var testDetails: TestDetails?
                    var testActivities: TestActivities?
                    // Skip getTestDetails for large xcresult files to avoid timeout
                    if sizeInGB < 10.0 {  // Only get details for xcresults < 10GB
                        if let testIdentifier = test.nodeIdentifier {
                            testDetails = getTestDetails(for: testIdentifier)
                            testActivities = getTestActivities(for: testIdentifier)
                        } else {
                            print("No test identifier for test: \(test.name)")
                        }
                    } else if result != "Passed" {
                        // For large files, only log failed tests
                        print("Skipping details for \(test.name) (large xcresult: \(String(format: "%.2f", sizeInGB)) GB)")
                    }

                    if let testDetails = testDetails {
                        let testDescription = testDetails.testDescription
                        let testResult = testDetails.testResult
                        if let testRuns = testDetails.testRuns {
                            sourceLocationCandidateTexts.append(
                                contentsOf: extractRunDetailTexts(from: testRuns))
                            let runsHtml = testRuns.compactMap { run in
                                guard let children = run.children else { return nil }
                                let runDetails = children.compactMap { child in
                                    let childDetails =
                                        child.children?.map { detail in
                                            return "<li><code>\(detail.name)</code></li>"
                                        }.joined(separator: "") ?? ""
                                    return
                                        "<li>\(child.name) (\(child.nodeType)): \(child.result ?? "Unknown")<ul>\(childDetails)</ul></li>"
                                }.joined(separator: "")
                                return
                                    "<li>\(run.name) (\(run.nodeType)): \(run.result ?? "Unknown")<ul>\(runDetails)</ul></li>"
                            }.joined(separator: "")

                            failureInfo += """
                                <p><strong>Test Description:</strong> \(testDescription)<br>
                                <strong>Test Result:</strong> \(testResult)</p>
                                <ul>\(runsHtml)</ul>
                                """
                        }

                        // Add previous runs information (skip for large files)
                        if sizeInGB < 10.0, let testIdentifier = test.nodeIdentifier {
                            let previousRuns = getPreviousRuns(for: testIdentifier)
                            if !previousRuns.isEmpty {
                                let runsEmoji = previousRuns.prefix(10).map {
                                    $0.result == "Passed" ? "✅" : "❌"
                                }.joined()
                                failureInfo += """
                                    <h3>Previous Runs (Last 10)</h3>
                                    <p>\(runsEmoji)</p>
                                    """
                                let previousRunsHTML = previousRuns.map { run in
                                    return
                                        "<tr><td>\(run.name)</td><td>\(run.result ?? "Unknown")</td><td>\(run.duration)</td></tr>"
                                }.joined(separator: "")
                                failureInfo += """
                                    <h3>Previous Runs (Last 10)</h3>
                                    <table>
                                    <tr><th>Run</th><th>Status</th><th>Duration</th></tr>
                                    \(previousRunsHTML)
                                    </table>
                                    """
                            } else {
                                print("No previous runs for test: \(test.name)")
                            }
                        } else {
                            print("No test identifier for test: \(test.name)")
                        }
                    } else {
                        print("No test details for test: \(test.name)")
                    }

                    if result != "Passed" {
                        let sourceLocationsHtml = renderSourceLocationSection(
                            candidateTexts: sourceLocationCandidateTexts)
                        if !sourceLocationsHtml.isEmpty {
                            failureInfo += sourceLocationsHtml
                        }

                        let stackTraceHtml = renderStackTraceSection(
                            for: test.nodeIdentifier,
                            attachmentsByTestIdentifier: attachmentsByTestIdentifier
                        )
                        if !stackTraceHtml.isEmpty {
                            failureInfo += stackTraceHtml
                        }
                    }

                    let compactFailureBoxHtml: String
                    if let primaryFailureMessage,
                        !primaryFailureMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    {
                        compactFailureBoxHtml = """
                            <div class="test-error-box"><pre>\(htmlEscape(primaryFailureMessage))</pre></div>
                            """
                    } else {
                        compactFailureBoxHtml = ""
                    }

                    let timelineSourceLocationMap: [String: SourceLocation]
                    if result != "Passed", let testRuns = testDetails?.testRuns {
                        timelineSourceLocationMap = sourceReferenceLocationMap(
                            from: testRuns,
                            testIdentifierURL: testDetails?.testIdentifierURL
                        )
                    } else {
                        timelineSourceLocationMap = [:]
                    }

                    let timelineAndVideoSection = renderTimelineVideoSection(
                        for: test.nodeIdentifier,
                        activities: testActivities,
                        attachmentsByTestIdentifier: attachmentsByTestIdentifier,
                        sourceLocationBySymbol: timelineSourceLocationMap,
                        template: timelineTemplate
                    )

                    let detailsPanelHtml: String
                    if failureInfo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        detailsPanelHtml = ""
                    } else {
                        detailsPanelHtml = """
                            <details class="test-meta-details">
                                <summary>Summary</summary>
                                <div class="test-meta-content">
                                    \(failureInfo)
                                </div>
                            </details>
                            """
                    }
                    let testSubtitle = htmlEscape(test.nodeIdentifier ?? "Test report")

                    let testDetailHTML: String
                    do {
                        testDetailHTML = try renderTemplate(
                            testDetailTemplate,
                            values: [
                                "page_title": htmlEscape(test.name),
                                "test_name": htmlEscape(test.name),
                                "status_badge_class": statusBadgeClass,
                                "status_text": htmlEscape(result),
                                "duration_text": htmlEscape(duration),
                                "test_subtitle": testSubtitle,
                                "compact_failure_box_html": compactFailureBoxHtml,
                                "details_panel_html": detailsPanelHtml,
                                "timeline_and_video_section_html": timelineAndVideoSection,
                            ],
                            templateName: "test-detail.html")
                    } catch {
                        print(
                            "Failed to render test detail template for \(test.name): \(error)")
                        continue
                    }
                    let testPagePath = (outputDir as NSString).appendingPathComponent(testPageName)
                    try? testDetailHTML.write(
                        toFile: testPagePath, atomically: true, encoding: .utf8)

                    processedTestsQueue.sync {
                        processedTests += 1
                        let progress = Double(processedTests) / Double(totalTests) * 100
                        print(
                            String(
                                format: "\rPreprocessing Progress: %.2f%% (%d/%d)", progress,
                                processedTests, totalTests), terminator: "")
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
                guard let durationStr = test.duration else { return nil }
                return parseDuration(durationStr)
            }.reduce(0, +)

            let durationText: String
            if totalDuration >= 3600 {
                let hours = floor(totalDuration / 3600)
                let minutes = floor((totalDuration.truncatingRemainder(dividingBy: 3600)) / 60)
                let seconds = totalDuration.truncatingRemainder(dividingBy: 60)
                if seconds > 0 {
                    durationText = String(
                        format: "%.0f hr %.0f min %.0f sec", hours, minutes, seconds)
                } else if minutes > 0 {
                    durationText = String(format: "%.0f hr %.0f min", hours, minutes)
                } else {
                    durationText = String(format: "%.0f hr", hours)
                }
            } else if totalDuration >= 60 {
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
                suiteSections[suite]?.append(
                    """
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
                    let suite =
                        test.nodeIdentifier?.split(separator: "/").first.map(String.init)
                        ?? "Unknown Suite"
                    let testPageName = "test_\(test.nodeIdentifier ?? test.name).html"
                        .replacingOccurrences(of: "/", with: "_")
                    let result = test.result ?? "Unknown"
                    let statusClass = result == "Passed" ? "passed" : "failed"
                    let duration = test.duration ?? "0s"
                    let rowClass = result == "Passed" ? "" : " class=\"failed\""

                    var statusEmoji = ""
                    if let previousResults = previousResults,
                        let testId = test.nodeIdentifier,
                        let previousResult = previousResults.results[testId]
                    {
                        print(
                            "Comparing test [\(testId)]: Current=\(result) Previous=\(previousResult.status)"
                        )
                        if result == "Failed" && previousResult.status == "Passed" {
                            print("Found newly failed test: \(test.name)")
                            statusEmoji = """
                                 <span class="emoji-status" title="Newly failed test">⭕️</span>
                                """
                        } else if result == "Passed" && previousResult.status == "Failed" {
                            print("Found fixed test: \(test.name)")
                            statusEmoji = """
                                 <span class="emoji-status" title="Fixed test">✨</span>
                                """
                        }
                    }

                    if sizeInGB < 10.0,
                        result == "Passed",
                        let testId = test.nodeIdentifier,
                        let testDetails = getTestDetails(for: testId),
                        let testRuns = testDetails.testRuns,
                        testRuns.count > 1,
                        let firstRun = testRuns.first,
                        let firstRunResult = firstRun.result,
                        firstRunResult != "Passed"
                    {
                        statusEmoji += """
                             <span class="emoji-status" title="Failed first attempt, succeeded on run #\(testRuns.count)">⚠️</span>
                            """
                    }

                    let testRow =
                        "<tr\(rowClass)><td><a href=\"\(testPageName)\">\(test.name)</a></td><td class=\"\(statusClass)\">\(result)\(statusEmoji)</td><td>\(duration)</td></tr>"

                    suiteHTMLQueue.sync {
                        suiteSections[suite]?.append(testRow)
                    }

                    processedTestsQueue.sync {
                        processedSuiteTests += 1
                        let progress = Double(processedSuiteTests) / Double(totalTests) * 100
                        print(
                            String(
                                format: "\rSuite Generation Progress: %.2f%% (%d/%d)", progress,
                                processedSuiteTests, totalTests), terminator: "")
                        fflush(stdout)
                    }
                }
                suiteGroup.leave()
            }
        }

        suiteGroup.wait()
        print("\n")

        // Export grouped tests to JSON
        print("Exporting grouped tests to JSON...")

        var suiteExports = [SuiteExportItem]()
        for (suiteName, tests) in groupedTests {
            let passedTests = tests.filter { $0.result == "Passed" }.count
            let failedTests = tests.filter { $0.result == "Failed" }.count
            let skippedTests = tests.filter { $0.result == "Skipped" }.count

            // Calculate total duration for the suite
            let totalDuration = tests.compactMap { test -> TimeInterval? in
                guard let durationStr = test.duration else { return nil }
                return parseDuration(durationStr)
            }.reduce(0, +)

            let testItems = tests.map { test -> TestExportItem in
                return TestExportItem(
                    name: test.name,
                    result: test.result ?? "Unknown",
                    duration: test.duration,
                    nodeIdentifier: test.nodeIdentifier,
                    details: test.details
                )
            }

            let suiteItem = SuiteExportItem(
                name: suiteName,
                totalTests: tests.count,
                passedTests: passedTests,
                failedTests: failedTests,
                skippedTests: skippedTests,
                duration: totalDuration,
                tests: testItems
            )

            suiteExports.append(suiteItem)
        }

        let exportSummary = ExportSummary(
            title: summary.title,
            totalTestCount: summary.totalTestCount,
            passedTests: summary.passedTests,
            failedTests: summary.failedTests,
            skippedTests: summary.skippedTests,
            timestamp: Date()
        )

        let groupedTestsExport = GroupedTestsExport(
            summary: exportSummary,
            suites: suiteExports
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            let jsonData = try encoder.encode(groupedTestsExport)
            let jsonPath = (outputDir as NSString).appendingPathComponent("tests_grouped.json")
            try jsonData.write(to: URL(fileURLWithPath: jsonPath))
            print("Grouped tests exported to \(jsonPath)")
        } catch {
            print("Error exporting grouped tests to JSON: \(error)")
        }

        // Close all suite sections
        for suite in groupedTests.keys {
            suiteSections[suite]?.append("</table></div></div>")
        }

        var buildResultsHTML = ""

        let buildResultsCmd = [
            "xcrun", "xcresulttool", "get", "build-results", "--path", xcresultPath, "--format",
            "json",
        ]
        let (buildResultsJSON, buildResultsExit) = shell(buildResultsCmd)
        if buildResultsExit == 0, let jsonStr = buildResultsJSON,
            let bdData = jsonStr.data(using: .utf8)
        {
            let buildResults = try? decoder.decode(BuildResults.self, from: bdData)
            if let buildResults = buildResults {
                buildResultsHTML =
                    "<p>🛑 Errors: \(buildResults.errorCount) &nbsp; ⚠️ Warnings: \(buildResults.warningCount)</p>"
            }
        }

        var comparisonInfoHTML = ""
        if let previousResults = previousResults {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .short
            dateFormatter.timeZone = TimeZone.current
            dateFormatter.locale = Locale(identifier: "en_US")
            let dateString = dateFormatter.string(from: previousResults.date)
                .replacingOccurrences(of: ":", with: "&#58;")
                .replacingOccurrences(of: " ", with: "&#32;")
            comparisonInfoHTML =
                "<p class=\"comparison-info\">Compared with previous run from: \(dateString)</p>"
        }

        // Add suite sections to HTML in sorted order
        var suiteSectionsHTML = ""
        for suite in groupedTests.keys.sorted() {
            if let section = suiteSections[suite] {
                suiteSectionsHTML += section.joined()
            }
        }

        let indexHTML = try renderTemplate(
            indexTemplate,
            values: [
                "report_title": htmlEscape(summary.title),
                "total_tests": String(summary.totalTestCount),
                "passed_tests": String(summary.passedTests),
                "failed_tests": String(summary.failedTests),
                "skipped_tests": String(summary.skippedTests),
                "build_results_html": buildResultsHTML,
                "comparison_info_html": comparisonInfoHTML,
                "suite_sections_html": suiteSectionsHTML,
            ],
            templateName: "index.html")

        let indexPath = (outputDir as NSString).appendingPathComponent("index.html")
        try indexHTML.write(toFile: indexPath, atomically: true, encoding: .utf8)

        print("HTML report generated at \(indexPath)")
    }
}
