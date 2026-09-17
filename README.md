# xctestreport

Generate static HTML reports from XCTest `.xcresult` bundles.

## Highlights
- Builds an `index.html` suite overview and per-test detail pages.
- Search box, per-status chips (passed/failed/skipped), and Duration-column sort
  on the main page, plus a collapsible "Slowest tests" section.
- Optional custom header note under the title (`--header-note`), e.g. the branch under test.
- Writes an agent/LLM-readable `report.md`, a failures-only `failures.md`, and per-test Markdown (see below).
- Renders timeline + scrubber + media previews for test activities.
- Exports attachments and supports video, image, text, and plist preview flows.
- Compares against previous report folders in the same parent directory.
- Packs each test's payloads into one ZIP per test, so a full run writes hundreds of files
  instead of thousands (see [Per-test bundles](#per-test-bundles)).

## Agent-readable report

Alongside the HTML, every run writes a Markdown view meant for LLMs/agents to dig
into failures without the `.xcresult`:

- `report.md` — start here. Run result, counts, pass rate, build errors/warnings,
  and a table of **failed tests** (each with a one-line reason), followed by every
  suite and test.
- `failures.md` — the cheap entry point. Every failed test's full detail inlined
  into one self-contained file, so an agent reads one file without following
  links. Always written; says so plainly when nothing failed.
- `agent-tests.md` — every test's full detail in one file: result, identifier, device, the
  failure message, source locations, stack-trace preview, the full activity
  **steps** tree (timestamps, `[FAIL]` marks the failing step), previous-run
  history, and every attachment. It opens with grep/sed recipes and a table of contents
  giving the exact starting line of every test, so an agent with limited context can jump
  straight to one section instead of reading the file:

  ```bash
  grep -n '^<!-- test:MySuite/testFoo()' agent-tests.md   # find the section
  sed -n '1240,1400p' agent-tests.md                      # read just that section
  grep -n '^## \[FAIL\]' agent-tests.md                   # failures only
  ```

  The same per-test Markdown is also stored inside each test's bundle as `test.md`
  (`unzip -p tests/test_MySuite_testFoo\(\).zip test.md`).

All links are relative, so the output folder works the same whether read locally or
hosted remotely. Point an agent at `report.md` and let it follow the links.

The Markdown is ASCII-only (typographic punctuation is folded, anything else becomes
`?`), so it never mojibakes when a host serves `.md` as non-UTF-8 `text/plain`.

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
USAGE: xctestreport <xcresult-path> <output-dir> [--compress-video] [--video-height <video-height>] [--header-note <header-note>] [--keep-loose-attachments] [--no-snapshot-diff] [--snapshot-tolerance <snapshot-tolerance>]

ARGUMENTS:
  <xcresult-path>         Path to the .xcresult file.
  <output-dir>            Output directory for the HTML report.

OPTIONS:
  --compress-video        Compress exported video attachments with ffmpeg (HEVC VideoToolbox).
  --video-height <n>      Maximum compressed video dimension (longest edge). Default: 1024.
  --header-note <note>    Custom note shown under the title on the report's main
                          page (e.g. "Branch: feature/new-thing").
  --keep-loose-attachments
                          Keep the loose copies of attachments that were packed into
                          per-test bundles. Needed only if you intend to re-run with
                          --html-only, which re-reads the attachments directory.
  --no-snapshot-diff      Disable snapshot visual-diff detection and rendering
                          (enabled by default).
  --snapshot-tolerance <n>
                          Per-channel tolerance (0-255) below which a snapshot
                          pixel counts as unchanged. Default: 12.
  -h, --help              Show help information.
```

## Quick Start
```bash
swift run xctestreport /path/to/Test.xcresult ~/Desktop/xcresultout --compress-video --video-height 1024
open ~/Desktop/xcresultout/index.html
```

Add a header note (shown under the title), handy in CI to label the run:

```bash
swift run xctestreport /path/to/Test.xcresult ~/Desktop/xcresultout --header-note "Branch: $(git rev-parse --abbrev-ref HEAD)"
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
- Timeline run-state and screenshot payloads are compact-encoded JSON, deflated into the test's
  bundle as `timeline/runstates.json` and `timeline/screenshots.json`.
- Loaded lazily by `timeline-view.js` through `web/bundle-reader.js`.
- If the bundle cannot be read, the page falls back to the inline JSON in the page itself.

## Output Layout
Typical output directory:

- `index.html`
- `snapshots.html` (snapshot gallery; written when the run produced at least one comparison)
- `report.md` (agent/LLM-readable index)
- `failures.md` (agent/LLM-readable, failures only, full detail inlined)
- `agent-tests.md` (agent/LLM-readable, every test's full detail, with a line-number index)
- `snapshots.json` (machine-readable snapshot comparison index; written whenever snapshot diffing is enabled, even with zero comparisons)
- `summary.json`
- `tests_full.json`
- `tests_grouped.json`
- `tests/test_<identifier>.html` (one per test case)
- `tests/test_<identifier>.zip` (one per test case; everything that page loads lazily)
- `web/report.css`, `web/index-page.js`, `web/bundle-reader.js`, `web/timeline-view.js`,
  `web/plist-preview.js`, `web/snapshot-diff.js`, `web/snapshot-gallery.js`, `web/snapshot-gallery.css`
- `attachments/` (videos and snapshot comparison images only; everything else is bundled)
- `test_details.json` (per-test detail keyed by test identifier, used to compare against previous runs)

A 403-test run that previously wrote 5,641 files now writes 889.

## Per-test bundles

Each test page has a sibling ZIP holding everything it loads lazily: the two timeline payloads,
every attachment preview, the UI-hierarchy plists, and the test's agent Markdown. The page itself
stays a normal HTML file, so a test costs **two files** instead of the dozen-plus it used to.

```
tests/test_MySuite_testFoo().html
tests/test_MySuite_testFoo().zip
  |-- timeline/runstates.json
  |-- timeline/screenshots.json
  |-- attachments/12.plist
  |-- attachments/31.dat.preview.txt
  `-- test.md
```

They are ordinary archives, so the shell works on them directly:

```bash
unzip -l 'tests/test_MySuite_testFoo().zip'
unzip -p 'tests/test_MySuite_testFoo().zip' test.md
```

### How the browser reads them
`web/bundle-reader.js` never downloads a whole bundle to show one attachment. A ZIP keeps its
central directory at the end, so the reader issues a suffix range request (`Range: bytes=-65536`)
to get the index, then one ranged request per entry, inflating with the browser's native
`DecompressionStream('deflate-raw')`. No WebAssembly and no third-party library are involved.
Entries become `blob:` URLs, which are same-origin, so canvas pixel reads keep working.

Reading one entry out of a 23 MB bundle costs about 300 KB.

### Serving requirements
- **Serve the report over HTTP(S).** Test pages need `fetch`, which browsers block on `file://`.
  `index.html`, `report.md`, `failures.md` and `agent-tests.md` are unaffected.
- The host should honour range requests. Google Cloud Storage, S3 and nginx all do
  (`Accept-Ranges: bytes`, answering `bytes=-N` with `206`). A host that ignores ranges still
  works: the reader falls back to fetching the bundle once and serving every entry from memory.
- Do **not** let the host gzip-transcode `.zip` objects. Content-encoding transcoding makes a
  range refer to the compressed stream, which breaks the index read, and the entries are already
  deflated so it saves nothing. On GCS this means uploading them with identity encoding.

### What stays a loose file
- **Videos**, because `<video>` needs real streaming and seeking, which a blob URL cannot give it.
- **Snapshot comparison images**, so the contact sheet and its download links keep working with
  JavaScript disabled.
- **Stack-trace attachments**, which are linked from outside the timeline section.

Attachments that xcresult stores zstd- or gzip-compressed are decompressed while packing, because
no browser can decode zstd natively. The archive always holds bytes the page can use directly.

## Web Assets (for edits)
- Templates: `Sources/xctestreport/Resources/Web/templates/`
- CSS: `Sources/xctestreport/Resources/Web/report.css`
- JS: `Sources/xctestreport/Resources/Web/index-page.js`
- JS: `Sources/xctestreport/Resources/Web/bundle-reader.js`
- JS: `Sources/xctestreport/Resources/Web/timeline-view.js`
- JS: `Sources/xctestreport/Resources/Web/plist-preview.js`
- JS: `Sources/xctestreport/Resources/Web/snapshot-diff.js`
- JS/CSS: `Sources/xctestreport/Resources/Web/snapshot-gallery.js`, `snapshot-gallery.css`

## Snapshot Comparisons
Attachments named `<name>.expected.png` / `<name>.actual.png` (aliases: `reference` / `failure`, plus an
optional `<name>.diff.png` or `<name>.difference.png`) are grouped into a visual comparison on the test
page, in the per-test Markdown, and in `snapshots.json`.

- Images of different sizes are compared top-left aligned over their union rect; area present in only
  one image counts as changed and is hatched in the diff.
- When no diff image was attached, one is synthesized next to the attachments as
  `<counter>.synth-diff.png` (unchanged pixels dimmed to grayscale, changed pixels magenta).
- In `snapshots.json`, every image carries `src` (relative to a test page, `../attachments/...`) and
  `rootSrc` (relative to the report root, `attachments/...`). External consumers should use `rootSrc`.
- Each test entry carries a `device` object since reference images are OS-version specific: `name`
  (hardware model), `deviceName` (simulator instance, which on a watchOS run is the paired host
  iPhone), `osVersion`, `osBuildNumber`, `platform` and `identifier`. Unresolved fields are null.

### Snapshot gallery (`snapshots.html`)
Every snapshot comparison in the run on one contact sheet, linked from `index.html`
and from the back-link in each test page's snapshot section (anchored at that comparison).

- Expected/actual previews let you scan failures without opening an inspector. **Show differences**
  switches the actual previews to their diff images. Grouping by test class is optional.
- Mixed-device reports show an **All devices** filter and device/OS labels on each card.
  The inspector shows the selected snapshot’s full device details. Single-device reports keep a compact header label.
- Search snapshot, test, or suite names; **Failed only** starts enabled when failures exist.
  Expand **Filter test classes** to narrow the sheet further.
- Click a preview to inspect it with all six comparison modes, synchronized zoom/pan, difference
  navigation, original-image downloads, and expandable **Pixel analysis** (statistics and tolerance).
- Comparisons default to side-by-side on desktop and Swipe on narrow screens. On touch devices,
  pinch to zoom, drag to pan, or use the zoom menu for precise magnification.
- **Previous/Next** or **[ / ]** moves through the currently visible comparisons and preserves the
  comparison mode. **Escape** closes the inspector and restores focus to the preview.
- The gallery loads the viewer script only when inspection starts. One viewer is active at a time;
  closing it releases pixel buffers, blink timers, and resize observers. Preview images load lazily.
- Serve the report over HTTP to enable canvas-based heatmaps, tolerance, and pixel inspection.
  Static image comparisons remain available without JavaScript.
- Xcode only attaches images when a snapshot assertion fails. A test that passed in a class that
  produced comparisons is still listed, as a compact "matched, no images" row - the result bundle
  carries no record of what it captured. The page says so; nothing is inferred from test names.

## Notes
- Very large `.xcresult` bundles can still take time due to attachment export and test detail extraction.
- Reading per-test bundles in the browser requires `DecompressionStream` (Chrome 80+, Safari 16.4+,
  Firefox 113+).

### Browser regression checks

Run `npm --prefix ui-tests test`. The Playwright suite uses the shipping templates and assets,
with real watchOS failure images served over HTTP. It covers gallery filtering, all comparison
modes, synthesized diffs, tolerance, keyboard navigation, mobile light/dark layouts, unavailable
images, no-JavaScript fallbacks, viewer cleanup, and a 180-comparison contact sheet.

`tests/bundle.spec.js` covers the bundle reader against a range-serving host: entry listing,
inflating deflated entries, byte-exact stored entries, blob-URL reuse, the partial-fetch path on a
large archive, and the whole-archive fallback when a host ignores `Range`.
