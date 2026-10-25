import Foundation

extension XCTestReport {
    // MARK: - Findings

    /// Plain-language observations shared by the HTML section and the Markdown.
    struct PerformanceFinding {
        enum Severity: String { case regression, noise, outlier, change }

        let severity: Severity
        let text: String
    }

    /// Regressions get a sentence each; noise, outliers and run-to-run changes are grouped so
    /// a pattern such as "iteration 5 is low in every metric" reads as one line.
    static func performanceFindings(for analysis: PerformanceTestAnalysis) -> [PerformanceFinding] {
        var regressions = [PerformanceFinding]()
        var grouped = [PerformanceFinding]()
        let labelRuns = analysis.runs.count > 1
        for run in analysis.runs {
            let runPrefix = labelRuns ? run.run.label.map { "\($0): " } ?? "" : ""
            var noisy = [String]()
            var worse = [String]()
            var better = [String]()
            var outliersByIteration = [Int: [String]]()
            for item in run.metrics {
                let metric = item.metric
                let statistics = item.statistics
                let format = PerformanceValueFormatter(
                    unit: metric.unitOfMeasurement,
                    values: metric.measurements + [metric.baseline, item.history.last].compactMap { $0 })
                let name = metric.displayName

                if item.exceedsRegressionLimit, let baseline = metric.baseline {
                    let change = item.baselineChange.map { " (\(formatPercentChange($0)))" } ?? ""
                    let limit = metric.maxPercentRegression.map { "; the limit is \(formatPercent($0))" } ?? ""
                    let baselineName = (metric.baselineName ?? "").isEmpty ? "" : " “\(metric.baselineName!)”"
                    regressions.append(PerformanceFinding(
                        severity: .regression,
                        text: "\(runPrefix)\(name) regressed from baseline\(baselineName): \(format.format(baseline)) → \(format.format(statistics.mean))\(change)\(limit)."))
                }
                for index in item.iterationsOverLimit {
                    let change = PerformanceMetricAnalysis.percentChange(from: statistics.mean, to: metric.measurements[index]) ?? 0
                    let limit = 4 * (metric.maxPercentRelativeStandardDeviation ?? 0)
                    regressions.append(PerformanceFinding(
                        severity: .regression,
                        text: "\(runPrefix)Iteration \(index + 1) of \(name) is \(formatPercent(abs(change))) worse than the average (\(format.format(metric.measurements[index])) vs \(format.format(statistics.mean))); XCTest allows \(formatPercent(limit))."))
                }
                if item.exceedsDeviationLimit, let deviation = statistics.relativeStandardDeviation {
                    noisy.append("\(name) \(formatPercent(deviation))")
                }
                for index in statistics.outlierIndices {
                    let value = metric.measurements[index]
                    if statistics.relativeStandardDeviation != nil,
                        let change = PerformanceMetricAnalysis.percentChange(from: statistics.median, to: value)
                    {
                        outliersByIteration[index, default: []].append("\(name) \(formatPercentChange(change))")
                    } else {
                        outliersByIteration[index, default: []].append("\(name) \(format.format(value)) vs \(format.format(statistics.median))")
                    }
                }
                // Run-to-run moves within the iteration noise are not worth reporting.
                if let change = item.previousChange, item.previousDirection != .neutral,
                    abs(change) >= max(5, metric.maxPercentRegression ?? 10),
                    abs(change) > 2 * (statistics.relativeStandardDeviation ?? 0)
                {
                    let entry = "\(name) \(formatPercentChange(change))"
                    if item.previousDirection == .worse { worse.append(entry) } else { better.append(entry) }
                }
            }
            if !worse.isEmpty {
                grouped.append(PerformanceFinding(
                    severity: .change, text: "\(runPrefix)Worse than the previous run: \(worse.joined(separator: ", "))."))
            }
            if !better.isEmpty {
                grouped.append(PerformanceFinding(
                    severity: .change, text: "\(runPrefix)Better than the previous run: \(better.joined(separator: ", "))."))
            }
            if !noisy.isEmpty {
                let limits = Set(run.metrics.filter(\.exceedsDeviationLimit).compactMap(\.metric.maxPercentRelativeStandardDeviation))
                let limit = limits.count == 1 ? " \(formatPercent(limits.first!))" : ""
                grouped.append(PerformanceFinding(
                    severity: .noise,
                    text: "\(runPrefix)Relative standard deviation over the\(limit) limit: \(noisy.joined(separator: ", "))."))
            }
            for (index, metrics) in outliersByIteration.sorted(by: { $0.key < $1.key }) {
                let count = metrics.count == 1 ? "" : " in \(metrics.count) metrics"
                grouped.append(PerformanceFinding(
                    severity: .outlier,
                    text: "\(runPrefix)Iteration \(index + 1) stands out\(count) (vs the median): \(metrics.joined(separator: ", "))."))
            }
        }
        return regressions + grouped
    }

