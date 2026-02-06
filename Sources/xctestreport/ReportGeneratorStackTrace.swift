import Dispatch
import Foundation

extension XCTestReport {
    func htmlEscape(_ input: String) -> String {
        return input
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    func urlEncodePath(_ path: String) -> String {
        return path.split(separator: "/").map { component in
            component.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
                ?? String(component)
        }.joined(separator: "/")
    }

    func xcodeURL(filePath: String, line: Int, column: Int?) -> String? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=?")
        guard let encodedFilePath = filePath.addingPercentEncoding(withAllowedCharacters: allowed)
        else { return nil }

        var url = "xcode://open?file=\(encodedFilePath)&line=\(line)"
        if let column {
            url += "&column=\(column)"
        }
        return url
    }

    func extractSourceLocations(from text: String) -> [SourceLocation] {
        let patterns = [
            #"([A-Za-z0-9_~\./\\-]+\.(?:swift|m|mm|c|cc|cpp|h|hpp|kt|java|js|ts|tsx|py|rb|go|rs)):(\d+)(?::(\d+))?"#,
            #"\(([^()]+\.(?:swift|m|mm|c|cc|cpp|h|hpp|kt|java|js|ts|tsx|py|rb|go|rs)):(\d+)(?::(\d+))?\)"#,
        ]

        var allMatches = [SourceLocation]()
        let nsText = text as NSString

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = regex.matches(
                in: text, options: [], range: NSRange(location: 0, length: nsText.length))

            for match in matches {
                guard match.numberOfRanges >= 3 else { continue }
                let filePath = nsText.substring(with: match.range(at: 1))
                let lineRaw = nsText.substring(with: match.range(at: 2))
                guard let line = Int(lineRaw) else { continue }

                var column: Int? = nil
                if match.numberOfRanges >= 4, match.range(at: 3).location != NSNotFound {
                    let columnRaw = nsText.substring(with: match.range(at: 3))
                    column = Int(columnRaw)
                }

                allMatches.append(SourceLocation(filePath: filePath, line: line, column: column))
            }
        }

        var deduped = [SourceLocation]()
        var seen = Set<String>()
        for location in allMatches {
            let key = "\(location.filePath)|\(location.line)|\(location.column ?? -1)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            deduped.append(location)
        }
        return deduped
    }

    func extractRunDetailTexts(from testRuns: [TestRunDetail]) -> [String] {
        var texts = [String]()
        for run in testRuns {
            texts.append(run.name)
            for child in run.children ?? [] {
                texts.append(child.name)
                for detail in child.children ?? [] {
                    texts.append(detail.name)
                }
            }
        }
        return texts
    }

    func renderSourceLocationSection(candidateTexts: [String]) -> String {
        let locations = candidateTexts.flatMap { extractSourceLocations(from: $0) }
        guard !locations.isEmpty else { return "" }

        let items = locations.prefix(20).map { location -> String in
            let columnSuffix = location.column.map { ":\($0)" } ?? ""
            let locationLabel = "\(location.filePath):\(location.line)\(columnSuffix)"
            let locationCode = "<code>\(htmlEscape(locationLabel))</code>"

            if let xcodeUrl = xcodeURL(
                filePath: location.filePath, line: location.line, column: location.column)
            {
                return "<li>\(locationCode) <a href=\"\(xcodeUrl)\">Open in Xcode</a></li>"
            }
            return "<li>\(locationCode)</li>"
        }.joined(separator: "")

        return """
            <h3>Source Locations</h3>
            <ul>\(items)</ul>
            """
    }

    func extractStackTracePreview(
        for testIdentifier: String?,
        attachmentsByTestIdentifier: [String: [AttachmentManifestItem]]
    ) -> StackTracePreview? {
        guard let testIdentifier else { return nil }
        let attachments = attachmentsByTestIdentifier[testIdentifier] ?? []
        guard !attachments.isEmpty else { return nil }

        let attachmentRoot = (outputDir as NSString).appendingPathComponent("attachments")
        var best: StackTracePreview? = nil

        for attachment in attachments {
            let ext = URL(fileURLWithPath: attachment.exportedFileName).pathExtension.lowercased()
            guard ["txt", "log", "crash", "ips"].contains(ext) else { continue }

            let absolutePath =
                (attachmentRoot as NSString).appendingPathComponent(attachment.exportedFileName)
            guard let fileData = FileManager.default.contents(atPath: absolutePath) else { continue }
            let limitedData = Data(fileData.prefix(220_000))
            guard let text = String(data: limitedData, encoding: .utf8) else { continue }

            let lines = text.components(separatedBy: .newlines)
            var frameLineIndexes = [Int]()
            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let isFrameLine =
                    trimmed.range(of: #"^#\d+"#, options: .regularExpression) != nil
                    || trimmed.range(
                        of: #"^\d+\s+\S+\s+0x[0-9a-fA-F]+"#, options: .regularExpression) != nil
                    || trimmed.range(
                        of: #"^\d+\s+\S+\s+[A-Za-z_]\w*.*\+"#, options: .regularExpression) != nil

                if isFrameLine {
                    frameLineIndexes.append(index)
                }
            }

            guard frameLineIndexes.count >= 3 else { continue }
            let firstIndex = frameLineIndexes[0]
            let lastIndex = frameLineIndexes[min(frameLineIndexes.count - 1, 20)]
            let start = max(0, firstIndex - 2)
            let end = min(lines.count - 1, lastIndex + 2)
            let preview = lines[start...end].joined(separator: "\n").trimmingCharacters(
                in: .whitespacesAndNewlines)
            guard !preview.isEmpty else { continue }

            let candidate = StackTracePreview(
                attachmentName: attachment.suggestedHumanReadableName ?? attachment.exportedFileName,
                relativePath: "attachments/\(urlEncodePath(attachment.exportedFileName))",
                preview: preview,
                frameCount: frameLineIndexes.count
            )

            if best == nil || candidate.frameCount > best!.frameCount {
                best = candidate
            }
        }

        return best
    }

    func renderStackTraceSection(
        for testIdentifier: String?,
        attachmentsByTestIdentifier: [String: [AttachmentManifestItem]]
    ) -> String {
        guard
            let stack = extractStackTracePreview(
                for: testIdentifier, attachmentsByTestIdentifier: attachmentsByTestIdentifier)
        else { return "" }

        return """
            <h3>Stack Trace (Preview)</h3>
            <p><a href="\(stack.relativePath)" target="_blank" rel="noopener">\(htmlEscape(stack.attachmentName))</a></p>
            <pre class="stack-trace">\(htmlEscape(stack.preview))</pre>
            """
    }

}
