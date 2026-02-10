import Foundation
import SQLite3
import XCTest

@testable import xctestreport

final class SQLActivityParserTests: XCTestCase {
    func testResolvesFailureIssueIntoChildFailureActivity() throws {
        let dbPath = try makeDatabase { db in
            try exec(
                db,
                """
                CREATE TABLE TestCases (identifier TEXT);
                CREATE TABLE TestCaseRuns (testCase_fk INTEGER, orderInTestSuiteRun INTEGER);
                CREATE TABLE Activities (
                    parent_fk INTEGER,
                    title TEXT,
                    startTime REAL,
                    failureIDs TEXT,
                    orderInParent INTEGER,
                    testCaseRun_fk INTEGER
                );
                CREATE TABLE Attachments (activity_fk INTEGER, name TEXT, timestamp REAL);
                CREATE TABLE TestIssues (
                    uuid TEXT,
                    compactDescription TEXT,
                    detailedDescription TEXT,
                    sourceCodeContext_fk INTEGER,
                    timestamp REAL,
                    testCaseRun_fk INTEGER
                );
                CREATE TABLE SourceCodeContexts (location_fk INTEGER);
                CREATE TABLE SourceCodeFrames (
                    context_fk INTEGER,
                    orderInContainer INTEGER,
                    address TEXT,
                    symbolInfo_fk INTEGER
                );
                CREATE TABLE SourceCodeLocations (filePath TEXT, lineNumber INTEGER);
                CREATE TABLE SourceCodeSymbolInfos (location_fk INTEGER, symbolName TEXT, imageName TEXT);
                """
            )

            try exec(db, "INSERT INTO TestCases (rowid, identifier) VALUES (1, 'Suite/testExample()');")
            try exec(db, "INSERT INTO TestCaseRuns (rowid, testCase_fk, orderInTestSuiteRun) VALUES (10, 1, 0);")
            try exec(
                db,
                "INSERT INTO Activities (rowid, parent_fk, title, startTime, failureIDs, orderInParent, testCaseRun_fk) VALUES (100, NULL, 'Parent Step', 10.0, '8F7A048A-B77C-453C-9B5A-123ABA7BB675', 0, 10);"
            )
            try exec(
                db,
                "INSERT INTO Activities (rowid, parent_fk, title, startTime, failureIDs, orderInParent, testCaseRun_fk) VALUES (101, 100, 'Child Step', 11.0, NULL, 0, 10);"
            )
            try exec(
                db,
                "INSERT INTO Attachments (activity_fk, name, timestamp) VALUES (100, 'Debug Description', 10.5);"
            )
            try exec(
                db,
                "INSERT INTO SourceCodeLocations (rowid, filePath, lineNumber) VALUES (500, '/tmp/TestSuite.swift', 42);"
            )
            try exec(
                db,
                "INSERT INTO SourceCodeContexts (rowid, location_fk) VALUES (300, 500);"
            )
            try exec(
                db,
                "INSERT INTO SourceCodeSymbolInfos (rowid, location_fk, symbolName, imageName) VALUES (400, 500, 'Suite.testExample()', 'xctest');"
            )
            try exec(
                db,
                "INSERT INTO SourceCodeFrames (context_fk, orderInContainer, address, symbolInfo_fk) VALUES (300, 0, '0x1', 400);"
            )
            try exec(
                db,
                "INSERT INTO TestIssues (uuid, compactDescription, detailedDescription, sourceCodeContext_fk, timestamp, testCaseRun_fk) VALUES ('8F7A048A-B77C-453C-9B5A-123ABA7BB675', 'XCTAssertTrue failed - boom', '', 300, 12.0, 10);"
            )
        }

        guard
            let parser = SQLActivityParser(
                dbPath: dbPath,
                normalizeTimestamp: { $0 }
            )
        else {
            XCTFail("Failed to initialize parser.")
            return
        }

        let activities = parser.parseTestActivities(for: "Suite/testExample()")
        let run = try XCTUnwrap(activities?.testRuns.first)
        let root = try XCTUnwrap(run.activities.first)

        XCTAssertEqual(root.title, "Parent Step")
        XCTAssertEqual(root.isAssociatedWithFailure, true)
        XCTAssertEqual(root.attachments?.count, 1)

        let children = root.childActivities ?? []
        XCTAssertEqual(children.count, 2)
        XCTAssertTrue(children.contains(where: { $0.title == "Child Step" }))

        let failureChild = try XCTUnwrap(
            children.first(where: { $0.title == "XCTAssertTrue failed - boom" })
        )
        XCTAssertEqual(failureChild.isAssociatedWithFailure, true)
        XCTAssertEqual(try XCTUnwrap(failureChild.startTime), 12.0, accuracy: 0.0001)
        let stackFrames = failureChild.childActivities ?? []
        XCTAssertEqual(stackFrames.count, 1)
        XCTAssertEqual(stackFrames[0].title, "Suite.testExample()")
    }

