import Foundation
import XCTest

@testable import xctestreport

final class ScreenshotSourcesTests: XCTestCase {
    func testRepeatedScreenshotNamesResolveByPayloadAcrossRetries() {
        let report = XCTestReport()
        let activities = XCTestReport.TestActivities(testIdentifier: "Suite/test()", testRuns: [
            run(start: 100, payload: "first"), run(start: 200, payload: "second")
        ])
        let sources = report.buildScreenshotSources(
            for: "Suite/test()", activities: activities,
            attachmentsByTestIdentifier: ["Suite/test()": [
                attachment(file: "1.png", payload: "first", timestamp: nil),
                attachment(file: "2.png", payload: "second", timestamp: nil)
            ]])
        XCTAssertEqual(sources.map { $0.time }, [100, 200])
        XCTAssertEqual(sources.map { $0.runIndex }, [0, 1])
        XCTAssertEqual(sources.map { $0.src }, ["../attachments/1.png", "../attachments/2.png"])
    }

    func testManifestTimestampIsPreservedWhenNoPayloadMatchExists() {
        let report = XCTestReport()
        let sources = report.buildScreenshotSources(
            for: "Suite/test()",
            activities: XCTestReport.TestActivities(testIdentifier: "Suite/test()", testRuns: [
                run(start: 100, payload: "first"), run(start: 200, payload: "second")
            ]),
            attachmentsByTestIdentifier: ["Suite/test()": [
                attachment(file: "2.png", payload: nil, timestamp: 201)
            ]])
        XCTAssertEqual(sources.first?.time, 201)
        XCTAssertEqual(sources.first?.runIndex, 1)
    }

    func testUntimedReferenceDoesNotOverrideTheMatchingRetry() {
        let untimed = XCTestReport.TestActivityRun(activities: [XCTestReport.TestActivity(
            title: "Take screenshot", startTime: 100, isAssociatedWithFailure: false,
            attachments: [XCTestReport.TestActivityAttachment(name: "Screenshot", timestamp: nil, payloadId: "shared")],
            childActivities: nil, failureBranchStyle: nil)])
        let sources = XCTestReport().buildScreenshotSources(
            for: "Suite/test()",
            activities: XCTestReport.TestActivities(testIdentifier: "Suite/test()", testRuns: [
                untimed, run(start: 200, payload: "shared")
            ]),
            attachmentsByTestIdentifier: ["Suite/test()": [attachment(file: "2.png", payload: "shared", timestamp: 201)]])
        XCTAssertEqual(sources.first?.time, 200)
        XCTAssertEqual(sources.first?.runIndex, 1)
    }

    func testBundledTimelineKeepsOnlyOneFullPayload() throws {
        let report = XCTestReport()
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let template = try String(contentsOf: root.appendingPathComponent(
            "Sources/xctestreport/Resources/Web/templates/timeline-section.html"), encoding: .utf8)
        let bundle = XCTestReport.Builder()
        let html = report.renderTimelineVideoSection(
            for: "Suite/test()",
            activities: XCTestReport.TestActivities(testIdentifier: "Suite/test()", testRuns: [run(start: 100, payload: "first")]),
            attachmentsByTestIdentifier: [:], template: template, payloadBaseName: "fixture", bundle: bundle)
        XCTAssertTrue(html.contains("data-timeline-run-states data-bundle-src=\"timeline/runstates.json\">[]</script>"))
        XCTAssertTrue(html.contains("data-timeline-screenshots data-bundle-src=\"timeline/screenshots.json\">[]</script>"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try bundle.write(to: directory.appendingPathComponent("test.zip").path, attachmentsDirectory: directory.path)
        let reader = try ReportBundleReader(path: directory.appendingPathComponent("test.zip").path)
        let entry = try XCTUnwrap(reader.entries.first { $0.name == "timeline/runstates.json" })
        let json = try XCTUnwrap(String(data: reader.data(for: entry), encoding: .utf8))
        XCTAssertTrue(json.contains("Take screenshot"))
    }

    private func run(start: Double, payload: String) -> XCTestReport.TestActivityRun {
        XCTestReport.TestActivityRun(activities: [XCTestReport.TestActivity(
            title: "Take screenshot", startTime: start, isAssociatedWithFailure: false,
            attachments: [XCTestReport.TestActivityAttachment(name: "Screenshot", timestamp: start, payloadId: payload)],
            childActivities: nil, failureBranchStyle: nil)])
    }

    private func attachment(file: String, payload: String?, timestamp: Double?) -> XCTestReport.AttachmentManifestItem {
        XCTestReport.AttachmentManifestItem(exportedFileName: file, isAssociatedWithFailure: false,
            suggestedHumanReadableName: "Screenshot", timestamp: timestamp, payloadRefId: payload)
    }
}
