import Foundation

// Review notes live only in the viewer's browser (notes.js). The generator tags pages so notes
// stay scoped to one report and the export can link back to each test.
extension XCTestReport {
    var reviewNotesEnabled: Bool { !noNotes }

    /// Stable across regenerations of the same xcresult, so notes survive a re-run of the tool,
    /// and different between test runs. Every report on a host shares one localStorage.
    static func reviewNotesReportID(title: String, startTime: Double, finishTime: Double) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(title)|\(startTime)|\(finishTime)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    /// Attributes for a page's `<body>`, with a leading space, or "" when notes are off.
    func reviewNotesBodyAttributes(
        reportID: String, reportRoot: String, extra: [(String, String)] = []
    ) -> String {
        guard reviewNotesEnabled else { return "" }
        let attributes = [("data-report-id", reportID), ("data-report-root", reportRoot)] + extra
        return attributes.map { " \($0.0)=\"\(htmlEscape($0.1))\"" }.joined()
    }

    func reviewNotesScriptHTML(webDirectory: String) -> String {
        guard reviewNotesEnabled else { return "" }
        return "<script src=\"\(webDirectory)/notes.js\" defer></script>"
    }
}
