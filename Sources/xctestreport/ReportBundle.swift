import Foundation

/// Per-test report bundles.
///
/// Everything a test page loads lazily -- timeline payloads, attachment previews, UI hierarchy
/// plists -- is packed into one ZIP next to the page instead of being scattered across
/// `attachments/` and `timeline_payloads/`. The browser pulls single entries back out with Range
/// requests (see `web/bundle-reader.js`).
///
/// Videos and snapshot comparison images stay loose: videos need real streaming and seeking, and
/// the snapshot contact sheet keeps working without JavaScript only while its `<img>` tags point at
/// real files.
extension XCTestReport {
    static let bundleAttachmentsPrefix = "attachments/"
    static let bundleRunStatesEntry = "timeline/runstates.json"
    static let bundleScreenshotsEntry = "timeline/screenshots.json"
    static let bundleMarkdownEntry = "test.md"

    /// Bundle entry name for an emitted test-page URL (`../attachments/12.png` -> `attachments/12.png`).
    func bundleEntryName(fromRelativePath relativePath: String?) -> String? {
        guard let relativePath, !relativePath.isEmpty else { return nil }
        let fileName = attachmentFileName(fromRelativePath: relativePath)
        guard !fileName.isEmpty else { return nil }
        return Self.bundleAttachmentsPrefix + fileName
    }

    func bundleFileName(forTestPageName testPageName: String) -> String {
        (testPageName as NSString).deletingPathExtension + ".zip"
    }

    /// Bundle entry for an emitted URL, or nil when the file must stay a loose file.
    ///
    /// Videos need range-served streaming and seeking that a blob URL cannot give them, and the
    /// snapshot contact sheet renders its `<img>` tags without JavaScript, so neither is packed.
    func bundleEntry(
        forRelativePath relativePath: String?,
        snapshotComparisonSources: Set<String>,
        bundle: Builder?
    ) -> String? {
        guard let bundle, let relativePath, !relativePath.isEmpty else { return nil }
        guard !snapshotComparisonSources.contains(relativePath) else { return nil }
        let fileName = attachmentFileName(fromRelativePath: relativePath)
        guard !fileName.isEmpty else { return nil }
        let ext = (fileName as NSString).pathExtension.lowercased()
        guard !["mp4", "mov", "m4v"].contains(ext) else { return nil }
        guard let entry = bundleEntryName(fromRelativePath: relativePath) else { return nil }
        bundle.addAttachment(entryName: entry)
        return entry
    }

    /// `src` for a loose file, `data-bundle-src` for one the reader has to unpack first.
    func mediaSourceAttributes(
        relativePath: String,
        attributeName: String = "src",
        snapshotComparisonSources: Set<String>,
        bundle: Builder?
    ) -> String {
        if let entry = bundleEntry(
            forRelativePath: relativePath, snapshotComparisonSources: snapshotComparisonSources,
            bundle: bundle)
        {
            return " data-bundle-src=\"\(htmlEscape(entry))\""
        }
        bundle?.keepLoose(fileName: attachmentFileName(fromRelativePath: relativePath))
        return " \(attributeName)=\"\(htmlEscape(relativePath))\""
    }

    func stillFrameSourceAttributes(
        for screenshot: ScreenshotSource,
        snapshotComparisonSources: Set<String>,
        bundle: Builder?
    ) -> String {
        mediaSourceAttributes(
            relativePath: screenshot.src, snapshotComparisonSources: snapshotComparisonSources,
            bundle: bundle)
    }

    /// Collects the entries one test page needs, then writes them as a single archive.
    final class Builder {
        private(set) var attachmentFileNames = Set<String>()
        /// Files this page links to as real files. A different test's bundle may still pack the
        /// same attachment, so these names have to survive the prune pass.
        private(set) var looseFileNames = Set<String>()
        private var extraEntries: [(name: String, data: Data)] = []

        func addAttachment(entryName: String) {
            guard entryName.hasPrefix(XCTestReport.bundleAttachmentsPrefix) else { return }
            attachmentFileNames.insert(
                String(entryName.dropFirst(XCTestReport.bundleAttachmentsPrefix.count)))
        }

        func keepLoose(fileName: String) {
            guard !fileName.isEmpty else { return }
            looseFileNames.insert(fileName)
        }

        func addEntry(name: String, data: Data) {
            extraEntries.append((name, data))
        }

        func addEntry(name: String, text: String) {
            addEntry(name: name, data: Data(text.utf8))
        }

        var isEmpty: Bool { attachmentFileNames.isEmpty && extraEntries.isEmpty }

        /// Returns the names of the attachment files that made it into the archive, so the caller
        /// can drop the loose copies once every page referencing them has been written.
        ///
        /// `decode` unwraps payloads the browser cannot open on its own -- xcresult stores some
        /// attachments zstd-compressed, and there is no native zstd in any browser -- so the
        /// archive always holds bytes the page can use directly.
        func write(
            to path: String, attachmentsDirectory: String, decode: (String) -> Data? = { _ in nil }
        ) throws -> Set<String> {
            let writer = try ZipArchiveWriter(path: path)
            for entry in extraEntries.sorted(by: { $0.name < $1.name }) {
                try writer.addFile(name: entry.name, data: entry.data)
            }

            var packed = Set<String>()
            for fileName in attachmentFileNames.sorted() {
                let source = (attachmentsDirectory as NSString).appendingPathComponent(fileName)
                guard let raw = FileManager.default.contents(atPath: source) else { continue }
                let decoded = decode(source) ?? raw
                // A decoded payload no longer matches the extension, so pick the method by content.
                let compress: Bool? = decoded.count == raw.count ? nil : true
                try writer.addFile(
                    name: XCTestReport.bundleAttachmentsPrefix + fileName, data: decoded,
                    compress: compress)
                packed.insert(fileName)
            }

            try writer.finish()
            return packed
        }
    }
}

extension XCTestReport {
    /// Drops the loose copies of every attachment that made it into a bundle.
    ///
    /// This runs once, after every page has been written, because an attachment the result bundle
    /// never attributed to a test can legitimately be referenced by more than one test page.
    func pruneLooseAttachments(
        packed: Set<String>, keepLoose: Set<String>, attachmentsDirectory: String
    ) {
        if keepLooseAttachments {
            print("Keeping \(packed.count) loose attachments alongside the per-test bundles.")
            return
        }
        let removable = packed.subtracting(keepLoose)
        guard !removable.isEmpty else { return }
        let fileManager = FileManager.default
        var removed = 0
        var reclaimed: Int64 = 0
        for fileName in removable {
            let path = (attachmentsDirectory as NSString).appendingPathComponent(fileName)
            if let attributes = try? fileManager.attributesOfItem(atPath: path),
                let size = attributes[.size] as? Int64
            {
                reclaimed += size
            }
            if (try? fileManager.removeItem(atPath: path)) != nil {
                removed += 1
            }
        }
        let megabytes = Double(reclaimed) / (1024.0 * 1024.0)
        print(
            "Packed \(removed) attachments into per-test bundles "
                + "(\(String(format: "%.1f", megabytes)) MB moved out of attachments/).")
    }
}
