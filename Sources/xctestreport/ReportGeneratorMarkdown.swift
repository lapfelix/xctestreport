import Foundation

// Agent/LLM-readable Markdown companion to the HTML report.
//
// Layout (all links relative so the folder works when hosted remotely):
//   <output>/report.md                 — index: counts, failed tests, per-suite listing
//   <output>/agent-tests/<id>.md       — one file per test: failure, source, steps, attachments
//
// From a test file, attachments resolve via ../attachments/... (same depth as tests/),
// so attachmentRelativePathForTestPage(fileName:) is reused as-is.

extension XCTestReport {
    var agentTestsDirectoryName: String { "agent-tests" }

    var agentTestsDirectoryPath: String {
        (outputDir as NSString).appendingPathComponent(agentTestsDirectoryName)
    }

    var agentReportFileName: String { "report.md" }

    struct AgentTestEntry {
        let name: String
        let suite: String
        let identifier: String?
        let result: String
        let duration: String?
        let failureSummary: String?
        let markdownRelativePath: String  // relative to output root
    }

    func agentMarkdownFileName(identifier: String?, name: String) -> String {
        let base = identifier ?? name
        var safe = ""
        for scalar in base.unicodeScalars {
            if (scalar.value >= 48 && scalar.value <= 57)       // 0-9
                || (scalar.value >= 65 && scalar.value <= 90)   // A-Z
                || (scalar.value >= 97 && scalar.value <= 122)  // a-z
                || scalar == "." || scalar == "_" || scalar == "-" {
                safe.unicodeScalars.append(scalar)
            } else {
                safe.append("_")
            }
        }
        if safe.isEmpty { safe = "test" }
        return "\(safe).md"
    }

    // MARK: - Per-test Markdown

    func renderTestMarkdown(
        test: TestNode,
        result: String,
        suite: String,
        testDetails: TestDetails?,
        testActivities: TestActivities?,
        attachmentsByTestIdentifier: [String: [AttachmentManifestItem]],
        primaryFailureMessage: String?,
        sourceLocationCandidateTexts: [String]
    ) -> (markdown: String, failureSummary: String?) {
        let isFailure = Self.isFailureTestResult(result)
        let attachments = test.nodeIdentifier.flatMap { attachmentsByTestIdentifier[$0] } ?? []

        var lines = [String]()
        lines.append("# \(test.name)")
        lines.append("")
        let htmlDetailDest = linkDestination("../\(testPagesDirectoryName)/\(htmlTestPageFileName(for: test))")
        lines.append("[← Report index](../\(agentReportFileName)) · [HTML detail](\(htmlDetailDest))")
        lines.append("")

        lines.append("- **Result:** \(result)")
        lines.append("- **Suite:** \(suite)")
        if let identifier = test.nodeIdentifier {
            lines.append("- **Identifier:** `\(identifier)`")
        }
        if let duration = test.duration {
            lines.append("- **Duration:** \(duration)")
        }
        if let device = (testDetails?.devices.first) {
            let os = device.osVersion.isEmpty ? "" : " (\(device.platform ?? "")\(device.platform == nil ? "" : " ")\(device.osVersion))"
            lines.append("- **Device:** \(device.deviceName)\(os)")
        }
        lines.append("")

        var failureSummary: String?

        if isFailure {
            if let message = primaryFailureMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
                !message.isEmpty {
                failureSummary = firstLine(of: message)
                lines.append("## Failure")
                lines.append("")
                lines.append(fencedCodeBlock(message))
                lines.append("")
            }

            let locations = sourceLocationCandidateTexts
                .flatMap { extractSourceLocations(from: $0) }
            let dedupedLocations = dedupeSourceLocations(locations)
            if !dedupedLocations.isEmpty {
                lines.append("## Source locations")
                lines.append("")
                for location in dedupedLocations.prefix(20) {
                    let column = location.column.map { ":\($0)" } ?? ""
                    lines.append("- `\(location.filePath):\(location.line)\(column)`")
                }
                lines.append("")
            }

            if let stack = extractStackTracePreview(
                for: test.nodeIdentifier,
                attachmentsByTestIdentifier: attachmentsByTestIdentifier) {
                lines.append("## Stack trace (preview)")
                lines.append("")
                lines.append("[\(markdownInline(stack.attachmentName))](\(linkDestination(stack.relativePath))) — \(stack.frameCount) frames")
                lines.append("")
                lines.append(fencedCodeBlock(stack.preview))
                lines.append("")
            }

            let previousRuns = test.nodeIdentifier.map { getPreviousRuns(for: $0) } ?? []
            if !previousRuns.isEmpty {
                let history = previousRuns.prefix(10)
                    .map { $0.result == "Passed" ? "✅" : "❌" }
                    .joined()
                lines.append("## Previous runs")
                lines.append("")
                lines.append(history)
                lines.append("")
            }
        }

        let stepsMarkdown = renderStepsMarkdown(
            activities: testActivities,
            attachments: attachments)
        if !stepsMarkdown.isEmpty {
            lines.append("## Steps")
            lines.append("")
            lines.append(contentsOf: stepsMarkdown)
            lines.append("")
        }

        if !attachments.isEmpty {
            let base = testActivities?.testRuns
                .compactMap { minStartTime(in: $0.activities) }
                .min()
            lines.append("## Attachments")
            lines.append("")
            for attachment in attachments {
                let relativePath = attachmentRelativePathForTestPage(
                    fileName: attachment.exportedFileName)
                let name = attachment.suggestedHumanReadableName ?? attachment.exportedFileName
                let offset = timeOffsetLabel(attachment.timestamp, base: base)
                var suffix = ""
                if attachment.isAssociatedWithFailure == true { suffix += " ⚠️ failure" }
                lines.append("- \(offset)[\(markdownInline(name))](\(linkDestination(relativePath)))\(suffix)")
            }
            lines.append("")
        }

        return (lines.joined(separator: "\n"), failureSummary)
    }

