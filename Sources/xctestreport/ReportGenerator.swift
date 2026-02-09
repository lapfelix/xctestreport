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
            if sizeInGB > 5.0 {
                print("WARNING: Large xcresult file detected (\(String(format: "%.2f", sizeInGB)) GB)")
                print("This may take a very long time to process...")
                print("Consider using smaller test batches or filtering tests")
            }
        }

        let overallStartTime = Date()
        var attachmentsByTestIdentifier = [String: [AttachmentManifestItem]]()
        var attachmentsExportDuration: TimeInterval = 0
        var summaryDuration: TimeInterval = 0
        var fullDuration: TimeInterval = 0
        var summaryJSON: String?
        var summaryExit: Int32 = 1
        var fullExit: Int32 = 1

        let exportGroup = DispatchGroup()
        let exportQueue = DispatchQueue(label: "reportExport", qos: .userInitiated, attributes: .concurrent)

        exportGroup.enter()
        exportQueue.async {
            let startTime = Date()
            let attachments = exportAttachments()
            attachmentsExportDuration = Date().timeIntervalSince(startTime)
            attachmentsByTestIdentifier = attachments
            exportGroup.leave()
        }

        // Get summary
        let summaryCmd = [
            "xcrun", "xcresulttool", "get", "test-results", "summary", "--path", xcresultPath,
            "--format", "json", "--compact",
        ]
        print("Running summary command: \(summaryCmd.joined(separator: " "))")
        exportGroup.enter()
        exportQueue.async {
            let startTime = Date()
            let (json, exitCode) = shell(summaryCmd)
            summaryDuration = Date().timeIntervalSince(startTime)
            summaryJSON = json
            summaryExit = exitCode
            exportGroup.leave()
        }

        let fullJSONPath = (outputDir as NSString).appendingPathComponent("tests_full.json")
        exportGroup.enter()
        exportQueue.async {
            print("Getting full results...")
            try? FileManager.default.removeItem(atPath: fullJSONPath)
            let fullCmd = [
                "xcrun", "xcresulttool", "get", "test-results", "tests", "--path", xcresultPath,
            ]
            print("Running: \(fullCmd.joined(separator: " "))")
            let fullStartTime = Date()
            let (_, exitCode) = shell(fullCmd, outputFile: fullJSONPath, captureOutput: false)
            fullDuration = Date().timeIntervalSince(fullStartTime)
            fullExit = exitCode
            exportGroup.leave()
        }

        exportGroup.wait()

        print("Summary command completed in \(String(format: "%.2f", summaryDuration)) seconds")
        print("Attachment export completed in \(String(format: "%.2f", attachmentsExportDuration)) seconds")
        print("Full results command completed in \(String(format: "%.2f", fullDuration)) seconds")

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

        guard fullExit == 0 else {
            print("Failed to get full results. Exit code: \(fullExit)")
            throw RuntimeError(message: "Failed to get full results.")
        }

        print("Full results exit code: \(fullExit)")

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
        let preprocessingQueue = DispatchQueue(
            label: "testPreprocessing", attributes: .concurrent)
        let suiteQueue = DispatchQueue(label: "suiteGeneration", attributes: .concurrent)
        let availableCores = max(1, ProcessInfo.processInfo.activeProcessorCount)
        let preprocessingWorkers = min(4, availableCores)
        let suiteWorkers = min(4, availableCores)  // Parallelize suite generation

        func chunkTests(_ tests: [TestNode], workerCount: Int) -> [[TestNode]] {
            guard !tests.isEmpty else { return [] }
            let boundedWorkers = max(1, workerCount)
            let chunkSize = max(1, (tests.count + boundedWorkers - 1) / boundedWorkers)
            return stride(from: 0, to: tests.count, by: chunkSize).map {
                Array(tests[$0..<min($0 + chunkSize, tests.count)])
            }
        }
        
        func chunkTestsWithIndices(_ tests: [TestNode], workerCount: Int) -> [[(index: Int, test: TestNode)]] {
            guard !tests.isEmpty else { return [] }
            let boundedWorkers = max(1, workerCount)
            let chunkSize = max(1, (tests.count + boundedWorkers - 1) / boundedWorkers)
            let indexedTests = tests.enumerated().map { (index: $0.offset, test: $0.element) }
            return stride(from: 0, to: indexedTests.count, by: chunkSize).map {
                Array(indexedTests[$0..<min($0 + chunkSize, indexedTests.count)])
            }
        }
        
        let preprocessingChunks = chunkTests(allTests, workerCount: preprocessingWorkers)
        let suiteChunks = chunkTestsWithIndices(allTests, workerCount: suiteWorkers)

        print("Preprocessing \(allTests.count) tests using \(preprocessingWorkers) cores...")

        for chunk in preprocessingChunks {
            preprocessingGroup.enter()
            preprocessingQueue.async {
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
                                        "<tr><td data-label=\"Run\">\(htmlEscape(run.name))</td><td data-label=\"Status\">\(htmlEscape(run.result ?? "Unknown"))</td><td data-label=\"Duration\">\(htmlEscape(run.duration))</td></tr>"
                                }.joined(separator: "")
                                failureInfo += """
                                    <h3>Previous Runs (Last 10)</h3>
                                    <table class="data-table previous-runs-table">
                                    <thead><tr><th scope="col">Run</th><th scope="col">Status</th><th scope="col">Duration</th></tr></thead>
                                    <tbody>\(previousRunsHTML)</tbody>
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
                        template: timelineTemplate,
                        payloadBaseName: (testPageName as NSString).deletingPathExtension
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
                    let minimizedTestDetailHTML = minifyHTMLInterTagWhitespace(testDetailHTML)
                    try? minimizedTestDetailHTML.write(
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
        print("Processing \(totalTests) tests for suite generation using \(suiteWorkers) cores...")

        let suiteHTMLQueue = DispatchQueue(label: "suiteHTML")
        var suiteSections = [String: [(index: Int, html: String)]](minimumCapacity: groupedTests.count)
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
                suiteSections[suite]?.append((index: -1, html:
                    """
                    <div class="suite"><h2 class="collapsible">
                        <span class="suite-name">\(suite)</span>
                        <span class="suite-stats">
                            <span class="stats-number">\(succeeded)/\(total)</span> Passed
                            <span class="stats-percent">(\(String(format: "%.1f", percentagePassed))%)</span>
                            <span class="suite-duration">\(durationText)</span>
                        </span>
                    </h2><div class="content">
                    <table class="data-table suite-tests-table" style="margin-top:0px">
                    <thead><tr><th scope="col">Test Name</th><th scope="col">Status</th><th scope="col">Duration</th></tr></thead>
                    <tbody>
                    """))
            }
        }

        let suiteGroup = DispatchGroup()
        for chunk in suiteChunks {
            suiteGroup.enter()
            suiteQueue.async {
                for (testIndex, test) in chunk {
                    let suite =
                        test.nodeIdentifier?.split(separator: "/").first.map(String.init)
                        ?? "Unknown Suite"
                    let testPageName = "test_\(test.nodeIdentifier ?? test.name).html"
                        .replacingOccurrences(of: "/", with: "_")
                    let result = test.result ?? "Unknown"
                    let statusClass = result == "Passed" ? "passed" : "failed"
                    let duration = test.duration ?? "0s"
                    let rowClass = result == "Passed" ? "" : " class=\"failed\""
                    let escapedResult = htmlEscape(result)
                    let escapedDuration = htmlEscape(duration)
                    let escapedTestName = htmlEscape(test.name)
                    let escapedPageName = htmlEscape(testPageName)

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
                        "<tr\(rowClass)><td data-label=\"Test Name\"><a href=\"\(escapedPageName)\">\(escapedTestName)</a></td><td data-label=\"Status\" class=\"\(statusClass)\">\(escapedResult)\(statusEmoji)</td><td data-label=\"Duration\">\(escapedDuration)</td></tr>"

                    suiteHTMLQueue.sync {
                        suiteSections[suite]?.append((index: testIndex, html: testRow))
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
            suiteSections[suite]?.append((index: Int.max, html: "</tbody></table></div></div>"))
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
                suiteSectionsHTML += section.sorted(by: { $0.index < $1.index }).map { $0.html }.joined()
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
        let minimizedIndexHTML = minifyHTMLInterTagWhitespace(indexHTML)
        try minimizedIndexHTML.write(toFile: indexPath, atomically: true, encoding: .utf8)

        let overallDuration = Date().timeIntervalSince(overallStartTime)
        print("HTML report generated at \(indexPath)")
        print("Report generation completed in \(String(format: "%.2f", overallDuration)) seconds")
    }
}
