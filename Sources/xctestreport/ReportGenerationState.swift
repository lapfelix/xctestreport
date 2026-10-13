import Foundation

private let reportDirectoriesLock = NSLock()
private var reportDirectoriesCache = [String: [String]]()

/// Collects worker errors so a report cannot appear successful after a required output failed.
final class ReportGenerationFailures {
    private let lock = NSLock()
    private var messages: [String] = []

    func record(_ error: Error, context: String) {
        lock.lock()
        messages.append("\(context): \(error)")
        lock.unlock()
    }

    func throwIfAny() throws {
        lock.lock()
        let failures = messages
        lock.unlock()
        guard failures.isEmpty else {
            throw XCTestReport.RuntimeError(message: failures.sorted().joined(separator: "\n"))
        }
    }
}

extension XCTestReport {
    struct ReportRunMetadata: Codable {
        var schemaVersion = 1
        let title: String
        let startTime: Double
        let finishTime: Double
    }

    struct SavedTestInventory: Codable {
        var schemaVersion = 1
        let tests: [TestNode]
        let sourceBundles: [String]
    }

    var historyOutputDirectory: String { generationOriginalOutputDir ?? outputDir }

    /// Generation runs on a copy; a failed command leaves the last complete report intact.
    static func withStagedOutput(at destination: String, _ generate: (String) throws -> Void) throws {
        let fm = FileManager.default
        let target = URL(fileURLWithPath: destination).standardizedFileURL.resolvingSymlinksInPath()
        let parent = target.deletingLastPathComponent()
        guard target.path != parent.path else {
            throw RuntimeError(message: "The output directory must not be the filesystem root.")
        }
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let stage = parent.appendingPathComponent(".xctestreport-stage-\(UUID().uuidString)")
        let backup = parent.appendingPathComponent(".xctestreport-backup-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: stage) }
        var isDirectory: ObjCBool = false
        let exists = fm.fileExists(atPath: target.path, isDirectory: &isDirectory)
        if exists {
            guard isDirectory.boolValue else {
                throw RuntimeError(message: "Output path is not a directory: \(target.path)")
            }
            try fm.copyItem(at: target, to: stage)
        } else {
            try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        }
        if let enumerator = fm.enumerator(at: stage, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
            for case let entry as URL in enumerator {
                if try entry.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                    throw RuntimeError(message: "Report regeneration cannot follow symbolic links inside its output: \(entry.lastPathComponent)")
                }
            }
        }
        try generate(stage.path)
        if exists { try fm.moveItem(at: target, to: backup) }
        do {
            try fm.moveItem(at: stage, to: target)
        } catch {
            if exists {
                do { try fm.moveItem(at: backup, to: target) }
                catch let rollbackError {
                    throw RuntimeError(message: "Could not publish report or restore its previous directory. The previous report is preserved at \(backup.path): \(rollbackError)")
                }
            }
            throw error
        }
        if exists {
            do { try fm.removeItem(at: backup) }
            catch { print("Report published; could not remove previous copy at \(backup.path): \(error)") }
        }
    }

    func validateGenerationPaths() throws {
        let target = URL(fileURLWithPath: outputDir).standardizedFileURL.resolvingSymlinksInPath().path
        let source = URL(fileURLWithPath: xcresultPath).standardizedFileURL.resolvingSymlinksInPath().path
        if !xcresultPath.isEmpty, FileManager.default.fileExists(atPath: source),
            target == source || target.hasPrefix(source + "/") || source.hasPrefix(target + "/") {
            throw RuntimeError(message: "The report output and .xcresult bundle must be in separate directories.")
        }
        if let baseline {
            let url = URL(fileURLWithPath: baseline).standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.appendingPathComponent("tests_full.json").path)
                || FileManager.default.fileExists(atPath: url.appendingPathComponent("tests_inventory.json").path) else {
                throw RuntimeError(message: "--baseline must point to a report containing tests_full.json or tests_inventory.json.")
            }
        }
    }

    func writeRunMetadata(summary: Summary) throws {
        let metadata = ReportRunMetadata(title: summary.title, startTime: summary.startTime, finishTime: summary.finishTime)
        try JSONEncoder().encode(metadata).write(
            to: URL(fileURLWithPath: outputDir).appendingPathComponent("report_metadata.json"), options: .atomic)
    }

    func loadSavedInventory() throws -> SavedTestInventory? {
        let url = URL(fileURLWithPath: outputDir).appendingPathComponent("tests_inventory.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let saved = try JSONDecoder().decode(SavedTestInventory.self, from: Data(contentsOf: url))
        guard saved.schemaVersion == 1 else { throw RuntimeError(message: "Unsupported saved test inventory version.") }
        return saved
    }

    func writeSavedInventory(tests: [TestNode], sourceBundles: [String]) throws {
        let saved = SavedTestInventory(tests: tests, sourceBundles: sourceBundles)
        try JSONEncoder().encode(saved).write(
            to: URL(fileURLWithPath: outputDir).appendingPathComponent("tests_inventory.json"), options: .atomic)
    }

    func runMetadata(in directory: String) -> ReportRunMetadata? {
        let root = URL(fileURLWithPath: directory)
        if let data = try? Data(contentsOf: root.appendingPathComponent("report_metadata.json")),
            let metadata = try? JSONDecoder().decode(ReportRunMetadata.self, from: data),
            metadata.startTime.isFinite {
            return metadata
        }
        // Reports predating metadata still have the authoritative summary timestamp and title.
        if let data = try? Data(contentsOf: root.appendingPathComponent("summary.json")),
            let summary = try? JSONDecoder().decode(Summary.self, from: data), summary.startTime.isFinite {
            return ReportRunMetadata(title: summary.title, startTime: summary.startTime, finishTime: summary.finishTime)
        }
        return nil
    }

    func previousReportDirectories() -> [String] {
        let cacheKey = "\(outputDir)|\(historyOutputDirectory)|\(baseline ?? "")"
        reportDirectoriesLock.lock()
        defer { reportDirectoriesLock.unlock() }
        if let saved = reportDirectoriesCache[cacheKey] { return saved }
        if let baseline { return [URL(fileURLWithPath: baseline).standardizedFileURL.path] }
        let currentURL = URL(fileURLWithPath: historyOutputDirectory).standardizedFileURL
        let parent = currentURL.deletingLastPathComponent()
        let current = runMetadata(in: outputDir)
        let children = (try? FileManager.default.contentsOfDirectory(
            at: parent, includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey], options: [.skipsHiddenFiles])) ?? []
        let candidates: [(String, Double)] = children.compactMap { url in
            guard url.standardizedFileURL != currentURL,
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            if let metadata = runMetadata(in: url.path) {
                if let current {
                    guard metadata.title == current.title, metadata.startTime < current.startTime else { return nil }
                }
                return (url.path, metadata.startTime)
            }
            // Without a current identity only, preserve support for legacy detail-only reports.
            guard current == nil else { return nil }
            let start = testDetailsIndex(inReportDir: url.path).values.compactMap { $0.startTime }.min()
                ?? (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate?.timeIntervalSince1970) ?? 0
            return (url.path, start)
        }
        let selected = candidates.sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }.map { $0.0 }
        reportDirectoriesCache[cacheKey] = selected
        return selected
    }
}
