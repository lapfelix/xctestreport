import Dispatch
import Foundation

private let sourceReferenceCacheLock = NSLock()
private var sourceReferenceResolvedCache = [String: XCTestReport.SourceLocation]()
private var sourceReferenceMissingCache = Set<String>()

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
        func collectDetailTexts(_ detail: TestRunChildDetail) {
            texts.append(detail.name)
            if let url = detail.url, !url.isEmpty {
                texts.append(url)
            }
            for child in detail.children ?? [] {
                collectDetailTexts(child)
            }
        }
        for run in testRuns {
            texts.append(run.name)
            for child in run.children ?? [] {
                texts.append(child.name)
                for detail in child.children ?? [] {
                    collectDetailTexts(detail)
                }
            }
        }
        return texts
    }

    func sourceReferenceLocationMap(
        from testRuns: [TestRunDetail],
        testIdentifierURL: String?
    ) -> [String: SourceLocation] {
        let references = sourceReferences(from: testRuns)
        guard !references.isEmpty else { return [:] }

        let projectHint = projectNameHint(from: testIdentifierURL)
        var locationsBySymbol = [String: SourceLocation]()

        for reference in references {
            guard let symbol = parseSourceReferenceSymbol(reference.name) else { continue }
            guard
                let location = resolveSourceReferenceLocation(
                    referenceName: reference.name,
                    referenceURL: reference.url,
                    projectHint: projectHint
                )
            else {
                continue
            }

            let exactKey = sourceReferenceSymbolKey(
                typeName: symbol.typeName, functionName: symbol.functionName)
            if locationsBySymbol[exactKey] == nil {
                locationsBySymbol[exactKey] = location
            }

            // Fallback for timeline rows that only show function names.
            let functionOnlyKey = sourceReferenceFunctionOnlyKey(symbol.functionName)
            if locationsBySymbol[functionOnlyKey] == nil {
                locationsBySymbol[functionOnlyKey] = location
            }
        }

        return locationsBySymbol
    }

    func sourceLocationLabelForTimelineTitle(
        _ title: String,
        sourceLocationBySymbol: [String: SourceLocation]
    ) -> String? {
        if let explicitLocation = extractSourceLocations(from: title).first {
            return shortSourceLocationLabel(explicitLocation)
        }

        guard let symbol = parseSourceReferenceSymbol(title) else { return nil }
        let exactKey = sourceReferenceSymbolKey(
            typeName: symbol.typeName, functionName: symbol.functionName)
        if let location = sourceLocationBySymbol[exactKey] {
            return shortSourceLocationLabel(location)
        }

        let functionOnlyKey = sourceReferenceFunctionOnlyKey(symbol.functionName)
        guard let location = sourceLocationBySymbol[functionOnlyKey] else { return nil }
        return shortSourceLocationLabel(location)
    }

    private func sourceReferences(from testRuns: [TestRunDetail]) -> [(name: String, url: String?)] {
        var references = [(name: String, url: String?)]()
        var seen = Set<String>()

        func walkDetail(_ detail: TestRunChildDetail) {
            if detail.nodeType == "Source Code Reference" {
                let key = "\(detail.name)|\(detail.url ?? "")"
                if !seen.contains(key) {
                    seen.insert(key)
                    references.append((detail.name, detail.url))
                }
            }
            for child in detail.children ?? [] {
                walkDetail(child)
            }
        }

        for run in testRuns {
            for child in run.children ?? [] {
                for detail in child.children ?? [] {
                    walkDetail(detail)
                }
            }
        }
        return references
    }

    private func projectNameHint(from testIdentifierURL: String?) -> String? {
        guard let testIdentifierURL, let components = URLComponents(string: testIdentifierURL)
        else { return nil }
        let pathComponents = components.path.split(separator: "/").map(String.init)
        return pathComponents.first
    }

    private func resolveSourceReferenceLocation(
        referenceName: String,
        referenceURL: String?,
        projectHint: String?
    ) -> SourceLocation? {
        let explicitTexts = [referenceName, referenceURL ?? ""].joined(separator: " ")
        if let explicit = extractSourceLocations(from: explicitTexts).first {
            return explicit
        }

        guard let symbol = parseSourceReferenceSymbol(referenceName) else { return nil }
        let cacheKey = "\(projectHint ?? "_")|\(symbol.typeName ?? "_")|\(symbol.functionName)"

        sourceReferenceCacheLock.lock()
        if let cached = sourceReferenceResolvedCache[cacheKey] {
            sourceReferenceCacheLock.unlock()
            return cached
        }
        if sourceReferenceMissingCache.contains(cacheKey) {
            sourceReferenceCacheLock.unlock()
            return nil
        }
        sourceReferenceCacheLock.unlock()

        let pattern =
            #"func\s+\#(NSRegularExpression.escapedPattern(for: symbol.functionName))\s*\("#
        for root in sourceSearchRoots(projectHint: projectHint) {
            var args = [
                "rg", "-n", "--no-heading", "--no-ignore-messages", "--glob", "*.swift", "-m",
                "40",
            ]
            if let typeName = symbol.typeName, !typeName.isEmpty {
                args += ["--glob", "*\(typeName)*.swift"]
            }
            args += [pattern, root]

            let (output, exitCode) = shell(args)
            guard exitCode == 0, let output else { continue }
            let matches = output
                .split(separator: "\n")
                .compactMap { parseRipgrepLocation(from: String($0)) }
            guard !matches.isEmpty else { continue }
            let location =
                matches.max { lhs, rhs in
                    let leftScore = sourcePathScore(lhs.filePath, projectHint: projectHint)
                    let rightScore = sourcePathScore(rhs.filePath, projectHint: projectHint)
                    if leftScore == rightScore {
                        return lhs.filePath.count > rhs.filePath.count
                    }
                    return leftScore < rightScore
                } ?? matches[0]

            sourceReferenceCacheLock.lock()
            sourceReferenceResolvedCache[cacheKey] = location
            sourceReferenceCacheLock.unlock()
            return location
        }

        sourceReferenceCacheLock.lock()
        sourceReferenceMissingCache.insert(cacheKey)
        sourceReferenceCacheLock.unlock()
        return nil
    }

    private func sourceSearchRoots(projectHint: String?) -> [String] {
        let fileManager = FileManager.default
        var orderedRoots = [String]()
        var seen = Set<String>()

        func appendRoot(_ root: String) {
            guard !root.isEmpty, !seen.contains(root) else { return }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: root, isDirectory: &isDirectory), isDirectory.boolValue
            else { return }
            seen.insert(root)
            orderedRoots.append(root)
        }

        appendRoot(fileManager.currentDirectoryPath)
        appendRoot((xcresultPath as NSString).deletingLastPathComponent)

        let home = fileManager.homeDirectoryForCurrentUser.path
        let gitsRoot = (home as NSString).appendingPathComponent("Gits")
        if let projectHint,
            let entries = try? fileManager.contentsOfDirectory(atPath: gitsRoot)
        {
            let filtered = entries
                .filter { $0.lowercased().contains(projectHint.lowercased()) }
                .sorted()
            for entry in filtered {
                appendRoot((gitsRoot as NSString).appendingPathComponent(entry))
            }
        }
        appendRoot(gitsRoot)

        return orderedRoots
    }

    private func parseSourceReferenceSymbol(_ sourceReference: String) -> (typeName: String?, functionName: String)? {
        var symbol = sourceReference.trimmingCharacters(in: .whitespacesAndNewlines)
        if symbol.hasPrefix("static ") {
            symbol = String(symbol.dropFirst("static ".count))
        }

        if let parenIndex = symbol.firstIndex(of: "(") {
            symbol = String(symbol[..<parenIndex])
        }
        symbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !symbol.isEmpty else { return nil }

        let parts = symbol.split(separator: ".").map(String.init)
        if parts.count >= 2 {
            let rawType = parts[parts.count - 2]
            let typeName = rawType.split(separator: " ").last.map(String.init)
            let functionName = parts[parts.count - 1]
            guard !functionName.isEmpty else { return nil }
            return (typeName, functionName)
        }

        let fallbackFunction = symbol.split(separator: " ").last.map(String.init) ?? symbol
        guard !fallbackFunction.isEmpty else { return nil }
        return (nil, fallbackFunction)
    }

    private func sourceReferenceSymbolKey(typeName: String?, functionName: String) -> String {
        let normalizedType = typeName?.lowercased() ?? "_"
        return "\(normalizedType)|\(functionName.lowercased())"
    }

    private func sourceReferenceFunctionOnlyKey(_ functionName: String) -> String {
        return "_|\(functionName.lowercased())"
    }

    private func shortSourceLocationLabel(_ location: SourceLocation) -> String {
        let fileName = (location.filePath as NSString).lastPathComponent
        return "\(fileName):\(location.line)"
    }

    private func parseRipgrepLocation(from line: String) -> SourceLocation? {
        let nsLine = line as NSString
        guard let regex = try? NSRegularExpression(pattern: #"^(.+?):(\d+):"#) else { return nil }
        let range = NSRange(location: 0, length: nsLine.length)
        guard let match = regex.firstMatch(in: line, options: [], range: range) else { return nil }
        guard match.numberOfRanges >= 3 else { return nil }

        let filePath = nsLine.substring(with: match.range(at: 1))
        let lineRaw = nsLine.substring(with: match.range(at: 2))
        guard let lineNumber = Int(lineRaw) else { return nil }
        return SourceLocation(filePath: filePath, line: lineNumber, column: nil)
    }

    private func sourcePathScore(_ filePath: String, projectHint: String?) -> Int {
        let lowercasedPath = filePath.lowercased()
        var score = 0

        if let projectHint = projectHint?.lowercased() {
            if lowercasedPath.contains("/\(projectHint)/") { score += 5 }
            if lowercasedPath.contains("/\(projectHint)-ios/") { score += 4 }
        }
        if lowercasedPath.contains("/uitests/") { score += 3 }
        if lowercasedPath.contains("/tests/") { score += 2 }
        if lowercasedPath.contains("codex") { score -= 3 }
        if lowercasedPath.contains("review") { score -= 2 }

        return score
    }

    func renderSourceLocationSection(candidateTexts: [String]) -> String {
        let locations = candidateTexts.flatMap { extractSourceLocations(from: $0) }
        guard !locations.isEmpty else { return "" }

        let items = locations.prefix(20).map { location -> String in
            let columnSuffix = location.column.map { ":\($0)" } ?? ""
            let locationLabel = "\(location.filePath):\(location.line)\(columnSuffix)"
            let locationCode = "<code>\(htmlEscape(locationLabel))</code>"
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
