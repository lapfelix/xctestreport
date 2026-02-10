import Foundation
import SQLite3

private let sqlActivityFailureIDRegex = try! NSRegularExpression(
    pattern: #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#
)

final class SQLActivityParser {
    typealias TimestampNormalizer = (Double?) -> Double?

    private var db: OpaquePointer?
    private let normalizeTimestamp: TimestampNormalizer

    init?(dbPath: String, normalizeTimestamp: @escaping TimestampNormalizer) {
        guard FileManager.default.fileExists(atPath: dbPath) else { return nil }
        var connection: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return nil
        }
        self.db = connection
        self.normalizeTimestamp = normalizeTimestamp
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    func parseTestActivities(for testIdentifier: String) -> XCTestReport.TestActivities? {
        guard let db else { return nil }

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

        var runs = [XCTestReport.TestActivityRun]()
        runs.reserveCapacity(runIds.count)
        for runId in runIds {
            let activities = loadActivities(for: runId)
            runs.append(XCTestReport.TestActivityRun(activities: activities))
        }

        return XCTestReport.TestActivities(testIdentifier: testIdentifier, testRuns: runs)
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

    private struct ActivityFailureIssue {
        let message: String
        let timestamp: Double?
        let stackFrames: [ActivityFailureFrame]
    }

    private struct ActivityFailureFrame {
        let symbolName: String
        let filePath: String
        let lineNumber: Int

        var timelineTitle: String {
            _ = filePath
            _ = lineNumber
            return symbolName
        }
    }

    private func loadActivities(for runId: Int64) -> [XCTestReport.TestActivity] {
        guard let db else { return [] }

        let activityQuery = """
            WITH RECURSIVE activity_tree(
                id,
                parent_fk,
                title,
                start_time,
                failure_ids,
                order_in_parent
            ) AS (
                SELECT
                    ROWID,
                    parent_fk,
                    title,
                    startTime,
                    failureIDs,
                    orderInParent
                FROM Activities
                WHERE testCaseRun_fk = ?
                UNION
                SELECT
                    child.ROWID,
                    child.parent_fk,
                    child.title,
                    child.startTime,
                    child.failureIDs,
                    child.orderInParent
                FROM Activities child
                JOIN activity_tree parent ON child.parent_fk = parent.id
            )
            SELECT id, title, start_time, failure_ids, parent_fk, order_in_parent
            FROM activity_tree
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
                    startTime: normalizeTimestamp(startTime),
                    failureIDs: failureIDs,
                    orderInParent: orderInParent
                )
            )
        }

        let attachmentsByActivity = loadAttachments(for: runId)
        let failureIssuesByID = loadFailureIssues(for: runId)

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

        func sortActivities(_ activities: [XCTestReport.TestActivity]) -> [XCTestReport.TestActivity]
        {
            return activities.sorted { lhs, rhs in
                if let leftStart = lhs.startTime,
                    let rightStart = rhs.startTime,
                    leftStart != rightStart
                {
                    return leftStart < rightStart
                }
                if lhs.startTime == nil, rhs.startTime != nil {
                    return false
                }
                if lhs.startTime != nil, rhs.startTime == nil {
                    return true
                }
                return lhs.title < rhs.title
            }
        }

        func buildActivity(_ row: ActivityRow) -> XCTestReport.TestActivity {
            let attachmentRows = attachmentsByActivity[row.id] ?? []
            let attachments = attachmentRows.map {
                XCTestReport.TestActivityAttachment(name: $0.name, timestamp: $0.timestamp, payloadId: nil)
            }
            let childRows = sortRows(rowsByParent[row.id] ?? [])
            var children = childRows.map { buildActivity($0) }

            let failureIssueIDs = parseFailureIssueIDs(row.failureIDs)
            let failureIssues = failureIssueIDs.compactMap { failureIssuesByID[$0] }

            if !failureIssues.isEmpty {
                let failureIssueActivities: [XCTestReport.TestActivity] = failureIssues.map { issue in
                    let stackFrameActivities = issue.stackFrames.map { frame in
                        XCTestReport.TestActivity(
                            title: frame.timelineTitle,
                            startTime: issue.timestamp ?? row.startTime,
                            isAssociatedWithFailure: false,
                            attachments: nil,
                            childActivities: nil,
                            failureBranchStyle: nil
                        )
                    }
                    return XCTestReport.TestActivity(
                        title: issue.message,
                        startTime: issue.timestamp ?? row.startTime,
                        isAssociatedWithFailure: true,
                        attachments: nil,
                        childActivities: stackFrameActivities.isEmpty ? nil : stackFrameActivities,
                        failureBranchStyle: true
                    )
                }
                children.append(contentsOf: failureIssueActivities)
                children = sortActivities(children)
            }

            let hasFailureIDs = row.failureIDs.map {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            } ?? false
            // Match xcresulttool semantics: the originating activity remains
            // failure-associated even when a child issue activity is materialized.
            let failureAssociated = hasFailureIDs

            return XCTestReport.TestActivity(
                title: row.title,
                startTime: row.startTime,
                isAssociatedWithFailure: failureAssociated,
                attachments: attachments.isEmpty ? nil : attachments,
                childActivities: children.isEmpty ? nil : children,
                failureBranchStyle: nil
            )
        }

        return sortRows(rootRows).map { buildActivity($0) }
    }

    private func parseFailureIssueIDs(_ rawValue: String?) -> [String] {
        guard let rawValue else { return [] }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let nsRange = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        let regexMatches = sqlActivityFailureIDRegex.matches(in: trimmed, range: nsRange)
        if !regexMatches.isEmpty {
            var identifiers = [String]()
            var seen = Set<String>()
            for match in regexMatches {
                guard let range = Range(match.range, in: trimmed) else { continue }
                let id = String(trimmed[range]).uppercased()
                guard !seen.contains(id) else { continue }
                seen.insert(id)
                identifiers.append(id)
            }
            return identifiers
        }

        let fallbackSeparators = CharacterSet(charactersIn: ",;| \n\t")
        var identifiers = [String]()
        var seen = Set<String>()
        for token in trimmed.components(separatedBy: fallbackSeparators) {
            let candidate = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidate.isEmpty else { continue }
            let normalized = candidate.uppercased()
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            identifiers.append(normalized)
        }
        return identifiers
    }

    private func loadFailureIssues(for runId: Int64) -> [String: ActivityFailureIssue] {
        guard let db else { return [:] }
        let issueQuery = """
            SELECT uuid, compactDescription, detailedDescription, sourceCodeContext_fk, timestamp
            FROM TestIssues
            WHERE testCaseRun_fk = ?
              AND uuid IS NOT NULL
              AND TRIM(uuid) <> ''
            ORDER BY timestamp ASC, ROWID ASC
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, issueQuery, -1, &stmt, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, runId)

        var issuesByID = [String: ActivityFailureIssue]()
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let uuidPtr = sqlite3_column_text(stmt, 0) else { continue }
            let id = String(cString: uuidPtr).uppercased()
            guard !id.isEmpty else { continue }

            let compactDescription = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let detailedDescription = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            let messageSource = compactDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty ? detailedDescription : compactDescription
            let message = messageSource.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else { continue }

            let sourceCodeContextId = sqlite3_column_type(stmt, 3) == SQLITE_NULL
                ? nil
                : sqlite3_column_int64(stmt, 3)
            let rawTimestamp = sqlite3_column_type(stmt, 4) == SQLITE_NULL
                ? nil
                : sqlite3_column_double(stmt, 4)
            let timestamp = normalizeTimestamp(rawTimestamp)
            let stackFrames = loadFailureIssueFrames(sourceCodeContextId)

            if issuesByID[id] == nil {
                issuesByID[id] = ActivityFailureIssue(
                    message: message,
                    timestamp: timestamp,
                    stackFrames: stackFrames
                )
            }
        }

