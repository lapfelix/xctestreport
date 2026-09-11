#!/usr/bin/env swift

import ArgumentParser

struct XCTestReport: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xctestreport",
        abstract: "A utility to generate simple HTML reports from XCTest results."
    )

    @Argument(help: "Path to the .xcresult file.")
    var xcresultPath: String

    @Argument(help: "Output directory for the HTML report.")
    var outputDir: String

    @Flag(name: .customLong("compress-video"), help: "Compress exported video attachments with ffmpeg.")
    var compressVideo: Bool = false

    @Flag(name: .customLong("fast-video"), help: "Favor fastest video compression settings.")
    var fastVideo: Bool = false

    @Option(name: .customLong("video-height"), help: "Maximum compressed video dimension (longest edge).")
    var videoHeight: Int = 720

    @Flag(
        name: .customLong("html-only"),
        help: "Reuse existing summary/tests_full/attachments in outputDir and only generate HTML."
    )
    var htmlOnly: Bool = false

    @Option(
        name: .customLong("header-note"),
        help: "Custom note shown under the title on the report's main page (e.g. \"Branch: feature/new-thing\")."
    )
    var headerNote: String?

    @Option(
        name: .customLong("additional-tests-from"),
        help: """
        Additional .xcresult bundle whose tests are appended to the report. May be repeated. \
        Works around `xcresulttool get test-results tests` listing only the first test plan of a \
        bundle merged from different test plans: pass the merged bundle as the main argument \
        (per-test details, activities and attachments resolve fine there) and the dropped plan's \
        bundle here so its tests appear in the report.
        """
    )
    var additionalTestsFrom: [String] = []

    @Flag(
        name: .customLong("no-snapshot-diff"),
        help: "Disable snapshot visual-diff detection and rendering (enabled by default)."
    )
    var noSnapshotDiff: Bool = false

    @Option(
        name: .customLong("snapshot-tolerance"),
        help: "Per-channel tolerance (0-255) below which a snapshot pixel counts as unchanged."
    )
    var snapshotTolerance: Int = 12

    struct RuntimeError: Error {
        let message: String
    }

    func run() throws {
        do {
            if compressVideo, videoHeight <= 0 {
                throw RuntimeError(message: "--video-height must be greater than 0.")
            }
            if !(0...255).contains(snapshotTolerance) {
                throw RuntimeError(message: "--snapshot-tolerance must be between 0 and 255.")
            }
            try generateHTMLReport()
        } catch {
            print("Error: \(error)")
            throw error
        }
    }
}

XCTestReport.main()