    // MARK: - Test page

    func renderPerformanceSection(_ analysis: PerformanceTestAnalysis) -> String {
        guard !analysis.runs.isEmpty else { return "" }
        let allMetrics = analysis.allMetrics
        let iterationCounts = Set(allMetrics.map(\.statistics.count)).sorted()
        var meta = ["\(allMetrics.count) metric\(allMetrics.count == 1 ? "" : "s")"]
        if let low = iterationCounts.first, let high = iterationCounts.last {
            let range = low == high ? "\(low)" : "\(low)–\(high)"
            meta.append("\(range) iteration\(high == 1 ? "" : "s")")
        }
        if analysis.runs.count == 1, let label = analysis.runs[0].run.label {
            meta.append(label)
        } else if analysis.runs.count > 1 {
            meta.append("\(analysis.runs.count) runs")
        }
        if !analysis.hasBaselines { meta.append("no baseline") }

        var badges = [String]()
        if analysis.regressionCount > 0 {
            badges.append(performanceBadge("\(analysis.regressionCount) regressed", kind: "regression"))
        }
        if analysis.noisyCount > 0 {
            badges.append(performanceBadge("\(analysis.noisyCount) noisy", kind: "noise"))
        }
        if analysis.outlierMetricCount > 0 {
            let count = analysis.outlierMetricCount
            badges.append(performanceBadge("outliers in \(count) metric\(count == 1 ? "" : "s")", kind: "outlier"))
        }

        let runsHTML = analysis.runs.map { run in
            renderPerformanceRun(run, showsTitle: analysis.runs.count > 1, previousDate: analysis.previousRunDate)
        }.joined()

        let findings = Self.performanceFindings(for: analysis)
        var findingsHTML = ""
        if !findings.isEmpty {
            let items = findings.map {
                "<li class=\"perf-finding perf-finding-\($0.severity.rawValue)\">\(htmlEscape($0.text))</li>"
            }.joined()
            findingsHTML = "<ul class=\"perf-findings\">\(items)</ul>"
        }

        return """
            <section class="perf-section" id="performance" aria-labelledby="performance-title">\
            <details class="perf-panel" open>\
            <summary class="perf-summary"><h2 id="performance-title" class="perf-title">Performance</h2>\
            <span class="perf-meta">\(htmlEscape(meta.joined(separator: " · ")))</span>\(badges.joined())</summary>\
            <div class="perf-body">\(findingsHTML)\(runsHTML)</div>\
            </details></section>
            """
    }

    private func performanceBadge(_ text: String, kind: String) -> String {
        "<span class=\"perf-badge perf-badge-\(kind)\">\(htmlEscape(text))</span>"
    }

    private func renderPerformanceRun(
        _ run: PerformanceRunAnalysis, showsTitle: Bool, previousDate: Date?
    ) -> String {
        let showsBaseline = run.metrics.contains { $0.metric.baseline != nil }
        let showsPrevious = run.metrics.contains { !$0.history.isEmpty }
        var headers = ["Metric", "Average", "Iterations", "Range", "Std dev"]
        if showsBaseline { headers.append("Baseline") }
        if showsPrevious { headers.append("Previous runs") }
        let headHTML = headers.map { "<th scope=\"col\">\($0)</th>" }.joined()

        let rows = run.metrics.map { item -> String in
            renderPerformanceRow(item, showsBaseline: showsBaseline, showsPrevious: showsPrevious, previousDate: previousDate)
        }.joined()

        let title = showsTitle
            ? "<h3 class=\"perf-run-title\">\(htmlEscape(run.run.label ?? "Run"))</h3>" : ""
        return """
            <div class="perf-run">\(title)\
            <div class="perf-table-wrap"><table class="data-table perf-table">\
            <thead><tr>\(headHTML)</tr></thead><tbody>\(rows)</tbody></table></div>\
            \(renderIterationValues(run))</div>
            """
    }

