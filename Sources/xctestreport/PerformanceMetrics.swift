import Foundation

// Performance metrics recorded by XCTest `measure` blocks, as reported by
// `xcresulttool get test-results metrics`. The raw payload is cached in the report as
// `performance_metrics.json`, so HTML-only regeneration and later runs can compare against it.

extension XCTestReport {
    static let performanceMetricsFileName = "performance_metrics.json"

    struct PerformanceTestMetrics: Codable {
        let testIdentifier: String
        let testIdentifierURL: String?
        let testRuns: [PerformanceRun]
    }

    struct PerformanceRun: Codable {
        struct Device: Codable {
            let deviceId: String?
            let deviceName: String?
        }

        struct Configuration: Codable {
            let configurationId: String?
            let configurationName: String?
        }

        let device: Device?
        let testPlanConfiguration: Configuration?
        let metrics: [PerformanceMetric]

        /// "iPhone 17 Pro · Configuration 1"; nil when neither is known.
        var label: String? {
            let parts = [device?.deviceName, testPlanConfiguration?.configurationName]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }

        /// Matches a run of the same test in another report.
        var matchKey: String {
            "\(device?.deviceName ?? "")|\(testPlanConfiguration?.configurationName ?? "")"
        }
    }

    struct PerformanceMetric: Codable {
        let displayName: String
        let identifier: String
        let unitOfMeasurement: String
        let polarity: String?
        let measurements: [Double]
        let baselineName: String?
        let baselineAverage: Double?
        let maxPercentRegression: Double?
        let maxPercentRelativeStandardDeviation: Double?
        let maxRegression: Double?
        let maxStandardDeviation: Double?

        var prefersSmaller: Bool? {
            switch polarity?.lowercased() {
            case "prefers smaller": return true
            case "prefers larger": return false
            default: return nil
            }
        }

        /// XCTest reports a zero average and an empty name when no baseline is set.
        var baseline: Double? {
            guard let baselineAverage, baselineAverage.isFinite else { return nil }
            let named = !(baselineName ?? "").isEmpty
            return baselineAverage != 0 || named ? baselineAverage : nil
        }
    }

    // MARK: - Loading

    /// Reads every test's metrics in one call. HTML-only regeneration reuses the cached copy.
    func loadPerformanceMetrics() throws -> [String: PerformanceTestMetrics] {
        let cachePath = (outputDir as NSString).appendingPathComponent(Self.performanceMetricsFileName)
        if htmlOnly {
            if FileManager.default.fileExists(atPath: cachePath) {
                return try Self.decodePerformanceMetrics(Data(contentsOf: URL(fileURLWithPath: cachePath)))
            }
            // Reports predating metrics support can still pick them up from the source bundle.
            guard FileManager.default.fileExists(atPath: xcresultPath) else { return [:] }
        }

        var metrics = [String: PerformanceTestMetrics]()
        for bundlePath in [xcresultPath] + additionalTestsFrom {
            let command = [
                "xcrun", "xcresulttool", "get", "test-results", "metrics", "--path", bundlePath,
                "--format", "json", "--compact",
            ]
            let (json, exitCode) = shell(command)
            guard exitCode == 0, let data = json?.data(using: .utf8) else {
                // Older xcresulttool versions lack the subcommand; metrics are optional.
                print("Could not read performance metrics from \(bundlePath) (exit \(exitCode)).")
                continue
            }
            let decoded = try Self.decodePerformanceMetrics(data)
            metrics.merge(decoded) { existing, _ in existing }
        }
        let ordered = metrics.keys.sorted().compactMap { metrics[$0] }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(ordered).write(to: URL(fileURLWithPath: cachePath), options: .atomic)
        return metrics
    }

    static func decodePerformanceMetrics(_ data: Data) throws -> [String: PerformanceTestMetrics] {
        let tests = try JSONDecoder().decode([PerformanceTestMetrics].self, from: data)
        var byIdentifier = [String: PerformanceTestMetrics]()
        for test in tests where test.testRuns.contains(where: { !$0.metrics.isEmpty }) {
            byIdentifier[test.testIdentifier] = test
        }
        return byIdentifier
    }

