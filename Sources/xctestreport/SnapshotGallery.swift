import Foundation

// snapshots.html: every snapshot-producing test in the run on one page, grouped by test class.
//
// Xcode only attaches reference/failure images when a snapshot assertion fails, so only failing
// tests can be shown with images. A test that passed is still listed - flat, without images - when
// its class produced at least one comparison, which is the only evidence the xcresult carries that
// the class takes snapshots at all. That inference is stated on the page rather than hidden.

extension XCTestReport {

    struct SnapshotGalleryItem {
        let entry: SnapshotReportTestEntry
        /// Same comparisons as the test page, with `src` rewritten relative to the report root.
        let comparisons: [SnapshotComparison]
        let elementID: String
        let failed: Bool

        var hasImages: Bool { !comparisons.isEmpty }
        var changedCount: Int { comparisons.filter { $0.changedPixels > 0 }.count }
        var matchedCount: Int { comparisons.count - changedCount }
    }

    struct SnapshotGallerySuite {
        let name: String
        let items: [SnapshotGalleryItem]

        var changedCount: Int { items.reduce(0) { $0 + $1.changedCount } }
        var failedCount: Int { items.filter { $0.failed }.count }
    }

    var snapshotGalleryFileName: String { "snapshots.html" }

    // MARK: - Identifiers