        return issuesByID
    }

    private func loadFailureIssueFrames(_ sourceCodeContextId: Int64?) -> [ActivityFailureFrame] {
        guard let db, let sourceCodeContextId else { return [] }

        let frameQuery = """
            SELECT si.symbolName, l.filePath, l.lineNumber
            FROM SourceCodeFrames f
            LEFT JOIN SourceCodeSymbolInfos si ON si.ROWID = f.symbolInfo_fk
            LEFT JOIN SourceCodeLocations l ON l.ROWID = si.location_fk
            WHERE f.context_fk = ?
            ORDER BY f.orderInContainer ASC, f.ROWID ASC
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, frameQuery, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, sourceCodeContextId)

        var frames = [ActivityFailureFrame]()
        var seen = Set<String>()

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let symbolPtr = sqlite3_column_text(stmt, 0) else { continue }
            let symbolName = String(cString: symbolPtr).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !symbolName.isEmpty else { continue }
            guard !symbolName.hasPrefix("partial apply for ") else { continue }
            guard !symbolName.hasPrefix("@objc ") else { continue }

            guard let filePathPtr = sqlite3_column_text(stmt, 1) else { continue }
            let filePath = String(cString: filePathPtr).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !filePath.isEmpty else { continue }
            guard !filePath.contains("<compiler-generated>") else { continue }

            guard sqlite3_column_type(stmt, 2) != SQLITE_NULL else { continue }
            let lineNumber = Int(sqlite3_column_int64(stmt, 2))
            guard lineNumber > 0 else { continue }

            let key = "\(symbolName)|\(filePath)|\(lineNumber)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            frames.append(
                ActivityFailureFrame(
                    symbolName: symbolName,
                    filePath: filePath,
                    lineNumber: lineNumber
                )
            )
        }

        return frames
    }

    private func loadAttachments(for runId: Int64) -> [Int64: [ActivityAttachmentRow]] {
        guard let db else { return [:] }
        let attachmentQuery = """
            WITH RECURSIVE activity_tree(id) AS (
                SELECT ROWID
                FROM Activities
                WHERE testCaseRun_fk = ?
                UNION
                SELECT child.ROWID
                FROM Activities child
                JOIN activity_tree parent ON child.parent_fk = parent.id
            )
            SELECT a.activity_fk, a.name, a.timestamp
            FROM Attachments a
            JOIN activity_tree tree ON a.activity_fk = tree.id
            WHERE a.name IS NOT NULL
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
                    timestamp: normalizeTimestamp(timestamp)
                )
            )
        }

        return attachmentsByActivity
    }
}