    private func renderPerformanceRow(
        _ item: PerformanceMetricAnalysis, showsBaseline: Bool, showsPrevious: Bool, previousDate: Date?
    ) -> String {
        let metric = item.metric
        let statistics = item.statistics
        let format = PerformanceValueFormatter(
            unit: metric.unitOfMeasurement,
            values: metric.measurements + [metric.baseline, item.history.last].compactMap { $0 })
        let polarity: String
        switch metric.prefersSmaller {
        case true?: polarity = "lower is better"
        case false?: polarity = "higher is better"
        case nil: polarity = metric.polarity ?? ""
        }

        var rowClasses = [String]()
        if item.exceedsRegressionLimit || !item.iterationsOverLimit.isEmpty { rowClasses.append("perf-row-regressed") }
        if item.exceedsDeviationLimit { rowClasses.append("perf-row-noisy") }
        let rowClass = rowClasses.isEmpty ? "" : " class=\"\(rowClasses.joined(separator: " "))\""

        let metricCell = """
            <th scope="row" data-label="Metric" class="perf-metric"><span class="perf-metric-name">\(htmlEscape(metric.displayName))</span>\
            <span class="perf-metric-sub" title="\(htmlEscape(metric.identifier))">\(htmlEscape([polarity, metric.unitOfMeasurement].filter { !$0.isEmpty }.joined(separator: " · ")))</span></th>
            """
        let averageCell = """
            <td data-label="Average" class="perf-average" title="\(htmlEscape(format.raw(statistics.mean)))">\
            <span class="perf-value">\(htmlEscape(format.format(statistics.mean)))</span>\
            <span class="perf-sub">median \(htmlEscape(format.format(statistics.median)))</span></td>
            """
        let chart = iterationChartSVG(item, format: format)
        let iterationsCell = "<td data-label=\"Iterations\" class=\"perf-iterations\">\(chart)</td>"
        let rangeCell = """
            <td data-label="Range" class="perf-range">\(htmlEscape(format.format(statistics.min)))\
            <span class="perf-range-dash"> – </span>\(htmlEscape(format.format(statistics.max)))</td>
            """

        // Its own scale: a 1.22 s metric can vary by a fraction of a millisecond.
        let deviationFormat = PerformanceValueFormatter(unit: metric.unitOfMeasurement, values: [statistics.standardDeviation])
        var deviationText = htmlEscape(deviationFormat.format(statistics.standardDeviation))
        if let relative = statistics.relativeStandardDeviation {
            let limit = metric.maxPercentRelativeStandardDeviation.map { " (limit \(Self.formatPercent($0)))" } ?? ""
            let deviationClass = item.exceedsDeviationLimit ? " perf-over-limit" : ""
            deviationText += "<span class=\"perf-sub\(deviationClass)\" title=\"Relative standard deviation\(htmlEscape(limit))\">RSD \(Self.formatPercent(relative))</span>"
        }
        var cells = [metricCell, averageCell, iterationsCell, rangeCell, "<td data-label=\"Std dev\" class=\"perf-deviation\">\(deviationText)</td>"]

        if showsBaseline {
            if let baseline = metric.baseline {
                let change = item.baselineChange.map(Self.formatPercentChange) ?? ""
                let directionClass = Self.directionClass(item.baselineDirection)
                var limits = [String]()
                if let limit = metric.maxPercentRegression { limits.append("max regression \(Self.formatPercent(limit))") }
                if let absolute = metric.maxRegression, absolute > 0 { limits.append("max \(format.format(absolute)) worse") }
                let name = (metric.baselineName ?? "").isEmpty ? "" : "<span class=\"perf-sub\">\(htmlEscape(metric.baselineName!))</span>"
                let flag = item.exceedsRegressionLimit ? performanceBadge("regressed", kind: "regression") : ""
                cells.append("""
                    <td data-label="Baseline" class="perf-baseline" title="\(htmlEscape(limits.joined(separator: ", ")))">\
                    <span class="perf-change \(directionClass)">\(htmlEscape(change))</span> \
                    <span class="perf-baseline-value">vs \(htmlEscape(format.format(baseline)))</span>\(flag)\(name)</td>
                    """)
            } else {
                cells.append("<td data-label=\"Baseline\" class=\"perf-baseline perf-empty\">None</td>")
            }
        }

        if showsPrevious {
            if let previous = item.history.last {
                let change = item.previousChange.map(Self.formatPercentChange) ?? ""
                let directionClass = Self.directionClass(item.previousDirection)
                let trend = trendSparklineSVG(item.history + [statistics.mean], format: format)
                let runs = item.history.count == 1 ? "previous run" : "last \(item.history.count) runs"
                cells.append("""
                    <td data-label="Previous runs" class="perf-previous">\(trend)\
                    <span class="perf-change \(directionClass)">\(htmlEscape(change))</span> \
                    <span class="perf-baseline-value" title="Trend over the \(runs)">vs \(htmlEscape(format.format(previous)))</span></td>
                    """)
            } else {
                cells.append("<td data-label=\"Previous runs\" class=\"perf-previous perf-empty\">New</td>")
            }
        }
        return "<tr\(rowClass)>\(cells.joined())</tr>"
    }