    func snapshotGallerySlug(_ input: String) -> String {
        var slug = ""
        var pendingSeparator = false
        for character in input.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(character) {
                if pendingSeparator && !slug.isEmpty { slug.append("-") }
                pendingSeparator = false
                slug.unicodeScalars.append(character)
            } else {
                pendingSeparator = true
            }
        }
        return slug.isEmpty ? "x" : slug
    }

    func snapshotGalleryTestElementID(suite: String, testName: String) -> String {
        "test-\(snapshotGallerySlug(suite))-\(snapshotGallerySlug(testName))"
    }

    func snapshotGalleryComparisonElementID(suite: String, testName: String, comparisonName: String)
        -> String
    {
        "cmp-\(snapshotGallerySlug(suite))-\(snapshotGallerySlug(testName))"
            + "-\(snapshotGallerySlug(comparisonName))"
    }

    // MARK: - Model

    func buildSnapshotGallerySuites(entries: [SnapshotReportTestEntry]) -> [SnapshotGallerySuite] {
        let suitesWithComparisons = Set(
            entries.filter { !$0.comparisons.isEmpty }.map { $0.suiteName })
        guard !suitesWithComparisons.isEmpty else { return [] }

        let relevant = entries.filter { suitesWithComparisons.contains($0.suiteName) }
        let grouped = Dictionary(grouping: relevant) { $0.suiteName }

        return grouped.keys.sorted().map { suiteName in
            let items = (grouped[suiteName] ?? [])
                .sorted { lhs, rhs in
                    let lhsHasImages = !lhs.comparisons.isEmpty
                    let rhsHasImages = !rhs.comparisons.isEmpty
                    if lhsHasImages != rhsHasImages { return lhsHasImages }
                    return lhs.testName.localizedStandardCompare(rhs.testName) == .orderedAscending
                }
                .map { entry -> SnapshotGalleryItem in
                    let comparisons = entry.comparisons.map(rootRelativeSnapshotComparison)
                    return SnapshotGalleryItem(
                        entry: entry,
                        comparisons: comparisons,
                        elementID: snapshotGalleryTestElementID(
                            suite: entry.suiteName, testName: entry.testName),
                        failed: Self.isFailureTestResult(entry.result)
                            || comparisons.contains { $0.changedPixels > 0 })
                }
            return SnapshotGallerySuite(name: suiteName, items: items)
        }
    }

    func rootRelativeSnapshotComparison(_ comparison: SnapshotComparison) -> SnapshotComparison {
        func rootRelative(_ image: SnapshotImageRef) -> SnapshotImageRef {
            SnapshotImageRef(
                src: image.rootSrc, rootSrc: image.rootSrc, width: image.width,
                height: image.height)
        }

        return SnapshotComparison(
            name: comparison.name,
            expected: rootRelative(comparison.expected),
            actual: rootRelative(comparison.actual),
            diff: comparison.diff.map(rootRelative),
            sizeMismatch: comparison.sizeMismatch,
            widthDelta: comparison.widthDelta,
            heightDelta: comparison.heightDelta,
            changedPixels: comparison.changedPixels,
            totalPixels: comparison.totalPixels,
            changedFraction: comparison.changedFraction,
            maxChannelDelta: comparison.maxChannelDelta,
            boundingBoxes: comparison.boundingBoxes,
            failureAssociated: comparison.failureAssociated,
            diffSynthesized: comparison.diffSynthesized)
    }

    // MARK: - Page

    /// Returns the index-page link markup, or "" when the run produced no comparison at all.
    @discardableResult
    func writeSnapshotGalleryPage(
        entries: [SnapshotReportTestEntry], reportTitle: String, template: String
    ) -> String {
        let suites = buildSnapshotGallerySuites(entries: entries)
        guard !suites.isEmpty else { return "" }

        let html: String
        do {
            html = try renderSnapshotGalleryPage(
                suites: suites, reportTitle: reportTitle, template: template)
        } catch {
            print("Error rendering snapshot gallery: \(error)")
            return ""
        }

        let path = (outputDir as NSString).appendingPathComponent(snapshotGalleryFileName)
        do {
            try minifyHTMLInterTagWhitespace(html).write(
                toFile: path, atomically: true, encoding: .utf8)
            print("Snapshot gallery written to \(path)")
        } catch {
            print("Error writing snapshot gallery: \(error)")
            return ""
        }

        let allComparisons = suites.flatMap { $0.items.flatMap { $0.comparisons } }
        let changed = allComparisons.filter { $0.changedPixels > 0 }.count
        let summary =
            changed > 0
            ? "\(changed) changed of \(allComparisons.count)"
            : "\(allComparisons.count) comparisons"
        return """
            <p class="agent-report-link snapshot-gallery-link">\
            <a href="\(snapshotGalleryFileName)">Snapshot gallery (\(summary))</a></p>
            """
    }

    func renderSnapshotGalleryPage(
        suites: [SnapshotGallerySuite], reportTitle: String, template: String
    ) throws -> String {
        let items = suites.flatMap { $0.items }
        let comparisons = items.flatMap { $0.comparisons }
        let changedComparisons = comparisons.filter { $0.changedPixels > 0 }.count
        let anyFailed = items.contains { $0.failed }
        let withoutImages = items.filter { !$0.hasImages }.count

        var headerNoteHTML = ""
        if let note = headerNote?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            headerNoteHTML = "<p class=\"header-note\">\(htmlEscape(note))</p>"
        }

        let deviceLabels = Set(items.map { $0.entry.device.displayLabel ?? "Device unknown" })
        let deviceLabel = deviceLabels.count > 1
            ? "All devices · \(deviceLabels.count)"
            : (deviceLabels.first ?? "Device unknown")

        var limitationNote =
            "Snapshot images are only attached to a test that failed, so only changed comparisons "
            + "can be shown side by side."
        if withoutImages > 0 {
            limitationNote +=
                " The \(withoutImages) test\(withoutImages == 1 ? "" : "s") listed without images "
                + "passed in a class that produced comparisons; the result bundle carries no "
                + "record of what they captured."
        }

        let chips = suites.map { suite -> String in
            """
            <button type="button" class="sg-chip" data-suite="\(htmlEscape(suite.name))" \
            aria-pressed="true">\(htmlEscape(suite.name))\
            <span class="sg-chip-count">\(suite.items.count)</span></button>
            """
        }.joined()

        let values: [String: String] = [
            "report_title": htmlEscape(reportTitle),
            "header_note_html": headerNoteHTML,
            "device_label": htmlEscape(deviceLabel),
            "total_comparisons": String(comparisons.count),
            "changed_comparisons": String(changedComparisons),
            "matched_comparisons": String(comparisons.count - changedComparisons),
            "total_items": String(items.count),
            "visible_items": String(anyFailed ? items.filter { $0.failed }.count : items.count),
            "failed_only_pressed": anyFailed ? "true" : "false",
            "suite_chips_html": chips,
            "limitation_note_html": "<p class=\"sg-note\">\(htmlEscape(limitationNote))</p>",
            "suite_sections_html": suites.map(renderSnapshotGallerySuite).joined(),
        ]
        return try renderTemplate(template, values: values, templateName: "snapshots.html")
    }

    private func renderSnapshotGallerySuite(_ suite: SnapshotGallerySuite) -> String {
        let stats =
            "<span class=\"sg-suite-count\"><span data-sg-visible>\(suite.items.count)</span>"
            + " of \(suite.items.count) tests</span>"
            + "<span class=\"sg-suite-changed\">\(suite.changedCount) changed</span>"

        return """
            <section class="sg-suite" data-suite="\(htmlEscape(suite.name))">
            <h2 class="sg-suite-head"><button type="button" class="sg-suite-toggle" \
            aria-expanded="true"><span class="sg-caret" aria-hidden="true"></span>\
            <span class="sg-suite-name">\(htmlEscape(suite.name))</span>\(stats)</button></h2>
            <div class="sg-suite-body">\(suite.items.map(renderSnapshotGalleryItem).joined())</div>
            </section>
            """
    }

    private func renderSnapshotGalleryItem(_ item: SnapshotGalleryItem) -> String {
        let entry = item.entry
        let searchText = ([entry.testName, entry.suiteName] + item.comparisons.map { $0.name })
            .joined(separator: " ")
            .lowercased()

        let badge: String
        let meta: String
        if item.hasImages {
            let changed = item.changedCount
            badge =
                changed > 0
                ? "<span class=\"sg-badge sg-badge-changed\">Changed</span>"
                : "<span class=\"sg-badge sg-badge-matched\">Matched</span>"
            let percent = item.comparisons.map { $0.changedFraction }.max() ?? 0
            meta =
                "\(item.comparisons.count) comparison\(item.comparisons.count == 1 ? "" : "s")"
                + (changed > 0 ? String(format: " - up to %.2f%% changed", percent * 100) : "")
        } else if Self.isSkippedTestResult(entry.result) {
            badge = "<span class=\"sg-badge sg-badge-skipped\">Skipped</span>"
            meta = "no images"
        } else if item.failed {
            badge = "<span class=\"sg-badge sg-badge-failed\">Failed</span>"
            meta = "failed without snapshot images"
        } else {
            badge = "<span class=\"sg-badge sg-badge-matched\">Matched</span>"
            meta = "no images - captured only on failure"
        }

        let anchors = item.comparisons.map { comparison in
            let id = snapshotGalleryComparisonElementID(
                suite: entry.suiteName, testName: entry.testName, comparisonName: comparison.name)
            return "<span class=\"sg-anchor\" id=\"\(id)\"></span>"
        }.joined()

        var body = ""
        if item.hasImages {
            // The gallery reads the parked payload to build lightweight previews. It creates
            // a live section for just the selected comparison when the inspector opens.
            let section = renderSnapshotDiffSection(
                comparisons: item.comparisons,
                device: entry.device,
                title: nil,
                payloadAttributeName: "data-snapshot-comparisons-pending")
            body = "<div class=\"sg-item-body\">\(section)</div>"
        }

        return """
            <article class="sg-item" id="\(item.elementID)" \
            data-suite="\(htmlEscape(entry.suiteName))" \
            data-device-label="\(htmlEscape(entry.device.displayLabel ?? "Device unknown"))" \
            data-failed="\(item.failed ? "true" : "false")" \
            data-has-viewer="\(item.hasImages ? "true" : "false")" \
            data-search="\(htmlEscape(searchText))">\(anchors)
            <header class="sg-item-head">
            <span class="sg-item-name">\(htmlEscape(entry.testName))</span>\(badge)
            <span class="sg-item-meta">\(htmlEscape(meta))</span>
            <a class="sg-item-link" href="\(htmlEscape(entry.testPagePath))">Test page</a>
            </header>\(body)
            </article>
            """
    }
}