    func testFallsBackToParentFailureWhenIssueCannotBeResolved() throws {
        let dbPath = try makeDatabase { db in
            try exec(
                db,
                """
                CREATE TABLE TestCases (identifier TEXT);
                CREATE TABLE TestCaseRuns (testCase_fk INTEGER, orderInTestSuiteRun INTEGER);
                CREATE TABLE Activities (
                    parent_fk INTEGER,
                    title TEXT,
                    startTime REAL,
                    failureIDs TEXT,
                    orderInParent INTEGER,
                    testCaseRun_fk INTEGER
                );
                CREATE TABLE Attachments (activity_fk INTEGER, name TEXT, timestamp REAL);
                CREATE TABLE TestIssues (
                    uuid TEXT,
                    compactDescription TEXT,
                    detailedDescription TEXT,
                    sourceCodeContext_fk INTEGER,
                    timestamp REAL,
                    testCaseRun_fk INTEGER
                );
                """
            )
            try exec(db, "INSERT INTO TestCases (rowid, identifier) VALUES (1, 'Suite/testMissingIssue()');")
            try exec(db, "INSERT INTO TestCaseRuns (rowid, testCase_fk, orderInTestSuiteRun) VALUES (10, 1, 0);")
            try exec(
                db,
                "INSERT INTO Activities (rowid, parent_fk, title, startTime, failureIDs, orderInParent, testCaseRun_fk) VALUES (100, NULL, 'Parent Step', 10.0, 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE', 0, 10);"
            )
        }

        guard
            let parser = SQLActivityParser(
                dbPath: dbPath,
                normalizeTimestamp: { $0 }
            )
        else {
            XCTFail("Failed to initialize parser.")
            return
        }

        let activities = parser.parseTestActivities(for: "Suite/testMissingIssue()")
        let run = try XCTUnwrap(activities?.testRuns.first)
        let root = try XCTUnwrap(run.activities.first)

        XCTAssertEqual(root.title, "Parent Step")
        XCTAssertEqual(root.isAssociatedWithFailure, true)
        XCTAssertNil(root.childActivities)
    }

    // MARK: - Helpers

    private func makeDatabase(seed: (OpaquePointer) throws -> Void) throws -> String {
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent(
            "xctestreport-sql-parser-\(UUID().uuidString).sqlite3"
        )

        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK, let db else {
            throw makeSQLiteError(db, fallback: "Failed to create sqlite database.")
        }

        do {
            try seed(db)
            sqlite3_close(db)
            return path
        } catch {
            sqlite3_close(db)
            throw error
        }
    }

    private func exec(_ db: OpaquePointer, _ sql: String) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            throw makeSQLiteError(db, fallback: "SQL execution failed.")
        }
    }

    private func makeSQLiteError(_ db: OpaquePointer?, fallback: String) -> NSError {
        guard let db, let message = sqlite3_errmsg(db) else {
            return NSError(domain: "SQLActivityParserTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: fallback
            ])
        }
        return NSError(domain: "SQLActivityParserTests", code: 1, userInfo: [
            NSLocalizedDescriptionKey: String(cString: message)
        ])
    }
}