    /// Metrics from earlier reports, most recent first, for trends and run-to-run deltas.
    func loadPreviousPerformanceMetrics(limit: Int = 10) -> [PerformanceHistoryEntry] {
        previousReportDirectories().prefix(limit).compactMap { directory in
            let path = (directory as NSString).appendingPathComponent(Self.performanceMetricsFileName)
            guard let data = FileManager.default.contents(atPath: path),
                let metrics = try? Self.decodePerformanceMetrics(data)
            else { return nil }
            let date = runMetadata(in: directory).map { Date(timeIntervalSince1970: $0.startTime) }
            return PerformanceHistoryEntry(date: date, tests: metrics)
        }
    }

    struct PerformanceHistoryEntry {
        let date: Date?
        let tests: [String: PerformanceTestMetrics]
    }

    // MARK: - Statistics

    struct PerformanceStatistics: Equatable {
        let count: Int
        let mean: Double
        let median: Double
        let min: Double
        let max: Double
        /// Sample standard deviation, as XCTest reports it.
        let standardDeviation: Double
        /// Percent of the mean; nil when the values straddle zero (e.g. memory deltas).
        let relativeStandardDeviation: Double?
        /// Iterations far from the rest, by a median-absolute-deviation test.
        let outlierIndices: [Int]

        init?(_ values: [Double]) {
            let values = values.filter(\.isFinite)
            guard !values.isEmpty else { return nil }
            let sorted = values.sorted()
            let mean = values.reduce(0, +) / Double(values.count)
            let deviation: Double
            if values.count > 1 {
                let squares = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
                deviation = (squares / Double(values.count - 1)).squareRoot()
            } else {
                deviation = 0
            }
            let sameSign = sorted[0] > 0 || sorted[sorted.count - 1] < 0
            count = values.count
            self.mean = mean
            median = Self.median(of: sorted)
            min = sorted[0]
            max = sorted[sorted.count - 1]
            standardDeviation = deviation
            relativeStandardDeviation = sameSign && mean != 0 ? abs(deviation / mean) * 100 : nil
            outlierIndices = Self.outliers(in: values, median: median, sameSign: sameSign)
        }

        private static func median(of sorted: [Double]) -> Double {
            let middle = sorted.count / 2
            return sorted.count % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
        }

        /// Modified z-score above 3.5 (Iglewicz–Hoaglin), and at least 5% off the median so
        /// that a perfectly steady metric doesn't flag rounding noise.
        private static func outliers(in values: [Double], median: Double, sameSign: Bool) -> [Int] {
            guard values.count >= 3 else { return [] }
            let deviations = values.map { abs($0 - median) }
            let mad = Self.median(of: deviations.sorted())
            let minimumDeviation = sameSign ? abs(median) * 0.05 : 0
            return values.indices.filter { index in
                let deviation = deviations[index]
                guard deviation > minimumDeviation, deviation > 0 else { return false }
                return mad == 0 || 0.6745 * deviation / mad > 3.5
            }
        }
    }

    /// Everything the report says about one metric of one run.
    struct PerformanceMetricAnalysis {
        enum Direction { case better, worse, neutral }

        let metric: PerformanceMetric
        let statistics: PerformanceStatistics
        /// Percent change of the average from the baseline.
        let baselineChange: Double?
        let baselineDirection: Direction
        /// Worse than the baseline by more than XCTest allows.
        let exceedsRegressionLimit: Bool
        /// Relative standard deviation over XCTest's limit.
        let exceedsDeviationLimit: Bool
        /// Iterations above the average by more than 4× the deviation limit, which XCTest fails as
        /// "measurement #N is X% worse (or, when larger is better, better) than average". It checks
        /// only upward spikes, whatever the polarity, and only against a baseline.
        let iterationsOverLimit: [Int]
        /// Averages from earlier reports, oldest first.
        let history: [Double]
        let previousChange: Double?
        let previousDirection: Direction

