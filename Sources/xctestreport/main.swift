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

    struct RuntimeError: Error {
        let message: String
    }

    func run() throws {
        do {
            if compressVideo, videoHeight <= 0 {
                throw RuntimeError(message: "--video-height must be greater than 0.")
            }
            try generateHTMLReport()
        } catch {
            print("Error: \(error)")
            throw error
        }
    }
}

XCTestReport.main()
