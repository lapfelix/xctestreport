import Dispatch
import Foundation

extension XCTestReport {
    func generateHTMLReport() throws {
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
            let result: String?
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
            let startTime: Double?
            let testDescription: String
            let testIdentifier: String
            let testName: String
            let testPlanConfigurations: [TestPlanConfiguration]
            let testResult: String
            let testRuns: [TestRunDetail]?
            var previousRuns: [TestRunDetail]?
        }

        struct TestRunDetail: Decodable {
            let children: [TestRunChild]?
            let duration: String
            let name: String
            let nodeIdentifier: String?
            let nodeType: String
            let result: String?
        }

        struct TestRunChild: Decodable {
            let children: [TestRunChildDetail]?
            let name: String
            let nodeType: String
            let result: String?
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

        struct BuildResults: Decodable {
            let startTime: Double
            let endTime: Double
            let errorCount: Int
            let warningCount: Int

            var buildTime: Double {
                return endTime - startTime
            }
        }

        struct TestExportItem: Codable {
            let name: String
            let result: String
            let duration: String?
            let nodeIdentifier: String?
            let details: String?
        }

        struct SuiteExportItem: Codable {
            let name: String
            let totalTests: Int
            let passedTests: Int
            let failedTests: Int
            let skippedTests: Int
            let duration: TimeInterval
            let tests: [TestExportItem]
        }

        struct GroupedTestsExport: Codable {
            let summary: ExportSummary
            let suites: [SuiteExportItem]
        }

        struct ExportSummary: Codable {
            let title: String
            let totalTestCount: Int
            let passedTests: Int
            let failedTests: Int
            let skippedTests: Int
            let timestamp: Date
        }

        struct AttachmentManifestEntry: Decodable {
            let attachments: [AttachmentManifestItem]
            let testIdentifier: String
        }

        struct AttachmentManifestItem: Decodable {
            let exportedFileName: String
            let isAssociatedWithFailure: Bool?
            let suggestedHumanReadableName: String?
        }

        struct TestActivities: Decodable {
            let testIdentifier: String
            let testRuns: [TestActivityRun]
        }

        struct TestActivityRun: Decodable {
            let activities: [TestActivity]
        }

        struct TestActivity: Decodable {
            let title: String
            let startTime: Double?
            let isAssociatedWithFailure: Bool?
            let attachments: [TestActivityAttachment]?
            let childActivities: [TestActivity]?
        }

        struct TestActivityAttachment: Decodable {
            let name: String
            let timestamp: Double?
        }

        struct VideoSource {
            let label: String
            let fileName: String
            let mimeType: String
            let startTime: Double?
            let failureAssociated: Bool
        }

        struct ScreenshotSource: Codable {
            let label: String
            let src: String
            let time: Double
            let failureAssociated: Bool
        }

        struct TimelineAttachment {
            let name: String
            let timestamp: Double?
            let relativePath: String?
            let failureAssociated: Bool
        }

        struct TimelineNode {
            let id: String
            let title: String
            let timestamp: Double?
            let endTimestamp: Double?
            let failureAssociated: Bool
            let attachments: [TimelineAttachment]
            let children: [TimelineNode]
            let repeatCount: Int
        }

        struct SourceLocation {
            let filePath: String
            let line: Int
            let column: Int?
        }

        struct StackTracePreview {
            let attachmentName: String
            let relativePath: String
            let preview: String
            let frameCount: Int
        }

        struct TouchGesturePoint: Codable {
            let time: Double
            let x: Double
            let y: Double
        }

        struct TouchGestureOverlay: Codable {
            let startTime: Double
            let endTime: Double
            let width: Double
            let height: Double
            let points: [TouchGesturePoint]
        }

        func shell(_ args: [String], outputFile: String? = nil, captureOutput: Bool = true) -> (
            String?, Int32
        ) {
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
            
            // For captured output, read data BEFORE waiting for exit to avoid deadlock
            var output: String? = nil
            if captureOutput, let pipe = task.standardOutput as? Pipe {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                output = String(data: data, encoding: .utf8)
            }
            
            task.waitUntilExit()
            return (output, task.terminationStatus)
        }

        func getTestDetails(for testIdentifier: String) -> TestDetails? {
            let testDetailsCmd = [
                "xcrun", "xcresulttool", "get", "test-results", "test-details", "--test-id",
                testIdentifier, "--path", xcresultPath, "--format", "json", "--compact",
            ]
            let (testDetailsJSON, exitCode) = shell(testDetailsCmd)
            guard exitCode == 0, let data = testDetailsJSON?.data(using: .utf8) else {
                print("Failed to get test details for: \(testIdentifier)")
                return nil
            }

            print("Got test details for: \(testIdentifier)")

            // Save test details JSON to test_details folder
            let testDetailsDir = (outputDir as NSString).appendingPathComponent("test_details")
            print("Saving test details to: \(testDetailsDir)")
            try? FileManager.default.createDirectory(
                atPath: testDetailsDir, withIntermediateDirectories: true)
            print("Test identifier: \(testIdentifier)")
            let safeTestIdentifier = testIdentifier.replacingOccurrences(of: "/", with: "_")
            print("Safe test identifier: \(safeTestIdentifier)")
            let testDetailsPath = (testDetailsDir as NSString).appendingPathComponent(
                "\(safeTestIdentifier).json")
            print("Writing test details to: \(testDetailsPath)")
            try? testDetailsJSON?.write(toFile: testDetailsPath, atomically: true, encoding: .utf8)
            print("Wrote \(testDetailsJSON?.count ?? 0) bytes")
            let decoder = JSONDecoder()
            do {
                let result = try decoder.decode(TestDetails.self, from: data)
                return result
            } catch {
                print("Failed to decode test details: \(error)")
                print("What we tried to decode: \(String(data: data, encoding: .utf8) ?? "nil")")
                return nil
            }
        }

        func getTestActivities(for testIdentifier: String) -> TestActivities? {
            let cmd = [
                "xcrun", "xcresulttool", "get", "test-results", "activities", "--test-id",
                testIdentifier, "--path", xcresultPath, "--format", "json", "--compact",
            ]
            let (output, exitCode) = shell(cmd)
            guard exitCode == 0, let output, let data = output.data(using: .utf8) else {
                print("Failed to get activities for: \(testIdentifier)")
                return nil
            }

            do {
                return try JSONDecoder().decode(TestActivities.self, from: data)
            } catch {
                print("Failed to decode activities for \(testIdentifier): \(error)")
                return nil
            }
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
            return Date().timeIntervalSince1970  // fallback
        }