        init(metric: PerformanceMetric, statistics: PerformanceStatistics, history: [Double]) {
            self.metric = metric
            self.statistics = statistics
            self.history = history

            if let baseline = metric.baseline {
                let change = Self.percentChange(from: baseline, to: statistics.mean)
                baselineChange = change
                baselineDirection = Self.direction(of: statistics.mean - baseline, prefersSmaller: metric.prefersSmaller)
                let limit = metric.maxPercentRegression ?? 10
                let absoluteLimit = metric.maxRegression ?? 0
                exceedsRegressionLimit = baselineDirection == .worse
                    && (change.map { abs($0) > limit } ?? true)
                    && abs(statistics.mean - baseline) > absoluteLimit
            } else {
                baselineChange = nil
                baselineDirection = .neutral
                exceedsRegressionLimit = false
            }

            if let limit = metric.maxPercentRelativeStandardDeviation, limit > 0,
                let deviation = statistics.relativeStandardDeviation
            {
                exceedsDeviationLimit = deviation > limit
            } else {
                exceedsDeviationLimit = false
            }

            if metric.baseline != nil, let limit = metric.maxPercentRelativeStandardDeviation, limit > 0 {
                iterationsOverLimit = metric.measurements.indices.filter { index in
                    guard let change = Self.percentChange(from: statistics.mean, to: metric.measurements[index]) else { return false }
                    return change > 4 * limit
                }
            } else {
                iterationsOverLimit = []
            }

            if let previous = history.last {
                previousChange = Self.percentChange(from: previous, to: statistics.mean)
                previousDirection = Self.direction(of: statistics.mean - previous, prefersSmaller: metric.prefersSmaller)
            } else {
                previousChange = nil
                previousDirection = .neutral
            }
        }

        /// Nil when the reference is zero, where a percentage means nothing.
        static func percentChange(from reference: Double, to value: Double) -> Double? {
            guard reference != 0, reference.isFinite, value.isFinite else { return nil }
            return (value - reference) / abs(reference) * 100
        }

        private static func direction(of difference: Double, prefersSmaller: Bool?) -> Direction {
            guard let prefersSmaller, difference != 0 else { return .neutral }
            return (difference < 0) == prefersSmaller ? .better : .worse
        }
    }

    struct PerformanceRunAnalysis {
        let run: PerformanceRun
        let metrics: [PerformanceMetricAnalysis]
    }

    struct PerformanceTestAnalysis {
        let testIdentifier: String
        let runs: [PerformanceRunAnalysis]
        let previousRunDate: Date?

        var allMetrics: [PerformanceMetricAnalysis] { runs.flatMap(\.metrics) }
        var regressionCount: Int {
            allMetrics.filter { $0.exceedsRegressionLimit || !$0.iterationsOverLimit.isEmpty }.count
        }
        var noisyCount: Int { allMetrics.filter(\.exceedsDeviationLimit).count }
        var outlierMetricCount: Int { allMetrics.filter { !$0.statistics.outlierIndices.isEmpty }.count }
        var hasBaselines: Bool { allMetrics.contains { $0.metric.baseline != nil } }
        var hasHistory: Bool { allMetrics.contains { !$0.history.isEmpty } }
    }

    static func analyzePerformance(
        _ test: PerformanceTestMetrics, history: [PerformanceHistoryEntry]
    ) -> PerformanceTestAnalysis {
        let runs = test.testRuns.compactMap { run -> PerformanceRunAnalysis? in
            let previousRuns = history.compactMap { entry -> PerformanceRun? in
                guard let runs = entry.tests[test.testIdentifier]?.testRuns else { return nil }
                // A single run on each side is the same destination even if it was renamed.
                if runs.count == 1, test.testRuns.count == 1 { return runs[0] }
                return runs.first { $0.matchKey == run.matchKey }
            }
            let metrics = run.metrics.compactMap { metric -> PerformanceMetricAnalysis? in
                guard let statistics = PerformanceStatistics(metric.measurements) else { return nil }
                let averages = previousRuns.reversed().compactMap { previous in
                    previous.metrics.first { $0.identifier == metric.identifier }
                        .flatMap { PerformanceStatistics($0.measurements)?.mean }
                }
                return PerformanceMetricAnalysis(metric: metric, statistics: statistics, history: averages)
            }
            return metrics.isEmpty ? nil : PerformanceRunAnalysis(run: run, metrics: metrics)
        }
        let previousDate = history.first { $0.tests[test.testIdentifier] != nil }?.date
        return PerformanceTestAnalysis(testIdentifier: test.testIdentifier, runs: runs, previousRunDate: previousDate)
    }