    private func renderIterationValues(_ run: PerformanceRunAnalysis) -> String {
        let iterations = run.metrics.map(\.statistics.count).max() ?? 0
        guard iterations > 0 else { return "" }
        let head = (1...iterations).map { "<th scope=\"col\">#\($0)</th>" }.joined()
        let rows = run.metrics.map { item -> String in
            let format = PerformanceValueFormatter(unit: item.metric.unitOfMeasurement, values: item.metric.measurements)
            let outliers = Set(item.statistics.outlierIndices + item.iterationsOverLimit)
            let cells = (0..<iterations).map { index -> String in
                guard index < item.metric.measurements.count else { return "<td></td>" }
                let value = item.metric.measurements[index]
                let outlier = outliers.contains(index) ? " class=\"perf-outlier\"" : ""
                return "<td\(outlier) title=\"\(htmlEscape(format.raw(value)))\">\(htmlEscape(format.format(value)))</td>"
            }.joined()
            return "<tr><th scope=\"row\">\(htmlEscape(item.metric.displayName))</th>\(cells)</tr>"
        }.joined()
        return """
            <details class="perf-raw"><summary>Iteration values</summary>\
            <div class="perf-table-wrap"><table class="perf-raw-table"><thead><tr><th scope="col">Metric</th>\(head)</tr></thead>\
            <tbody>\(rows)</tbody></table></div></details>
            """
    }

    private static func directionClass(_ direction: PerformanceMetricAnalysis.Direction) -> String {
        switch direction {
        case .better: return "perf-better"
        case .worse: return "perf-worse"
        case .neutral: return "perf-neutral"
        }
    }

    // MARK: - Charts

