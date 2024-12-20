# xctestreport

<img width="51.7%" alt="Screenshot 2024-12-06 at 9 02 20 PM" src="https://github.com/user-attachments/assets/77cb4224-4266-4ed8-9b86-47f464d5d178"><img width="48.3%" alt="Screenshot 2024-12-06 at 9 03 14 PM" src="https://github.com/user-attachments/assets/3a81baf0-f54d-4c4c-84e0-45cb07b4d898">

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

## What's missing

- Support for attachments (the last screenshot of a failed test would be nice)
- Support for multiple test plans

## Installation

To install `xctestreport`, follow these steps:

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/xctestreport.git
   cd xctestreport
   ```

2. Build the project using Swift Package Manager:
   ```bash
   swift build -c release
   ```

3. Copy the executable to a directory in your PATH:
   ```bash
   cp .build/release/xctestreport /usr/local/bin/xctestreport
   ```
