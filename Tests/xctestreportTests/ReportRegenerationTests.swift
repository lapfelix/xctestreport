import Foundation
import XCTest

@testable import xctestreport

final class ReportRegenerationTests: XCTestCase {
    func testFailedGenerationLeavesPreviousReportAndAttachmentsIntact() throws {
        let root = try temporaryDirectory()
        let output = root.appendingPathComponent("report")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try Data("previous complete report".utf8).write(to: output.appendingPathComponent("index.html"))
        XCTAssertThrowsError(try XCTestReport.withStagedOutput(at: output.path) { stage in
            try Data("incomplete replacement".utf8).write(to: URL(fileURLWithPath: stage).appendingPathComponent("index.html"))
            throw XCTestReport.RuntimeError(message: "simulated required output failure")
        })
        XCTAssertEqual(try String(contentsOf: output.appendingPathComponent("index.html")), "previous complete report")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["report"])
    }

    func testSuccessfulGenerationPublishesStagedFilesAndKeepsCustomFiles() throws {
        let root = try temporaryDirectory()
        let output = root.appendingPathComponent("report")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try Data("custom".utf8).write(to: output.appendingPathComponent("custom.txt"))
        try XCTestReport.withStagedOutput(at: output.path) { stage in
            try Data("complete".utf8).write(to: URL(fileURLWithPath: stage).appendingPathComponent("index.html"))
        }
        XCTAssertEqual(try String(contentsOf: output.appendingPathComponent("index.html")), "complete")
        XCTAssertEqual(try String(contentsOf: output.appendingPathComponent("custom.txt")), "custom")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["report"])
    }

    func testRecoversStoredAndCompressedAttachmentEntriesWithoutLooseCopies() throws {
        let root = try temporaryDirectory()
        let tests = root.appendingPathComponent("tests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        let writer = try ZipArchiveWriter(path: tests.appendingPathComponent("previous.zip").path)
        let stored = Data("a short attachment".utf8)
        let compressed = Data(String(repeating: "a longer decoded attachment\n", count: 1000).utf8)
        try writer.addFile(name: "attachments/1.txt", data: stored, compress: false)
        try writer.addFile(name: "attachments/2.txt.gz", data: compressed, compress: true)
        try writer.addFile(name: "timeline/screenshots.json", data: Data("[]".utf8))
        try writer.finish()
        var report = makeReport(output: root)
        report.htmlOnly = true
        try report.recoverBundledAttachments()
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("attachments/1.txt")), stored)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("attachments/2.txt.gz")), compressed)
        XCTAssertEqual(report.readAttachmentData(at: root.appendingPathComponent("attachments/2.txt.gz").path), compressed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("timeline").path))
    }

    func testCorruptAndUnsafeBundlesCannotOverwriteReportData() throws {
        let root = try temporaryDirectory()
        let tests = root.appendingPathComponent("tests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        let zip = tests.appendingPathComponent("bad.zip")
        let writer = try ZipArchiveWriter(path: zip.path)
        try writer.addFile(name: "attachments/../escaped.txt", data: Data("invalid".utf8), compress: false)
        try writer.finish()
        let report = makeReport(output: root)
        XCTAssertThrowsError(try report.recoverBundledAttachments())
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("escaped.txt").path))
        var bytes = try Data(contentsOf: zip)
        bytes[0] = 0
        try bytes.write(to: zip)
        let reader = try ReportBundleReader(path: zip.path)
        XCTAssertThrowsError(try reader.data(for: reader.entries[0]))
    }

    func testPreviousRunUsesTimestampIdentityAndMergedInventory() throws {
        let root = try temporaryDirectory()
        let current = root.appendingPathComponent("middle-name")
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        let report = makeReport(output: current)
        try writeMetadata(title: "Project A", start: 300, at: current)
        let nearest = root.appendingPathComponent("a-nearest")
        let older = root.appendingPathComponent("z-older")
        let future = root.appendingPathComponent("z-future")
        let unrelated = root.appendingPathComponent("z-other-project")
        for (directory, title, start) in [(nearest, "Project A", 200.0), (older, "Project A", 100),
                                         (future, "Project A", 400), (unrelated, "Project B", 250)] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try writeMetadata(title: title, start: start, at: directory)
            let prior = makeReport(output: directory)
            try prior.writeSavedInventory(tests: [testNode(identifier: "AdditionalPlan/test()", result: "Failed")], sourceBundles: ["merged.xcresult", "other.xcresult"])
        }
        XCTAssertEqual(report.previousReportDirectories(), [nearest.path, older.path])
        let history = try XCTUnwrap(report.findPreviousResults())
        XCTAssertEqual(history.date.timeIntervalSince1970, 200)
        XCTAssertEqual(history.results["AdditionalPlan/test()"]?.status, "Failed")
        var explicit = report
        explicit.baseline = unrelated.path
        XCTAssertEqual(explicit.previousReportDirectories(), [unrelated.path])
    }

    func testCachedActivitiesAndMergedInventorySurviveSourceRemoval() throws {
        let root = try temporaryDirectory()
        var report = makeReport(output: root)
        let tests = [testNode(identifier: "MainPlan/test()", result: "Passed"),
                     testNode(identifier: "AdditionalPlan/test()", result: "Failed")]
        try report.writeSavedInventory(tests: tests, sourceBundles: ["merged.xcresult", "other.xcresult"])
        try Data("{}".utf8).write(to: root.appendingPathComponent("test_details.json"))
        let activity = XCTestReport.TestActivities(testIdentifier: "AdditionalPlan/test()", testRuns: [
            XCTestReport.TestActivityRun(activities: [XCTestReport.TestActivity(title: "Cached step", startTime: 200,
                isAssociatedWithFailure: true, attachments: nil, childActivities: nil, failureBranchStyle: nil)])])
        report.recordTestActivities(activity, for: activity.testIdentifier)
        try report.writeTestActivitiesIndex()
        report.htmlOnly = true
        try report.prepareRegenerationCaches()
        XCTAssertEqual(try report.loadSavedInventory()?.tests.map { $0.nodeIdentifier }, tests.map { $0.nodeIdentifier })
        XCTAssertEqual(report.getTestActivities(for: activity.testIdentifier)?.testRuns[0].activities[0].title, "Cached step")
        XCTAssertNil(report.getTestDetails(for: activity.testIdentifier))
        try report.writeTestDetailsIndex()
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("test_details.json")), "{}")
    }

    func testMissingManifestAndMissingAttachmentsAreExplicitErrors() throws {
        let root = try temporaryDirectory()
        let report = makeReport(output: root)
        XCTAssertThrowsError(try report.loadAttachmentsFromManifest(at: root.path))
        try Data("invalid JSON".utf8).write(to: root.appendingPathComponent("manifest.json"))
        XCTAssertThrowsError(try report.loadAttachmentsFromManifest(at: root.path))
        let item = XCTestReport.AttachmentManifestItem(exportedFileName: "absent.png", isAssociatedWithFailure: true,
            suggestedHumanReadableName: "Expected.png", timestamp: nil, payloadRefId: nil)
        XCTAssertThrowsError(try report.validateRegenerationAttachments(["Suite/test()": [item]]))
    }

    func testSymlinkInsideCopiedOutputCannotEscapeStaging() throws {
        let root = try temporaryDirectory()
        let output = root.appendingPathComponent("report")
        let external = root.appendingPathComponent("external")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: output.appendingPathComponent("attachments"), withDestinationURL: external)
        var invoked = false
        XCTAssertThrowsError(try XCTestReport.withStagedOutput(at: output.path) { _ in invoked = true })
        XCTAssertFalse(invoked)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: external.path).isEmpty)
    }

    private func temporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("regeneration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func makeReport(output: URL) -> XCTestReport {
        var report = XCTestReport()
        report.xcresultPath = output.appendingPathComponent("nonexistent.xcresult").path
        report.outputDir = output.path
        return report
    }

    private func writeMetadata(title: String, start: Double, at directory: URL) throws {
        let metadata = XCTestReport.ReportRunMetadata(title: title, startTime: start, finishTime: start + 1)
        try JSONEncoder().encode(metadata).write(to: directory.appendingPathComponent("report_metadata.json"))
    }

    private func testNode(identifier: String, result: String) -> XCTestReport.TestNode {
        XCTestReport.TestNode(name: "test()", nodeType: "Test Case", nodeIdentifier: identifier, result: result,
            duration: "1s", details: nil, children: nil, startTime: 100)
    }
}
