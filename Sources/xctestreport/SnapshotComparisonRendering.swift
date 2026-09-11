import Foundation

// encodeURIComponent's unreserved set, ASCII only, so the JSON payload is safe inside a
// double-quoted HTML attribute.
private let snapshotURIComponentAllowed = CharacterSet(
    charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()"
)

extension XCTestReport {

    struct SnapshotReportTestEntry: Encodable {
        let testIdentifier: String?
        let testName: String
        let suiteName: String
        let testPagePath: String
        let result: String
        let failureMessage: String?
        let device: SnapshotDeviceInfo
        let comparisons: [SnapshotComparison]
    }

    struct SnapshotReport: Encodable {
        let generatedAt: String
        let totalComparisons: Int
        let failedComparisons: Int
        let tests: [SnapshotReportTestEntry]
    }

    var snapshotReportFileName: String { "snapshots.json" }

    // MARK: - HTML

    /// The title is the only server-rendered node the viewer keeps, so anything that must survive
    /// enhancement (the gallery back-link) goes in `titleExtraHTML`. A non-default
    /// `payloadAttributeName` hides the payload from snapshot-diff.js until a caller renames it.
    func renderSnapshotDiffSection(
        comparisons: [SnapshotComparison],
        device: SnapshotDeviceInfo? = nil,
        title: String? = "Snapshot comparisons",
        titleExtraHTML: String = "",
        payloadAttributeName: String = "data-snapshot-comparisons"
    ) -> String {
        guard !comparisons.isEmpty else { return "" }

        let payload = snapshotComparisonsJSON(comparisons)
        let encodedPayload =
            payload.addingPercentEncoding(withAllowedCharacters: snapshotURIComponentAllowed)
            ?? ""

        var deviceAttribute = ""
        if let device, let deviceJSON = snapshotJSONString(device),
            let encodedDevice = deviceJSON.addingPercentEncoding(
                withAllowedCharacters: snapshotURIComponentAllowed)
        {
            deviceAttribute = " data-snapshot-device=\"\(encodedDevice)\""
        }

        let titleHTML = title.map {
            "<h2 class=\"snapshot-diffs-title\">\(htmlEscape($0))\(titleExtraHTML)</h2>"
        } ?? ""

        var html = """
            <section class="snapshot-diffs" \(payloadAttributeName)="\(encodedPayload)"\(deviceAttribute)>
            \(titleHTML)
            """

        let deviceHTML = device?.displayLabel.map {
            "<span class=\"snapshot-comparison-device\">\(htmlEscape($0))</span>"
        } ?? ""

        for comparison in comparisons {
            let percent = String(format: "%.2f%%", comparison.changedFraction * 100)
            let deltaText =
                comparison.sizeMismatch
                ? "\(comparison.widthDelta >= 0 ? "+" : "")\(comparison.widthDelta) x "
                    + "\(comparison.heightDelta >= 0 ? "+" : "")\(comparison.heightDelta)"
                : "same size"

            var images = ""
            images += snapshotFigureImageHTML(
                label: "Expected", name: comparison.name, image: comparison.expected)
            images += snapshotFigureImageHTML(
                label: "Actual", name: comparison.name, image: comparison.actual)
            if let diff = comparison.diff {
                images += snapshotFigureImageHTML(
                    label: comparison.diffSynthesized ? "Diff (generated)" : "Diff",
                    name: comparison.name,
                    image: diff)
            }

            html += """
                <figure class="snapshot-comparison">
                <figcaption class="snapshot-comparison-name">\(htmlEscape(comparison.name))\(deviceHTML)</figcaption>
                <div class="snapshot-comparison-images">\(images)</div>
                <table class="data-table snapshot-comparison-stats">
                <thead><tr><th scope="col">Expected size</th><th scope="col">Actual size</th><th scope="col">Size delta</th><th scope="col">Changed</th><th scope="col">Max channel delta</th></tr></thead>
                <tbody><tr>
                <td data-label="Expected size">\(comparison.expected.width)x\(comparison.expected.height)</td>
                <td data-label="Actual size">\(comparison.actual.width)x\(comparison.actual.height)</td>
                <td data-label="Size delta">\(htmlEscape(deltaText))</td>
                <td data-label="Changed">\(percent) (\(comparison.changedPixels) / \(comparison.totalPixels) px)</td>
                <td data-label="Max channel delta">\(comparison.maxChannelDelta)</td>
                </tr></tbody>
                </table>
                </figure>
                """
        }

        html += "</section>"
        return html
    }

    private func snapshotFigureImageHTML(label: String, name: String, image: SnapshotImageRef)
        -> String
    {
        """
        <div class="snapshot-image snapshot-image-\(label.prefix(while: { $0.isLetter }).lowercased())">
        <h3 class="snapshot-image-label">\(htmlEscape(label))</h3>
        <img src="\(image.src)" width="\(image.width)" height="\(image.height)" loading="lazy" \
        alt="\(htmlEscape("\(label) snapshot for \(name)"))">
        </div>
        """
    }

    func snapshotComparisonsJSON(_ comparisons: [SnapshotComparison]) -> String {
        snapshotJSONString(comparisons) ?? "[]"
    }

    private func snapshotJSONString<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - snapshots.json
    //
    // Written at the report root next to index.html. Every image carries two paths: `src` is
    // relative to a test page (`tests/*.html`, i.e. "../attachments/3.png") and matches the HTML
    // payload; `rootSrc` is relative to this file's own directory (i.e. "attachments/3.png") and is
    // what an external consumer should join onto its base URL. The file is written whenever the
    // feature is enabled, even with zero comparisons.

    func writeSnapshotReport(entries: [SnapshotReportTestEntry]) {
        let sortedEntries = entries.sorted {
            ($0.suiteName, $0.testName) < ($1.suiteName, $1.testName)
        }
        let allComparisons = sortedEntries.flatMap { $0.comparisons }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"

        let report = SnapshotReport(
            generatedAt: formatter.string(from: Date()),
            totalComparisons: allComparisons.count,
            // A comparison "fails" when any pixel differs beyond the tolerance.
            failedComparisons: allComparisons.filter { $0.changedPixels > 0 }.count,
            tests: sortedEntries)

        let path = (outputDir as NSString).appendingPathComponent(snapshotReportFileName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(report)
            try data.write(to: URL(fileURLWithPath: path))
            print("Snapshot comparison report written to \(path)")
        } catch {
            print("Error writing snapshot comparison report: \(error)")
        }
    }
}