    /// Iterations left to right; the dashed line is the average, the accent line the baseline.
    func iterationChartSVG(_ item: PerformanceMetricAnalysis, format: PerformanceValueFormatter) -> String {
        let values = item.metric.measurements
        guard !values.isEmpty else { return "" }
        let width = 168.0, height = 40.0, padX = 6.0, padY = 6.0
        var low = item.statistics.min, high = item.statistics.max
        if let baseline = item.metric.baseline { low = min(low, baseline); high = max(high, baseline) }
        // At least ±5% of the average, so sub-percent jitter draws as the flat line it is.
        let minimumSpan = abs(item.statistics.mean) * 0.1
        if high - low < minimumSpan {
            let middle = (high + low) / 2
            (low, high) = (middle - minimumSpan / 2, middle + minimumSpan / 2)
        }
        let span = high - low
        func y(_ value: Double) -> Double {
            guard span > 0 else { return height / 2 }
            return padY + (1 - (value - low) / span) * (height - 2 * padY)
        }
        func x(_ index: Int) -> Double {
            values.count == 1 ? width / 2 : padX + Double(index) * (width - 2 * padX) / Double(values.count - 1)
        }
        func coordinate(_ value: Double) -> String { String(format: "%.1f", value) }

        var parts = [String]()
        let meanY = coordinate(y(item.statistics.mean))
        parts.append("<line class=\"perf-chart-mean\" x1=\"0\" x2=\"\(Int(width))\" y1=\"\(meanY)\" y2=\"\(meanY)\"><title>Average \(htmlEscape(format.format(item.statistics.mean)))</title></line>")
        if let baseline = item.metric.baseline {
            let baselineY = coordinate(y(baseline))
            parts.append("<line class=\"perf-chart-baseline\" x1=\"0\" x2=\"\(Int(width))\" y1=\"\(baselineY)\" y2=\"\(baselineY)\"><title>Baseline \(htmlEscape(format.format(baseline)))</title></line>")
        }
        if values.count > 1 {
            let points = values.indices.map { "\(coordinate(x($0))),\(coordinate(y(values[$0])))" }.joined(separator: " ")
            parts.append("<polyline class=\"perf-chart-line\" points=\"\(points)\"/>")
        }
        let outliers = Set(item.statistics.outlierIndices + item.iterationsOverLimit)
        for (index, value) in values.enumerated() {
            let outlier = outliers.contains(index)
            let label = "Iteration \(index + 1): \(format.format(value))\(outlier ? " (outlier)" : "")"
            parts.append("<circle class=\"perf-chart-dot\(outlier ? " perf-chart-outlier" : "")\" cx=\"\(coordinate(x(index)))\" cy=\"\(coordinate(y(value)))\" r=\"\(outlier ? "4" : "3")\"><title>\(htmlEscape(label))</title></circle>")
        }
        let summary = values.map(format.format).joined(separator: ", ")
        return """
            <svg class="perf-chart" viewBox="0 0 \(Int(width)) \(Int(height))" width="\(Int(width))" height="\(Int(height))" role="img" \
            aria-label="\(htmlEscape("Iterations: \(summary)"))">\(parts.joined())</svg>
            """
    }

    /// Averages of earlier runs, oldest first, ending with this run.
    func trendSparklineSVG(_ averages: [Double], format: PerformanceValueFormatter) -> String {
        guard averages.count > 1 else { return "" }
        let width = 64.0, height = 20.0, pad = 3.0
        let low = averages.min()!, high = averages.max()!
        func x(_ index: Int) -> Double { pad + Double(index) * (width - 2 * pad) / Double(averages.count - 1) }
        func y(_ value: Double) -> Double {
            high == low ? height / 2 : pad + (1 - (value - low) / (high - low)) * (height - 2 * pad)
        }
        let points = averages.indices.map { String(format: "%.1f,%.1f", x($0), y(averages[$0])) }.joined(separator: " ")
        let last = averages.count - 1
        let label = averages.map(format.format).joined(separator: " → ")
        return """
            <svg class="perf-trend" viewBox="0 0 \(Int(width)) \(Int(height))" width="\(Int(width))" height="\(Int(height))" role="img" \
            aria-label="\(htmlEscape("Averages by run: \(label)"))"><title>\(htmlEscape(label))</title>\
            <polyline class="perf-chart-line" points="\(points)"/>\
            <circle class="perf-chart-dot" cx="\(String(format: "%.1f", x(last)))" cy="\(String(format: "%.1f", y(averages[last])))" r="2.5"/></svg>
            """
    }

    // MARK: - Index

    struct PerformanceOverviewEntry {
        let test: TestNode
        let pagePath: String
        let analysis: PerformanceTestAnalysis
    }

