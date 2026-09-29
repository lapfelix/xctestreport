import Foundation
import SQLite3
import XCTest
import libzstd

@testable import xctestreport

final class AttachmentExportTests: XCTestCase {

    /// Only top-level activities carry `testCaseRun_fk`; an attachment on a nested step, or on a
    /// test issue with no activity, still has to land under its test.
    func testDirectExportAttributesNestedAndIssueAttachmentsToTheirTest() throws {
        let root = (NSTemporaryDirectory() as NSString).appendingPathComponent(
            "xctestreport-export-\(UUID().uuidString)")
        let xcresult = (root as NSString).appendingPathComponent("Test.xcresult")
        let dataDir = (xcresult as NSString).appendingPathComponent("Data")
        try FileManager.default.createDirectory(atPath: dataDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: root) }

        var db: OpaquePointer?
        XCTAssertEqual(
            sqlite3_open((xcresult as NSString).appendingPathComponent("database.sqlite3"), &db),
            SQLITE_OK)
        let sql = """
            CREATE TABLE TestCases (identifier TEXT);
            CREATE TABLE TestCaseRuns (testCase_fk INTEGER);
            CREATE TABLE Activities (parent_fk INTEGER, testCaseRun_fk INTEGER);
            CREATE TABLE TestIssues (testCaseRun_fk INTEGER);
            CREATE TABLE Attachments (
                name TEXT, uniformTypeIdentifier TEXT, xcResultKitPayloadRefId TEXT,
                activity_fk INTEGER, timestamp REAL, testIssue_fk INTEGER);
            INSERT INTO TestCases (rowid, identifier) VALUES (1, 'Suite/testCrash()');
            INSERT INTO TestCaseRuns (rowid, testCase_fk) VALUES (10, 1);
            INSERT INTO Activities (rowid, parent_fk, testCaseRun_fk) VALUES (100, NULL, 10);
            INSERT INTO Activities (rowid, parent_fk, testCaseRun_fk) VALUES (101, 100, NULL);
            INSERT INTO Activities (rowid, parent_fk, testCaseRun_fk) VALUES (102, 101, NULL);
            INSERT INTO TestIssues (rowid, testCaseRun_fk) VALUES (50, 10);
            INSERT INTO Attachments VALUES ('kXCTAttachmentScreenRecording', 'public.mpeg-4', 'video', 100, 1.0, NULL);
            INSERT INTO Attachments VALUES ('App UI hierarchy', 'public.plain-text', 'hierarchy', 102, 2.0, NULL);
            INSERT INTO Attachments VALUES ('kXCTAttachmentLegacyDiagnosticReportData', 'public.data', 'crash', NULL, 3.0, 50);
            INSERT INTO Attachments VALUES ('kXCTAttachmentLegacySnapshot', 'com.apple.property-list', 'snapshot', 102, 4.0, NULL);
            """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        for payload in ["video", "crash"] {
            FileManager.default.createFile(
                atPath: (dataDir as NSString).appendingPathComponent("data.\(payload)"),
                contents: Data(payload.utf8))
        }
        let hierarchy = Data("Application, pid: 1".utf8)
        var compressed = Data(count: ZSTD_compressBound(hierarchy.count))
        let compressedSize = compressed.withUnsafeMutableBytes { destination in
            hierarchy.withUnsafeBytes { source in
                ZSTD_compress(
                    destination.baseAddress, destination.count, source.baseAddress, source.count, 3)
            }
        }
        FileManager.default.createFile(
            atPath: (dataDir as NSString).appendingPathComponent("data.hierarchy"),
            contents: compressed.prefix(compressedSize))
        FileManager.default.createFile(
            atPath: (dataDir as NSString).appendingPathComponent("data.snapshot"),
            contents: compressed.prefix(compressedSize))

        var report = XCTestReport()
        report.xcresultPath = xcresult
        report.outputDir = (root as NSString).appendingPathComponent("out")
        report.compressVideo = false
        report.fastVideo = false
        let byTest = try XCTUnwrap(report.exportAttachmentsDirect())

