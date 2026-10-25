import XCTest

@testable import xctestreport

final class GCSSignedInViewingTests: XCTestCase {
    func testTheBootstrapGoesFirstInTheHeadOnce() {
        let page = "<!DOCTYPE html><html><head><link rel=\"stylesheet\" href=\"web/report.css\"></head></html>"
        let once = GCSSignedInViewing.injected(into: page)
        let head = once.range(of: "<head>")!.upperBound
        XCTAssertTrue(once[head...].hasPrefix(GCSSignedInViewing.marker + "<script>"))
        XCTAssertTrue(once.contains(GCSSignedInViewing.workerObjectName))
        XCTAssertEqual(GCSSignedInViewing.injected(into: once), once, "a second pass leaves the page alone")
    }

    func testTheWorkerAndEveryPageAreWritten() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GCSSignedInViewingTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("tests"), withIntermediateDirectories: true)
        for page in ["index.html", "tests/test_a.html"] {
            try "<html><head></head></html>".write(
                to: root.appendingPathComponent(page), atomically: true, encoding: .utf8)
        }

        let report = try XCTestReport.parse(["unused.xcresult", root.path])
        try GCSSignedInViewing.install(inReportAt: root.path, report: report)

        let worker = try String(
            contentsOf: root.appendingPathComponent("web/\(GCSSignedInViewing.workerFileName)"), encoding: .utf8)
        XCTAssertTrue(worker.contains("addEventListener('fetch'"))
        for page in ["index.html", "tests/test_a.html"] {
            let html = try String(contentsOf: root.appendingPathComponent(page), encoding: .utf8)
            XCTAssertTrue(html.contains(GCSSignedInViewing.marker), page)
        }
    }
}