    /// One table per set of metrics, with a row per test and run, so every metric stays visible:
    /// a suite measuring the same metrics reads as one matrix, a mixed one as several small ones.
    func renderPerformanceOverview(_ entries: [PerformanceOverviewEntry]) -> String {
        let entries = entries.filter { !$0.analysis.runs.isEmpty }
            .sorted { ($0.test.nodeIdentifier ?? $0.test.name) < ($1.test.nodeIdentifier ?? $1.test.name) }
        guard !entries.isEmpty else { return "" }

        var groups = [(columns: [String], rows: [String])]()
        for entry in entries {
            let multipleRuns = entry.analysis.runs.count > 1
            let suite = entry.test.nodeIdentifier?.split(separator: "/").first.map(String.init)
            let suiteLabel = suite.map { "<span class=\"perf-sub\">\(htmlEscape($0))</span>" } ?? ""
            for run in entry.analysis.runs {
                var columns = [String]()
                for name in run.metrics.map(\.metric.displayName) where !columns.contains(name) { columns.append(name) }
                let runLabel = multipleRuns ? run.run.label.map { "<span class=\"perf-sub\">\(htmlEscape($0))</span>" } ?? "" : ""
                var cells = ["<th scope=\"row\" data-label=\"Test\"><a href=\"\(htmlEscape(entry.pagePath))#performance\">\(htmlEscape(entry.test.name))</a>\(suiteLabel)\(runLabel)</th>"]
                for column in columns {
                    if let item = run.metrics.first(where: { $0.metric.displayName == column }) {
                        cells.append(renderOverviewCell(item, column: column))
                    }
                }
                let row = "<tr>\(cells.joined())</tr>"
                if let index = groups.firstIndex(where: { $0.columns == columns }) {
                    groups[index].rows.append(row)
                } else {
                    groups.append((columns, [row]))
                }
            }
        }

        let regressions = entries.map(\.analysis.regressionCount).reduce(0, +)
        let noisy = entries.map(\.analysis.noisyCount).reduce(0, +)
        let metricCount = entries.map { $0.analysis.allMetrics.count }.reduce(0, +)
        var meta = [
            "\(entries.count) test\(entries.count == 1 ? "" : "s")",
            "\(metricCount) metric\(metricCount == 1 ? "" : "s")",
        ]
        if !entries.contains(where: \.analysis.hasBaselines) { meta.append("no baselines") }
        var badges = ""
        if regressions > 0 { badges += performanceBadge("\(regressions) regressed", kind: "regression") }
        if noisy > 0 { badges += performanceBadge("\(noisy) noisy", kind: "noise") }

        let tables = groups.map { group -> String in
            let head = (["Test"] + group.columns).map { "<th scope=\"col\">\(htmlEscape($0))</th>" }.joined()
            return """
                <div class="perf-table-wrap"><table class="data-table perf-overview-table"><thead><tr>\(head)</tr></thead>\
                <tbody>\(group.rows.joined())</tbody></table></div>
                """
        }.joined()
        return """
            <section class="perf-overview" id="performance-overview" aria-labelledby="performance-overview-title">\
            <details open><summary><h2 id="performance-overview-title">Performance</h2>\
            <span class="perf-meta">\(htmlEscape(meta.joined(separator: " · ")))</span>\(badges)</summary>\
            \(tables)</details></section>
            """
    }

    private func renderOverviewCell(_ item: PerformanceMetricAnalysis, column: String) -> String {
        let statistics = item.statistics
        let format = PerformanceValueFormatter(
            unit: item.metric.unitOfMeasurement,
            values: [statistics.mean, item.metric.baseline, item.history.last].compactMap { $0 })
        var classes = ["perf-cell"]
        if item.exceedsRegressionLimit || !item.iterationsOverLimit.isEmpty { classes.append("perf-cell-regressed") }
        if item.exceedsDeviationLimit { classes.append("perf-cell-noisy") }
        var details = [String]()
        if let relative = statistics.relativeStandardDeviation {
            let over = item.exceedsDeviationLimit ? " perf-over-limit" : ""
            details.append("<span class=\"perf-sub\(over)\">±\(Self.formatPercent(relative))</span>")
        }
        if let change = item.baselineChange {
            details.append("<span class=\"perf-change \(Self.directionClass(item.baselineDirection))\" title=\"vs baseline\">\(Self.formatPercentChange(change)) base</span>")
        } else if let change = item.previousChange {
            details.append("<span class=\"perf-change \(Self.directionClass(item.previousDirection))\" title=\"vs previous run\">\(Self.formatPercentChange(change)) prev</span>")
        }
        if !statistics.outlierIndices.isEmpty {
            let iterations = statistics.outlierIndices.map { "#\($0 + 1)" }.joined(separator: ", ")
            details.append("<span class=\"perf-outlier-mark\" title=\"Outlier iterations \(iterations)\">outlier \(iterations)</span>")
        }
        return """
            <td data-label="\(htmlEscape(column))" class="\(classes.joined(separator: " "))" title="\(htmlEscape(format.raw(statistics.mean)))">\
            <span class="perf-value">\(htmlEscape(format.format(statistics.mean)))</span>\(details.joined())</td>
            """
    }

