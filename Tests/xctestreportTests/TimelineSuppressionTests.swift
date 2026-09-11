import Foundation
import XCTest

@testable import xctestreport

/// The timeline/scrubber is chrome: it must disappear for tests that have nothing to scrub, and it
/// must survive for anything that resembles a UI test.
final class TimelineSuppressionTests: XCTestCase {

    func testSuppressesSectionWhenThereIsNoActivityAndNoMedia() throws {
        let report = makeReport()
        let html = report.renderTimelineVideoSection(
            for: "PlainTests/testNothing()",
            activities: activities(runs: [[]]),
            attachmentsByTestIdentifier: [:],
            template: try timelineTemplate(),
            payloadBaseName: nil)

        XCTAssertEqual(html, "")
    }

    func testSuppressesSectionWhenActivitiesOnlyCarrySnapshotComparisonImages() throws {
        let report = makeReport()
        let attachments = [
            attachment(fileName: "1.png", name: "Card.actual.png", timestamp: 100),
            attachment(fileName: "2.png", name: "Card.expected.png", timestamp: 100.001),
        ]
        let html = report.renderTimelineVideoSection(
            for: "SnapshotTests/testCard()",
            activities: activities(runs: [
                [
                    activity(title: "Card actual", startTime: 100, attachmentNames: ["Card.actual.png"]),
                    activity(
                        title: "Card expected", startTime: 100.001,
                        attachmentNames: ["Card.expected.png"]),
                ]
            ]),
            attachmentsByTestIdentifier: ["SnapshotTests/testCard()": attachments],
            template: try timelineTemplate(),
            payloadBaseName: nil,
            snapshotComparisonSources: ["../attachments/1.png", "../attachments/2.png"])

        XCTAssertEqual(html, "")
    }

    func testKeepsSectionForScreenshotsTheComparisonSectionDoesNotRender() throws {
        let report = makeReport()
        let attachments = [attachment(fileName: "1.png", name: "Screenshot_1.png", timestamp: 100)]
        let html = report.renderTimelineVideoSection(
            for: "UITests/testFlow()",
            activities: activities(runs: [
                [activity(title: "Screenshot", startTime: 100, attachmentNames: ["Screenshot_1.png"])]
            ]),
            attachmentsByTestIdentifier: ["UITests/testFlow()": attachments],
            template: try timelineTemplate(),
            payloadBaseName: nil)

        XCTAssertTrue(html.contains("data-timeline-root"))
        XCTAssertTrue(html.contains("data-media-mode=\"screenshot\""))
    }

    func testKeepsSectionWhenAVideoIsAttached() throws {
        let report = makeReport()
        let attachments = [
            attachment(fileName: "1.mp4", name: "Screen Recording.mp4", timestamp: 100)
        ]
        let html = report.renderTimelineVideoSection(
            for: "UITests/testFlow()",
            activities: activities(runs: [[]]),
            attachmentsByTestIdentifier: ["UITests/testFlow()": attachments],
            template: try timelineTemplate(),
            payloadBaseName: nil)

        XCTAssertTrue(html.contains("data-media-mode=\"video\""))
    }

    func testKeepsSectionForNestedActivitiesWithoutAnyMedia() throws {
        let report = makeReport()
        let html = report.renderTimelineVideoSection(
            for: "UITests/testFlow()",
            activities: activities(runs: [
                [
                    XCTestReport.TestActivity(
                        title: "Tap \"Nearby\"",
                        startTime: 100,
                        isAssociatedWithFailure: false,
                        attachments: nil,
                        childActivities: [activity(title: "Wait for app to idle", startTime: 100.5)],
                        failureBranchStyle: nil)
                ]
            ]),
            attachmentsByTestIdentifier: [:],
            template: try timelineTemplate(),
            payloadBaseName: nil)

        XCTAssertTrue(html.contains("data-timeline-root"))
    }

    func testKeepsSectionWhenAnActivityIsAssociatedWithTheFailure() throws {
        let report = makeReport()
        let attachments = [attachment(fileName: "1.png", name: "Card.actual.png", timestamp: 100)]
        let html = report.renderTimelineVideoSection(
            for: "SnapshotTests/testCard()",
            activities: activities(runs: [
                [
                    activity(
                        title: "Card actual", startTime: 100, attachmentNames: ["Card.actual.png"],
                        failureAssociated: true)
                ]
            ]),
            attachmentsByTestIdentifier: ["SnapshotTests/testCard()": attachments],
            template: try timelineTemplate(),
            payloadBaseName: nil,
            snapshotComparisonSources: ["../attachments/1.png"])

        XCTAssertTrue(html.contains("data-timeline-root"))
    }

    // MARK: - Helpers

    private func makeReport() -> XCTestReport {
        var report = XCTestReport()
        report.xcresultPath = ""
        report.outputDir = NSTemporaryDirectory()
        report.noSnapshotDiff = false
        report.snapshotTolerance = 12
        return report
    }

    private func timelineTemplate() throws -> String {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Sources/xctestreport/Resources/Web/templates/timeline-section.html"),
            encoding: .utf8)
    }

    private func activities(runs: [[XCTestReport.TestActivity]]) -> XCTestReport.TestActivities {
        XCTestReport.TestActivities(
            testIdentifier: "Tests/test()",
            testRuns: runs.map { XCTestReport.TestActivityRun(activities: $0) })
    }

    private func activity(
        title: String, startTime: Double, attachmentNames: [String] = [],
        failureAssociated: Bool = false
    ) -> XCTestReport.TestActivity {
        XCTestReport.TestActivity(
            title: title,
            startTime: startTime,
            isAssociatedWithFailure: failureAssociated,
            attachments: attachmentNames.isEmpty
                ? nil
                : attachmentNames.map {
                    XCTestReport.TestActivityAttachment(
                        name: $0, timestamp: startTime, payloadId: nil)
                },
            childActivities: nil,
            failureBranchStyle: nil)
    }

    private func attachment(fileName: String, name: String, timestamp: Double)
        -> XCTestReport.AttachmentManifestItem
    {
        XCTestReport.AttachmentManifestItem(
            exportedFileName: fileName,
            isAssociatedWithFailure: false,
            suggestedHumanReadableName: name,
            timestamp: timestamp,
            payloadRefId: nil)
    }
}
