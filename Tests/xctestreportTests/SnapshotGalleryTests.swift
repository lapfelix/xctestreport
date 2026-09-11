import Foundation
import XCTest

@testable import xctestreport

final class SnapshotGalleryTests: XCTestCase {

    func testOnlyClassesThatProducedComparisonsAreListed() {
        let report = makeReport()
        let suites = report.buildSnapshotGallerySuites(entries: [
            makeEntry(suite: "SnapTests", test: "testChanged()", result: "Failed", comparisons: 1),
            makeEntry(suite: "SnapTests", test: "testPassed()", result: "Passed", comparisons: 0),
            makeEntry(suite: "LogicTests", test: "testOther()", result: "Passed", comparisons: 0),
        ])

        XCTAssertEqual(suites.map { $0.name }, ["SnapTests"])
        // Tests with images sort first so the gallery opens on what can be looked at.
        XCTAssertEqual(suites[0].items.map { $0.entry.testName }, ["testChanged()", "testPassed()"])
        XCTAssertEqual(suites[0].items.map { $0.failed }, [true, false])
        XCTAssertEqual(suites[0].items.map { $0.hasImages }, [true, false])
    }

    func testComparisonImagesAreRewrittenRelativeToTheReportRoot() {
        let report = makeReport()
        let suites = report.buildSnapshotGallerySuites(entries: [
            makeEntry(suite: "SnapTests", test: "testChanged()", result: "Failed", comparisons: 1)
        ])
        let comparison = try! XCTUnwrap(suites.first?.items.first?.comparisons.first)

        XCTAssertEqual(comparison.expected.src, "attachments/1.png")
        XCTAssertEqual(comparison.actual.src, "attachments/2.png")
        XCTAssertEqual(comparison.diff?.src, "attachments/3.png")
    }

    func testPageCarriesFiltersGroupingAndPendingPayloads() throws {
        let report = makeReport()
        let suites = report.buildSnapshotGallerySuites(entries: [
            makeEntry(suite: "SnapTests", test: "testChanged()", result: "Failed", comparisons: 1),
            makeEntry(suite: "SnapTests", test: "testPassed()", result: "Passed", comparisons: 0),
        ])
        let html = try report.renderSnapshotGalleryPage(
            suites: suites, reportTitle: "MyScheme", template: try loadTemplate())

        XCTAssertFalse(html.contains("{{"))
        XCTAssertTrue(html.contains("aria-pressed=\"true\">Failed only"))
        XCTAssertTrue(html.contains("Showing 1 of 2 tests"))
        XCTAssertTrue(html.contains("data-suite=\"SnapTests\""))
        XCTAssertTrue(html.contains("id=\"test-snaptests-testchanged\""))
        XCTAssertTrue(html.contains("id=\"cmp-snaptests-testchanged-card\""))
        // The payload stays parked until the gallery decides to build that viewer.
        XCTAssertTrue(html.contains("data-snapshot-comparisons-pending=\""))
        XCTAssertFalse(html.contains(" data-snapshot-comparisons=\""))
        XCTAssertTrue(html.contains("only attached to a test that failed"))
        XCTAssertTrue(html.contains("1 test listed without images"))
    }

    func testFailedOnlyDefaultsOffWhenNothingFailed() throws {
        let report = makeReport()
        let suites = report.buildSnapshotGallerySuites(entries: [
            makeEntry(
                suite: "SnapTests", test: "testMatched()", result: "Passed", comparisons: 1,
                changedPixels: 0)
        ])
        let html = try report.renderSnapshotGalleryPage(
            suites: suites, reportTitle: "MyScheme", template: try loadTemplate())

        XCTAssertTrue(html.contains("aria-pressed=\"false\">Failed only"))
        XCTAssertTrue(html.contains("Showing 1 of 1 tests"))
    }

    func testMixedDeviceHeaderAndItemMetadata() throws {
        let report = makeReport()
        let watch = XCTestReport.SnapshotDeviceInfo(
            name: "Apple Watch Series 11", deviceName: "Paired iPhone", osVersion: "27.0",
            osBuildNumber: "24R1", platform: "watchOS Simulator", identifier: "WATCH")
        let entries = [
            makeEntry(suite: "PhoneTests", test: "testPhone()", result: "Failed", comparisons: 1),
            makeEntry(suite: "PhoneTests", test: "testOtherPhone()", result: "Failed", comparisons: 1),
            makeEntry(suite: "WatchTests", test: "testWatch()", result: "Failed", comparisons: 1, device: watch),
        ]
        let html = try report.renderSnapshotGalleryPage(
            suites: report.buildSnapshotGallerySuites(entries: entries),
            reportTitle: "Mixed targets", template: try loadTemplate())
        XCTAssertTrue(html.contains("All devices · 2"))
        XCTAssertTrue(html.contains("data-device-label=\"\(watch.displayLabel!)\""))
        XCTAssertTrue(html.contains("data-device-label=\"\(entries[0].device.displayLabel!)\""))
        let single = try report.renderSnapshotGalleryPage(
            suites: report.buildSnapshotGallerySuites(entries: [entries[2]]),
            reportTitle: "Watch only", template: try loadTemplate())
        XCTAssertTrue(single.contains("<span class=\"sg-device\">\(watch.displayLabel!)</span>"))
    }

    // MARK: - Helpers

    private func loadTemplate() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/xctestreport/Resources/Web/templates/snapshots.html")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func makeReport() -> XCTestReport {
        var report = XCTestReport()
        report.xcresultPath = ""
        report.outputDir = NSTemporaryDirectory()
        report.noSnapshotDiff = false
        report.snapshotTolerance = 12
        report.headerNote = nil
        return report
    }

    private func makeEntry(
        suite: String, test: String, result: String, comparisons: Int, changedPixels: Int = 12,
        device: XCTestReport.SnapshotDeviceInfo? = nil
    ) -> XCTestReport.SnapshotReportTestEntry {
        XCTestReport.SnapshotReportTestEntry(
            testIdentifier: "\(suite)/\(test)",
            testName: test,
            suiteName: suite,
            testPagePath: "tests/test_\(suite)_\(test).html",
            result: result,
            failureMessage: nil,
            device: device ?? XCTestReport.SnapshotDeviceInfo(
                name: "iPhone 17", deviceName: "iPhone 17", osVersion: "26.0",
                osBuildNumber: "23A1", platform: "iOS Simulator", identifier: "ABC"),
            comparisons: (0..<comparisons).map { _ in makeComparison(changedPixels: changedPixels) })
    }

    private func makeComparison(changedPixels: Int) -> XCTestReport.SnapshotComparison {
        XCTestReport.SnapshotComparison(
            name: "Card",
            expected: XCTestReport.SnapshotImageRef(
                src: "../attachments/1.png", rootSrc: "attachments/1.png", width: 4, height: 4),
            actual: XCTestReport.SnapshotImageRef(
                src: "../attachments/2.png", rootSrc: "attachments/2.png", width: 4, height: 4),
            diff: XCTestReport.SnapshotImageRef(
                src: "../attachments/3.png", rootSrc: "attachments/3.png", width: 4, height: 4),
            sizeMismatch: false,
            widthDelta: 0,
            heightDelta: 0,
            changedPixels: changedPixels,
            totalPixels: 16,
            changedFraction: Double(changedPixels) / 16,
            maxChannelDelta: changedPixels > 0 ? 255 : 0,
            boundingBoxes: [],
            failureAssociated: changedPixels > 0,
            diffSynthesized: false)
    }
}