        XCTAssertEqual(Array(byTest.keys), ["Suite/testCrash()"])
        XCTAssertEqual(
            byTest["Suite/testCrash()"]?.map(\.exportedFileName),
            ["Suite_testCrash.mp4", "2.txt", "3.ips", "4.plist"])
        XCTAssertEqual(
            FileManager.default.contents(
                atPath: (report.outputDir as NSString).appendingPathComponent("attachments/2.txt")),
            hierarchy, "zstd text payloads are unwrapped on export")
        XCTAssertEqual(
            FileManager.default.contents(
                atPath: (report.outputDir as NSString).appendingPathComponent("attachments/4.plist")),
            compressed.prefix(compressedSize),
            "Plists stay as stored; the timeline and synthesized-event parser decode them")
    }

    func testGunzipsWithSystemZlib() {
        let gzipped = Data([
            31, 139, 8, 0, 0, 0, 0, 0, 2, 255, 171, 72, 46, 73, 45, 46, 41, 74, 45, 200, 47, 42, 81,
            72, 175, 202, 44, 80, 40, 202, 47, 205, 75, 81, 40, 41, 202, 44, 224, 170, 32, 91, 18, 0,
            239, 201, 196, 67, 87, 0, 0, 0,
        ])
        let report = XCTestReport()
        XCTAssertEqual(
            report.decompressGzipData(gzipped),
            Data(String(repeating: "xctestreport gzip round trip\n", count: 3).utf8))
        XCTAssertNil(report.decompressGzipData(Data("not gzip".utf8)))
        XCTAssertNil(report.decompressGzipData(gzipped.prefix(20)), "truncated input")
    }

    /// The xcresulttool fallback decorates names; snapshot pairing needs them as written.
    func testStripsXCResultToolExportSuffixFromAttachmentNames() {
        let report = XCTestReport()
        XCTAssertEqual(
            report.attachmentNameWithoutExportSuffix(
                "RouteDetailsPinButton-pinned.expected_0_BFC432E3-D995-4A29-B1D8-0368457E90D1.png"),
            "RouteDetailsPinButton-pinned.expected.png")
        XCTAssertEqual(
            report.attachmentNameWithoutExportSuffix(
                "kXCTAttachmentScreenRecording_12_A310F634-271F-40E1-9ECF-958FEF5C94C5"),
            "kXCTAttachmentScreenRecording")
        XCTAssertEqual(
            report.attachmentNameWithoutExportSuffix("Debug description for `Button_1`"),
            "Debug description for `Button_1`")
    }

    func testSummarizesIPSCrashReportFromExceptionBacktrace() throws {
        let body: [String: Any] = [
            "procName": "Transit",
            "bundleInfo": ["CFBundleIdentifier": "com.example.app", "CFBundleShortVersionString": "6.3"],
            "exception": ["type": "EXC_CRASH", "signal": "SIGABRT"],
            "faultingThread": 0,
            "threads": [["queue": "GULMutableDictionary", "frames": [["imageIndex": 0, "symbol": "__pthread_kill"]]]],
            "usedImages": [["name": "libsystem_kernel.dylib"], ["name": "Transit.debug.dylib"]],
            "lastExceptionBacktrace": [
                ["imageIndex": 0, "symbol": "objc_exception_throw", "symbolLocation": 72],
                [
                    "imageIndex": 1, "symbol": "-[GULMutableDictionary setObject:forKeyedSubscript:]",
                    "symbolLocation": 52, "sourceFile": "GULMutableDictionary.m", "sourceLine": 90,
                ],
            ],
        ]
        var data = Data(#"{"app_name":"Transit","bug_type":"309"}"#.utf8)
        data.append(UInt8(ascii: "\n"))
        data.append(try JSONSerialization.data(withJSONObject: body))

        let crash = try XCTUnwrap(XCTestReport().crashReportPreview(fromIPS: data))
        XCTAssertEqual(crash.frameCount, 2)
        let lines = crash.preview.components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "Transit (com.example.app 6.3) crashed: EXC_CRASH (SIGABRT)")
        XCTAssertEqual(lines[1], "Queue: GULMutableDictionary")
        XCTAssertEqual(
            lines[2],
            "Crash site: GULMutableDictionary.m:90 in -[GULMutableDictionary setObject:forKeyedSubscript:]")
        XCTAssertTrue(crash.preview.contains("Last exception backtrace:"))
        XCTAssertTrue(crash.preview.contains("objc_exception_throw + 72"))
        XCTAssertNil(XCTestReport().crashReportPreview(fromIPS: Data("plain text log\n".utf8)))
    }
}
