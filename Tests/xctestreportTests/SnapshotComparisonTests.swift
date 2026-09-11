import Foundation
import XCTest

@testable import xctestreport

final class SnapshotComparisonTests: XCTestCase {

    // MARK: - Name parsing

    func testParsesCanonicalRoles() throws {
        let expected = try XCTUnwrap(
            XCTestReport.parseSnapshotAttachmentName("RouteDetails-noSeparators.expected.png"))
        XCTAssertEqual(expected.name, "RouteDetails-noSeparators")
        XCTAssertEqual(expected.role, .expected)

        let actual = try XCTUnwrap(
            XCTestReport.parseSnapshotAttachmentName("RouteDetails-noSeparators.actual.png"))
        XCTAssertEqual(actual.role, .actual)

        let diff = try XCTUnwrap(
            XCTestReport.parseSnapshotAttachmentName("RouteDetails-noSeparators.diff.png"))
        XCTAssertEqual(diff.role, .diff)
    }

    func testParsesRoleAliasesCaseInsensitively() throws {
        let reference = try XCTUnwrap(
            XCTestReport.parseSnapshotAttachmentName("Card.Reference.PNG"))
        XCTAssertEqual(reference.name, "Card")
        XCTAssertEqual(reference.role, .expected)

        let failure = try XCTUnwrap(XCTestReport.parseSnapshotAttachmentName("Card.FAILURE.png"))
        XCTAssertEqual(failure.role, .actual)

        let difference = try XCTUnwrap(
            XCTestReport.parseSnapshotAttachmentName("Card.difference.png"))
        XCTAssertEqual(difference.role, .diff)
    }

    func testRejectsNonMatchingNames() {
        XCTAssertNil(XCTestReport.parseSnapshotAttachmentName("Screenshot.png"))
        XCTAssertNil(XCTestReport.parseSnapshotAttachmentName("Card.expected.jpg"))
        XCTAssertNil(XCTestReport.parseSnapshotAttachmentName("Card.unexpected.png"))
        XCTAssertNil(XCTestReport.parseSnapshotAttachmentName(".expected.png"))
    }

    // MARK: - Comparison

    func testComparisonUsesUnionRectWhenSizesDiffer() {
        let report = makeReport()
        let expected = solidBitmap(width: 4, height: 4, color: (255, 255, 255, 255))
        let actual = solidBitmap(width: 4, height: 2, color: (255, 255, 255, 255))

        let result = report.compareSnapshotBitmaps(
            expected: expected, actual: actual, tolerance: 12)

        XCTAssertEqual(result.width, 4)
        XCTAssertEqual(result.height, 4)
        XCTAssertEqual(result.changedPixels, 8)
        XCTAssertEqual(result.maxChannelDelta, 255)
        XCTAssertEqual(result.boundingBoxes, [XCTestReport.SnapshotBoundingBox(x: 0, y: 2, w: 4, h: 2)])
    }

    func testToleranceSuppressesSmallChannelDifferences() {
        let report = makeReport()
        let expected = solidBitmap(width: 3, height: 3, color: (100, 100, 100, 255))
        let actual = solidBitmap(width: 3, height: 3, color: (108, 100, 100, 255))

        let withinTolerance = report.compareSnapshotBitmaps(
            expected: expected, actual: actual, tolerance: 12)
        XCTAssertEqual(withinTolerance.changedPixels, 0)
        XCTAssertEqual(withinTolerance.maxChannelDelta, 8)
        XCTAssertTrue(withinTolerance.boundingBoxes.isEmpty)

        let strict = report.compareSnapshotBitmaps(expected: expected, actual: actual, tolerance: 0)
        XCTAssertEqual(strict.changedPixels, 9)
    }

