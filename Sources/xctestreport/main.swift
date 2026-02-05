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

    struct RuntimeError: Error {
        let message: String
    }

    func run() throws {
        do {
            try generateHTMLReport()
        } catch {
            print("Error: \(error)")
            throw error
        }
    }
}

XCTestReport.main()