    private func htmlTestPageFileName(for test: TestNode) -> String {
        "test_\(test.nodeIdentifier ?? test.name).html"
            .replacingOccurrences(of: "/", with: "_")
    }

    // MARK: - Steps (activity tree)

    private func renderStepsMarkdown(
        activities: TestActivities?,
        attachments: [AttachmentManifestItem]
    ) -> [String] {
        guard let runs = activities?.testRuns, !runs.isEmpty else { return [] }
        let payloadToFile = Dictionary(
            attachments.compactMap { item -> (String, String)? in
                guard let payloadRefId = item.payloadRefId else { return nil }
                return (payloadRefId, item.exportedFileName)
            },
            uniquingKeysWith: { first, _ in first })

        let nonEmptyRuns = runs.filter { !$0.activities.isEmpty }
        guard !nonEmptyRuns.isEmpty else { return [] }

        var lines = [String]()
        let labelRuns = nonEmptyRuns.count > 1
        for (index, run) in nonEmptyRuns.enumerated() {
            if labelRuns {
                if index > 0 { lines.append("") }
                lines.append("**Run \(index + 1)**")
                lines.append("")
            }
            let base = minStartTime(in: run.activities)
            for activity in run.activities {
                appendActivityLines(
                    activity, base: base, depth: 0,
                    payloadToFile: payloadToFile, into: &lines)
            }
        }
        return lines
    }

    private func appendActivityLines(
        _ activity: TestActivity,
        base: Double?,
        depth: Int,
        payloadToFile: [String: String],
        into lines: inout [String]
    ) {
        let indent = String(repeating: "  ", count: depth)
        let marker = (activity.isAssociatedWithFailure == true) ? "❌ " : ""
        let offset = timeOffsetLabel(activity.startTime, base: base)
        let title = markdownInline(activity.title)
        lines.append("\(indent)- \(marker)\(offset)\(title)")

        let childIndent = String(repeating: "  ", count: depth + 1)
        for attachment in activity.attachments ?? [] {
            guard let payloadId = attachment.payloadId,
                let fileName = payloadToFile[payloadId] else { continue }
            let relativePath = attachmentRelativePathForTestPage(fileName: fileName)
            lines.append("\(childIndent)- 📎 [\(markdownInline(attachment.name))](\(linkDestination(relativePath)))")
        }

        for child in activity.childActivities ?? [] {
            appendActivityLines(
                child, base: base, depth: depth + 1,
                payloadToFile: payloadToFile, into: &lines)
        }
    }

    private func minStartTime(in activities: [TestActivity]) -> Double? {
        var best: Double?
        func walk(_ list: [TestActivity]) {
            for activity in list {
                if let start = activity.startTime, start.isFinite {
                    if best == nil || start < best! { best = start }
                }
                walk(activity.childActivities ?? [])
            }
        }
        walk(activities)
        return best
    }

    private func timeOffsetLabel(_ startTime: Double?, base: Double?) -> String {
        guard let startTime, let base, startTime.isFinite, base.isFinite else { return "" }
        let offset = max(0, startTime - base)
        if offset >= 60 {
            let minutes = Int(offset) / 60
            let seconds = offset - Double(minutes * 60)
            return String(format: "[%d:%06.3f] ", minutes, seconds)
        }
        return String(format: "[%.3fs] ", offset)
    }

    // MARK: - Index

