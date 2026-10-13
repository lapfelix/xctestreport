import ArgumentParser
import Foundation

@testable import xctestreport

/// ArgumentParser keeps property wrappers as definitions until the command is parsed.
/// Give unit tests a command with the same initialized defaults as the shipping CLI.
func makeTestReport() -> XCTestReport {
    try! XCTestReport.parse(["fixture.xcresult", NSTemporaryDirectory()])
}