    // MARK: - Markdown

    func renderPerformanceMarkdown(_ analysis: PerformanceTestAnalysis) -> [String] {
        guard !analysis.runs.isEmpty else { return [] }
        var lines = ["## Performance", ""]
        let findings = Self.performanceFindings(for: analysis)
        if !findings.isEmpty {
            lines.append(contentsOf: findings.map { "- \($0.severity == .regression ? "**Regression:** " : "")\($0.text)" })
            lines.append("")
        }
        for run in analysis.runs {
            if let label = run.run.label { lines.append("### \(label)"); lines.append("") }
            let showsBaseline = run.metrics.contains { $0.metric.baseline != nil }
            let showsPrevious = run.metrics.contains { !$0.history.isEmpty }
            var header = ["Metric", "Average", "Median", "Min", "Max", "Std dev", "RSD"]
            if showsBaseline { header.append("Baseline") }
            if showsPrevious { header.append("Previous") }
            header.append("Iterations")
            lines.append("| \(header.joined(separator: " | ")) |")
            lines.append("|\(Array(repeating: " --- |", count: header.count).joined())")
            for item in run.metrics {
                let metric = item.metric
                let statistics = item.statistics
                let format = PerformanceValueFormatter(
                    unit: metric.unitOfMeasurement,
                    values: metric.measurements + [metric.baseline, item.history.last].compactMap { $0 })
                let outliers = Set(statistics.outlierIndices + item.iterationsOverLimit)
                let iterations = metric.measurements.enumerated().map { index, value in
                    outliers.contains(index) ? "**\(format.format(value))**" : format.format(value)
                }.joined(separator: ", ")
                var cells = [
                    "\(metric.displayName) (\(metric.prefersSmaller == false ? "higher" : "lower") is better)",
                    format.format(statistics.mean),
                    format.format(statistics.median),
                    format.format(statistics.min),
                    format.format(statistics.max),
                    PerformanceValueFormatter(unit: metric.unitOfMeasurement, values: [statistics.standardDeviation])
                        .format(statistics.standardDeviation),
                    statistics.relativeStandardDeviation.map(Self.formatPercent) ?? "–",
                ]
                if showsBaseline {
                    if let baseline = metric.baseline {
                        let change = item.baselineChange.map { " (\(Self.formatPercentChange($0)))" } ?? ""
                        let flag = item.exceedsRegressionLimit ? " **regressed**" : ""
                        cells.append("\(format.format(baseline))\(change)\(flag)")
                    } else {
                        cells.append("–")
                    }
                }
                if showsPrevious {
                    if let previous = item.history.last {
                        let change = item.previousChange.map { " (\(Self.formatPercentChange($0)))" } ?? ""
                        cells.append("\(format.format(previous))\(change)")
                    } else {
                        cells.append("–")
                    }
                }
                cells.append(iterations)
                lines.append("| \(cells.map(markdownPerformanceCell).joined(separator: " | ")) |")
            }
            lines.append("")
        }
        lines.append("Bold iterations are outliers. Raw values: `\(Self.performanceMetricsFileName)` at the report root.")
        lines.append("")
        return lines
    }

    private func markdownPerformanceCell(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
    }
}
