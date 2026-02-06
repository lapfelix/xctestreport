import Dispatch
import Foundation

extension XCTestReport {
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
}
