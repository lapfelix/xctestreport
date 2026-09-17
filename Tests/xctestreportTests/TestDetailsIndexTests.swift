import Foundation
import XCTest

@testable import xctestreport

final class TestDetailsIndexTests: XCTestCase {

    func testIndexRoundTripsCollectedTestDetails() throws {
        let reportDir = try makeReportDir()
        var report = makeReport()
        report.outputDir = reportDir

        report.recordTestDetailsJSON(
            testDetailsJSON(identifier: "MyTests/testAlpha()", runName: "Run 1", result: "Passed"),
            for: "MyTests/testAlpha()")
        report.recordTestDetailsJSON(
            testDetailsJSON(identifier: "MyTests/testBeta()", runName: "Run 1", result: "Failed"),
            for: "MyTests/testBeta()")
        report.writeTestDetailsIndex()

        let indexPath = (reportDir as NSString).appendingPathComponent("test_details.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: indexPath))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: (reportDir as NSString).appendingPathComponent("test_details")),
            "The per-test directory should no longer be produced.")

        let raw = try JSONSerialization.jsonObject(
            with: try Data(contentsOf: URL(fileURLWithPath: indexPath)))
        let entries = try XCTUnwrap(raw as? [String: Any])
        XCTAssertEqual(Set(entries.keys), ["MyTests/testAlpha()", "MyTests/testBeta()"])
        XCTAssertTrue(
            entries["MyTests/testAlpha()"] is [String: Any],
            "Each value should be the nested test-details object, not a JSON string.")

        let index = report.testDetailsIndex(inReportDir: reportDir)
        let alpha = try XCTUnwrap(index["MyTests/testAlpha()"])
        XCTAssertEqual(alpha.testIdentifier, "MyTests/testAlpha()")
        XCTAssertEqual(alpha.testName, "testAlpha()")
        XCTAssertEqual(alpha.testResult, "Passed")
        XCTAssertEqual(alpha.devices.first?.deviceName, "iPhone 17")
        XCTAssertEqual(alpha.testRuns?.map { $0.name }, ["Run 1"])
        XCTAssertEqual(index["MyTests/testBeta()"]?.testResult, "Failed")
    }

    func testIndexIsWrittenWhenNothingWasCollected() throws {
        let reportDir = try makeReportDir()
        var report = makeReport()
        report.outputDir = reportDir

        report.writeTestDetailsIndex()
        report.writeTestDetailsIndex()

        let indexPath = (reportDir as NSString).appendingPathComponent("test_details.json")
        let contents = try String(contentsOfFile: indexPath, encoding: .utf8)
        XCTAssertEqual(contents, "{}")
        XCTAssertTrue(report.testDetailsIndex(inReportDir: reportDir).isEmpty)
    }

    func testLegacyPerFileLayoutIsStillReadable() throws {
        let parentDir = try makeReportDir()
        let previousDir = (parentDir as NSString).appendingPathComponent("2024-01-01")
        try writeLegacyTestDetails(
            in: previousDir, identifier: "MyTests/testAlpha()", runName: "Legacy run")

        var report = makeReport()
        report.outputDir = (parentDir as NSString).appendingPathComponent("2024-01-02")
        try FileManager.default.createDirectory(
            atPath: report.outputDir, withIntermediateDirectories: true)

        let runs = report.getPreviousRuns(for: "MyTests/testAlpha()")
        XCTAssertEqual(runs.map { $0.name }, ["Legacy run"])
    }

    func testIndexWinsOverLegacyLayoutInTheSameDirectory() throws {
        let parentDir = try makeReportDir()
        let previousDir = (parentDir as NSString).appendingPathComponent("2024-01-01")
        try writeLegacyTestDetails(
            in: previousDir, identifier: "MyTests/testAlpha()", runName: "Legacy run")

        var previousReport = makeReport()
        previousReport.outputDir = previousDir
        previousReport.recordTestDetailsJSON(
            testDetailsJSON(
                identifier: "MyTests/testAlpha()", runName: "Indexed run", result: "Passed"),
            for: "MyTests/testAlpha()")
        previousReport.writeTestDetailsIndex()

        var report = makeReport()
        report.outputDir = (parentDir as NSString).appendingPathComponent("2024-01-02")
        try FileManager.default.createDirectory(
            atPath: report.outputDir, withIntermediateDirectories: true)

        let runs = report.getPreviousRuns(for: "MyTests/testAlpha()")
        XCTAssertEqual(runs.map { $0.name }, ["Indexed run"])
    }

    // MARK: - Helpers

    private func makeReport() -> XCTestReport {
        var report = XCTestReport()
        report.xcresultPath = ""
        report.outputDir = NSTemporaryDirectory()
        return report
    }

    private func makeReportDir() throws -> String {
        let dir = (NSTemporaryDirectory() as NSString).appendingPathComponent(
            "test-details-index-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: dir) }
        return dir
    }

    private func writeLegacyTestDetails(
        in reportDir: String, identifier: String, runName: String
    ) throws {
        let legacyDir = (reportDir as NSString).appendingPathComponent("test_details")
        try FileManager.default.createDirectory(
            atPath: legacyDir, withIntermediateDirectories: true)
        let path = (legacyDir as NSString).appendingPathComponent(
            "\(identifier.replacingOccurrences(of: "/", with: "_")).json")
        try testDetailsJSON(identifier: identifier, runName: runName, result: "Passed")
            .write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func testDetailsJSON(identifier: String, runName: String, result: String) -> String {
        let testName = (identifier as NSString).lastPathComponent
        return """
            {"devices":[{"deviceId":"ABC","deviceName":"iPhone 17","architecture":"arm64",\
            "modelName":"iPhone 17","platform":"iOS Simulator","osVersion":"26.0",\
            "osBuildNumber":"23A1"}],"duration":"1s","hasMediaAttachments":false,\
            "hasPerformanceMetrics":false,"startTime":1700000000,"testDescription":"",\
            "testIdentifier":"\(identifier)","testIdentifierURL":null,"testName":"\(testName)",\
            "testPlanConfigurations":[{"configurationId":"1","configurationName":"Default"}],\
            "testResult":"\(result)","testRuns":[{"children":null,"duration":"1s",\
            "name":"\(runName)","nodeIdentifier":"\(identifier)","nodeType":"Test Case",\
            "result":"\(result)"}]}
            """
    }
}
