import Foundation

/// Compact duration used everywhere on the index page: "26ms", "12.3s", "3m 39s", "1h 2m".
/// Mirrored by `formatDuration` in index-page.js.
func formatCompactDuration(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0s" }
    let milliseconds = (seconds * 1000).rounded()
    if milliseconds < 1 { return "<1ms" }
    if milliseconds < 1000 { return "\(Int(milliseconds))ms" }
    let tenths = (seconds * 10).rounded()
    if tenths < 600 {
        let whole = Int(tenths) / 10
        let fraction = Int(tenths) % 10
        return fraction == 0 ? "\(whole)s" : "\(whole).\(fraction)s"
    }
    // Round the total first so the seconds part never reads "60s".
    let total = Int(seconds.rounded())
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    var parts = [String]()
    if hours > 0 { parts.append("\(hours)h") }
    if minutes > 0 || (hours > 0 && secs > 0) { parts.append("\(minutes)m") }
    if secs > 0 { parts.append("\(secs)s") }
    return parts.joined(separator: " ")
}

extension XCTestReport {
    struct PreviousRunChange: Equatable {
        let identifier: String
        let name: String
        let pagePath: String
    }

    struct PreviousRunDelta: Equatable {
        var newlyFailing = [PreviousRunChange]()
        var fixed = [PreviousRunChange]()
    }

    /// A test that passed overall after at least one earlier attempt did not.
    static func isFlakyTest(result: String?, testRuns: [TestRunDetail]?) -> Bool {
        guard isPassedTestResult(result), let testRuns, testRuns.count > 1,
            let firstResult = testRuns.first?.result
        else { return false }
        return !isPassedTestResult(firstResult)
    }

    static func previousRunDelta(
        current tests: [TestNode], previous: [String: TestResult],
        pagePath: (TestNode) -> String
    ) -> PreviousRunDelta {
        var delta = PreviousRunDelta()
        for test in tests {
            guard let identifier = test.nodeIdentifier, let before = previous[identifier] else {
                continue
            }
            let change = PreviousRunChange(
                identifier: identifier, name: test.name, pagePath: pagePath(test))
            if isFailureTestResult(test.result) && isPassedTestResult(before.status) {
                delta.newlyFailing.append(change)
            } else if isPassedTestResult(test.result) && isFailureTestResult(before.status) {
                delta.fixed.append(change)
            }
        }
        delta.newlyFailing.sort { $0.identifier < $1.identifier }
        delta.fixed.sort { $0.identifier < $1.identifier }
        return delta
    }

    func renderPreviousRunDeltaHTML(_ delta: PreviousRunDelta, dateHTML: String) -> String {
        func list(_ changes: [PreviousRunChange], title: String, className: String) -> String {
            guard !changes.isEmpty else { return "" }
            let items = changes.map { change in
                "<li><a href=\"\(htmlEscape(change.pagePath))\">\(htmlEscape(change.name))</a></li>"
            }.joined()
            // Long lists start closed so a broken run doesn't push the suites off screen.
            let open = changes.count <= 10 ? " open" : ""
            return
                "<details class=\"comparison-group \(className)\"\(open)><summary>\(title) (\(changes.count))</summary><ul>\(items)</ul></details>"
        }
        let intro = "Compared with previous run from \(dateHTML)"
        if delta.newlyFailing.isEmpty && delta.fixed.isEmpty {
            return "<div class=\"comparison-info\"><p>\(intro): no status changes.</p></div>"
        }
        return """
            <div class="comparison-info"><p>\(intro)</p>\
            \(list(delta.newlyFailing, title: "Newly failing", className: "comparison-newly-failing"))\
            \(list(delta.fixed, title: "Fixed", className: "comparison-fixed"))</div>
            """
    }
}