        func findPreviousResults() -> TestHistory? {
            let fileManager = FileManager.default
            let parentDir = (outputDir as NSString).deletingLastPathComponent
            let currentDirName = (outputDir as NSString).lastPathComponent
            print("\nLooking for previous results...")
            print("Current directory: \(currentDirName)")
            print("Parent directory: \(parentDir)")

            if let contents = try? fileManager.contentsOfDirectory(atPath: parentDir) {
                let previousDirs =
                    contents
                    .filter { $0 != currentDirName && $0 != ".DS_Store" }
                    .sorted()
                    .reversed()

                print("Found \(previousDirs.count) potential previous directories:")
                previousDirs.forEach { print("- \($0)") }

                for dir in previousDirs {
                    let fullTestsPath = (parentDir as NSString).appendingPathComponent(
                        "\(dir)/tests_full.json")
                    print("\nChecking directory: \(dir)")
                    print("Looking for: \(fullTestsPath)")

                    if FileManager.default.fileExists(atPath: fullTestsPath) {
                        print("Found tests_full.json")
                        if let fullData = try? Data(contentsOf: URL(fileURLWithPath: fullTestsPath))
                        {
                            print("Loaded \(fullData.count) bytes")
                            do {
                                let previousResults = try JSONDecoder().decode(
                                    FullTestResults.self, from: fullData)
                                print(
                                    "Successfully decoded results with \(previousResults.testNodes.count) test nodes"
                                )

                                // Convert to simplified format
                                var testResults = [String: TestResult]()
                                func processNodes(_ nodes: [TestNode]) {
                                    for node in nodes {
                                        if let ident = node.nodeIdentifier, let result = node.result {
                                            let testResult = TestResult(
                                                name: node.name, status: result,
                                                duration: node.duration)
                                            testResults[ident] = testResult
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

        func getPreviousRuns(for testIdentifier: String) -> [TestRunDetail] {
            var previousRuns = [TestRunDetail]()
            let fileManager = FileManager.default
            let parentDir = (outputDir as NSString).deletingLastPathComponent
            let currentDirName = (outputDir as NSString).lastPathComponent

            print("Parent directory: \(parentDir)")
            print("Current directory name: \(currentDirName)")

            if let contents = try? fileManager.contentsOfDirectory(atPath: parentDir) {
                print("Contents of parent directory: \(contents)")

                let previousDirs =
                    contents
                    .filter { $0 != currentDirName && $0 != ".DS_Store" }
                    .sorted()
                    .reversed()

                print("Filtered and sorted previous directories: \(previousDirs)")

                for dir in previousDirs.prefix(10) {
                    let testDetailsPath = (parentDir as NSString).appendingPathComponent(
                        "\(dir)/test_details/\(testIdentifier.replacingOccurrences(of: "/", with: "_")).json"
                    )
                    print("Looking for test details file at path: \(testDetailsPath)")

                    if fileManager.fileExists(atPath: testDetailsPath) {
                        print("Found test details file: \(testDetailsPath)")

                        do {
                            let data = try Data(contentsOf: URL(fileURLWithPath: testDetailsPath))
                            print("Loaded data from file.")

                            let testDetails = try JSONDecoder().decode(TestDetails.self, from: data)

                            if let testRuns = testDetails.testRuns {
                                previousRuns.append(contentsOf: testRuns)
                            }
                        } catch {
                            print(
                                "Failed to load or decode file at \(testDetailsPath). Error: \(error)"
                            )
                        }
                    } else {
                        print("Test details file does not exist: \(testDetailsPath)")
                    }
                }
            } else {
                print("Failed to read contents of directory: \(parentDir)")
            }

            print("Collected \(previousRuns.count) previous runs")
            return previousRuns
        }

        func htmlEscape(_ input: String) -> String {
            return input
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&#39;")
        }

        func urlEncodePath(_ path: String) -> String {
            return path.split(separator: "/").map { component in
                component.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
                    ?? String(component)
            }.joined(separator: "/")
        }

        func xcodeURL(filePath: String, line: Int, column: Int?) -> String? {
            var allowed = CharacterSet.urlQueryAllowed
            allowed.remove(charactersIn: "&=?")
            guard let encodedFilePath = filePath.addingPercentEncoding(withAllowedCharacters: allowed)
            else { return nil }

            var url = "xcode://open?file=\(encodedFilePath)&line=\(line)"
            if let column {
                url += "&column=\(column)"
            }
            return url
        }

        func extractSourceLocations(from text: String) -> [SourceLocation] {
            let patterns = [
                #"([A-Za-z0-9_~\./\\-]+\.(?:swift|m|mm|c|cc|cpp|h|hpp|kt|java|js|ts|tsx|py|rb|go|rs)):(\d+)(?::(\d+))?"#,
                #"\(([^()]+\.(?:swift|m|mm|c|cc|cpp|h|hpp|kt|java|js|ts|tsx|py|rb|go|rs)):(\d+)(?::(\d+))?\)"#,
            ]

            var allMatches = [SourceLocation]()
            let nsText = text as NSString

            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                let matches = regex.matches(
                    in: text, options: [], range: NSRange(location: 0, length: nsText.length))

                for match in matches {
                    guard match.numberOfRanges >= 3 else { continue }
                    let filePath = nsText.substring(with: match.range(at: 1))
                    let lineRaw = nsText.substring(with: match.range(at: 2))
                    guard let line = Int(lineRaw) else { continue }

                    var column: Int? = nil
                    if match.numberOfRanges >= 4, match.range(at: 3).location != NSNotFound {
                        let columnRaw = nsText.substring(with: match.range(at: 3))
                        column = Int(columnRaw)
                    }

                    allMatches.append(SourceLocation(filePath: filePath, line: line, column: column))
                }
            }

            var deduped = [SourceLocation]()
            var seen = Set<String>()
            for location in allMatches {
                let key = "\(location.filePath)|\(location.line)|\(location.column ?? -1)"
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                deduped.append(location)
            }
            return deduped
        }

        func extractRunDetailTexts(from testRuns: [TestRunDetail]) -> [String] {
            var texts = [String]()
            for run in testRuns {
                texts.append(run.name)
                for child in run.children ?? [] {
                    texts.append(child.name)
                    for detail in child.children ?? [] {
                        texts.append(detail.name)
                    }
                }
            }
            return texts
        }

        func renderSourceLocationSection(candidateTexts: [String]) -> String {
            let locations = candidateTexts.flatMap { extractSourceLocations(from: $0) }
            guard !locations.isEmpty else { return "" }

            let items = locations.prefix(20).map { location -> String in
                let columnSuffix = location.column.map { ":\($0)" } ?? ""
                let locationLabel = "\(location.filePath):\(location.line)\(columnSuffix)"
                let locationCode = "<code>\(htmlEscape(locationLabel))</code>"

                if let xcodeUrl = xcodeURL(
                    filePath: location.filePath, line: location.line, column: location.column)
                {
                    return "<li>\(locationCode) <a href=\"\(xcodeUrl)\">Open in Xcode</a></li>"
                }
                return "<li>\(locationCode)</li>"
            }.joined(separator: "")

            return """
                <h3>Source Locations</h3>
                <ul>\(items)</ul>
                """
        }

        func extractStackTracePreview(
            for testIdentifier: String?,
            attachmentsByTestIdentifier: [String: [AttachmentManifestItem]]
        ) -> StackTracePreview? {
            guard let testIdentifier else { return nil }
            let attachments = attachmentsByTestIdentifier[testIdentifier] ?? []
            guard !attachments.isEmpty else { return nil }

            let attachmentRoot = (outputDir as NSString).appendingPathComponent("attachments")
            var best: StackTracePreview? = nil

            for attachment in attachments {
                let ext = URL(fileURLWithPath: attachment.exportedFileName).pathExtension.lowercased()
                guard ["txt", "log", "crash", "ips"].contains(ext) else { continue }

                let absolutePath =
                    (attachmentRoot as NSString).appendingPathComponent(attachment.exportedFileName)
                guard let fileData = FileManager.default.contents(atPath: absolutePath) else { continue }
                let limitedData = Data(fileData.prefix(220_000))
                guard let text = String(data: limitedData, encoding: .utf8) else { continue }

                let lines = text.components(separatedBy: .newlines)
                var frameLineIndexes = [Int]()
                for (index, line) in lines.enumerated() {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    let isFrameLine =
                        trimmed.range(of: #"^#\d+"#, options: .regularExpression) != nil
                        || trimmed.range(
                            of: #"^\d+\s+\S+\s+0x[0-9a-fA-F]+"#, options: .regularExpression) != nil
                        || trimmed.range(
                            of: #"^\d+\s+\S+\s+[A-Za-z_]\w*.*\+"#, options: .regularExpression) != nil

                    if isFrameLine {
                        frameLineIndexes.append(index)
                    }
                }

                guard frameLineIndexes.count >= 3 else { continue }
                let firstIndex = frameLineIndexes[0]
                let lastIndex = frameLineIndexes[min(frameLineIndexes.count - 1, 20)]
                let start = max(0, firstIndex - 2)
                let end = min(lines.count - 1, lastIndex + 2)
                let preview = lines[start...end].joined(separator: "\n").trimmingCharacters(
                    in: .whitespacesAndNewlines)
                guard !preview.isEmpty else { continue }

                let candidate = StackTracePreview(
                    attachmentName: attachment.suggestedHumanReadableName ?? attachment.exportedFileName,
                    relativePath: "attachments/\(urlEncodePath(attachment.exportedFileName))",
                    preview: preview,
                    frameCount: frameLineIndexes.count
                )

                if best == nil || candidate.frameCount > best!.frameCount {
                    best = candidate
                }
            }

            return best
        }

        func renderStackTraceSection(
            for testIdentifier: String?,
            attachmentsByTestIdentifier: [String: [AttachmentManifestItem]]
        ) -> String {
            guard
                let stack = extractStackTracePreview(
                    for: testIdentifier, attachmentsByTestIdentifier: attachmentsByTestIdentifier)
            else { return "" }

            return """
                <h3>Stack Trace (Preview)</h3>
                <p><a href="\(stack.relativePath)" target="_blank" rel="noopener">\(htmlEscape(stack.attachmentName))</a></p>
                <pre class="stack-trace">\(htmlEscape(stack.preview))</pre>
                """
        }

        func videoMimeType(for fileName: String) -> String {
            let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
            switch ext {
            case "mov":
                return "video/quicktime"
            case "m4v":
                return "video/x-m4v"
            default:
                return "video/mp4"
            }
        }

        func isVideoAttachment(_ attachment: AttachmentManifestItem) -> Bool {
            let ext = URL(fileURLWithPath: attachment.exportedFileName).pathExtension.lowercased()
            if ["mp4", "mov", "m4v"].contains(ext) {
                return true
            }

            if let humanReadableName = attachment.suggestedHumanReadableName?.lowercased(),
                humanReadableName.contains("screen recording")
            {
                return true
            }

            return false
        }

        func parseSnapshotTimestamp(from label: String) -> Double? {
            let patterns = [
                ("'UI Snapshot 'yyyy-MM-dd 'at' h.mm.ss a", "UI Snapshot "),
                ("'Screenshot 'yyyy-MM-dd 'at' h.mm.ss a", "Screenshot "),
            ]

            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current

            for (format, prefix) in patterns where label.hasPrefix(prefix) {
                formatter.dateFormat = format
                if let date = formatter.date(from: label) {
                    return date.timeIntervalSince1970
                }
            }

            return nil
        }

        func isScreenshotAttachment(_ attachment: AttachmentManifestItem) -> Bool {
            let ext = URL(fileURLWithPath: attachment.exportedFileName).pathExtension.lowercased()
            if ["png", "jpg", "jpeg", "heic", "gif", "webp", "tiff", "bmp"].contains(ext) {
                return true
            }

            if let humanReadableName = attachment.suggestedHumanReadableName?.lowercased(),
                humanReadableName.contains("snapshot")
                    || humanReadableName.contains("screenshot")
            {
                return true
            }

            return false
        }

        func jsStringEscape(_ input: String) -> String {
            return input
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "")
        }

        func formatTimelineOffset(_ offset: Double) -> String {
            let safeSeconds = max(0, Int(offset.rounded()))
            let hours = safeSeconds / 3600
            let minutes = (safeSeconds % 3600) / 60
            let seconds = safeSeconds % 60

            if hours > 0 {
                return String(format: "%d:%02d:%02d", hours, minutes, seconds)
            }
            return String(format: "%02d:%02d", minutes, seconds)
        }

        func collectActivityAttachmentTimestamps(
            from activities: [TestActivity], into storage: inout [String: [Double]]
        ) {
            for activity in activities {
                for attachment in activity.attachments ?? [] {
                    guard let timestamp = attachment.timestamp else { continue }
                    storage[attachment.name, default: []].append(timestamp)
                }
                if let children = activity.childActivities {
                    collectActivityAttachmentTimestamps(from: children, into: &storage)
                }
            }
        }

        func collectEarliestActivityTimestamp(from activities: [TestActivity]) -> Double? {
            var earliest: Double?

            func traverse(_ nodes: [TestActivity]) {
                for node in nodes {
                    if let start = node.startTime {
                        if earliest == nil || start < earliest! {
                            earliest = start
                        }
                    }

                    for attachment in node.attachments ?? [] {
                        if let timestamp = attachment.timestamp {
                            if earliest == nil || timestamp < earliest! {
                                earliest = timestamp
                            }
                        }
                    }

                    if let children = node.childActivities {
                        traverse(children)
                    }
                }
            }

            traverse(activities)
            return earliest
        }

        func keyedArchiveUIDIndex(_ value: Any?) -> Int? {
            guard let value else { return nil }
            if let directInt = value as? Int { return directInt }

            let description = String(describing: value)
            guard let markerRange = description.range(of: "value = ") else { return nil }
            let suffix = description[markerRange.upperBound...]
            let digits = suffix.prefix { $0.isWholeNumber }
            return digits.isEmpty ? nil : Int(digits)
        }

        func keyedArchiveObject(_ reference: Any?, objects: [Any]) -> Any? {
            guard let reference else { return nil }
            if let index = keyedArchiveUIDIndex(reference), index >= 0, index < objects.count {
                return objects[index]
            }
            return reference
        }

        func keyedArchiveArray(_ reference: Any?, objects: [Any]) -> [Any] {
            guard
                let archiveObject = keyedArchiveObject(reference, objects: objects) as? [String: Any],
                let itemRefs = archiveObject["NS.objects"] as? [Any]
            else { return [] }

            return itemRefs.compactMap { keyedArchiveObject($0, objects: objects) }
        }

        func keyedArchiveDictionary(_ reference: Any?, objects: [Any]) -> [String: Any] {
            guard
                let archiveObject = keyedArchiveObject(reference, objects: objects) as? [String: Any],
                let keyRefs = archiveObject["NS.keys"] as? [Any],
                let valueRefs = archiveObject["NS.objects"] as? [Any]
            else { return [:] }

            var dictionary = [String: Any](minimumCapacity: min(keyRefs.count, valueRefs.count))
            for index in 0..<min(keyRefs.count, valueRefs.count) {
                guard
                    let keyObject = keyedArchiveObject(keyRefs[index], objects: objects),
                    let key = keyObject as? String
                else { continue }

                dictionary[key] = keyedArchiveObject(valueRefs[index], objects: objects)
            }
            return dictionary
        }

        func keyedArchiveDouble(_ reference: Any?, objects: [Any]) -> Double? {
            guard let value = keyedArchiveObject(reference, objects: objects) else { return nil }
            if let number = value as? NSNumber {
                return number.doubleValue
            }
            if let string = value as? String {
                return Double(string)
            }
            return nil
        }

        func parseSynthesizedEventGesture(
            at filePath: String, baseTimestamp: Double
        ) -> TouchGestureOverlay? {
            guard let data = FileManager.default.contents(atPath: filePath) else { return nil }
            let plistObject = (try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil))
            guard let plistObject else { return nil }

            guard
                let root = plistObject as? [String: Any],
                let objects = root["$objects"] as? [Any],
                let top = root["$top"] as? [String: Any],
                let rootArchiveObject = keyedArchiveObject(top["root"], objects: objects) as? [String: Any]
            else { return nil }

            let parentWindow = keyedArchiveDictionary(
                rootArchiveObject["parentWindowSize"], objects: objects)
            let width = (parentWindow["Width"] as? NSNumber)?.doubleValue ?? 0
            let height = (parentWindow["Height"] as? NSNumber)?.doubleValue ?? 0

            let eventPaths = keyedArchiveArray(rootArchiveObject["eventPaths"], objects: objects)
            guard !eventPaths.isEmpty else { return nil }

            var points = [TouchGesturePoint]()
            points.reserveCapacity(16)

            for eventPathObject in eventPaths {
                guard let eventPath = eventPathObject as? [String: Any] else { continue }
                let pointerEvents = keyedArchiveArray(eventPath["pointerEvents"], objects: objects)

                for pointerEventObject in pointerEvents {
                    guard let pointerEvent = pointerEventObject as? [String: Any] else { continue }
                    guard
                        let x = keyedArchiveDouble(pointerEvent["coordinate.x"], objects: objects),
                        let y = keyedArchiveDouble(pointerEvent["coordinate.y"], objects: objects)
                    else { continue }

                    let offset = keyedArchiveDouble(pointerEvent["offset"], objects: objects) ?? 0
                    let clampedX = min(max(0, x), width)
                    let clampedY = min(max(0, y), height)
                    let absoluteTime = baseTimestamp + max(0, offset)
                    points.append(TouchGesturePoint(time: absoluteTime, x: clampedX, y: clampedY))
                }
            }

            guard !points.isEmpty else { return nil }
            points.sort { $0.time < $1.time }

            guard let first = points.first, let last = points.last else { return nil }
            return TouchGestureOverlay(
                startTime: first.time,
                endTime: last.time,
                width: width,
                height: height,
                points: points
            )
        }

        func parseSynthesizedEventTimestamp(from label: String) -> Double? {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = "'Synthesized Event 'yyyy-MM-dd 'at' h.mm.ss a"
            return formatter.date(from: label)?.timeIntervalSince1970
        }

        func buildTouchGestures(
            from nodes: [TimelineNode],
            testIdentifier: String,
            attachmentsByTestIdentifier: [String: [AttachmentManifestItem]]
        ) -> [TouchGestureOverlay] {
            var flatNodes = [TimelineNode]()
            flattenTimelineNodes(nodes, into: &flatNodes)

            let attachmentRoot = (outputDir as NSString).appendingPathComponent("attachments")
            var parsedCache = [String: TouchGestureOverlay?]()
            var gestures = [TouchGestureOverlay]()
            var seenGestureKeys = Set<String>()
            var seenExportedFiles = Set<String>()

            for node in flatNodes {
                for attachment in node.attachments {
                    guard
                        attachment.name.localizedCaseInsensitiveContains("synthesized event"),
                        let relativePath = attachment.relativePath
                    else { continue }

                    let fileName = relativePath
                        .replacingOccurrences(of: "attachments/", with: "")
                        .removingPercentEncoding ?? relativePath.replacingOccurrences(
                        of: "attachments/", with: "")
                    let filePath = (attachmentRoot as NSString).appendingPathComponent(fileName)
                    seenExportedFiles.insert(fileName)

                    let baseTimestamp = attachment.timestamp ?? node.timestamp
                    guard let baseTimestamp else { continue }

                    let cacheKey = "\(filePath)|\(String(format: "%.6f", baseTimestamp))"
                    let overlay: TouchGestureOverlay?
                    if let cached = parsedCache[cacheKey] {
                        overlay = cached
                    } else {
                        let parsed = parseSynthesizedEventGesture(
                            at: filePath, baseTimestamp: baseTimestamp)
                        parsedCache[cacheKey] = parsed
                        overlay = parsed
                    }

                    guard let overlay else { continue }
                    let dedupeKey = cacheKey
                    guard !seenGestureKeys.contains(dedupeKey) else { continue }
                    seenGestureKeys.insert(dedupeKey)
                    gestures.append(overlay)
                }
            }

            for attachment in attachmentsByTestIdentifier[testIdentifier] ?? [] {
                let label = attachment.suggestedHumanReadableName ?? attachment.exportedFileName
                guard label.localizedCaseInsensitiveContains("synthesized event") else { continue }
                guard !seenExportedFiles.contains(attachment.exportedFileName) else { continue }
                guard let baseTimestamp = parseSynthesizedEventTimestamp(from: label) else { continue }

                let filePath = (attachmentRoot as NSString).appendingPathComponent(
                    attachment.exportedFileName)
                let cacheKey = "\(filePath)|\(String(format: "%.6f", baseTimestamp))"
                let overlay: TouchGestureOverlay?
                if let cached = parsedCache[cacheKey] {
                    overlay = cached
                } else {
                    let parsed = parseSynthesizedEventGesture(
                        at: filePath, baseTimestamp: baseTimestamp)
                    parsedCache[cacheKey] = parsed
                    overlay = parsed
                }

                guard let overlay else { continue }
                guard !seenGestureKeys.contains(cacheKey) else { continue }
                seenGestureKeys.insert(cacheKey)
                gestures.append(overlay)
                seenExportedFiles.insert(attachment.exportedFileName)
            }

            let fallbackSizeGesture = gestures.first { $0.width > 1 && $0.height > 1 }
            let fallbackWidth = fallbackSizeGesture?.width ?? 402
            let fallbackHeight = fallbackSizeGesture?.height ?? 874

            let normalizedGestures = gestures.map { gesture -> TouchGestureOverlay in
                guard gesture.width <= 1 || gesture.height <= 1 else { return gesture }

                let maxX = gesture.points.map(\.x).max() ?? 0
                let maxY = gesture.points.map(\.y).max() ?? 0
                let inferredWidth = max(fallbackWidth, maxX + 1)
                let inferredHeight = max(fallbackHeight, maxY + 1)

                return TouchGestureOverlay(
                    startTime: gesture.startTime,
                    endTime: gesture.endTime,
                    width: inferredWidth,
                    height: inferredHeight,
                    points: gesture.points
                )
            }

            let sortedGestures = normalizedGestures.sorted { $0.startTime < $1.startTime }
            return sortedGestures
        }

        func buildAttachmentLookup(
            for testIdentifier: String, attachmentsByTestIdentifier: [String: [AttachmentManifestItem]]
        ) -> [String: [AttachmentManifestItem]] {
            var lookup = [String: [AttachmentManifestItem]]()
            for attachment in attachmentsByTestIdentifier[testIdentifier] ?? [] {
                if let name = attachment.suggestedHumanReadableName {
                    lookup[name, default: []].append(attachment)
                }
            }
            return lookup
        }

        func buildVideoSources(
            for testIdentifier: String, activities: TestActivities?,
            attachmentsByTestIdentifier: [String: [AttachmentManifestItem]]
        ) -> [VideoSource] {
            let allAttachments = attachmentsByTestIdentifier[testIdentifier] ?? []
            let videoAttachments = allAttachments.filter { isVideoAttachment($0) }
            guard !videoAttachments.isEmpty else { return [] }

            let rootActivities = activities?.testRuns.flatMap { $0.activities } ?? []
            var attachmentTimestamps = [String: [Double]]()
            collectActivityAttachmentTimestamps(from: rootActivities, into: &attachmentTimestamps)
            let fallbackStartTime = collectEarliestActivityTimestamp(from: rootActivities)

            return videoAttachments.map { attachment in
                let label = attachment.suggestedHumanReadableName ?? attachment.exportedFileName
                let startTime = attachmentTimestamps[label]?.min() ?? fallbackStartTime

                return VideoSource(
                    label: label,
                    fileName: attachment.exportedFileName,
                    mimeType: videoMimeType(for: attachment.exportedFileName),
                    startTime: startTime,
                    failureAssociated: attachment.isAssociatedWithFailure ?? false
                )
            }
        }

        func buildScreenshotSources(
            for testIdentifier: String, activities: TestActivities?,
            attachmentsByTestIdentifier: [String: [AttachmentManifestItem]]
        ) -> [ScreenshotSource] {
            let allAttachments = attachmentsByTestIdentifier[testIdentifier] ?? []
            let screenshotAttachments = allAttachments.filter { isScreenshotAttachment($0) }
            guard !screenshotAttachments.isEmpty else { return [] }

            let rootActivities = activities?.testRuns.flatMap { $0.activities } ?? []
            var attachmentTimestamps = [String: [Double]]()
            collectActivityAttachmentTimestamps(from: rootActivities, into: &attachmentTimestamps)
            let fallbackStartTime = collectEarliestActivityTimestamp(from: rootActivities)

            var seenSources = Set<String>()
            let mapped = screenshotAttachments.compactMap { attachment -> ScreenshotSource? in
                let label = attachment.suggestedHumanReadableName ?? attachment.exportedFileName
                let timestamp =
                    attachmentTimestamps[label]?.min() ?? parseSnapshotTimestamp(from: label)
                    ?? fallbackStartTime
                guard let timestamp else { return nil }

                let src = "attachments/\(urlEncodePath(attachment.exportedFileName))"
                guard !seenSources.contains(src) else { return nil }
                seenSources.insert(src)

                return ScreenshotSource(
                    label: label,
                    src: src,
                    time: timestamp,
                    failureAssociated: attachment.isAssociatedWithFailure ?? false
                )
            }

            return mapped.sorted { lhs, rhs in
                if lhs.time == rhs.time { return lhs.label < rhs.label }
                return lhs.time < rhs.time
            }
        }

        func buildTimelineNodes(
            from activities: [TestActivity], attachmentLookup: [String: [AttachmentManifestItem]],
            nextId: inout Int
        ) -> [TimelineNode] {
            return activities.map { activity in
                let nodeId = "timeline_event_\(nextId)"
                nextId += 1

                var seenAttachments = Set<String>()
                let attachments: [TimelineAttachment] = (activity.attachments ?? []).compactMap {
                    attachment -> TimelineAttachment? in
                    let key = "\(attachment.name)|\(attachment.timestamp ?? -1)"
                    guard !seenAttachments.contains(key) else { return nil }
                    seenAttachments.insert(key)

                    let matching = attachmentLookup[attachment.name]?.first
                    let relativePath =
                        matching != nil ? "attachments/\(urlEncodePath(matching!.exportedFileName))" : nil
                    return TimelineAttachment(
                        name: attachment.name,
                        timestamp: attachment.timestamp,
                        relativePath: relativePath,
                        failureAssociated: matching?.isAssociatedWithFailure ?? false
                    )
                }

                let timestamp = activity.startTime ?? attachments.compactMap { $0.timestamp }.min()
                let children = buildTimelineNodes(
                    from: activity.childActivities ?? [], attachmentLookup: attachmentLookup,
                    nextId: &nextId)
                let childEndTimestamp = children.compactMap { $0.endTimestamp ?? $0.timestamp }.max()
                let attachmentEndTimestamp = attachments.compactMap { $0.timestamp }.max()
                let endTimestamp = [timestamp, childEndTimestamp, attachmentEndTimestamp].compactMap { $0 }
                    .max()
                let failureAssociated =
                    activity.isAssociatedWithFailure ?? attachments.contains { $0.failureAssociated }

                return TimelineNode(
                    id: nodeId,
                    title: activity.title,
                    timestamp: timestamp,
                    endTimestamp: endTimestamp,
                    failureAssociated: failureAssociated,
                    attachments: attachments,
                    children: children,
                    repeatCount: 1
                )
            }
        }

        func canMergeTimelineNodes(_ lhs: TimelineNode, _ rhs: TimelineNode) -> Bool {
            return lhs.title == rhs.title
                && lhs.attachments.isEmpty
                && rhs.attachments.isEmpty
                && lhs.children.isEmpty
                && rhs.children.isEmpty
                && lhs.failureAssociated == rhs.failureAssociated
        }

        func collapseRepeatedTimelineNodes(_ nodes: [TimelineNode]) -> [TimelineNode] {
            let normalizedNodes = nodes.map { node in
                let collapsedChildren = collapseRepeatedTimelineNodes(node.children)
                return TimelineNode(
                    id: node.id,
                    title: node.title,
                    timestamp: node.timestamp,
                    endTimestamp: node.endTimestamp ?? node.timestamp,
                    failureAssociated: node.failureAssociated,
                    attachments: node.attachments,
                    children: collapsedChildren,
                    repeatCount: max(node.repeatCount, 1)
                )
            }

            var collapsed = [TimelineNode]()
            var index = 0

            while index < normalizedNodes.count {
                var current = normalizedNodes[index]
                var lookahead = index + 1

                while lookahead < normalizedNodes.count,
                    canMergeTimelineNodes(current, normalizedNodes[lookahead])
                {
                    let next = normalizedNodes[lookahead]
                    current = TimelineNode(
                        id: current.id,
                        title: current.title,
                        timestamp: current.timestamp ?? next.timestamp,
                        endTimestamp: next.endTimestamp ?? next.timestamp ?? current.endTimestamp,
                        failureAssociated: current.failureAssociated || next.failureAssociated,
                        attachments: current.attachments,
                        children: current.children,
                        repeatCount: current.repeatCount + next.repeatCount
                    )
                    lookahead += 1
                }

                collapsed.append(current)
                index = lookahead
            }

            return collapsed
        }

        func flattenTimelineNodes(_ nodes: [TimelineNode], into flat: inout [TimelineNode]) {
            for node in nodes {
                flat.append(node)
                flattenTimelineNodes(node.children, into: &flat)
            }
        }

        func timelineDisplayTitle(_ node: TimelineNode, baseTime: Double?) -> String {
            guard node.repeatCount > 1 else { return node.title }

            if let start = node.timestamp, let end = node.endTimestamp, let baseTime {
                let startText = formatTimelineOffset(start - baseTime)
                let endText = formatTimelineOffset(end - baseTime)
                return "\(node.title) ×\(node.repeatCount) (\(startText)-\(endText))"
            }

            return "\(node.title) ×\(node.repeatCount)"
        }

        func renderTimelineNodesHTML(_ nodes: [TimelineNode], baseTime: Double?, depth: Int) -> String {
            let renderedNodes = nodes.map { node -> String in
                let timeLabel: String
                if let timestamp = node.timestamp, let baseTime {
                    timeLabel = formatTimelineOffset(timestamp - baseTime)
                } else {
                    timeLabel = "--:--"
                }

                let timeAttribute = node.timestamp.map { String(format: "%.6f", $0) } ?? ""
                let hasChildren = !node.children.isEmpty
                var eventClassList = ["timeline-event"]
                if node.failureAssociated {
                    eventClassList.append("timeline-failure")
                }
                let loweredTitle = node.title.lowercased()
                let hasInteractionAttachment = node.attachments.contains {
                    $0.name.lowercased().contains("synthesized event")
                }
                if loweredTitle.hasPrefix("tap ")
                    || loweredTitle.hasPrefix("swipe ")
                    || loweredTitle.contains("synthesize event")
                    || hasInteractionAttachment
                {
                    eventClassList.append("timeline-interaction")
                }
                if hasChildren {
                    eventClassList.append("timeline-has-children")
                }
                let eventClasses = eventClassList.joined(separator: " ")
                let displayTitle = htmlEscape(timelineDisplayTitle(node, baseTime: baseTime))
                let disclosure = hasChildren
                    ? "<span class=\"timeline-disclosure\" aria-hidden=\"true\"></span>"
                    : "<span class=\"timeline-disclosure timeline-disclosure-placeholder\" aria-hidden=\"true\"></span>"
                let row = """
                    <div class="\(eventClasses)" data-event-id="\(node.id)" data-event-time="\(timeAttribute)">
                        \(disclosure)
                        <span class="timeline-title">\(displayTitle)</span>
                        <span class="timeline-time">\(timeLabel)</span>
                    </div>
                    """

                let attachmentList: String
                if node.attachments.isEmpty {
                    attachmentList = ""
                } else {
                    let renderedAttachments = node.attachments.map { attachment -> String in
                        let attachmentName = htmlEscape(attachment.name)
                        let timeText: String
                        if let timestamp = attachment.timestamp, let baseTime {
                            timeText = " @ \(formatTimelineOffset(timestamp - baseTime))"
                        } else {
                            timeText = ""
                        }
                        let linkOrText: String
                        if let relativePath = attachment.relativePath {
                            linkOrText =
                                "<a href=\"\(relativePath)\" target=\"_blank\" rel=\"noopener\">\(attachmentName)</a>"
                        } else {
                            linkOrText = attachmentName
                        }

                        return "<li class=\"timeline-attachment\">\(linkOrText)\(timeText)</li>"
                    }.joined(separator: "")
                    attachmentList = "<ul class=\"timeline-attachments\">\(renderedAttachments)</ul>"
                }

                if node.children.isEmpty {
                    return "<li class=\"timeline-node\" style=\"--timeline-depth: \(depth);\">\(row)\(attachmentList)</li>"
                }

                let childHTML = renderTimelineNodesHTML(node.children, baseTime: baseTime, depth: depth + 1)
                return """
                    <li class="timeline-node" style="--timeline-depth: \(depth);">
                        <details>
                            <summary>\(row)</summary>
                            \(attachmentList)
                            <ul>\(childHTML)</ul>
                        </details>
                    </li>
                    """
            }.joined(separator: "")

            return renderedNodes
        }

        func renderTimelineVideoSection(
            for testIdentifier: String?, activities: TestActivities?,
            attachmentsByTestIdentifier: [String: [AttachmentManifestItem]]
        ) -> String {
            guard let testIdentifier else { return "" }

            let rootActivities = activities?.testRuns.flatMap { $0.activities } ?? []
            let videoSources = buildVideoSources(
                for: testIdentifier, activities: activities,
                attachmentsByTestIdentifier: attachmentsByTestIdentifier)
            let screenshotSources = buildScreenshotSources(
                for: testIdentifier, activities: activities,
                attachmentsByTestIdentifier: attachmentsByTestIdentifier)
            let attachmentLookup = buildAttachmentLookup(
                for: testIdentifier, attachmentsByTestIdentifier: attachmentsByTestIdentifier)

            var nextId = 1
            let timelineNodes = buildTimelineNodes(
                from: rootActivities, attachmentLookup: attachmentLookup, nextId: &nextId)
            let collapsedTimelineNodes = collapseRepeatedTimelineNodes(timelineNodes)

            var flatNodes = [TimelineNode]()
            flattenTimelineNodes(collapsedTimelineNodes, into: &flatNodes)
            let timestampedNodes = flatNodes.filter { $0.timestamp != nil }.sorted {
                ($0.timestamp ?? 0) < ($1.timestamp ?? 0)
            }
            let touchGestures = buildTouchGestures(
                from: collapsedTimelineNodes,
                testIdentifier: testIdentifier,
                attachmentsByTestIdentifier: attachmentsByTestIdentifier
            )
            let touchGestureJSON: String = {
                guard !touchGestures.isEmpty else { return "[]" }
                guard let encoded = try? JSONEncoder().encode(touchGestures) else { return "[]" }
                return String(data: encoded, encoding: .utf8) ?? "[]"
            }()
            let screenshotJSON: String = {
                guard !screenshotSources.isEmpty else { return "[]" }
                guard let encoded = try? JSONEncoder().encode(screenshotSources) else { return "[]" }
                return String(data: encoded, encoding: .utf8) ?? "[]"
            }()

            let timelineBaseTime =
                timestampedNodes.first?.timestamp ?? videoSources.first?.startTime
                ?? screenshotSources.first?.time ?? Date()
                .timeIntervalSince1970
            let defaultVideoStart =
                videoSources.first?.startTime ?? screenshotSources.first?.time ?? timelineBaseTime

            let timelineTree: String
            if collapsedTimelineNodes.isEmpty {
                timelineTree =
                    "<div class=\"timeline-status\">No activity timeline was found for this test.</div>"
            } else {
                timelineTree =
                    "<div class=\"timeline-tree\"><ul class=\"timeline-root\">\(renderTimelineNodesHTML(collapsedTimelineNodes, baseTime: timelineBaseTime, depth: 0))</ul></div>"
            }

            let videoSelector: String
            let videoElements: String
            let mediaMode: String
            let layoutClass: String
            if !videoSources.isEmpty {
                mediaMode = "video"
                layoutClass = ""
                if videoSources.count > 1 {
                    let options = videoSources.enumerated().map { index, source in
                        "<option value=\"\(index)\">\(htmlEscape(source.label))</option>"
                    }.joined(separator: "")
                    videoSelector = "<select class=\"video-selector\" data-video-selector>\(options)</select>"
                } else {
                    videoSelector = ""
                }

                videoElements = videoSources.enumerated().map { index, source in
                    let relativePath = "attachments/\(urlEncodePath(source.fileName))"
                    let startTime = source.startTime ?? timelineBaseTime
                    let hiddenStyle = index == 0 ? "" : " style=\"display:none;\""
                    return """
                        <div class="video-card timeline-video-card"\(hiddenStyle) data-video-index="\(index)">
                            <div class="timeline-video-frame">
                                <video class="timeline-video" preload="metadata" data-video-start="\(startTime)">
                                    <source src="\(relativePath)" type="\(source.mimeType)">
                                    <a href="\(relativePath)">Download video</a>
                                </video>
                                <div class="touch-overlay-layer" data-touch-overlay></div>
                            </div>
                        </div>
                        """
                }.joined(separator: "")
            } else if !screenshotSources.isEmpty {
                mediaMode = "screenshot"
                layoutClass = ""
                videoSelector = ""
                let firstScreenshot = screenshotSources.first!
                let firstAlt = htmlEscape(firstScreenshot.label)
                videoElements = """
                    <div class="video-card timeline-video-card" data-video-index="0">
                        <div class="timeline-video-frame">
                            <img class="timeline-still" data-still-frame src="\(firstScreenshot.src)" alt="\(firstAlt)">
                            <div class="touch-overlay-layer" data-touch-overlay></div>
                        </div>
                    </div>
                    """
            } else {
                mediaMode = "none"
                layoutClass = " timeline-layout-single"
                videoSelector = ""
                videoElements = ""
            }

            let firstEventLabel = timestampedNodes.first.map {
                htmlEscape(timelineDisplayTitle($0, baseTime: timelineBaseTime))
            } ?? "No event selected"
            let eventData = timestampedNodes.map { node in
                let title = jsStringEscape(timelineDisplayTitle(node, baseTime: timelineBaseTime))
                let time = node.timestamp ?? timelineBaseTime
                return "{id:'\(node.id)',title:'\(title)',time:\(time)}"
            }.joined(separator: ",")
            let initialFailureEventIndex = timestampedNodes.firstIndex { $0.failureAssociated } ?? -1
            let videoPanelHtml: String =
                mediaMode == "none"
                ? ""
                : """
                    <div class="video-panel">
                        \(videoSelector)
                        \(videoElements)
                    </div>
                    """

            return """
                <div class="timeline-video-section">
                    <div class="timeline-video-layout\(layoutClass)" data-timeline-root data-media-mode="\(mediaMode)" data-timeline-base="\(timelineBaseTime)" data-video-base="\(defaultVideoStart)">
                        <div class="timeline-panel">
                            <div class="timeline-current" data-active-event>\(firstEventLabel)</div>
                            \(timelineTree)
                        </div>
                        \(videoPanelHtml)
                    </div>
                    <div class="timeline-controls" data-timeline-controls>
                        <input type="range" class="timeline-scrubber" min="0" max="0" step="0.05" value="0" data-scrubber>
                        <div class="timeline-timebar">
                            <span data-playback-time>00:00</span>
                            <span data-total-time>00:00</span>
                        </div>
                        <div class="timeline-buttons">
                            <button type="button" class="timeline-button" data-nav="prev" aria-label="Previous event">
                                <svg class="timeline-icon" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
                                    <path d="M15.5 6L9.5 12L15.5 18L17 16.5L12.5 12L17 7.5Z"></path>
                                </svg>
                            </button>
                            <button type="button" class="timeline-button timeline-button-play" data-nav="play" aria-label="Play or pause">
                                <svg class="timeline-icon" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
                                    <path d="M8 6V18L18 12Z"></path>
                                </svg>
                            </button>
                            <button type="button" class="timeline-button" data-nav="next" aria-label="Next event">
                                <svg class="timeline-icon" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
                                    <path d="M8.5 6L14.5 12L8.5 18L7 16.5L11.5 12L7 7.5Z"></path>
                                </svg>
                            </button>
                        </div>
                    </div>
                </div>
                <script>
                (function() {
                  var root = document.querySelector('[data-timeline-root]');
                  if (!root) return;

                  var controls = document.querySelector('[data-timeline-controls]');
                  var scrubber = controls.querySelector('[data-scrubber]');
                  var timeLabel = controls.querySelector('[data-playback-time]');
                  var totalTimeLabel = controls.querySelector('[data-total-time]');
                  var eventLabel = root.querySelector('[data-active-event]');
                  var playButton = controls.querySelector('[data-nav=\"play\"]');
                  var prevButton = controls.querySelector('[data-nav=\"prev\"]');
                  var nextButton = controls.querySelector('[data-nav=\"next\"]');
                  var selector = root.querySelector('[data-video-selector]');
                  var cards = Array.prototype.slice.call(root.querySelectorAll('[data-video-index]'));
                  var events = [\(eventData)];
                  var initialFailureEventIndex = \(initialFailureEventIndex);
                  var mediaMode = root.dataset.mediaMode || 'video';
                  var touchGestures = \(touchGestureJSON);
                  var screenshots = \(screenshotJSON);
                  var timelineBase = parseFloat(root.dataset.timelineBase || '0');
                  var fallbackVideoBase = parseFloat(root.dataset.videoBase || '0');
                  var activeIndex = 0;
                  var activeEventId = null;
                  var activeEventIndex = -1;
                  var pendingSeekTime = null;
                  var virtualCurrentTime = 0;
                  var virtualDuration = 0;
                  var virtualPlaying = false;
                  var virtualAnimationFrame = 0;
                  var virtualLastTick = 0;
                  var touchMarker = null;
                  var touchAnimationFrame = 0;
                  var scrubPreviewState = null;
                  var TOUCH_RELEASE_DURATION = 0.18;
                  var SCRUB_PREVIEW_WINDOW = 0.22;
                  var PLAY_ICON = '<svg class="timeline-icon" viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path d="M8 6V18L18 12Z"></path></svg>';
                  var PAUSE_ICON = '<svg class="timeline-icon" viewBox="0 0 24 24" aria-hidden="true" focusable="false"><rect x="7" y="6" width="4" height="12" rx="1"></rect><rect x="13" y="6" width="4" height="12" rx="1"></rect></svg>';

                  function formatSeconds(seconds) {
                    var safe = Math.max(0, Math.floor(seconds));
                    var h = Math.floor(safe / 3600);
                    var m = Math.floor((safe % 3600) / 60);
                    var s = safe % 60;
                    if (h > 0) return h + ':' + String(m).padStart(2, '0') + ':' + String(s).padStart(2, '0');
                    return String(m).padStart(2, '0') + ':' + String(s).padStart(2, '0');
                  }

                  function setPlayButtonIcon(isPlaying) {
                    if (!playButton) return;
                    playButton.innerHTML = isPlaying ? PAUSE_ICON : PLAY_ICON;
                  }

                  function getActiveVideoCard() {
                    return cards[activeIndex] || null;
                  }

                  function getActiveVideo() {
                    var card = getActiveVideoCard();
                    return card ? card.querySelector('video') : null;
                  }

                  function getActiveMediaElement() {
                    var video = getActiveVideo();
                    if (video) return video;
                    var card = getActiveVideoCard();
                    return card ? card.querySelector('[data-still-frame]') : null;
                  }

                  function getActiveTouchLayer() {
                    var card = getActiveVideoCard();
                    return card ? card.querySelector('[data-touch-overlay]') : null;
                  }

                  function activeMediaStartTime() {
                    var video = getActiveVideo();
                    if (!video) return timelineBase || fallbackVideoBase || 0;
                    var value = parseFloat(video.dataset.videoStart || '');
                    if (Number.isFinite(value)) return value;
                    return fallbackVideoBase || timelineBase || 0;
                  }

                  function currentAbsoluteTime() {
                    var video = getActiveVideo();
                    if (video) return activeMediaStartTime() + (video.currentTime || 0);
                    return (timelineBase || 0) + (virtualCurrentTime || 0);
                  }

                  function getDisplayedMediaRect(mediaElement) {
                    var containerWidth = mediaElement.clientWidth || 0;
                    var containerHeight = mediaElement.clientHeight || 0;
                    var mediaWidth = mediaElement.videoWidth || mediaElement.naturalWidth || 0;
                    var mediaHeight = mediaElement.videoHeight || mediaElement.naturalHeight || 0;
                    if (!containerWidth || !containerHeight || !mediaWidth || !mediaHeight) {
                      return { x: 0, y: 0, width: containerWidth, height: containerHeight };
                    }

                    var scale = Math.min(containerWidth / mediaWidth, containerHeight / mediaHeight);
                    var width = mediaWidth * scale;
                    var height = mediaHeight * scale;
                    return {
                      x: (containerWidth - width) / 2,
                      y: (containerHeight - height) / 2,
                      width: width,
                      height: height
                    };
                  }

                  function updateStillFrameForTime(absoluteTime) {
                    if (mediaMode !== 'screenshot' || !screenshots.length) return;
                    var frame = root.querySelector('[data-still-frame]');
                    if (!frame) return;

                    var idx = 0;
                    while (idx + 1 < screenshots.length && screenshots[idx + 1].time <= absoluteTime + 0.05) idx += 1;
                    var nextShot = screenshots[idx];
                    if (!nextShot) return;

                    if (frame.dataset.currentSrc !== nextShot.src) {
                      frame.src = nextShot.src;
                      frame.dataset.currentSrc = nextShot.src;
                    }
                    frame.alt = nextShot.label || 'Screenshot';
                  }

                  function setAbsoluteTime(absoluteTime) {
                    var video = getActiveVideo();
                    if (video) {
                      var target = Math.max(0, absoluteTime - activeMediaStartTime());
                      if (video.readyState < 1) {
                        pendingSeekTime = target;
                      } else {
                        video.currentTime = target;
                      }
                      return;
                    }

                    virtualCurrentTime = Math.max(0, Math.min(virtualDuration, absoluteTime - (timelineBase || 0)));
                    updateStillFrameForTime((timelineBase || 0) + virtualCurrentTime);
                  }

                  function ensureTouchMarker(layer) {
                    if (!layer) return null;
                    if (!touchMarker || touchMarker.parentElement !== layer) {
                      if (touchMarker && touchMarker.parentElement) {
                        touchMarker.parentElement.removeChild(touchMarker);
                      }
                      touchMarker = document.createElement('div');
                      touchMarker.className = 'touch-indicator';
                      layer.appendChild(touchMarker);
                    }
                    return touchMarker;
                  }

                  function hideTouchMarker() {
                    if (!touchMarker) return;
                    touchMarker.style.opacity = '0';
                  }

                  function pointForGestureAtTime(gesture, absoluteTime) {
                    if (!gesture || !gesture.points || !gesture.points.length) return null;
                    var points = gesture.points;
                    if (absoluteTime <= points[0].time) {
                      return { x: points[0].x, y: points[0].y };
                    }
                    for (var i = 1; i < points.length; i += 1) {
                      var nextPoint = points[i];
                      if (absoluteTime <= nextPoint.time) {
                        var prevPoint = points[i - 1];
                        var span = Math.max(0.0001, nextPoint.time - prevPoint.time);
                        var ratio = (absoluteTime - prevPoint.time) / span;
                        return {
                          x: prevPoint.x + (nextPoint.x - prevPoint.x) * ratio,
                          y: prevPoint.y + (nextPoint.y - prevPoint.y) * ratio
                        };
                      }
                    }
                    var last = points[points.length - 1];
                    return { x: last.x, y: last.y };
                  }

                  function activeGestureAtTime(absoluteTime, previewMode) {
                    if (!touchGestures.length) return null;
                    var lead = previewMode ? SCRUB_PREVIEW_WINDOW : 0.02;
                    var tail = previewMode ? SCRUB_PREVIEW_WINDOW : TOUCH_RELEASE_DURATION;
                    var best = null;
                    var bestIndex = -1;
                    for (var i = 0; i < touchGestures.length; i += 1) {
                      var gesture = touchGestures[i];
                      if (absoluteTime < gesture.startTime - lead) continue;
                      if (absoluteTime > gesture.endTime + tail) continue;
                      if (!best || gesture.startTime >= best.startTime) {
                        best = gesture;
                        bestIndex = i;
                      }
                    }
                    return best ? { gesture: best, index: bestIndex } : null;
                  }

                  function maybeStartScrubPreview(absoluteTime) {
                    var info = activeGestureAtTime(absoluteTime, true);
                    if (!info) {
                      scrubPreviewState = null;
                      return;
                    }

                    if (scrubPreviewState && scrubPreviewState.index === info.index) {
                      if (Math.abs(absoluteTime - scrubPreviewState.anchorTime) <= 0.35) {
                        return;
                      }
                    }

                    var gesture = info.gesture;
                    scrubPreviewState = {
                      index: info.index,
                      anchorTime: Math.max(gesture.startTime, Math.min(gesture.endTime, absoluteTime)),
                      startedAt: performance.now()
                    };
                    startTouchAnimation();
                  }

                  function updateTouchOverlay() {
                    var media = getActiveMediaElement();
                    var layer = getActiveTouchLayer();
                    if (!media || !layer || !touchGestures.length) {
                      hideTouchMarker();
                      return;
                    }

                    var absoluteTime = currentAbsoluteTime();
                    var previewMode = !(mediaMode === 'video' && getActiveVideo() && !getActiveVideo().paused) && !virtualPlaying;
                    var gesture = null;
                    var pointTime = absoluteTime;
                    var releaseProgress = 0;

                    if (previewMode && scrubPreviewState) {
                      gesture = touchGestures[scrubPreviewState.index] || null;
                      if (gesture) {
                        var elapsed = Math.max(0, (performance.now() - scrubPreviewState.startedAt) / 1000);
                        var animatedTime = scrubPreviewState.anchorTime + elapsed;
                        pointTime = Math.max(gesture.startTime, Math.min(gesture.endTime, animatedTime));
                        if (animatedTime > gesture.endTime) {
                          releaseProgress = Math.min(1, (animatedTime - gesture.endTime) / TOUCH_RELEASE_DURATION);
                        }
                        if (releaseProgress >= 1) {
                          scrubPreviewState = null;
                        }
                      } else {
                        scrubPreviewState = null;
                      }
                    }

                    if (!gesture) {
                      var gestureInfo = activeGestureAtTime(absoluteTime, previewMode);
                      gesture = gestureInfo ? gestureInfo.gesture : null;
                      if (previewMode && !gesture) {
                        scrubPreviewState = null;
                      }
                      if (previewMode && gesture) {
                        pointTime = Math.max(gesture.startTime, Math.min(gesture.endTime, absoluteTime));
                      }
                    }

                    if (!gesture) {
                      hideTouchMarker();
                      return;
                    }

                    var marker = ensureTouchMarker(layer);
                    if (!marker) return;
                    var point = pointForGestureAtTime(gesture, pointTime);
                    if (!point) {
                      hideTouchMarker();
                      return;
                    }

                    var rect = getDisplayedMediaRect(media);
                    if (rect.width <= 0 || rect.height <= 0 || gesture.width <= 0 || gesture.height <= 0) {
                      hideTouchMarker();
                      return;
                    }

                    var normalizedX = Math.min(1, Math.max(0, point.x / gesture.width));
                    var normalizedY = Math.min(1, Math.max(0, point.y / gesture.height));
                    var x = rect.x + normalizedX * rect.width;
                    var y = rect.y + normalizedY * rect.height;

                    if (!previewMode && absoluteTime > gesture.endTime) {
                      releaseProgress = Math.min(1, (absoluteTime - gesture.endTime) / TOUCH_RELEASE_DURATION);
                    }
                    var scale = 1 + (releaseProgress * 0.65);
                    var isActiveTouch = previewMode ? (releaseProgress <= 0) : (absoluteTime <= gesture.endTime);
                    var opacity = isActiveTouch ? 0.9 : (1 - releaseProgress) * 0.9;

                    marker.style.left = x + 'px';
                    marker.style.top = y + 'px';
                    marker.style.opacity = String(Math.max(0, opacity));
                    marker.style.transform = 'translate(-50%, -50%) scale(' + scale.toFixed(3) + ')';
                  }

                  function stopTouchAnimation() {
                    if (!touchAnimationFrame) return;
                    cancelAnimationFrame(touchAnimationFrame);
                    touchAnimationFrame = 0;
                  }

                  function startTouchAnimation() {
                    if (touchAnimationFrame) return;
                    function tick() {
                      touchAnimationFrame = 0;
                      updateTouchOverlay();
                      var video = getActiveVideo();
                      var shouldContinue = (video && !video.paused) || (!video && virtualPlaying) || !!scrubPreviewState;
                      if (shouldContinue) {
                        touchAnimationFrame = requestAnimationFrame(tick);
                      }
                    }
                    touchAnimationFrame = requestAnimationFrame(tick);
                  }

                  function stopVirtualPlayback() {
                    if (!virtualPlaying && !virtualAnimationFrame) return;
                    virtualPlaying = false;
                    virtualLastTick = 0;
                    if (virtualAnimationFrame) {
                      cancelAnimationFrame(virtualAnimationFrame);
                      virtualAnimationFrame = 0;
                    }
                    stopTouchAnimation();
                    updateFromVideoTime();
                  }

                  function startVirtualPlayback() {
                    if (virtualPlaying || virtualDuration <= 0) return;
                    virtualPlaying = true;
                    virtualLastTick = 0;

                    function tick(timestamp) {
                      if (!virtualPlaying) return;
                      if (!virtualLastTick) virtualLastTick = timestamp;
                      var delta = Math.max(0, (timestamp - virtualLastTick) / 1000);
                      virtualLastTick = timestamp;
                      virtualCurrentTime = Math.min(virtualDuration, virtualCurrentTime + delta);
                      updateFromVideoTime();
                      if (virtualCurrentTime >= virtualDuration) {
                        stopVirtualPlayback();
                        return;
                      }
                      virtualAnimationFrame = requestAnimationFrame(tick);
                    }

                    virtualAnimationFrame = requestAnimationFrame(tick);
                    startTouchAnimation();
                    updateFromVideoTime();
                  }

                  function eventIndexById(eventId) {
                    if (!eventId) return -1;
                    for (var i = 0; i < events.length; i += 1) {
                      if (events[i].id === eventId) return i;
                    }
                    return -1;
                  }

                  function expandAncestorDetails(node) {
                    var details = node ? node.closest('details') : null;
                    while (details) {
                      details.open = true;
                      details = details.parentElement ? details.parentElement.closest('details') : null;
                    }
                  }

                  function setActiveEvent(eventId, shouldReveal) {
                    if (!eventId) return;
                    var idx = eventIndexById(eventId);
                    if (idx >= 0) activeEventIndex = idx;
                    if (eventId === activeEventId) return;
                    var oldActive = root.querySelector('.timeline-event.timeline-active');
                    if (oldActive) oldActive.classList.remove('timeline-active');
                    var next = root.querySelector('.timeline-event[data-event-id=\"' + eventId + '\"]');
                    if (next) {
                      if (shouldReveal) {
                        expandAncestorDetails(next);
                      }
                      next.classList.add('timeline-active');
                      if (shouldReveal) {
                        next.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
                      }
                    }
                    activeEventId = eventId;
                  }

                  function jumpToEventByIndex(index, shouldReveal) {
                    if (!events.length) return;
                    if (index < 0 || index >= events.length) return;
                    var event = events[index];
                    setActiveEvent(event.id, shouldReveal);
                    if (eventLabel) eventLabel.textContent = event.title;
                    setAbsoluteTime(event.time);
                    updateFromVideoTime();
                  }

                  function eventIndexForAbsoluteTime(absTime) {
                    if (!events.length) return -1;
                    var idx = 0;
                    while (idx + 1 < events.length && events[idx + 1].time <= absTime + 0.05) idx += 1;
                    return idx;
                  }

                  function currentEventIndexForNavigation() {
                    if (activeEventIndex >= 0 && activeEventIndex < events.length) return activeEventIndex;
                    if (!events.length) return -1;
                    var absoluteTime = currentAbsoluteTime();
                    return eventIndexForAbsoluteTime(absoluteTime);
                  }

                  function goToPreviousEvent() {
                    if (!events.length) return;
                    var currentIdx = currentEventIndexForNavigation();
                    if (currentIdx < 0) return;
                    jumpToEventByIndex(Math.max(0, currentIdx - 1), true);
                  }

                  function goToNextEvent() {
                    if (!events.length) return;
                    var currentIdx = currentEventIndexForNavigation();
                    if (currentIdx < 0) return;
                    jumpToEventByIndex(Math.min(events.length - 1, currentIdx + 1), true);
                  }

                  function togglePlayback() {
                    var video = getActiveVideo();
                    if (video) {
                      if (video.paused) {
                        scrubPreviewState = null;
                        video.play().catch(function() {});
                      } else {
                        video.pause();
                      }
                      return;
                    }
                    if (virtualPlaying) {
                      stopVirtualPlayback();
                    } else {
                      startVirtualPlayback();
                    }
                  }

                  function isKeyboardEditableTarget(target) {
                    if (!target || !(target instanceof Element)) return false;
                    if (target.closest('[contenteditable=\"true\"]')) return true;
                    var interactive = target.closest('input, textarea, select, button, a');
                    if (!interactive) return false;
                    if (interactive.tagName === 'INPUT' && interactive.type === 'range') return false;
                    return true;
                  }

                  function updateFromVideoTime() {
                    var video = getActiveVideo();
                    var absoluteTime = 0;
                    if (video) {
                      scrubber.value = video.currentTime || 0;
                      absoluteTime = activeMediaStartTime() + (video.currentTime || 0);
                    } else {
                      scrubber.value = virtualCurrentTime || 0;
                      absoluteTime = (timelineBase || 0) + (virtualCurrentTime || 0);
                      updateStillFrameForTime(absoluteTime);
                    }
                    var idx = eventIndexForAbsoluteTime(absoluteTime);
                    if (video && pendingSeekTime != null && activeEventIndex >= 0 && activeEventIndex < events.length) {
                      idx = activeEventIndex;
                    }
                    if (video && video.paused && activeEventIndex >= 0 && activeEventIndex < events.length) {
                      var selected = events[activeEventIndex];
                      if (Math.abs((selected.time || 0) - absoluteTime) <= 0.06) {
                        idx = activeEventIndex;
                      }
                    }
                    if (idx >= 0) {
                      setActiveEvent(events[idx].id, false);
                      if (eventLabel) eventLabel.textContent = events[idx].title;
                    }
                    var currentOffset = video ? (video.currentTime || 0) : (virtualCurrentTime || 0);
                    timeLabel.textContent = formatSeconds(currentOffset);
                    var duration = video ? (Number.isFinite(video.duration) ? video.duration : 0) : virtualDuration;
                    if (totalTimeLabel) totalTimeLabel.textContent = formatSeconds(duration);
                    setPlayButtonIcon(video ? !video.paused : virtualPlaying);
                    updateTouchOverlay();
                  }

                  function clampScrubber(video) {
                    if (!video) {
                      scrubber.max = virtualDuration;
                      updateFromVideoTime();
                      return;
                    }
                    var hasMetadata = video.readyState >= 1 && Number.isFinite(video.duration);
                    var duration = hasMetadata ? Math.max(0, video.duration) : 0;
                    scrubber.max = duration;
                    if (pendingSeekTime != null && hasMetadata) {
                      video.currentTime = Math.min(duration, Math.max(0, pendingSeekTime));
                      pendingSeekTime = null;
                    }
                    updateFromVideoTime();
                  }

                  function attachVideoHandlers(video) {
                    if (!video) return;
                    video.addEventListener('loadedmetadata', function() { clampScrubber(video); });
                    video.addEventListener('timeupdate', updateFromVideoTime);
                    video.addEventListener('play', function() {
                      updateFromVideoTime();
                      startTouchAnimation();
                    });
                    video.addEventListener('pause', function() {
                      stopTouchAnimation();
                      updateFromVideoTime();
                    });
                    video.addEventListener('seeking', updateFromVideoTime);
                    video.addEventListener('seeked', updateFromVideoTime);
                  }

                  cards.forEach(function(card) {
                    var video = card.querySelector('video');
                    attachVideoHandlers(video);
                  });

                  root.addEventListener('click', function(event) {
                    var node = event.target.closest('.timeline-event[data-event-time]');
                    if (!node) return;
                    var raw = node.getAttribute('data-event-time');
                    if (!raw) return;
                    var absoluteTime = parseFloat(raw);
                    if (!Number.isFinite(absoluteTime)) return;
                    setAbsoluteTime(absoluteTime);
                    setActiveEvent(node.getAttribute('data-event-id'), true);
                    var matched = events.find(function(item) { return item.id === node.getAttribute('data-event-id'); });
                    if (matched && eventLabel) eventLabel.textContent = matched.title;
                    updateFromVideoTime();
                  });

                  prevButton.addEventListener('click', function() {
                    goToPreviousEvent();
                  });

                  nextButton.addEventListener('click', function() {
                    goToNextEvent();
                  });

                  playButton.addEventListener('click', function() {
                    togglePlayback();
                  });

                  scrubber.addEventListener('input', function() {
                    var video = getActiveVideo();
                    var value = parseFloat(scrubber.value || '0');
                    if (video) {
                      video.currentTime = value;
                    } else {
                      virtualCurrentTime = Math.max(0, Math.min(virtualDuration, value));
                    }
                    var absoluteTime = video ? (activeMediaStartTime() + value) : ((timelineBase || 0) + virtualCurrentTime);
                    var idx = eventIndexForAbsoluteTime(absoluteTime);
                    if (idx >= 0) {
                      setActiveEvent(events[idx].id, false);
                      if (eventLabel) eventLabel.textContent = events[idx].title;
                    }
                    maybeStartScrubPreview(absoluteTime);
                    if (!video) {
                      updateStillFrameForTime(absoluteTime);
                    }
                    updateTouchOverlay();
                    updateFromVideoTime();
                  });

                  if (selector) {
                    selector.addEventListener('change', function() {
                      stopTouchAnimation();
                      stopVirtualPlayback();
                      activeIndex = parseInt(selector.value, 10) || 0;
                      cards.forEach(function(card, idx) {
                        var video = card.querySelector('video');
                        if (idx === activeIndex) {
                          card.style.display = '';
                        } else {
                          card.style.display = 'none';
                          if (video) video.pause();
                        }
                      });
                      var activeVideo = getActiveVideo();
                      if (activeVideo) {
                        clampScrubber(activeVideo);
                        updateFromVideoTime();
                        if (!activeVideo.paused) {
                          startTouchAnimation();
                        }
                      }
                    });
                  }

                  window.addEventListener('resize', updateTouchOverlay);

                  window.addEventListener('keydown', function(event) {
                    if (event.defaultPrevented) return;
                    if (isKeyboardEditableTarget(event.target)) return;
                    if (event.metaKey || event.ctrlKey || event.altKey) return;

                    if (event.code === 'Space' || event.key === ' ') {
                      event.preventDefault();
                      togglePlayback();
                      return;
                    }

                    if (event.key === 'ArrowRight' || event.key === 'ArrowDown') {
                      event.preventDefault();
                      goToNextEvent();
                      return;
                    }

                    if (event.key === 'ArrowLeft' || event.key === 'ArrowUp') {
                      event.preventDefault();
                      goToPreviousEvent();
                    }
                  });

                  var lastEventTime = events.length ? events[events.length - 1].time : (timelineBase || 0);
                  var lastScreenshotTime = screenshots.length ? screenshots[screenshots.length - 1].time : (timelineBase || 0);
                  virtualDuration = Math.max(0, Math.max(lastEventTime, lastScreenshotTime) - (timelineBase || 0));
                  setPlayButtonIcon(false);
                  var startingVideo = getActiveVideo();
                  var didFocusFailureOnLoad = false;
                  if (initialFailureEventIndex >= 0 && events.length) {
                    var focusIndex = Math.min(events.length - 1, initialFailureEventIndex);
                    jumpToEventByIndex(focusIndex, true);
                    didFocusFailureOnLoad = true;
                  }
                  if (startingVideo) {
                    clampScrubber(startingVideo);
                    if (!didFocusFailureOnLoad || pendingSeekTime == null) {
                      updateFromVideoTime();
                    }
                    if (!startingVideo.paused) {
                      startTouchAnimation();
                    }
                  } else {
                    clampScrubber(null);
                    if (!didFocusFailureOnLoad) {
                      updateFromVideoTime();
                    }
                  }
                })();
                </script>
                """
        }

        func exportAttachments() -> [String: [AttachmentManifestItem]] {
            let attachmentsDir = (outputDir as NSString).appendingPathComponent("attachments")
            try? FileManager.default.removeItem(atPath: attachmentsDir)
            try? FileManager.default.createDirectory(
                atPath: attachmentsDir, withIntermediateDirectories: true)

            let exportCmd = [
                "xcrun", "xcresulttool", "export", "attachments", "--path", xcresultPath,
                "--output-path", attachmentsDir,
            ]
            print("Running attachment export: \(exportCmd.joined(separator: " "))")
            let (_, exportExit) = shell(exportCmd)
            guard exportExit == 0 else {
                print("Attachment export failed. Continuing without media attachments.")
                return [:]
            }

            let manifestPath = (attachmentsDir as NSString).appendingPathComponent("manifest.json")
            guard FileManager.default.fileExists(atPath: manifestPath) else {
                print("Attachment manifest not found at \(manifestPath)")
                return [:]
            }

            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: manifestPath))
                let manifestEntries = try JSONDecoder().decode([AttachmentManifestEntry].self, from: data)
                var attachmentsByTest = [String: [AttachmentManifestItem]](
                    minimumCapacity: manifestEntries.count)

                for entry in manifestEntries where !entry.attachments.isEmpty {
                    attachmentsByTest[entry.testIdentifier, default: []].append(
                        contentsOf: entry.attachments)
                }

                let totalAttachmentCount = attachmentsByTest.values.reduce(0) { $0 + $1.count }
                let totalVideoCount = attachmentsByTest.values.reduce(0) { partialResult, attachments in
                    partialResult + attachments.filter { isVideoAttachment($0) }.count
                }
                print(
                    "Loaded \(totalAttachmentCount) attachments (\(totalVideoCount) videos) from manifest."
                )

                return attachmentsByTest
            } catch {
                print("Failed to parse attachment manifest: \(error)")
                return [:]
            }
        }

        try? FileManager.default.createDirectory(
            atPath: outputDir, withIntermediateDirectories: true)

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

                    let timelineAndVideoSection = renderTimelineVideoSection(
                        for: test.nodeIdentifier,
                        activities: testActivities,
                        attachmentsByTestIdentifier: attachmentsByTestIdentifier
                    )

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

                    let detailsPanelHtml: String
                    if failureInfo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        detailsPanelHtml = ""
                    } else {
                        detailsPanelHtml = """
                            <details class="test-meta-details">
                                <summary>Details</summary>
                                <div class="test-meta-content">
                                    \(failureInfo)
                                </div>
                            </details>
                            """
                    }
                    let testSubtitle = htmlEscape(test.nodeIdentifier ?? "Test report")

                    let testDetailHTML = """
                        <!DOCTYPE html>
                        <html>
                        <head>
                        <meta charset="UTF-8">
                        <title>Test Detail: \(test.name)</title>
                        <style>
                        \(sharedStyles)
                        </style>
                        </head>
                        <body class="test-detail-page">
                        <div class="test-detail-shell">
                            <header class="test-header-compact">
                                <a class="test-back-link" href="index.html" aria-label="Back to report index">
                                    <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
                                        <path fill="currentColor" d="M14.71 5.29a1 1 0 0 1 0 1.42L10.41 11H20a1 1 0 1 1 0 2h-9.59l4.3 4.29a1 1 0 1 1-1.42 1.42l-6-6a1 1 0 0 1 0-1.42l6-6a1 1 0 0 1 1.42 0Z"/>
                                    </svg>
                                    <span>Back</span>
                                </a>
                                <div class="test-title-group">
                                    <div class="test-title-row">
                                        <h1 class="test-title-compact">\(htmlEscape(test.name))</h1>
                                        <span class="status-badge \(statusBadgeClass)">\(htmlEscape(result))</span>
                                        <span class="test-duration-pill">\(htmlEscape(duration))</span>
                                    </div>
                                    <div class="test-subtitle">\(testSubtitle)</div>
                                </div>
                                <div class="test-header-spacer" aria-hidden="true"></div>
                            </header>
                            \(compactFailureBoxHtml)
                            \(detailsPanelHtml)
                            <main class="test-main-content">
                                \(timelineAndVideoSection)
                            </main>
                        </div>
                        </body>
                        </html>
                        """
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

        // Initialize the HTML template first
        var indexHTML = """
            <!DOCTYPE html>
            <html>
            <head>
            <meta charset="UTF-8">
            <title>Test Report</title>
            <style>
            \(sharedStyles)
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
                indexHTML +=
                    "<p>🛑 Errors: \(buildResults.errorCount) &nbsp; ⚠️ Warnings: \(buildResults.warningCount)</p>"
            }
        }

        if let previousResults = previousResults {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .short
            dateFormatter.timeZone = TimeZone.current
            dateFormatter.locale = Locale(identifier: "en_US")
            let dateString = dateFormatter.string(from: previousResults.date)
                .replacingOccurrences(of: ":", with: "&#58;")
                .replacingOccurrences(of: " ", with: "&#32;")
            indexHTML +=
                "<p class=\"comparison-info\">Compared with previous run from: \(dateString)</p>"
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
