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

    @Flag(name: .customLong("compress-video"), help: "Compress exported video attachments with ffmpeg (HEVC VideoToolbox).")
    var compressVideo: Bool = false

    @Option(name: .customLong("video-height"), help: "Maximum compressed video dimension (longest edge).")
    var videoHeight: Int = 1024

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
