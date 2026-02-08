# xctestreport

Generate static HTML reports from XCTest `.xcresult` bundles.

## Highlights
- Builds an `index.html` suite overview and per-test detail pages.
- Renders timeline + scrubber + media previews for test activities.
- Exports attachments and supports video, image, text, and plist preview flows.
- Compares against previous report folders in the same parent directory.
- Keeps heavy web payloads compressed to reduce output size.

## Requirements
- macOS with Xcode command-line tools (`xcrun xcresulttool`).
- Swift 5.5+ (SwiftPM build).
- Optional: `ffmpeg` for `--compress-video`.
- Optional: `gzip` for extra payload compression (fallbacks are automatic).

## Install
```bash
git clone https://github.com/lapfelix/xctestreport.git
cd xctestreport
swift build -c release
cp .build/release/xctestreport /usr/local/bin/xctestreport
```

## CLI
```bash
USAGE: xctestreport <xcresult-path> <output-dir> [--compress-video] [--video-height <video-height>]

ARGUMENTS:
  <xcresult-path>         Path to the .xcresult file.
  <output-dir>            Output directory for the HTML report.

OPTIONS:
  --compress-video        Compress exported video attachments with ffmpeg (HEVC VideoToolbox).
  --video-height <n>      Maximum compressed video dimension (longest edge). Default: 1024.
  -h, --help              Show help information.
```

## Quick Start
```bash
swift run xctestreport /path/to/Test.xcresult ~/Desktop/xcresultout --compress-video --video-height 1024
open ~/Desktop/xcresultout/index.html
```

`index.html` is always written at `<output-dir>/index.html`.

## Compression Behavior

### Video compression (`--compress-video`)
- Uses `ffmpeg` when available.
- Tries hardware first (`hevc_videotoolbox`), then falls back to `libx264` if needed.
- Preserves aspect ratio and constrains the longest edge to `--video-height`.
- Replaces the original exported video only when output is valid and smaller.
- If `ffmpeg` is missing, logs a skip and continues report generation.

### Binary plist attachment compression
- Detects binary plist attachments (`bplist00`).
- Generates text previews via `plutil -p`.
- Gzip-compresses preview text and stores it as `<original-name>.gz` when smaller.
- Browser decompresses on demand with `DecompressionStream`.

### Timeline payload compression
- Timeline run-state and screenshot payloads are compact-encoded JSON, then gzip-compressed.
- Stored under `timeline_payloads/*.bin` and loaded lazily by `timeline-view.js`.
- If compression fails, falls back to inline JSON in the page.

## Output Layout
Typical output directory:

- `index.html`
- `test_<identifier>.html` (one per test case)
- `attachments/` (exported media + previews)
- `timeline_payloads/` (compressed timeline payload blobs)
- `summary.json`
- `tests_full.json`
- `tests_grouped.json`
- `test_details/*.json`
- `report.css`, `vue.global.prod.js`, `index-page.js`, `timeline-view.js`, `plist-preview.js`

## Web Assets (for edits)
- Templates: `Sources/xctestreport/Resources/Web/templates/`
- CSS: `Sources/xctestreport/Resources/Web/report.css`
- JS vendor: `Sources/xctestreport/Resources/Web/vue.global.prod.js`
- JS: `Sources/xctestreport/Resources/Web/index-page.js`
- JS: `Sources/xctestreport/Resources/Web/timeline-view.js`
- JS: `Sources/xctestreport/Resources/Web/plist-preview.js`

## Notes
- Very large `.xcresult` bundles can still take time due to attachment export and test detail extraction.
- Decompressed plist preview in-browser requires `DecompressionStream` support.