    func writeAgentReport(
        summaryTitle: String,
        counts: TestCounts,
        result: String,
        entries: [AgentTestEntry],
        buildErrorCount: Int?,
        buildWarningCount: Int?,
        previousResultsDate: Date?
    ) {
        var lines = [String]()
        lines.append("# \(summaryTitle) — Test Report")
        lines.append("")
        lines.append("> Agent-readable companion to `index.html`. Every test links to a Markdown file with its failure, source locations, steps, and attachments. All paths are relative, so this folder works when hosted remotely.")
        lines.append("")

        lines.append("- **Result:** \(result)")
        lines.append("- **Total:** \(counts.totalTests) · **Passed:** \(counts.passedTests) · **Failed:** \(counts.failedTests) · **Skipped:** \(counts.skippedTests)")
        lines.append("- **Pass rate:** \(String(format: "%.1f", counts.percentagePassed))%")
        if let errors = buildErrorCount, let warnings = buildWarningCount {
            lines.append("- **Build:** 🛑 \(errors) errors · ⚠️ \(warnings) warnings")
        }
        if let date = previousResultsDate {
            let formatter = ISO8601DateFormatter()
            lines.append("- **Compared with previous run from:** \(formatter.string(from: date))")
        }
        lines.append("")

        let failed = entries
            .filter { Self.isFailureTestResult($0.result) }
            .sorted { $0.suite == $1.suite ? $0.name < $1.name : $0.suite < $1.suite }
        let skipped = entries
            .filter { Self.isSkippedTestResult($0.result) }
            .sorted { $0.suite == $1.suite ? $0.name < $1.name : $0.suite < $1.suite }

        if failed.isEmpty {
            lines.append("## Failed tests")
            lines.append("")
            lines.append("None. ✅")
            lines.append("")
        } else {
            lines.append("## Failed tests (\(failed.count))")
            lines.append("")
            lines.append("| Test | Suite | Reason |")
            lines.append("| --- | --- | --- |")
            for entry in failed {
                let reason = entry.failureSummary.map { markdownTableCell($0) } ?? ""
                lines.append("| [\(markdownTableCell(entry.name))](\(entry.markdownRelativePath)) | \(markdownTableCell(entry.suite)) | \(reason) |")
            }
            lines.append("")
        }

        if !skipped.isEmpty {
            lines.append("## Skipped tests (\(skipped.count))")
            lines.append("")
            for entry in skipped {
                lines.append("- [\(markdownInline(entry.name))](\(entry.markdownRelativePath)) — \(markdownInline(entry.suite))")
            }
            lines.append("")
        }

        lines.append("## All suites")
        lines.append("")
        let grouped = Dictionary(grouping: entries) { $0.suite }
        for suite in grouped.keys.sorted() {
            let suiteEntries = (grouped[suite] ?? [])
                .sorted { $0.name < $1.name }
            let passed = suiteEntries.filter { Self.isPassedTestResult($0.result) }.count
            let total = suiteEntries.filter { !Self.isSkippedTestResult($0.result) }.count
            lines.append("### \(suite) — \(passed)/\(total) passed")
            lines.append("")
            for entry in suiteEntries {
                let icon = statusIcon(entry.result)
                let duration = entry.duration.map { " · \($0)" } ?? ""
                lines.append("- \(icon) [\(markdownInline(entry.name))](\(entry.markdownRelativePath))\(duration)")
            }
            lines.append("")
        }

        let markdown = lines.joined(separator: "\n")
        let path = (outputDir as NSString).appendingPathComponent(agentReportFileName)
        do {
            try markdown.write(toFile: path, atomically: true, encoding: .utf8)
            print("Agent report written to \(path)")
        } catch {
            print("Error writing agent report: \(error)")
        }
    }

    private func statusIcon(_ result: String) -> String {
        if Self.isPassedTestResult(result) { return "✅" }
        if Self.isSkippedTestResult(result) { return "⏭️" }
        return "❌"
    }

    // MARK: - Markdown helpers

    private func firstLine(of text: String) -> String {
        let line = text
            .components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            ?? text
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 200 {
            return String(trimmed.prefix(197)) + "…"
        }
        return trimmed
    }

    private func dedupeSourceLocations(_ locations: [SourceLocation]) -> [SourceLocation] {
        var seen = Set<String>()
        var result = [SourceLocation]()
        for location in locations {
            let key = "\(location.filePath)|\(location.line)|\(location.column ?? -1)"
            if seen.insert(key).inserted { result.append(location) }
        }
        return result
    }

    private func fencedCodeBlock(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Pick a fence long enough to survive any backtick runs inside the body.
        var fence = "```"
        while trimmed.contains(fence) { fence += "`" }
        return "\(fence)\n\(trimmed)\n\(fence)"
    }

    private func linkDestination(_ path: String) -> String {
        // CommonMark angle-bracket form survives parens/spaces in the path.
        if path.contains("(") || path.contains(")") || path.contains(" ") {
            return "<\(path)>"
        }
        return path
    }

    private func markdownInline(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
            .trimmingCharacters(in: .whitespaces)
    }

    private func markdownTableCell(_ text: String) -> String {
        markdownInline(text)
            .replacingOccurrences(of: "|", with: "\\|")
    }
}
