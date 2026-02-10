import Dispatch
import Foundation
import SQLite3

private let testDetailsCacheLock = NSLock()
private var testDetailsCache = [String: XCTestReport.TestDetails]()
private let testActivitiesCacheLock = NSLock()
private var testActivitiesCache = [String: XCTestReport.TestActivities]()
private let previousRunsCacheLock = NSLock()
private var previousRunsCache = [String: [XCTestReport.TestRunDetail]]()
private let previousRunsDirsCacheLock = NSLock()
private var previousRunsDirsCache = [String: [String]]()
private let cocoaToUnixEpochOffset: Double = 978_307_200

extension XCTestReport {
    func normalizeXCResultTimestamp(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        // xcresult SQLite tables often store Cocoa absolute time (seconds since 2001-01-01).
        // Convert to Unix epoch so DB-derived timestamps align with xcresulttool JSON.
        if value > 0 && value < 1_000_000_000 {
            return value + cocoaToUnixEpochOffset
        }
        return value
    }

    func activitiesContainRichTimelineData(_ activities: TestActivities) -> Bool {
        var hasChildren = false
        var hasFailureAssociation = false

        func traverse(_ nodes: [TestActivity]) {
            for node in nodes {
                if let children = node.childActivities, !children.isEmpty {
                    hasChildren = true
                    traverse(children)
                }
                if node.isAssociatedWithFailure == true {
                    hasFailureAssociation = true
                }
                if hasChildren && hasFailureAssociation {
                    return
                }
            }
        }

        for run in activities.testRuns {
            traverse(run.activities)
            if hasChildren && hasFailureAssociation {
                break
            }
        }

        return hasChildren || hasFailureAssociation
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
            // Keep stderr separate so parser callers get clean JSON from stdout.
            task.standardError = nil
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

        // Prefer xcresulttool activities for timeline fidelity.
        let cmd = [
            "xcrun", "xcresulttool", "get", "test-results", "activities", "--test-id",
            testIdentifier, "--path", xcresultPath, "--format", "json", "--compact",
        ]
        let (output, exitCode) = shell(cmd)
        if exitCode == 0, let output, let data = output.data(using: .utf8),
            let activities = try? JSONDecoder().decode(TestActivities.self, from: data)
        {
            testActivitiesCacheLock.lock()
            testActivitiesCache[cacheKey] = activities
            testActivitiesCacheLock.unlock()
            return activities
        }

        // Fallback: direct SQL extraction if xcresulttool is unavailable or fails.
        if let activities = loadTestActivitiesFromDatabase(for: testIdentifier),
            activitiesContainRichTimelineData(activities)
        {
            testActivitiesCacheLock.lock()
            testActivitiesCache[cacheKey] = activities
            testActivitiesCacheLock.unlock()
            return activities
        }

        if let activities = loadTestActivitiesFromDatabase(for: testIdentifier) {
            testActivitiesCacheLock.lock()
            testActivitiesCache[cacheKey] = activities
            testActivitiesCacheLock.unlock()
            return activities
        }

        print("Failed to get activities for: \(testIdentifier)")
        return nil
    }

    private struct ActivityRow {
        let id: Int64
        let parentId: Int64?
        let title: String
        let startTime: Double?
        let failureIDs: String?
        let orderInParent: Int?
    }

    private struct ActivityAttachmentRow {
        let activityId: Int64
        let name: String
        let timestamp: Double?
    }

    private func loadTestActivitiesFromDatabase(for testIdentifier: String) -> TestActivities? {
        let dbPath = (xcresultPath as NSString).appendingPathComponent("database.sqlite3")
        guard FileManager.default.fileExists(atPath: dbPath) else { return nil }

        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_close(db) }