    func testBoundingBoxesSeparateDistantRegions() {
        let report = makeReport()
        var changed = [Bool](repeating: false, count: 40 * 10)
        changed[0] = true  // (0, 0)
        changed[1] = true  // (1, 0)
        changed[9 * 40 + 38] = true  // (38, 9)

        let boxes = report.snapshotBoundingBoxes(changed: changed, width: 40, height: 10)

        XCTAssertEqual(boxes.count, 2)
        XCTAssertEqual(boxes[0], XCTestReport.SnapshotBoundingBox(x: 0, y: 0, w: 2, h: 1))
        XCTAssertEqual(boxes[1], XCTestReport.SnapshotBoundingBox(x: 38, y: 9, w: 1, h: 1))
    }

    func testCoalescesAdjacentBoundingBoxes() {
        let report = makeReport()
        let boxes = [
            XCTestReport.SnapshotBoundingBox(x: 0, y: 0, w: 10, h: 10),
            XCTestReport.SnapshotBoundingBox(x: 11, y: 0, w: 5, h: 5),
            XCTestReport.SnapshotBoundingBox(x: 200, y: 200, w: 4, h: 4),
        ]

        let merged = report.coalesceSnapshotBoundingBoxes(boxes, gap: 4)

        XCTAssertEqual(merged.count, 2)
        XCTAssertTrue(merged.contains(XCTestReport.SnapshotBoundingBox(x: 0, y: 0, w: 16, h: 10)))
        XCTAssertTrue(merged.contains(XCTestReport.SnapshotBoundingBox(x: 200, y: 200, w: 4, h: 4)))
    }

    // MARK: - End-to-end grouping

    func testBuildsComparisonAndSynthesizesDiffImage() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let report = makeReport(outputDir: directory.path)
        try FileManager.default.createDirectory(
            atPath: report.attachmentsDirectoryPath, withIntermediateDirectories: true)

        writePNG(report, solidBitmap(width: 4, height: 4, color: (255, 255, 255, 255)), "1.png")
        writePNG(report, solidBitmap(width: 4, height: 2, color: (255, 255, 255, 255)), "2.png")

        let comparisons = report.buildSnapshotComparisons(attachments: [
            makeItem(fileName: "1.png", name: "Card.expected.png"),
            makeItem(fileName: "2.png", name: "Card.actual.png", failure: true),
            makeItem(fileName: "3.txt", name: "Not a snapshot"),
        ])

        XCTAssertEqual(comparisons.count, 1)
        let comparison = try XCTUnwrap(comparisons.first)
        XCTAssertEqual(comparison.name, "Card")
        XCTAssertEqual(comparison.expected.src, "../attachments/1.png")
        XCTAssertEqual(comparison.expected.rootSrc, "attachments/1.png")
        XCTAssertEqual(comparison.actual.rootSrc, "attachments/2.png")
        XCTAssertTrue(comparison.sizeMismatch)
        XCTAssertEqual(comparison.widthDelta, 0)
        XCTAssertEqual(comparison.heightDelta, -2)
        XCTAssertEqual(comparison.changedPixels, 8)
        XCTAssertEqual(comparison.totalPixels, 16)
        XCTAssertEqual(comparison.changedFraction, 0.5, accuracy: 0.000_001)
        XCTAssertTrue(comparison.failureAssociated)
        XCTAssertTrue(comparison.diffSynthesized)

