import Dispatch
import Foundation

private let testDetailsCacheLock = NSLock()
private var testDetailsCache = [String: XCTestReport.TestDetails]()
private let testActivitiesCacheLock = NSLock()
private var testActivitiesCache = [String: XCTestReport.TestActivities]()

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
        let cacheKey = "\(xcresultPath)|\(testIdentifier)"
        testDetailsCacheLock.lock()
        if let cached = testDetailsCache[cacheKey] {
            testDetailsCacheLock.unlock()
            return cached
        }
        testDetailsCacheLock.unlock()

        let testDetailsCmd = [
            "xcrun", "xcresulttool", "get", "test-results", "test-details", "--test-id",
            testIdentifier, "--path", xcresultPath, "--format", "json", "--compact",
        ]
        let (testDetailsJSON, exitCode) = shell(testDetailsCmd)
        guard exitCode == 0, let data = testDetailsJSON?.data(using: .utf8) else {
            print("Failed to get test details for: \(testIdentifier)")
            return nil
        }

        // Save test details JSON to test_details folder
        let testDetailsDir = (outputDir as NSString).appendingPathComponent("test_details")
        try? FileManager.default.createDirectory(
            atPath: testDetailsDir, withIntermediateDirectories: true)
        let safeTestIdentifier = testIdentifier.replacingOccurrences(of: "/", with: "_")
        let testDetailsPath = (testDetailsDir as NSString).appendingPathComponent(
            "\(safeTestIdentifier).json")
        try? testDetailsJSON?.write(toFile: testDetailsPath, atomically: true, encoding: .utf8)
        let decoder = JSONDecoder()
        do {
            let result = try decoder.decode(TestDetails.self, from: data)
            testDetailsCacheLock.lock()
            testDetailsCache[cacheKey] = result
            testDetailsCacheLock.unlock()
            return result
        } catch {
            print("Failed to decode test details: \(error)")
            print("What we tried to decode: \(String(data: data, encoding: .utf8) ?? "nil")")
            return nil
        }
    }

    func getTestActivities(for testIdentifier: String) -> TestActivities? {
        let cacheKey = "\(xcresultPath)|\(testIdentifier)"
        testActivitiesCacheLock.lock()
        if let cached = testActivitiesCache[cacheKey] {
            testActivitiesCacheLock.unlock()
            return cached
        }
        testActivitiesCacheLock.unlock()

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
            let activities = try JSONDecoder().decode(TestActivities.self, from: data)
            testActivitiesCacheLock.lock()
            testActivitiesCache[cacheKey] = activities
            testActivitiesCacheLock.unlock()
            return activities
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

        if let contents = try? fileManager.contentsOfDirectory(atPath: parentDir) {
            let previousDirs =
                contents
                .filter { entry in
                    guard entry != currentDirName && entry != ".DS_Store" else { return false }
                    let fullPath = (parentDir as NSString).appendingPathComponent(entry)
                    var isDirectory: ObjCBool = false
                    guard fileManager.fileExists(atPath: fullPath, isDirectory: &isDirectory) else {
                        return false
                    }
                    return isDirectory.boolValue
                }
                .sorted()
                .reversed()

            for dir in previousDirs {
                let fullTestsPath = (parentDir as NSString).appendingPathComponent(
                    "\(dir)/tests_full.json")

                if FileManager.default.fileExists(atPath: fullTestsPath) {
                    if let fullData = try? Data(contentsOf: URL(fileURLWithPath: fullTestsPath))
                    {
                        do {
                            let previousResults = try JSONDecoder().decode(
                                FullTestResults.self, from: fullData)

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

                            let startTime = findFirstValidStartTime(previousResults.testNodes)

                            return TestHistory(
                                date: Date(timeIntervalSince1970: startTime),
                                results: testResults
                            )
                        } catch {
                            continue
                        }
                    }
                }
            }
        }
        return nil
    }

    func getPreviousRuns(for testIdentifier: String) -> [TestRunDetail] {
        var previousRuns = [TestRunDetail]()
        let fileManager = FileManager.default
        let parentDir = (outputDir as NSString).deletingLastPathComponent
        let currentDirName = (outputDir as NSString).lastPathComponent

        if let contents = try? fileManager.contentsOfDirectory(atPath: parentDir) {
            let previousDirs =
                contents
                .filter { entry in
                    guard entry != currentDirName && entry != ".DS_Store" else { return false }
                    let fullPath = (parentDir as NSString).appendingPathComponent(entry)
                    var isDirectory: ObjCBool = false
                    guard fileManager.fileExists(atPath: fullPath, isDirectory: &isDirectory) else {
                        return false
                    }
                    return isDirectory.boolValue
                }
                .sorted()
                .reversed()

            for dir in previousDirs.prefix(10) {
                let testDetailsPath = (parentDir as NSString).appendingPathComponent(
                    "\(dir)/test_details/\(testIdentifier.replacingOccurrences(of: "/", with: "_")).json"
                )

                if fileManager.fileExists(atPath: testDetailsPath) {
                    do {
                        let data = try Data(contentsOf: URL(fileURLWithPath: testDetailsPath))
                        let testDetails = try JSONDecoder().decode(TestDetails.self, from: data)

                        if let testRuns = testDetails.testRuns {
                            previousRuns.append(contentsOf: testRuns)
                        }
                    } catch {
                        print("Failed to load previous run details at \(testDetailsPath): \(error)")
                    }
                }
            }
        }
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

            if compressVideo {
                compressExportedVideosIfPossible(
                    in: attachmentsDir,
                    manifestEntries: manifestEntries,
                    maxDimension: videoHeight
                )
            }

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

    private func compressExportedVideosIfPossible(
        in attachmentsDir: String,
        manifestEntries: [AttachmentManifestEntry],
        maxDimension: Int
    ) {
        guard maxDimension > 0 else {
            print("Video compression skipped: invalid --video-height (\(maxDimension)).")
            return
        }

        guard isFFmpegInstalled() else {
            print("Video compression requested, but ffmpeg was not found. Skipping compression.")
            return
        }

        let videoFileNames = Set(
            manifestEntries
                .flatMap(\.attachments)
                .filter { isVideoAttachment($0) }
                .map(\.exportedFileName)
        )
        guard !videoFileNames.isEmpty else {
            print("No video attachments found to compress.")
            return
        }

        print(
            "Compressing \(videoFileNames.count) video attachment(s) with ffmpeg (max dimension: \(maxDimension))..."
        )

        var compressedCount = 0
        var failedCount = 0
        var skippedCount = 0
        let fileManager = FileManager.default
        let scaleFilter =
            "scale='if(gte(iw,ih),trunc(min(iw,\(maxDimension))/2)*2,-2)':'if(gte(iw,ih),-2,trunc(min(ih,\(maxDimension))/2)*2)'"

        for exportedFileName in videoFileNames.sorted() {
            let inputPath = (attachmentsDir as NSString).appendingPathComponent(exportedFileName)
            guard fileManager.fileExists(atPath: inputPath) else {
                skippedCount += 1
                print("Video compression skipped (missing file): \(exportedFileName)")
                continue
            }

            let inputExtension = URL(fileURLWithPath: inputPath).pathExtension
            let tempOutputPath: String
            if inputExtension.isEmpty {
                tempOutputPath = inputPath + ".compressed"
            } else {
                tempOutputPath = inputPath + ".compressed.\(inputExtension)"
            }
            try? fileManager.removeItem(atPath: tempOutputPath)

            let compressCmd = [
                "ffmpeg",
                "-y",
                "-i",
                inputPath,
                "-map",
                "0:0",
                "-map_chapters",
                "0",
                "-threads",
                "0",
                "-vf",
                scaleFilter,
                "-c:v",
                "hevc_videotoolbox",
                "-pix_fmt",
                "yuv420p",
                "-q:v",
                "50",
                "-allow_sw",
                "1",
                "-movflags",
                "+faststart",
                "-profile:v",
                "main",
                "-vtag",
                "hvc1",
                "-an",
                "-sn",
                "-max_muxing_queue_size",
                "40000",
                "-map_metadata",
                "0",
                tempOutputPath,
            ]

            let (_, compressExit) = shell(compressCmd)
            guard compressExit == 0, fileManager.fileExists(atPath: tempOutputPath) else {
                failedCount += 1
                try? fileManager.removeItem(atPath: tempOutputPath)
                print("Video compression failed: \(exportedFileName)")
                continue
            }

            do {
                try fileManager.removeItem(atPath: inputPath)
                try fileManager.moveItem(atPath: tempOutputPath, toPath: inputPath)
                compressedCount += 1
            } catch {
                failedCount += 1
                print("Video compression replace failed for \(exportedFileName): \(error)")
                try? fileManager.removeItem(atPath: tempOutputPath)
            }
        }

        print(
            "Video compression complete: compressed \(compressedCount), failed \(failedCount), skipped \(skippedCount)."
        )
    }

    private func isFFmpegInstalled() -> Bool {
        let (_, exitCode) = shell(["ffmpeg", "-version"])
        return exitCode == 0
    }
}
