import Foundation

private let templatePlaceholderRegex = try! NSRegularExpression(
    pattern: #"\{\{([a-zA-Z0-9_]+)\}\}"#
)
private let htmlInterTagWhitespaceRegex = try! NSRegularExpression(
    pattern: #">\s+<"#
)
private let htmlMinifyProtectedBlockRegex = try! NSRegularExpression(
    pattern: #"(?is)<(script|style|pre|textarea)\b[^>]*>.*?</\1>"#
)

extension XCTestReport {
    struct WebTemplates {
        let indexTemplate: String
        let testDetailTemplate: String
        let timelineSectionTemplate: String
    }

    func loadWebTemplates() throws -> WebTemplates {
        return WebTemplates(
            indexTemplate: try loadWebTextResource(
                named: "index", withExtension: "html", subdirectory: "Web/templates"),
            testDetailTemplate: try loadWebTextResource(
                named: "test-detail", withExtension: "html", subdirectory: "Web/templates"),
            timelineSectionTemplate: try loadWebTextResource(
                named: "timeline-section", withExtension: "html", subdirectory: "Web/templates")
        )
    }

    func copyWebAssets(to directory: String) throws {
        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true)
        try copyWebAsset(
            named: "report", withExtension: "css", subdirectory: "Web", to: directory)
        try copyWebAsset(
            named: "index-page", withExtension: "js", subdirectory: "Web", to: directory)
        try copyWebAsset(
            named: "plist-preview", withExtension: "js", subdirectory: "Web", to: directory)
        try copyWebAsset(
            named: "timeline-view", withExtension: "js", subdirectory: "Web", to: directory)
    }

    func renderTemplate(_ template: String, values: [String: String], templateName: String) throws -> String {
        let requiredKeys = Set(templatePlaceholders(in: template))
        let missingKeys = requiredKeys.subtracting(values.keys)
        if !missingKeys.isEmpty {
            let sorted = missingKeys.sorted().joined(separator: ", ")
            throw RuntimeError(message: "Template \(templateName) is missing placeholders: \(sorted)")
        }

        var rendered = template
        for key in requiredKeys.sorted() {
            rendered = rendered.replacingOccurrences(of: "{{\(key)}}", with: values[key] ?? "")
        }
        return rendered
    }

    func jsonForScriptTag(_ json: String) -> String {
        return json
            .replacingOccurrences(of: "</script", with: "<\\/script")
            .replacingOccurrences(of: "<!--", with: "<\\!--")
    }

    func minifyHTMLInterTagWhitespace(_ html: String) -> String {
        let fullRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let protectedMatches = htmlMinifyProtectedBlockRegex.matches(
            in: html, options: [], range: fullRange)
        guard !protectedMatches.isEmpty else {
            return minifyInterTagWhitespaceSegment(html)
        }

        var output = String()
        var currentIndex = html.startIndex

        for match in protectedMatches {
            guard let protectedRange = Range(match.range, in: html) else { continue }
            let prefixSegment = String(html[currentIndex..<protectedRange.lowerBound])
            output += minifyInterTagWhitespaceSegment(prefixSegment)
            output += String(html[protectedRange])
            currentIndex = protectedRange.upperBound
        }

        if currentIndex < html.endIndex {
            output += minifyInterTagWhitespaceSegment(String(html[currentIndex...]))
        }
        return output
    }

    private func minifyInterTagWhitespaceSegment(_ segment: String) -> String {
        let segmentRange = NSRange(segment.startIndex..<segment.endIndex, in: segment)
        return htmlInterTagWhitespaceRegex.stringByReplacingMatches(
            in: segment,
            options: [],
            range: segmentRange,
            withTemplate: "><"
        )
    }

    private func templatePlaceholders(in template: String) -> [String] {
        let range = NSRange(template.startIndex..<template.endIndex, in: template)
        let matches = templatePlaceholderRegex.matches(in: template, options: [], range: range)
        return matches.compactMap { match in
            guard let tokenRange = Range(match.range(at: 1), in: template) else { return nil }
            return String(template[tokenRange])
        }
    }

    private func loadWebTextResource(
        named resourceName: String,
        withExtension fileExtension: String,
        subdirectory: String
    ) throws -> String {
        let url = try webResourceURL(
            named: resourceName,
            withExtension: fileExtension,
            subdirectory: subdirectory)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func copyWebAsset(
        named resourceName: String,
        withExtension fileExtension: String,
        subdirectory: String,
        to destinationDirectory: String
    ) throws {
        let sourceURL = try webResourceURL(
            named: resourceName,
            withExtension: fileExtension,
            subdirectory: subdirectory)
        let destinationURL = URL(fileURLWithPath: destinationDirectory)
            .appendingPathComponent("\(resourceName).\(fileExtension)")

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    private func webResourceURL(
        named resourceName: String,
        withExtension fileExtension: String,
        subdirectory: String
    ) throws -> URL {
        if let nestedURL = Bundle.module.url(
            forResource: resourceName,
            withExtension: fileExtension,
            subdirectory: subdirectory)
        {
            return nestedURL
        }

        if let flatURL = Bundle.module.url(forResource: resourceName, withExtension: fileExtension)
        {
            return flatURL
        }

        if let baseURL = Bundle.module.resourceURL {
            let candidate = baseURL
                .appendingPathComponent(subdirectory)
                .appendingPathComponent("\(resourceName).\(fileExtension)")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        throw RuntimeError(
            message:
                "Missing required web resource: \(subdirectory)/\(resourceName).\(fileExtension)")
    }
}
