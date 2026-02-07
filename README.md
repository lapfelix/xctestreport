# xctestreport

<img width="51.7%" alt="Screenshot 2024-12-06 at 9 02 20 PM" src="https://github.com/user-attachments/assets/77cb4224-4266-4ed8-9b86-47f464d5d178"><img width="48.3%" alt="Screenshot 2024-12-06 at 9 03 14 PM" src="https://github.com/user-attachments/assets/3a81baf0-f54d-4c4c-84e0-45cb07b4d898">

A command-line utility to generate a simple HTML test report from an `.xcresult` file produced by `xcodebuild`. Doesn't use any of the deprecated `xcodebuild` options, so it should be future-proof-ish.

## Usage

```bash
OVERVIEW: A utility to generate simple HTML reports from XCTest results.

USAGE: xctestreport <xcresult-path> <output-dir> [--compress-video] [--video-height <video-height>]

ARGUMENTS:
  <xcresult-path>         Path to the .xcresult file.
  <output-dir>            Output directory for the HTML report.

OPTIONS:
  --compress-video        Compress exported video attachments with ffmpeg (HEVC VideoToolbox).
  --video-height <video-height>
                          Maximum compressed video dimension (longest edge).
  -h, --help              Show help information.
```

## What's missing

- Support for non-video attachments (for example screenshots and text logs) in test detail pages
- Support for multiple test plans

## Web rendering layout

Web UI assets are now file-based (not embedded as large Swift strings):

- HTML templates: `Sources/xctestreport/Resources/Web/templates/`
- Stylesheet: `Sources/xctestreport/Resources/Web/report.css`
- Page behavior scripts: `Sources/xctestreport/Resources/Web/index-page.js`, `Sources/xctestreport/Resources/Web/timeline-view.js`, and `Sources/xctestreport/Resources/Web/plist-preview.js`
- Mobile-first rendering: test tables collapse into labeled cards on narrow screens; detail timeline reflows to avoid clipping.
- Binary plist attachments are converted to textual previews and then gzip-compressed in place at the end of report generation; preview content is decompressed in-browser on demand.

Rendering flow:

1. Swift loads templates and verifies required `{{placeholders}}`.
2. Swift copies static web assets into the report output directory.
3. Swift injects dynamic report/test/timeline data into templates.
4. Timeline data is passed via JSON script tags, and consumed by `timeline-view.js`.

## Local validation

Example run with an external xcresult (not copied into this repo):

```bash
swift run xctestreport /path/to/results.xcresult /tmp/xctestreport-output
```

Video compression examples:

```bash
# Enable compression (longest edge defaults to 1024)
swift run xctestreport /path/to/results.xcresult /tmp/xctestreport-output --compress-video

# Enable compression and cap longest edge at 1280
swift run xctestreport /path/to/results.xcresult /tmp/xctestreport-output --compress-video --video-height 1280
```

If `--compress-video` is set but `ffmpeg` is not installed, compression is skipped and report generation continues.
The default VideoToolbox setting uses `-q:v 45`, tuned for faster export and smaller files on Apple Silicon while preserving readable UI detail.

If plist attachment payloads are compressed, preview requires browser `DecompressionStream` support.

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