    // MARK: - Formatting

    /// Formats a metric's values at one shared scale, so a row reads "2.98 s … 3.01 s" rather
    /// than mixing prefixes. `kI`/`kC`/`kB` are XCTest's kilo-instructions, -cycles and -bytes.
    struct PerformanceValueFormatter {
        let unit: String
        private let factor: Double
        private let suffix: String

        init(unit: String, values: [Double]) {
            self.unit = unit
            let magnitude = values.map(abs).filter(\.isFinite).max() ?? 0
            switch unit {
            // The legacy `measure {}` wall-clock metric spells it out.
            case "s", "seconds":
                if magnitude >= 1 || magnitude == 0 {
                    (factor, suffix) = (1, " s")
                } else if magnitude >= 0.001 {
                    (factor, suffix) = (1000, " ms")
                } else {
                    (factor, suffix) = (1_000_000, " µs")
                }
            case "kB", "kI", "kC":
                let base = magnitude * 1000
                let prefixes: [(Double, String)] = [(1e12, "T"), (1e9, "G"), (1e6, "M"), (1e3, "k"), (1, "")]
                let (scale, prefix) = prefixes.first { base >= $0.0 } ?? (1, "")
                factor = 1000 / scale
                switch unit {
                case "kB": suffix = " \(prefix)B"
                case "kI": suffix = " \(prefix)\(prefix.isEmpty ? "" : " ")instr"
                default: suffix = " \(prefix)\(prefix.isEmpty ? "" : " ")cycles"
                }
            default:
                // Custom units ("routes/s") still scale once the numbers get long.
                let (scale, prefix) = Self.largeNumberPrefix(magnitude)
                factor = 1 / scale
                let parts = [prefix, unit].filter { !$0.isEmpty }
                suffix = parts.isEmpty ? "" : " " + parts.joined(separator: " ")
            }
        }

        func format(_ value: Double) -> String {
            Self.number(value * factor) + suffix
        }

        func formatSigned(_ value: Double) -> String {
            (value > 0 ? "+" : "") + format(value)
        }

        /// The value exactly as XCTest recorded it.
        func raw(_ value: Double) -> String {
            let formatted = String(format: "%.6g", value)
            return unit.isEmpty ? formatted : "\(formatted) \(unit)"
        }

        /// Scale and SI prefix for a magnitude, starting at 10,000 so four-digit values stay exact.
        static func largeNumberPrefix(_ magnitude: Double) -> (scale: Double, prefix: String) {
            let prefixes: [(Double, Double, String)] = [(1e12, 1e12, "T"), (1e9, 1e9, "G"), (1e6, 1e6, "M"), (1e4, 1e3, "k")]
            return prefixes.first { magnitude >= $0.0 }.map { ($0.1, $0.2) } ?? (1, "")
        }

        /// Three significant digits, keeping trailing zeros so columns line up.
        static func number(_ value: Double) -> String {
            guard value.isFinite else { return "–" }
            let magnitude = abs(value)
            let decimals = magnitude >= 100 || magnitude == 0 ? 0 : magnitude >= 10 ? 1 : magnitude >= 1 ? 2 : 3
            let text = String(format: "%.\(decimals)f", value)
            return Double(text) == 0 ? text.replacingOccurrences(of: "-", with: "") : text
        }
    }

    static func formatPercentChange(_ change: Double) -> String {
        // Past +1000%, a multiple reads better: "×91" rather than "+9000%".
        if change >= 1000 {
            let ratio = 1 + change / 100
            let (scale, prefix) = PerformanceValueFormatter.largeNumberPrefix(ratio)
            return "×" + PerformanceValueFormatter.number(ratio / scale) + prefix
        }
        let magnitude = abs(change)
        let text = magnitude >= 10 ? String(format: "%.0f", magnitude) : String(format: "%.1f", magnitude)
        if text == "0.0" || text == "0" { return "±0%" }
        return (change > 0 ? "+" : "−") + text + "%"
    }

    static func formatPercent(_ value: Double) -> String {
        if value > 0, value < 0.05 { return "<0.1%" }
        return value >= 10 ? String(format: "%.0f%%", value) : String(format: "%.1f%%", value)
    }
}