        let runQuery = """
            SELECT r.ROWID
            FROM TestCaseRuns r
            JOIN TestCases c ON r.testCase_fk = c.ROWID
            WHERE c.identifier = ?
            ORDER BY r.orderInTestSuiteRun
            """
        var runStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, runQuery, -1, &runStmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(runStmt) }

        let testIdentifierCString = (testIdentifier as NSString).utf8String
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(runStmt, 1, testIdentifierCString, -1, transient)

        var runIds = [Int64]()
        while sqlite3_step(runStmt) == SQLITE_ROW {
            runIds.append(sqlite3_column_int64(runStmt, 0))
        }
        guard !runIds.isEmpty else { return nil }

        var runs = [TestActivityRun]()
        runs.reserveCapacity(runIds.count)
        for runId in runIds {
            let activities = loadActivities(for: runId, db: db)
            runs.append(TestActivityRun(activities: activities))
        }

        return TestActivities(testIdentifier: testIdentifier, testRuns: runs)
    }

    private func loadActivities(for runId: Int64, db: OpaquePointer?) -> [TestActivity] {
        guard let db else { return [] }

        let activityQuery = """
            SELECT ROWID, title, startTime, failureIDs, parent_fk, orderInParent
            FROM Activities
            WHERE testCaseRun_fk = ?
            ORDER BY orderInParent, startTime, ROWID
            """
        var activityStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, activityQuery, -1, &activityStmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(activityStmt) }

        sqlite3_bind_int64(activityStmt, 1, runId)

        var rows = [ActivityRow]()
        while sqlite3_step(activityStmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(activityStmt, 0)
            let title = sqlite3_column_text(activityStmt, 1).map { String(cString: $0) } ?? ""
            let startTime = sqlite3_column_type(activityStmt, 2) == SQLITE_NULL
                ? nil
                : sqlite3_column_double(activityStmt, 2)
            let failureIDs = sqlite3_column_text(activityStmt, 3).map { String(cString: $0) }
            let parentId = sqlite3_column_type(activityStmt, 4) == SQLITE_NULL
                ? nil
                : sqlite3_column_int64(activityStmt, 4)
            let orderInParent = sqlite3_column_type(activityStmt, 5) == SQLITE_NULL
                ? nil
                : Int(sqlite3_column_int64(activityStmt, 5))

            rows.append(
                ActivityRow(
                    id: id,
                    parentId: parentId,
                    title: title,
                    startTime: normalizeXCResultTimestamp(startTime),
                    failureIDs: failureIDs,
                    orderInParent: orderInParent
                )
            )
        }

        let attachmentsByActivity = loadAttachments(for: runId, db: db)
        var rowsByParent = [Int64: [ActivityRow]]()
        var rootRows = [ActivityRow]()
        for row in rows {
            if let parentId = row.parentId {
                rowsByParent[parentId, default: []].append(row)
            } else {
                rootRows.append(row)
            }
        }

        func sortRows(_ rows: [ActivityRow]) -> [ActivityRow] {
            return rows.sorted { lhs, rhs in
                if let leftOrder = lhs.orderInParent,
                    let rightOrder = rhs.orderInParent,
                    leftOrder != rightOrder
                {
                    return leftOrder < rightOrder
                }
                if let leftStart = lhs.startTime,
                    let rightStart = rhs.startTime,
                    leftStart != rightStart
                {
                    return leftStart < rightStart
                }
                return lhs.id < rhs.id
            }
        }

        func buildActivity(_ row: ActivityRow) -> TestActivity {
            let attachmentRows = attachmentsByActivity[row.id] ?? []
            let attachments = attachmentRows.map {
                TestActivityAttachment(name: $0.name, timestamp: $0.timestamp, payloadId: nil)
            }
            let childRows = sortRows(rowsByParent[row.id] ?? [])
            let children = childRows.map { buildActivity($0) }
            let failureAssociated =
                row.failureIDs.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return TestActivity(
                title: row.title,
                startTime: row.startTime,
                isAssociatedWithFailure: failureAssociated,
                attachments: attachments.isEmpty ? nil : attachments,
                childActivities: children.isEmpty ? nil : children
            )
        }

        return sortRows(rootRows).map { buildActivity($0) }
    }

    private func loadAttachments(for runId: Int64, db: OpaquePointer?) -> [Int64: [ActivityAttachmentRow]] {
        guard let db else { return [:] }
        let attachmentQuery = """
            SELECT a.activity_fk, a.name, a.timestamp
            FROM Attachments a
            JOIN Activities act ON a.activity_fk = act.ROWID
            WHERE act.testCaseRun_fk = ? AND a.name IS NOT NULL
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, attachmentQuery, -1, &stmt, nil) == SQLITE_OK else {
            return [:]
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, runId)

        var attachmentsByActivity = [Int64: [ActivityAttachmentRow]]()
        while sqlite3_step(stmt) == SQLITE_ROW {
            let activityId = sqlite3_column_int64(stmt, 0)
            guard let namePtr = sqlite3_column_text(stmt, 1) else { continue }
            let name = String(cString: namePtr)
            let timestamp = sqlite3_column_type(stmt, 2) == SQLITE_NULL
                ? nil
                : sqlite3_column_double(stmt, 2)

            attachmentsByActivity[activityId, default: []].append(
                ActivityAttachmentRow(
                    activityId: activityId,
                    name: name,
                    timestamp: normalizeXCResultTimestamp(timestamp)
                )
            )
        }
        return attachmentsByActivity
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

    func exportAttachmentsDirect() -> [String: [AttachmentManifestItem]]? {
        let exportStartTime = Date()
        let attachmentsDir = (outputDir as NSString).appendingPathComponent("attachments")
        try? FileManager.default.removeItem(atPath: attachmentsDir)
        
        guard let result = try? exportAttachmentsDirectInternal(attachmentsDir: attachmentsDir, startTime: exportStartTime) else {
            return nil
        }
        
        let exportElapsed = Date().timeIntervalSince(exportStartTime)
        if let stats = directorySizeAndCount(at: attachmentsDir) {
            let exportMB = Double(stats.bytes) / (1024.0 * 1024.0)
            let mbPerSec = exportElapsed > 0 ? exportMB / exportElapsed : 0
            let filesPerSec = exportElapsed > 0 ? Double(stats.fileCount) / exportElapsed : 0
            print(
                "Attachment export completed in \(String(format: "%.2f", exportElapsed))s; exported \(String(format: "%.1f", exportMB)) MB across \(stats.fileCount) files (\(String(format: "%.2f", mbPerSec)) MB/s, \(String(format: "%.2f", filesPerSec)) files/s)"
            )
        }
        
        return result
    }
    
    func exportAttachmentsDirectInternal(attachmentsDir: String, startTime: Date) throws -> [String: [AttachmentManifestItem]] {
        print("Using fast direct extraction from xcresult database...")
        
        try FileManager.default.createDirectory(
            atPath: attachmentsDir, withIntermediateDirectories: true)
        
        // Open the xcresult database
        let dbPath = (xcresultPath as NSString).appendingPathComponent("database.sqlite3")
        let dataDir = (xcresultPath as NSString).appendingPathComponent("Data")
        
        guard FileManager.default.fileExists(atPath: dbPath) else {
            print("Database not found at \(dbPath)")
            throw NSError(domain: "xctestreport", code: 1)
        }
        
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            print("Failed to open database")
            throw NSError(domain: "xctestreport", code: 2)
        }
        defer { sqlite3_close(db) }
        
        // Query to get attachments with their test identifiers
        let query = """
            SELECT 
                a.name,
                a.uniformTypeIdentifier,
                a.xcResultKitPayloadRefId,
                a.activity_fk,
                tc.identifier,
                a.timestamp,
                a.testIssue_fk
            FROM Attachments a
            LEFT JOIN Activities act ON a.activity_fk = act.ROWID
            LEFT JOIN TestCaseRuns tcr ON act.testCaseRun_fk = tcr.ROWID
            LEFT JOIN TestCases tc ON tcr.testCase_fk = tc.ROWID
            WHERE a.xcResultKitPayloadRefId IS NOT NULL
            ORDER BY a.timestamp, a.ROWID
            """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            print("Failed to prepare query")
            throw NSError(domain: "xctestreport", code: 3)
        }
        defer { sqlite3_finalize(stmt) }
        
        var attachmentsByTest = [String: [AttachmentManifestItem]]()
        var manifestEntries = [AttachmentManifestEntry]()
        var fileCounter = 0
        var lastProgressTime = Date()
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let payloadRefIdPtr = sqlite3_column_text(stmt, 2) else { continue }
            let payloadRefId = String(cString: payloadRefIdPtr)
            
            // Get test identifier
            var testIdentifier = ""
            if let testIdPtr = sqlite3_column_text(stmt, 4) {
                testIdentifier = String(cString: testIdPtr)
            }
            
            // Construct source and destination paths
            let sourceFileName = "data.\(payloadRefId)"
            let sourcePath = (dataDir as NSString).appendingPathComponent(sourceFileName)
            
            guard FileManager.default.fileExists(atPath: sourcePath) else {
                continue
            }
            
            // Get attachment name for human-readable filename
            var suggestedName: String? = nil
            if let namePtr = sqlite3_column_text(stmt, 0) {
                suggestedName = String(cString: namePtr)
            }
            
            // Determine file extension from UTI
            var fileExt = "dat"
            if let utiPtr = sqlite3_column_text(stmt, 1) {
                let uti = String(cString: utiPtr)
                fileExt = fileExtensionForUTI(uti)
            }
            
            fileCounter += 1
            let destFileName = "\(fileCounter).\(fileExt)"
            let destPath = (attachmentsDir as NSString).appendingPathComponent(destFileName)
            
            // Copy file
            do {
                try FileManager.default.copyItem(atPath: sourcePath, toPath: destPath)
            } catch {
                print("Failed to copy \(sourcePath): \(error)")
                continue
            }
            
            // Create manifest item
            let attachmentTimestamp = sqlite3_column_type(stmt, 5) == SQLITE_NULL
                ? nil
                : normalizeXCResultTimestamp(sqlite3_column_double(stmt, 5))
            let associatedWithFailure = sqlite3_column_type(stmt, 6) != SQLITE_NULL
            let item = AttachmentManifestItem(
                exportedFileName: destFileName,
                isAssociatedWithFailure: associatedWithFailure ? true : nil,
                suggestedHumanReadableName: suggestedName,
                timestamp: attachmentTimestamp,
                payloadRefId: payloadRefId
            )
            
            attachmentsByTest[testIdentifier, default: []].append(item)
            
            // Progress reporting every 5 seconds
            let now = Date()
            if now.timeIntervalSince(lastProgressTime) >= 5.0 {
                let elapsed = now.timeIntervalSince(startTime)
                if let stats = directorySizeAndCount(at: attachmentsDir) {
                    let mb = Double(stats.bytes) / (1024.0 * 1024.0)
                    print(
                        "Export progress (\(String(format: "%.0f", elapsed))s): \(stats.fileCount) files, \(String(format: "%.1f", mb)) MB"
                    )
                }
                lastProgressTime = now
            }
        }
        
        // Generate manifest entries
        for (testId, items) in attachmentsByTest {
            manifestEntries.append(
                AttachmentManifestEntry(attachments: items, testIdentifier: testId)
            )
        }
        
        // Write manifest.json
        let manifestPath = (attachmentsDir as NSString).appendingPathComponent("manifest.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData = try encoder.encode(manifestEntries)
        try manifestData.write(to: URL(fileURLWithPath: manifestPath))
        
        // Video compression if enabled
        if compressVideo {
            if fastVideo {
                print("Fast video mode enabled: max dimension \(videoHeight); skipping duration validation.")
            }
            let compressionStartTime = Date()
            compressExportedVideosIfPossible(
                in: attachmentsDir,
                manifestEntries: manifestEntries,
                maxDimension: videoHeight
            )
            let compressionElapsed = Date().timeIntervalSince(compressionStartTime)
            if let compressedBytes = directorySizeInBytes(at: attachmentsDir) {
                let compressedMB = Double(compressedBytes) / (1024.0 * 1024.0)
                print(
                    "Video compression completed in \(String(format: "%.2f", compressionElapsed))s; attachments now \(String(format: "%.1f", compressedMB)) MB"
                )
            }
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
    }
    
    func fileExtensionForUTI(_ uti: String) -> String {
        switch uti {
        case "public.mpeg-4": return "mp4"
        case "public.png": return "png"
        case "public.jpeg": return "jpg"
        case "public.plain-text": return "txt"
        case "public.xml": return "xml"
        case "public.json": return "json"
        case "com.apple.property-list": return "plist"
        case "com.apple.dt.xctest.element-snapshot": return "plist"
        case "public.html": return "html"
        default: return "dat"
        }
    }

    func exportAttachments() -> [String: [AttachmentManifestItem]] {
        // Try fast direct extraction first, fall back to xcresulttool if needed
        if let result = exportAttachmentsDirect() {
            return result
        }
        print("Direct extraction failed, falling back to xcresulttool...")
        return exportAttachmentsViaXCResultTool()
    }

    func loadAttachmentsFromManifest(at attachmentsDir: String) -> [String: [AttachmentManifestItem]] {
        let manifestPath = (attachmentsDir as NSString).appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestPath) else {
            print("Attachment manifest not found at \(manifestPath)")
            return [:]
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: manifestPath))
            let manifestEntries = try JSONDecoder().decode([AttachmentManifestEntry].self, from: data)
            let attachmentsByTest = buildAttachmentsByTest(from: manifestEntries)
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

    func buildAttachmentsByTest(
        from manifestEntries: [AttachmentManifestEntry]
    ) -> [String: [AttachmentManifestItem]] {
        var attachmentsByTest = [String: [AttachmentManifestItem]](
            minimumCapacity: manifestEntries.count)

        for entry in manifestEntries where !entry.attachments.isEmpty {
            attachmentsByTest[entry.testIdentifier, default: []].append(
                contentsOf: entry.attachments)
        }
        return attachmentsByTest
    }

    func exportAttachmentsViaXCResultTool() -> [String: [AttachmentManifestItem]] {
        let exportStartTime = Date()
        let attachmentsDir = (outputDir as NSString).appendingPathComponent("attachments")
        try? FileManager.default.removeItem(atPath: attachmentsDir)
        try? FileManager.default.createDirectory(
            atPath: attachmentsDir, withIntermediateDirectories: true)

        let exportCmd = [
            "xcrun", "xcresulttool", "export", "attachments", "--path", xcresultPath,
            "--output-path", attachmentsDir,
        ]
        print("Running attachment export: \(exportCmd.joined(separator: " "))")

        let exportProcess = Process()
        exportProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        exportProcess.arguments = exportCmd
        exportProcess.standardOutput = nil
        exportProcess.standardError = nil

        let progressQueue = DispatchQueue(label: "attachmentExportProgress")
        let progressTimer = DispatchSource.makeTimerSource(queue: progressQueue)
        progressTimer.schedule(deadline: .now() + .seconds(30), repeating: .seconds(30))
        progressTimer.setEventHandler { [weak exportProcess] in
            guard exportProcess?.isRunning == true else { return }
            let elapsed = Date().timeIntervalSince(exportStartTime)
            if let stats = self.directorySizeAndCount(at: attachmentsDir) {
                let mb = Double(stats.bytes) / (1024.0 * 1024.0)
                print(
                    "Attachment export progress (\(String(format: "%.0f", elapsed))s): \(stats.fileCount) files, \(String(format: "%.1f", mb)) MB"
                )
            } else {
                print("Attachment export progress (\(String(format: "%.0f", elapsed))s): waiting for output...")
            }
        }
        progressTimer.resume()

        do {
            try exportProcess.run()
        } catch {
            progressTimer.cancel()
            print("Attachment export failed to start: \(error)")
            return [:]
        }
        exportProcess.waitUntilExit()
        progressTimer.cancel()
        let exportExit = exportProcess.terminationStatus
        guard exportExit == 0 else {
            print("Attachment export failed. Continuing without media attachments.")
            return [:]
        }

        let exportElapsed = Date().timeIntervalSince(exportStartTime)
        if let stats = directorySizeAndCount(at: attachmentsDir) {
            let exportMB = Double(stats.bytes) / (1024.0 * 1024.0)
            let mbPerSec = exportElapsed > 0 ? exportMB / exportElapsed : 0
            let filesPerSec = exportElapsed > 0 ? Double(stats.fileCount) / exportElapsed : 0
            print(
                "Attachment export completed in \(String(format: "%.2f", exportElapsed))s; exported \(String(format: "%.1f", exportMB)) MB across \(stats.fileCount) files (\(String(format: "%.2f", mbPerSec)) MB/s, \(String(format: "%.2f", filesPerSec)) files/s)"
            )
        } else {
            print(
                "Attachment export completed in \(String(format: "%.2f", exportElapsed))s"
            )
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
                if fastVideo {
                    print("Fast video mode enabled: max dimension \(videoHeight); skipping duration validation.")
                }
                let compressionStartTime = Date()
                compressExportedVideosIfPossible(
                    in: attachmentsDir,
                    manifestEntries: manifestEntries,
                    maxDimension: videoHeight
                )
                let compressionElapsed = Date().timeIntervalSince(compressionStartTime)
                if let compressedBytes = directorySizeInBytes(at: attachmentsDir) {
                    let compressedMB = Double(compressedBytes) / (1024.0 * 1024.0)
                    print(
                        "Video compression completed in \(String(format: "%.2f", compressionElapsed))s; attachments now \(String(format: "%.1f", compressedMB)) MB"
                    )
                } else {
                    print(
                        "Video compression completed in \(String(format: "%.2f", compressionElapsed))s"
                    )
                }
            }

            var attachmentsByTest = buildAttachmentsByTest(from: manifestEntries)

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

    func directorySizeInBytes(at path: String) -> UInt64? {
        let url = URL(fileURLWithPath: path)
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: resourceKeys) else {
                continue
            }
            guard resourceValues.isRegularFile == true else { continue }
            if let fileSize = resourceValues.totalFileAllocatedSize {
                total += UInt64(fileSize)
            }
        }
        return total
    }

    func directorySizeAndCount(at path: String) -> (bytes: UInt64, fileCount: Int)? {
        let url = URL(fileURLWithPath: path)
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var total: UInt64 = 0
        var count = 0
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: resourceKeys) else {
                continue
            }
            guard resourceValues.isRegularFile == true else { continue }
            if let fileSize = resourceValues.totalFileAllocatedSize {
                total += UInt64(fileSize)
                count += 1
            }
        }
        return (total, count)
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
        let compressionWorkers = max(1, min(4, ProcessInfo.processInfo.activeProcessorCount))
        print("Video compression workers: \(compressionWorkers)")

        var compressedCount = 0
        var failedCount = 0
        var skippedCount = 0
        var startedCount = 0
        var totalElapsed: TimeInterval = 0
        var maxElapsed: TimeInterval = 0
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
                let startTime = Date()
                let result = self.compressSingleVideoAttachment(
                    exportedFileName: exportedFileName,
                    attachmentsDir: attachmentsDir,
                    maxDimension: maxDimension
                )
                let elapsed = Date().timeIntervalSince(startTime)

                statsLock.lock()
                switch result {
                case .compressed:
                    compressedCount += 1
                    totalElapsed += elapsed
                    maxElapsed = max(maxElapsed, elapsed)
                case .failed:
                    failedCount += 1
                case .skipped:
                    skippedCount += 1
                }
                statsLock.unlock()
            }
        }
        group.wait()

        let averageElapsed = compressedCount > 0 ? (totalElapsed / Double(compressedCount)) : 0
        print(
            "Video compression complete: compressed \(compressedCount), failed \(failedCount), skipped \(skippedCount). Avg \(String(format: "%.2f", averageElapsed))s Max \(String(format: "%.2f", maxElapsed))s."
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

        let h264HardwareCmd = [
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
            "h264_videotoolbox",
            "-pix_fmt",
            "yuv420p",
            "-q:v",
            "60",
            "-allow_sw",
            "1",
            "-movflags",
            "+faststart",
            "-profile:v",
            "main",
            "-an",
            "-sn",
            "-max_muxing_queue_size",
            "40000",
            "-map_metadata",
            "0",
            tempOutputPath,
        ]

        let hevcHardwareCmd = [
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
            "28",
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
        let h264Result = runFFmpegCommand(h264HardwareCmd, timeoutSeconds: ffmpegTimeoutSeconds)
        let hardwareElapsed = Date().timeIntervalSince(hardwareStartTime)

        var compressionSucceeded = false
        var successfulMode = "h264_videotoolbox"
        var successfulElapsed = hardwareElapsed

        if h264Result.timedOut {
            print(
                "Video compression timed out after \(Int(hardwareElapsed))s (h264_videotoolbox): \(exportedFileName)"
            )
        } else if h264Result.exitCode != 0 || !fileManager.fileExists(atPath: tempOutputPath) {
            print(
                "Video compression failed (\(String(format: "%.1f", hardwareElapsed))s, h264_videotoolbox): \(exportedFileName)"
            )
        } else if !isCompressionOutputUsable(sourcePath: inputPath, outputPath: tempOutputPath) {
            print("Video compression output failed validation (h264_videotoolbox): \(exportedFileName)")
        } else {
            compressionSucceeded = true
        }

        if !compressionSucceeded {
            try? fileManager.removeItem(atPath: tempOutputPath)
            print("Retrying with hardware encoder (hevc_videotoolbox): \(exportedFileName)")

            let hevcStartTime = Date()
            let hevcResult = runFFmpegCommand(hevcHardwareCmd, timeoutSeconds: ffmpegTimeoutSeconds)
            let hevcElapsed = Date().timeIntervalSince(hevcStartTime)
            successfulElapsed = hevcElapsed
            successfulMode = "hevc_videotoolbox"

            if hevcResult.timedOut {
                print(
                    "Video compression timed out after \(Int(hevcElapsed))s (hevc_videotoolbox): \(exportedFileName)"
                )
            } else if hevcResult.exitCode != 0 || !fileManager.fileExists(atPath: tempOutputPath) {
                print(
                    "Video compression failed (\(String(format: "%.1f", hevcElapsed))s, hevc_videotoolbox): \(exportedFileName)"
                )
            } else if !isCompressionOutputUsable(sourcePath: inputPath, outputPath: tempOutputPath) {
                print("Video compression output failed validation (hevc_videotoolbox): \(exportedFileName)")
            } else {
                compressionSucceeded = true
            }
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

        if fastVideo {
            return true
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