        let diff = try XCTUnwrap(comparison.diff)
        XCTAssertEqual(diff.rootSrc, "attachments/1.synth-diff.png")
        XCTAssertEqual(diff.width, 4)
        XCTAssertEqual(diff.height, 4)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: (report.attachmentsDirectoryPath as NSString)
                    .appendingPathComponent("1.synth-diff.png")))
    }

    func testSkipsGroupsMissingExpectedOrActual() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let report = makeReport(outputDir: directory.path)
        try FileManager.default.createDirectory(
            atPath: report.attachmentsDirectoryPath, withIntermediateDirectories: true)
        writePNG(report, solidBitmap(width: 2, height: 2, color: (0, 0, 0, 255)), "1.png")

        let comparisons = report.buildSnapshotComparisons(attachments: [
            makeItem(fileName: "1.png", name: "Card.expected.png")
        ])

        XCTAssertTrue(comparisons.isEmpty)
    }

    func testDisabledFlagProducesNoComparisons() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var report = makeReport(outputDir: directory.path)
        report.noSnapshotDiff = true

        XCTAssertFalse(report.snapshotDiffEnabled)
        XCTAssertTrue(
            report.buildSnapshotComparisons(attachments: [
                makeItem(fileName: "1.png", name: "Card.expected.png"),
                makeItem(fileName: "2.png", name: "Card.actual.png"),
            ]).isEmpty)
    }

    // MARK: - JSON payload

    func testJSONPayloadShape() throws {
        let report = makeReport()
        let comparison = XCTestReport.SnapshotComparison(
            name: "Card",
            expected: XCTestReport.SnapshotImageRef(
                src: "../attachments/1.png", rootSrc: "attachments/1.png", width: 4, height: 4),
            actual: XCTestReport.SnapshotImageRef(
                src: "../attachments/2.png", rootSrc: "attachments/2.png", width: 4, height: 2),
            diff: nil,
            sizeMismatch: true,
            widthDelta: 0,
            heightDelta: -2,
            changedPixels: 8,
            totalPixels: 16,
            changedFraction: 0.5,
            maxChannelDelta: 255,
            boundingBoxes: [XCTestReport.SnapshotBoundingBox(x: 0, y: 2, w: 4, h: 2)],
            failureAssociated: true,
            diffSynthesized: false)

        let json = report.snapshotComparisonsJSON([comparison])
        let parsed = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        XCTAssertEqual(parsed.count, 1)
        let object = parsed[0]
        XCTAssertEqual(
            Set(object.keys),
            [
                "name", "expected", "actual", "diff", "sizeMismatch", "widthDelta", "heightDelta",
                "changedPixels", "totalPixels", "changedFraction", "maxChannelDelta",
                "boundingBoxes", "failureAssociated", "diffSynthesized",
            ])
        XCTAssertTrue(object["diff"] is NSNull)
        XCTAssertEqual(object["name"] as? String, "Card")
        let expectedImage = try XCTUnwrap(object["expected"] as? [String: Any])
        XCTAssertEqual(expectedImage["src"] as? String, "../attachments/1.png")
        XCTAssertEqual(expectedImage["rootSrc"] as? String, "attachments/1.png")
        XCTAssertEqual(expectedImage["width"] as? Int, 4)
        let boxes = try XCTUnwrap(object["boundingBoxes"] as? [[String: Any]])
        XCTAssertEqual(boxes[0]["y"] as? Int, 2)
        XCTAssertEqual(boxes[0]["h"] as? Int, 2)
    }

    func testHTMLSectionCarriesEncodedPayloadAndStaticFallback() throws {
        let report = makeReport()
        let comparison = XCTestReport.SnapshotComparison(
            name: "Card & \"Quoted\"",
            expected: XCTestReport.SnapshotImageRef(
                src: "../attachments/1.png", rootSrc: "attachments/1.png", width: 4, height: 4),
            actual: XCTestReport.SnapshotImageRef(
                src: "../attachments/2.png", rootSrc: "attachments/2.png", width: 4, height: 2),
            diff: XCTestReport.SnapshotImageRef(
                src: "../attachments/1.synth-diff.png",
                rootSrc: "attachments/1.synth-diff.png", width: 4, height: 4),
            sizeMismatch: true,
            widthDelta: 0,
            heightDelta: -2,
            changedPixels: 8,
            totalPixels: 16,
            changedFraction: 0.5,
            maxChannelDelta: 255,
            boundingBoxes: [],
            failureAssociated: true,
            diffSynthesized: true)

        XCTAssertTrue(report.renderSnapshotDiffSection(comparisons: []).isEmpty)

        let html = report.renderSnapshotDiffSection(comparisons: [comparison])
        XCTAssertTrue(html.hasPrefix("<section class=\"snapshot-diffs\" data-snapshot-comparisons=\""))
        XCTAssertTrue(html.contains("<img src=\"../attachments/1.png\""))
        XCTAssertTrue(html.contains("<img src=\"../attachments/2.png\""))
        XCTAssertTrue(html.contains("<img src=\"../attachments/1.synth-diff.png\""))
        XCTAssertTrue(html.contains("50.00%"))

        let deviceHTML = report.renderSnapshotDiffSection(
            comparisons: [comparison],
            device: XCTestReport.SnapshotDeviceInfo(
                name: "Apple Watch Series 11", deviceName: "iPhone 17 Pro Max", osVersion: "27.0",
                osBuildNumber: "24R5355a", platform: "watchOS Simulator", identifier: "ABC"))
        XCTAssertTrue(deviceHTML.contains("data-snapshot-device=\""))
        XCTAssertTrue(
            deviceHTML.contains(
                "<span class=\"snapshot-comparison-device\">"
                    + "Apple Watch Series 11 - watchOS Simulator 27.0 (24R5355a)</span>"))

        let attribute = try XCTUnwrap(
            html.components(separatedBy: "data-snapshot-comparisons=\"").last?
                .components(separatedBy: "\"").first)
        XCTAssertFalse(attribute.contains("\""))
        XCTAssertFalse(attribute.contains("&"))
        let decoded = try XCTUnwrap(attribute.removingPercentEncoding)
        let payload = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(decoded.utf8)) as? [[String: Any]])
        XCTAssertEqual(payload[0]["name"] as? String, "Card & \"Quoted\"")
    }

    func testDeviceInfoPrefersTestDetailsAndFallsBackToSummary() {
        let report = makeReport()
        // On a watchOS run deviceName is the paired host iPhone, so the model name wins.
        let fallback = XCTestReport.Device(
            deviceId: "10B307D8", deviceName: "iPhone 17 Pro Max", architecture: "arm64",
            modelName: "Apple Watch Series 11", platform: "watchOS Simulator", osVersion: "27.0",
            osBuildNumber: "24R5355a")

        let resolved = report.snapshotDeviceInfo(testDetails: nil, fallbackDevice: fallback)
        XCTAssertEqual(resolved.name, "Apple Watch Series 11")
        XCTAssertEqual(resolved.deviceName, "iPhone 17 Pro Max")
        XCTAssertEqual(resolved.osVersion, "27.0")
        XCTAssertEqual(resolved.osBuildNumber, "24R5355a")
        XCTAssertEqual(resolved.platform, "watchOS Simulator")
        XCTAssertEqual(resolved.identifier, "10B307D8")
        XCTAssertEqual(
            resolved.displayLabel, "Apple Watch Series 11 - watchOS Simulator 27.0 (24R5355a)")

        let empty = report.snapshotDeviceInfo(testDetails: nil, fallbackDevice: nil)
        XCTAssertNil(empty.name)
        XCTAssertNil(empty.deviceName)
        XCTAssertNil(empty.displayLabel)
    }

    func testWritesSnapshotReportEvenWithoutComparisons() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let report = makeReport(outputDir: directory.path)

        report.writeSnapshotReport(entries: [])

        let path = directory.appendingPathComponent("snapshots.json")
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
        XCTAssertEqual(object["totalComparisons"] as? Int, 0)
        XCTAssertEqual(object["failedComparisons"] as? Int, 0)
        XCTAssertEqual((object["tests"] as? [Any])?.count, 0)
        XCTAssertNotNil(object["generatedAt"] as? String)
    }

    func testSnapshotReportEntryCarriesDeviceAndRootRelativePaths() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let report = makeReport(outputDir: directory.path)
        let entry = XCTestReport.SnapshotReportTestEntry(
            testIdentifier: "SnapshotTests/testCard()",
            testName: "testCard()",
            suiteName: "SnapshotTests",
            testPagePath: "tests/test_SnapshotTests_testCard__.html",
            result: "Failed",
            failureMessage: "does not match its reference",
            device: XCTestReport.SnapshotDeviceInfo(
                name: "Apple Watch Series 11", deviceName: "iPhone 17 Pro Max", osVersion: "27.0",
                osBuildNumber: "24R5355a", platform: nil, identifier: nil),
            comparisons: [
                XCTestReport.SnapshotComparison(
                    name: "Card",
                    expected: XCTestReport.SnapshotImageRef(
                        src: "../attachments/1.png", rootSrc: "attachments/1.png", width: 4,
                        height: 4),
                    actual: XCTestReport.SnapshotImageRef(
                        src: "../attachments/2.png", rootSrc: "attachments/2.png", width: 4,
                        height: 4),
                    diff: nil,
                    sizeMismatch: false,
                    widthDelta: 0,
                    heightDelta: 0,
                    changedPixels: 4,
                    totalPixels: 16,
                    changedFraction: 0.25,
                    maxChannelDelta: 31,
                    boundingBoxes: [],
                    failureAssociated: true,
                    diffSynthesized: false),
            ])

        report.writeSnapshotReport(entries: [entry])

        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: directory.appendingPathComponent("snapshots.json")))
                as? [String: Any])
        XCTAssertEqual(object["totalComparisons"] as? Int, 1)
        XCTAssertEqual(object["failedComparisons"] as? Int, 1)
        let tests = try XCTUnwrap(object["tests"] as? [[String: Any]])
        let device = try XCTUnwrap(tests[0]["device"] as? [String: Any])
        XCTAssertEqual(device["name"] as? String, "Apple Watch Series 11")
        XCTAssertEqual(device["deviceName"] as? String, "iPhone 17 Pro Max")
        XCTAssertEqual(device["osBuildNumber"] as? String, "24R5355a")
        XCTAssertTrue(device["platform"] is NSNull)
        XCTAssertTrue(device["identifier"] is NSNull)
        let comparison = try XCTUnwrap((tests[0]["comparisons"] as? [[String: Any]])?.first)
        let expected = try XCTUnwrap(comparison["expected"] as? [String: Any])
        XCTAssertEqual(expected["rootSrc"] as? String, "attachments/1.png")
        XCTAssertFalse(comparison.keys.contains("hint"))
    }

    // MARK: - Helpers

    private func makeReport(outputDir: String = NSTemporaryDirectory()) -> XCTestReport {
        var report = XCTestReport()
        report.xcresultPath = ""
        report.outputDir = outputDir
        // ArgumentParser property wrappers only hold a value once parsed or assigned.
        report.noSnapshotDiff = false
        report.snapshotTolerance = 12
        return report
    }

    private func makeItem(fileName: String, name: String, failure: Bool = false)
        -> XCTestReport.AttachmentManifestItem
    {
        XCTestReport.AttachmentManifestItem(
            exportedFileName: fileName,
            isAssociatedWithFailure: failure ? true : nil,
            suggestedHumanReadableName: name,
            timestamp: nil,
            payloadRefId: nil)
    }

    private func solidBitmap(
        width: Int, height: Int, color: (UInt8, UInt8, UInt8, UInt8)
    ) -> XCTestReport.SnapshotBitmap {
        var pixels = [UInt8]()
        pixels.reserveCapacity(width * height * 4)
        for _ in 0..<(width * height) {
            pixels.append(contentsOf: [color.0, color.1, color.2, color.3])
        }
        return XCTestReport.SnapshotBitmap(width: width, height: height, pixels: pixels)
    }

    private func writePNG(
        _ report: XCTestReport, _ bitmap: XCTestReport.SnapshotBitmap, _ fileName: String
    ) {
        let path = (report.attachmentsDirectoryPath as NSString).appendingPathComponent(fileName)
        XCTAssertTrue(
            report.writeSnapshotPNG(
                pixels: bitmap.pixels, width: bitmap.width, height: bitmap.height, toPath: path))
    }

    private func makeTempDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("snapshotdiff-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
