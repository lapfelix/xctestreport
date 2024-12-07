# xctestreport

A command-line utility to generate a simple HTML test report from an `.xcresult` file produced by `xcodebuild`. Doesn't use any of the deprecated `xcodebuild` options, so it should be future-proof-ish.

## Usage

```bash
OVERVIEW: A utility to generate simple HTML reports from XCTest results.

USAGE: xctestreport <xcresult-path> <output-dir>

ARGUMENTS:
  <xcresult-path>         Path to the .xcresult file.
  <output-dir>            Output directory for the HTML report.

OPTIONS:
  -h, --help              Show help information.
```