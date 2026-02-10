import Foundation

extension XCTestReport {
    var webAssetsDirectoryName: String { "web" }
    var testPagesDirectoryName: String { "tests" }

    var webAssetsDirectoryPath: String {
        (outputDir as NSString).appendingPathComponent(webAssetsDirectoryName)
    }

    var testPagesDirectoryPath: String {
        (outputDir as NSString).appendingPathComponent(testPagesDirectoryName)
    }

    func rootRelativePathFromTestPage(_ rootRelativePath: String) -> String {
        "../\(rootRelativePath)"
    }

    func attachmentRelativePathForTestPage(fileName: String) -> String {
        rootRelativePathFromTestPage("attachments/\(urlEncodePath(fileName))")
    }

    func timelinePayloadRelativePathForTestPage(fileName: String) -> String {
        rootRelativePathFromTestPage("timeline_payloads/\(urlEncodePath(fileName))")
    }

    func attachmentFileName(fromRelativePath relativePath: String) -> String {
        let decodedPath = relativePath.removingPercentEncoding ?? relativePath

        if let range = decodedPath.range(of: "/attachments/") {
            return String(decodedPath[range.upperBound...])
        }

        if let range = decodedPath.range(of: "attachments/") {
            return String(decodedPath[range.upperBound...])
        }

        return (decodedPath as NSString).lastPathComponent
    }
}
