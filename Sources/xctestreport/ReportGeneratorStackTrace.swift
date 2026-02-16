import Dispatch
import Foundation
import SQLite3

private let sourceReferenceCacheLock = NSLock()
private var sourceReferenceResolvedCache = [String: XCTestReport.SourceLocation]()
private var sourceReferenceMissingCache = Set<String>()
private let sourceSearchRootsLock = NSLock()
private var sourceSearchRootsCache = [String: [String]]()
private let sourceSymbolLocationsLock = NSLock()
private var sourceSymbolLocationsCache = [String: [SourceSymbolLocationEntry]]()

private struct SourceSymbolLocationEntry {
    let symbolName: String
    let functionName: String
    let typeName: String?
    let location: XCTestReport.SourceLocation
}

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

        if let location = resolveSourceReferenceLocationFromSymbols(
            referenceName: referenceName, parsedSymbol: symbol, projectHint: projectHint)
        {
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

    private func resolveSourceReferenceLocationFromSymbols(
        referenceName: String,
        parsedSymbol: (typeName: String?, functionName: String),
        projectHint: String?
    ) -> SourceLocation? {
        let entries = sourceSymbolLocations()
        guard !entries.isEmpty else { return nil }

        if let direct = entries.first(where: { $0.symbolName == referenceName }) {
            return direct.location
        }

        var candidates = entries.filter { $0.functionName == parsedSymbol.functionName }
        if let typeName = parsedSymbol.typeName?.lowercased() {
            let typed = candidates.filter { $0.typeName?.lowercased() == typeName }
            if !typed.isEmpty {
                candidates = typed
            }
        }
        guard !candidates.isEmpty else { return nil }

        return candidates.max { lhs, rhs in
            let leftScore = sourcePathScore(lhs.location.filePath, projectHint: projectHint)
            let rightScore = sourcePathScore(rhs.location.filePath, projectHint: projectHint)
            if leftScore == rightScore {
                return lhs.location.filePath.count > rhs.location.filePath.count
            }
            return leftScore < rightScore
        }?.location
    }

    private func sourceSearchRoots(projectHint: String?) -> [String] {
        let cacheKey = projectHint ?? "_"
        sourceSearchRootsLock.lock()
        if let cached = sourceSearchRootsCache[cacheKey] {
            sourceSearchRootsLock.unlock()
            return cached
        }
        sourceSearchRootsLock.unlock()

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

        sourceSearchRootsLock.lock()
        sourceSearchRootsCache[cacheKey] = orderedRoots
        sourceSearchRootsLock.unlock()
        return orderedRoots
    }

    private func sourceSymbolLocations() -> [SourceSymbolLocationEntry] {
        let cacheKey = xcresultPath
        sourceSymbolLocationsLock.lock()
        if let cached = sourceSymbolLocationsCache[cacheKey] {
            sourceSymbolLocationsLock.unlock()
            return cached
        }
        sourceSymbolLocationsLock.unlock()

        let dbPath = (xcresultPath as NSString).appendingPathComponent("database.sqlite3")
        guard FileManager.default.fileExists(atPath: dbPath) else { return [] }

        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_close(db) }

        let query = """
            SELECT s.symbolName, l.filePath, l.lineNumber
            FROM SourceCodeSymbolInfos s
            JOIN SourceCodeLocations l ON s.location_fk = l.ROWID
            WHERE s.symbolName IS NOT NULL AND l.filePath IS NOT NULL AND l.lineNumber IS NOT NULL
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var entries = [SourceSymbolLocationEntry]()
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let symbolPtr = sqlite3_column_text(stmt, 0),
                let filePtr = sqlite3_column_text(stmt, 1)
            else { continue }
            let lineNumber = Int(sqlite3_column_int(stmt, 2))
            guard lineNumber > 0 else { continue }
            let filePath = String(cString: filePtr)
            guard filePath != "/<compiler-generated>" else { continue }

            let symbolName = String(cString: symbolPtr)
            guard let parsed = parseSourceReferenceSymbol(symbolName) else { continue }

            let location = SourceLocation(filePath: filePath, line: lineNumber, column: nil)
            entries.append(
                SourceSymbolLocationEntry(
                    symbolName: symbolName,
                    functionName: parsed.functionName,
                    typeName: parsed.typeName,
                    location: location
                )
            )
        }

        sourceSymbolLocationsLock.lock()
        sourceSymbolLocationsCache[cacheKey] = entries
        sourceSymbolLocationsLock.unlock()
        return entries
    }

    private func parseSourceReferenceSymbol(_ sourceReference: String) -> (typeName: String?, functionName: String)? {
        var symbol = sourceReference.trimmingCharacters(in: .whitespacesAndNewlines)
        if symbol.hasPrefix("@objc ") {
            symbol = String(symbol.dropFirst("@objc ".count))
        }
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

    func renderSourceReferenceSection(
        from testRuns: [TestRunDetail],
        testIdentifierURL: String?
    ) -> String {
        let references = failingSourceReferences(from: testRuns)
        guard !references.isEmpty else { return "" }

        let projectHint = projectNameHint(from: testIdentifierURL)
        var seen = Set<String>()
        let items = references.compactMap { reference -> String? in
            let dedupeKey = "\(reference.name)|\(reference.url ?? "")"
            guard !seen.contains(dedupeKey) else { return nil }
            seen.insert(dedupeKey)

            let escapedName = htmlEscape(reference.name)
            if let location = resolveSourceReferenceLocation(
                referenceName: reference.name,
                referenceURL: reference.url,
                projectHint: projectHint
            ) {
                let columnSuffix = location.column.map { ":\($0)" } ?? ""
                let label = "\(location.filePath):\(location.line)\(columnSuffix)"
                let escapedLabel = htmlEscape(label)
                return "<li><code>\(escapedName)</code><br><code>\(escapedLabel)</code></li>"
            }

            return "<li><code>\(escapedName)</code></li>"
        }.joined(separator: "")

        guard !items.isEmpty else { return "" }
        return """
            <h3>Failure Source References</h3>
            <ul>\(items)</ul>
            """
    }

    private func failingSourceReferences(
        from testRuns: [TestRunDetail]
    ) -> [(name: String, url: String?)] {
        var references = [(name: String, url: String?)]()
        var seen = Set<String>()

        func appendReference(name: String, url: String?) {
            let key = "\(name)|\(url ?? "")"
            guard !seen.contains(key) else { return }
            seen.insert(key)
            references.append((name: name, url: url))
        }

        func walkDetail(_ detail: TestRunChildDetail, inFailureContext: Bool) {
            let isFailureNode =
                inFailureContext
                || (detail.result?.lowercased() == "failed")
                || detail.name.localizedCaseInsensitiveContains("failed")

            if detail.nodeType == "Source Code Reference" && isFailureNode {
                appendReference(name: detail.name, url: detail.url)
            }

            for child in detail.children ?? [] {
                walkDetail(child, inFailureContext: isFailureNode)
            }
        }

        for run in testRuns {
            for child in run.children ?? [] {
                let childFailure = child.result?.lowercased() == "failed"
                for detail in child.children ?? [] {
                    walkDetail(detail, inFailureContext: childFailure)
                }
            }
        }

        return references
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
                relativePath: attachmentRelativePathForTestPage(fileName: attachment.exportedFileName),
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
