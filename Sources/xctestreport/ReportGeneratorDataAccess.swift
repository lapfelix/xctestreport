import Dispatch
import Foundation

private let testDetailsCacheLock = NSLock()
private var testDetailsCache = [String: XCTestReport.TestDetails]()
private let testActivitiesCacheLock = NSLock()
private var testActivitiesCache = [String: XCTestReport.TestActivities]()
private let previousRunsCacheLock = NSLock()
private var previousRunsCache = [String: [XCTestReport.TestRunDetail]]()
private let previousRunsDirsCacheLock = NSLock()
private var previousRunsDirsCache = [String: [String]]()

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
        let fileManager = FileManager.default
        let parentDir = (outputDir as NSString).deletingLastPathComponent
        let currentDirName = (outputDir as NSString).lastPathComponent
        let previousRunsCacheKey = "\(parentDir)|\(currentDirName)|\(testIdentifier)"

        previousRunsCacheLock.lock()
        if let cached = previousRunsCache[previousRunsCacheKey] {
            previousRunsCacheLock.unlock()
            return cached
        }
        previousRunsCacheLock.unlock()

        let dirsCacheKey = "\(parentDir)|\(currentDirName)"
        let previousDirs: [String]
        previousRunsDirsCacheLock.lock()
        if let cached = previousRunsDirsCache[dirsCacheKey] {
            previousDirs = cached
            previousRunsDirsCacheLock.unlock()
        } else {
            previousRunsDirsCacheLock.unlock()
            let discoveredDirs: [String]
            if let contents = try? fileManager.contentsOfDirectory(atPath: parentDir) {
                discoveredDirs =
                    contents
                    .filter { entry in
                        guard entry != currentDirName && entry != ".DS_Store" else { return false }
                        let fullPath = (parentDir as NSString).appendingPathComponent(entry)
                        var isDirectory: ObjCBool = false
                        guard fileManager.fileExists(atPath: fullPath, isDirectory: &isDirectory)
                        else {
                            return false
                        }
                        return isDirectory.boolValue
                    }
                    .sorted()
                    .reversed()
            } else {
                discoveredDirs = []
            }
            previousRunsDirsCacheLock.lock()
            previousRunsDirsCache[dirsCacheKey] = discoveredDirs
            previousRunsDirsCacheLock.unlock()
            previousDirs = discoveredDirs
        }

        var previousRuns = [TestRunDetail]()
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

        previousRunsCacheLock.lock()
        previousRunsCache[previousRunsCacheKey] = previousRuns
        previousRunsCacheLock.unlock()
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

            compressBinaryPlistAttachmentsForWebPreviewIfPossible(
                attachmentsByTestIdentifier: &attachmentsByTest)

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

    func compressBinaryPlistAttachmentsForWebPreviewIfPossible(
        attachmentsByTestIdentifier: inout [String: [AttachmentManifestItem]]
    ) {
        let attachmentsDir = (outputDir as NSString).appendingPathComponent("attachments")
        guard FileManager.default.fileExists(atPath: attachmentsDir) else {
            return
        }

        guard isGzipInstalled() else {
            print("Binary plist compression skipped: gzip was not found.")
            return
        }

        let fileManager = FileManager.default
        var candidateCount = 0
        var compressedCount = 0
        var skippedCount = 0
        var failedCount = 0
        var originalBytesTotal: UInt64 = 0
        var compressedBytesTotal: UInt64 = 0
        var renamedFiles = [String: String]()

        let exportedFileNames = Set(
            attachmentsByTestIdentifier
                .values
                .flatMap { $0.map(\.exportedFileName) }
        )
        let synthesizedEventFileNames = Set(
            attachmentsByTestIdentifier
                .values
                .flatMap { $0 }
                .filter {
                    ($0.suggestedHumanReadableName ?? "").localizedCaseInsensitiveContains(
                        "synthesized event")
                }
                .map(\.exportedFileName)
        )
        let candidateFiles = exportedFileNames.sorted().compactMap { exportedFileName -> (String, String)? in
            guard !synthesizedEventFileNames.contains(exportedFileName) else { return nil }
            let inputPath = (attachmentsDir as NSString).appendingPathComponent(exportedFileName)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: inputPath, isDirectory: &isDirectory),
                !isDirectory.boolValue
            else { return nil }
            guard isBinaryPlistFile(at: inputPath) else { return nil }
            return (exportedFileName, inputPath)
        }

        candidateCount = candidateFiles.count
        guard !candidateFiles.isEmpty else {
            print("No binary plist attachments found to compress.")
            return
        }

        // `plutil -p` output is large for UI snapshots. Keep worker count bounded,
        // but allow enough parallelism to reduce end-of-run latency.
        let compressionWorkers = max(1, min(8, ProcessInfo.processInfo.activeProcessorCount))
        let limiter = DispatchSemaphore(value: compressionWorkers)
        let statsLock = NSLock()
        let group = DispatchGroup()
        let compressionQueue = DispatchQueue(label: "binaryPlistCompression", attributes: .concurrent)

        for (exportedFileName, inputPath) in candidateFiles {
            limiter.wait()
            group.enter()
            compressionQueue.async {
                defer {
                    limiter.signal()
                    group.leave()
                }

                let localFileManager = FileManager.default
                let (plutilOutput, plutilExit) = self.shell(["plutil", "-p", inputPath])
                guard plutilExit == 0, let plutilOutput,
                    let previewData = plutilOutput.data(using: .utf8),
                    !previewData.isEmpty
                else {
                    statsLock.lock()
                    failedCount += 1
                    statsLock.unlock()
                    return
                }

                let tempPlainPath = (attachmentsDir as NSString).appendingPathComponent(
                    ".plist-preview-\(UUID().uuidString).txt")
                let tempCompressedPath = tempPlainPath + ".gz"
                defer {
                    try? localFileManager.removeItem(atPath: tempPlainPath)
                    try? localFileManager.removeItem(atPath: tempCompressedPath)
                }

                do {
                    try previewData.write(to: URL(fileURLWithPath: tempPlainPath), options: .atomic)
                } catch {
                    statsLock.lock()
                    failedCount += 1
                    statsLock.unlock()
                    return
                }
                guard self.gzipCompressFile(inputPath: tempPlainPath, outputPath: tempCompressedPath)
                else {
                    statsLock.lock()
                    failedCount += 1
                    statsLock.unlock()
                    return
                }

                guard let originalSize = self.fileSizeInBytes(at: inputPath),
                    let compressedSize = self.fileSizeInBytes(at: tempCompressedPath)
                else {
                    statsLock.lock()
                    failedCount += 1
                    statsLock.unlock()
                    return
                }
                guard compressedSize < originalSize else {
                    statsLock.lock()
                    skippedCount += 1
                    statsLock.unlock()
                    return
                }

                let compressedFileName = exportedFileName + ".gz"
                let destinationPath = (attachmentsDir as NSString).appendingPathComponent(
                    compressedFileName)
                do {
                    try? localFileManager.removeItem(atPath: destinationPath)
                    try localFileManager.removeItem(atPath: inputPath)
                    try localFileManager.moveItem(atPath: tempCompressedPath, toPath: destinationPath)
                    statsLock.lock()
                    compressedCount += 1
                    originalBytesTotal += originalSize
                    compressedBytesTotal += compressedSize
                    renamedFiles[exportedFileName] = compressedFileName
                    statsLock.unlock()
                } catch {
                    statsLock.lock()
                    failedCount += 1
                    statsLock.unlock()
                    print("Binary plist compression replace failed for \(exportedFileName): \(error)")
                }
            }
        }

        group.wait()

        let ratioText: String
        if compressedBytesTotal > 0 {
            let ratio = Double(originalBytesTotal) / Double(compressedBytesTotal)
            ratioText = String(format: "%.2fx", ratio)
        } else {
            ratioText = "n/a"
        }

        if !renamedFiles.isEmpty {
            for testIdentifier in attachmentsByTestIdentifier.keys {
                guard var items = attachmentsByTestIdentifier[testIdentifier] else { continue }
                for index in items.indices {
                    if let compressedFileName = renamedFiles[items[index].exportedFileName] {
                        items[index].exportedFileName = compressedFileName
                    }
                }
                attachmentsByTestIdentifier[testIdentifier] = items
            }
        }

        print(
            """
            Binary plist compression complete: candidates \(candidateCount), compressed \(compressedCount), skipped \(skippedCount), failed \(failedCount), ratio \(ratioText).
            """
        )
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

        let sortedVideoFileNames = videoFileNames.sorted()
        let compressionWorkers = max(1, min(8, ProcessInfo.processInfo.activeProcessorCount))
        print("Video compression workers: \(compressionWorkers)")

        var compressedCount = 0
        var failedCount = 0
        var skippedCount = 0
        var startedCount = 0
        let statsLock = NSLock()
        let limiter = DispatchSemaphore(value: compressionWorkers)
        let group = DispatchGroup()
        let compressionQueue = DispatchQueue(label: "videoCompression", attributes: .concurrent)

        for exportedFileName in sortedVideoFileNames {
            limiter.wait()
            group.enter()
            compressionQueue.async {
                defer {
                    limiter.signal()
                    group.leave()
                }

                let indexLabel: Int = {
                    statsLock.lock()
                    defer { statsLock.unlock() }
                    startedCount += 1
                    return startedCount
                }()

                print(
                    "Compressing video \(indexLabel)/\(sortedVideoFileNames.count): \(exportedFileName)"
                )
                let result = self.compressSingleVideoAttachment(
                    exportedFileName: exportedFileName,
                    attachmentsDir: attachmentsDir,
                    maxDimension: maxDimension
                )

                statsLock.lock()
                switch result {
                case .compressed:
                    compressedCount += 1
                case .failed:
                    failedCount += 1
                case .skipped:
                    skippedCount += 1
                }
                statsLock.unlock()
            }
        }
        group.wait()

        print(
            "Video compression complete: compressed \(compressedCount), failed \(failedCount), skipped \(skippedCount)."
        )
    }

    private enum VideoCompressionResult {
        case compressed
        case failed
        case skipped
    }

    private func compressSingleVideoAttachment(
        exportedFileName: String,
        attachmentsDir: String,
        maxDimension: Int
    ) -> VideoCompressionResult {
        let fileManager = FileManager.default
        let ffmpegTimeoutSeconds: TimeInterval = 180
        let scaleFilter =
            "scale='if(gte(iw,ih),trunc(min(iw,\(maxDimension))/2)*2,-2)':'if(gte(iw,ih),-2,trunc(min(ih,\(maxDimension))/2)*2)'"
        let inputPath = (attachmentsDir as NSString).appendingPathComponent(exportedFileName)
        guard fileManager.fileExists(atPath: inputPath) else {
            print("Video compression skipped (missing file): \(exportedFileName)")
            return .skipped
        }

        let inputExtension = URL(fileURLWithPath: inputPath).pathExtension
        let tempOutputPath: String
        if inputExtension.isEmpty {
            tempOutputPath = inputPath + ".compressed"
        } else {
            tempOutputPath = inputPath + ".compressed.\(inputExtension)"
        }
        try? fileManager.removeItem(atPath: tempOutputPath)

        let hardwareCompressCmd = [
            "ffmpeg",
            "-nostdin",
            "-hide_banner",
            "-loglevel",
            "error",
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
            "45",
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

        let softwareCompressCmd = [
            "ffmpeg",
            "-nostdin",
            "-hide_banner",
            "-loglevel",
            "error",
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
            "libx264",
            "-preset",
            "veryfast",
            "-crf",
            "32",
            "-pix_fmt",
            "yuv420p",
            "-movflags",
            "+faststart",
            "-profile:v",
            "high",
            "-an",
            "-sn",
            "-max_muxing_queue_size",
            "40000",
            "-map_metadata",
            "0",
            tempOutputPath,
        ]

        let hardwareStartTime = Date()
        let hardwareResult = runFFmpegCommand(hardwareCompressCmd, timeoutSeconds: ffmpegTimeoutSeconds)
        let hardwareElapsed = Date().timeIntervalSince(hardwareStartTime)

        var compressionSucceeded = false
        var successfulMode = "videotoolbox"
        var successfulElapsed = hardwareElapsed

        if hardwareResult.timedOut {
            print(
                "Video compression timed out after \(Int(hardwareElapsed))s (videotoolbox): \(exportedFileName)"
            )
        } else if hardwareResult.exitCode != 0 || !fileManager.fileExists(atPath: tempOutputPath) {
            print(
                "Video compression failed (\(String(format: "%.1f", hardwareElapsed))s, videotoolbox): \(exportedFileName)"
            )
        } else if !isCompressionOutputUsable(sourcePath: inputPath, outputPath: tempOutputPath) {
            print("Video compression output failed validation (videotoolbox): \(exportedFileName)")
        } else {
            compressionSucceeded = true
        }

        if !compressionSucceeded {
            try? fileManager.removeItem(atPath: tempOutputPath)
            print("Retrying with software encoder (libx264): \(exportedFileName)")

            let softwareStartTime = Date()
            let softwareResult = runFFmpegCommand(softwareCompressCmd, timeoutSeconds: 300)
            let softwareElapsed = Date().timeIntervalSince(softwareStartTime)
            successfulElapsed = softwareElapsed
            successfulMode = "libx264"

            if softwareResult.timedOut {
                print(
                    "Video compression timed out after \(Int(softwareElapsed))s (libx264): \(exportedFileName)"
                )
            } else if softwareResult.exitCode != 0 || !fileManager.fileExists(atPath: tempOutputPath) {
                print(
                    "Video compression failed (\(String(format: "%.1f", softwareElapsed))s, libx264): \(exportedFileName)"
                )
            } else if !isCompressionOutputUsable(sourcePath: inputPath, outputPath: tempOutputPath) {
                print("Video compression output failed validation (libx264): \(exportedFileName)")
            } else {
                compressionSucceeded = true
            }
        }

        guard compressionSucceeded else {
            try? fileManager.removeItem(atPath: tempOutputPath)
            print("Video compression skipped after encoder failures: \(exportedFileName)")
            return .failed
        }

        do {
            try fileManager.removeItem(atPath: inputPath)
            try fileManager.moveItem(atPath: tempOutputPath, toPath: inputPath)
            print(
                "Video compression complete (\(String(format: "%.1f", successfulElapsed))s, \(successfulMode)): \(exportedFileName)"
            )
            return .compressed
        } catch {
            print("Video compression replace failed for \(exportedFileName): \(error)")
            try? fileManager.removeItem(atPath: tempOutputPath)
            return .failed
        }
    }

    private func isFFmpegInstalled() -> Bool {
        let (_, exitCode) = shell(["ffmpeg", "-version"])
        return exitCode == 0
    }

    private func isGzipInstalled() -> Bool {
        let (_, exitCode) = shell(["gzip", "--version"])
        return exitCode == 0
    }

    private func isBinaryPlistFile(at path: String) -> Bool {
        guard let fileHandle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else {
            return false
        }
        defer {
            try? fileHandle.close()
        }

        let headerData = fileHandle.readData(ofLength: 8)
        return headerData == Data("bplist00".utf8)
    }

    private func gzipCompressFile(inputPath: String, outputPath: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["gzip", "-9", "-c", inputPath]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        do {
            try task.run()
        } catch {
            return false
        }

        let compressedData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        _ = errorPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0, !compressedData.isEmpty else {
            return false
        }

        do {
            try compressedData.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private func runFFmpegCommand(
        _ args: [String], timeoutSeconds: TimeInterval
    ) -> (exitCode: Int32, timedOut: Bool) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = args

        guard let nullHandle = FileHandle(forWritingAtPath: "/dev/null") else {
            return (1, false)
        }
        defer { nullHandle.closeFile() }
        task.standardOutput = nullHandle
        task.standardError = nullHandle

        do {
            try task.run()
        } catch {
            return (1, false)
        }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while task.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
        }

        guard task.isRunning else {
            task.waitUntilExit()
            return (task.terminationStatus, false)
        }

        task.terminate()
        Thread.sleep(forTimeInterval: 0.2)
        if task.isRunning {
            task.interrupt()
        }
        return (124, true)
    }

    private func isCompressionOutputUsable(sourcePath: String, outputPath: String) -> Bool {
        guard let sourceSize = fileSizeInBytes(at: sourcePath),
            let outputSize = fileSizeInBytes(at: outputPath),
            outputSize > 0
        else {
            return false
        }

        if outputSize >= sourceSize {
            print(
                "Compressed output is not smaller (\(outputSize) >= \(sourceSize)); keeping original."
            )
            return false
        }

        guard let sourceDuration = probeVideoDurationSeconds(at: sourcePath),
            let outputDuration = probeVideoDurationSeconds(at: outputPath),
            sourceDuration > 0
        else {
            return true
        }

        let minExpectedDuration = sourceDuration * 0.95
        if outputDuration + 0.25 < minExpectedDuration {
            print(
                "Compressed output duration mismatch (\(String(format: "%.2f", outputDuration))s vs \(String(format: "%.2f", sourceDuration))s)."
            )
            return false
        }

        return true
    }

    private func fileSizeInBytes(at path: String) -> UInt64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
            return nil
        }
        if let size = attributes[.size] as? UInt64 {
            return size
        }
        if let size = attributes[.size] as? Int64, size >= 0 {
            return UInt64(size)
        }
        if let size = attributes[.size] as? NSNumber, size.int64Value >= 0 {
            return UInt64(size.int64Value)
        }
        return nil
    }

    private func probeVideoDurationSeconds(at path: String) -> Double? {
        let ffprobeCmd = [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "default=nokey=1:noprint_wrappers=1",
            path,
        ]
        let (output, exitCode) = shell(ffprobeCmd)
        guard exitCode == 0, let output else { return nil }
        return Double(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
