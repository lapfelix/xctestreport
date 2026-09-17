import Foundation
import XCTest

@testable import xctestreport

final class ReportBundleTests: XCTestCase {

    private func makeReport(outputDir: String = NSTemporaryDirectory()) -> XCTestReport {
        var report = XCTestReport()
        report.xcresultPath = ""
        report.outputDir = outputDir
        report.noSnapshotDiff = false
        report.snapshotTolerance = 12
        report.keepLooseAttachments = false
        return report
    }

    // MARK: - What gets bundled

    func testBundlesOrdinaryAttachments() {
        let report = makeReport()
        let bundle = XCTestReport.Builder()
        let entry = report.bundleEntry(
            forRelativePath: "../attachments/12.plist", snapshotComparisonSources: [],
            bundle: bundle)
        XCTAssertEqual(entry, "attachments/12.plist")
        XCTAssertEqual(bundle.attachmentFileNames, ["12.plist"])
    }

    /// Videos need real streaming and seeking, which a blob URL cannot provide.
    func testLeavesVideosLoose() {
        let report = makeReport()
        for fileName in ["7.mp4", "7.mov", "7.m4v"] {
            let bundle = XCTestReport.Builder()
            XCTAssertNil(
                report.bundleEntry(
                    forRelativePath: "../attachments/\(fileName)", snapshotComparisonSources: [],
                    bundle: bundle),
                "\(fileName) must stay a loose file")
            XCTAssertTrue(bundle.attachmentFileNames.isEmpty)
        }
    }

    /// The snapshot contact sheet renders its <img> tags with JavaScript disabled.
    func testLeavesSnapshotComparisonImagesLoose() {
        let report = makeReport()
        let bundle = XCTestReport.Builder()
        let sources: Set<String> = ["../attachments/1.png"]
        XCTAssertNil(
            report.bundleEntry(
                forRelativePath: "../attachments/1.png", snapshotComparisonSources: sources,
                bundle: bundle))
        XCTAssertNil(
            report.bundleEntry(
                forRelativePath: nil, snapshotComparisonSources: sources, bundle: bundle))
        // An image that is not part of a comparison is still bundled.
        XCTAssertEqual(
            report.bundleEntry(
                forRelativePath: "../attachments/2.png", snapshotComparisonSources: sources,
                bundle: bundle),
            "attachments/2.png")
    }

    func testEmitsBundleAttributeForBundledAssetsAndPlainSourceOtherwise() {
        let report = makeReport()
        let bundle = XCTestReport.Builder()

        XCTAssertEqual(
            report.mediaSourceAttributes(
                relativePath: "../attachments/12.plist", attributeName: "href",
                snapshotComparisonSources: [], bundle: bundle),
            " data-bundle-src=\"attachments/12.plist\"")

        XCTAssertEqual(
            report.mediaSourceAttributes(
                relativePath: "../attachments/7.mp4", snapshotComparisonSources: [],
                bundle: bundle),
            " src=\"../attachments/7.mp4\"")
        XCTAssertTrue(
            bundle.looseFileNames.contains("7.mp4"),
            "a loose asset must be protected from the prune pass")
    }

    func testBundleEntryNameStripsTestPagePrefix() {
        let report = makeReport()
        XCTAssertEqual(
            report.bundleEntryName(fromRelativePath: "../attachments/3.png"), "attachments/3.png")
        XCTAssertEqual(
            report.bundleEntryName(fromRelativePath: "attachments/3.png"), "attachments/3.png")
        XCTAssertNil(report.bundleEntryName(fromRelativePath: nil))
        XCTAssertNil(report.bundleEntryName(fromRelativePath: ""))
    }

    func testBundleFileNameIsSiblingOfTestPage() {
        let report = makeReport()
        XCTAssertEqual(
            report.bundleFileName(forTestPageName: "test_MySuite_testFoo().html"),
            "test_MySuite_testFoo().zip")
    }

    // MARK: - Packing

    func testWritesReferencedAttachmentsAndReportsWhatItPacked() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bundle-\(UUID().uuidString)")
        let attachments = directory.appendingPathComponent("attachments")
        try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let payload = Data(String(repeating: "plist body. ", count: 200).utf8)
        try payload.write(to: attachments.appendingPathComponent("12.plist"))

        let bundle = XCTestReport.Builder()
        bundle.addEntry(name: XCTestReport.bundleMarkdownEntry, text: "# detail")
        bundle.addAttachment(entryName: "attachments/12.plist")
        bundle.addAttachment(entryName: "attachments/missing.plist")

        let archivePath = directory.appendingPathComponent("test.zip").path
        let packed = try bundle.write(
            to: archivePath, attachmentsDirectory: attachments.path)

        XCTAssertEqual(packed, ["12.plist"], "a missing file must not be reported as packed")

        let listed = try shellOutput(["/usr/bin/unzip", "-Z1", archivePath])
        XCTAssertTrue(listed.contains("attachments/12.plist"))
        XCTAssertTrue(listed.contains("test.md"))
        XCTAssertFalse(listed.contains("missing"))

        let extracted = try shellOutput(["/usr/bin/unzip", "-p", archivePath, "attachments/12.plist"])
        XCTAssertEqual(extracted, String(decoding: payload, as: UTF8.self))
    }

    /// xcresult stores some attachments zstd-compressed and no browser can decode zstd, so the
    /// packer unwraps them and the archive holds bytes the page can use directly.
    func testStoresDecodedPayloadWhenTheSourceIsCompressed() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bundle-\(UUID().uuidString)")
        let attachments = directory.appendingPathComponent("attachments")
        try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data([0x28, 0xB5, 0x2F, 0xFD, 0x00]).write(
            to: attachments.appendingPathComponent("9.dat"))

        let bundle = XCTestReport.Builder()
        bundle.addAttachment(entryName: "attachments/9.dat")
        let archivePath = directory.appendingPathComponent("test.zip").path
        _ = try bundle.write(
            to: archivePath, attachmentsDirectory: attachments.path,
            decode: { _ in Data("decoded payload".utf8) })

        let extracted = try shellOutput(["/usr/bin/unzip", "-p", archivePath, "attachments/9.dat"])
        XCTAssertEqual(extracted, "decoded payload")
    }

    // MARK: - Pruning

    func testPruneKeepsVideosSnapshotsAndAnythingStillLinkedLoose() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("prune-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for fileName in ["12.plist", "13.txt", "1.png", "7.mp4"] {
            try Data("x".utf8).write(to: directory.appendingPathComponent(fileName))
        }

        let report = makeReport()
        // 1.png was packed by one test but another test links it as a snapshot image.
        report.pruneLooseAttachments(
            packed: ["12.plist", "13.txt", "1.png"], keepLoose: ["1.png", "7.mp4"],
            attachmentsDirectory: directory.path)

        let remaining = Set(
            try FileManager.default.contentsOfDirectory(atPath: directory.path))
        XCTAssertEqual(remaining, ["1.png", "7.mp4"])
    }

    func testKeepLooseAttachmentsFlagPreservesEverything() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("prune-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("x".utf8).write(to: directory.appendingPathComponent("12.plist"))

        var report = makeReport()
        report.keepLooseAttachments = true
        report.pruneLooseAttachments(
            packed: ["12.plist"], keepLoose: [], attachmentsDirectory: directory.path)

        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: directory.path), ["12.plist"])
    }

    private func shellOutput(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: arguments[0])
        process.arguments = Array(arguments.dropFirst())
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
