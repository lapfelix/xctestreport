# Real xcresult fixtures

Open `XCResultFixture.xcodeproj` and select the shared `XCResultFixture` scheme.
It contains a tiny offline iOS app, hosted XCTest/Swift Testing unit tests, and
XCUITests. The project is checked in and requires no third-party packages or
project generator to run. Use Xcode 16 or newer and an iOS 17+ simulator.

## Generate both bundles

From the repository root:

```sh
Fixtures/XCResultFixture/generate.sh
```

The script writes `output/xcresult-fixtures/Baseline.xcresult` and
`output/xcresult-fixtures/Mixed.xcresult`, full build/test logs, and extracted
summary/test-tree JSON, and a per-test `Baseline.media.json` / `Mixed.media.json`
inventory. It verifies the fixture contract before reporting success.
Existing outputs are preserved; supply a fresh directory to regenerate:

```sh
FIXTURE_DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' \
  Fixtures/XCResultFixture/generate.sh output/xcresult-fixtures-next
```

Any installed iPhone/iPad simulator is usable; override `FIXTURE_DESTINATION`
with its name/OS or `platform=iOS Simulator,id=<UDID>`.

The Performance plan is generated separately, into `output/xcresult-fixtures-perf` by default:

```sh
Fixtures/XCResultFixture/generate.sh --performance
```

It writes `Performance.xcresult`, its log, and the exported `summary`, `tests`, `metrics`,
`test-details`, `activities`, and `insights` JSON beside it.
The script uses the currently selected Xcode (`xcode-select` / `DEVELOPER_DIR`).
It runs serially with one simulator and reuses its own DerivedData across plans.
Verbose simulator sysdiagnoses are disabled to keep the fixtures compact; test
screenshots, recordings, activities, and failure attachments are retained.
Baseline uses automatic screenshots; Mixed uses screen recordings. Explicit
screenshots are attached selectively, so the mixed bundle includes video-only,
image-only, combined video/image, and no-media tests.

In Xcode, choose **Product > Scheme > Edit Scheme > Test > Test Plans** to select
`Baseline` or `Mixed`, then **Product > Test**. Mixed intentionally fails.
Its retries run in the same process, so `testFailsOnceThenPasses` fails on its
first attempt and succeeds on its second. Start a new test session to reset it.

## Coverage map

The plans run the same test identifiers, which also makes them useful for previous-run history.

| Cases | Baseline | Mixed | Report behavior to exercise |
| --- | --- | --- | --- |
| `ActivityTests` | Pass | Pass | Three levels of activities; text, JSON, binary/XML plist, PNG, empty/opaque payloads; duplicate attachment names in different steps; duration sorting and performance metrics |
| `OutcomeTests/testPassingAssertion` | Pass | Pass | Plain success with no custom attachments |
| `OutcomeTests/testSkippedWithReason` | Pass | Skip | Skip reason and skipped counts |
| `OutcomeTests/testExpectedFailure` | Pass | Expected failure | Known issue with a reason, source location, and passing overall test status |
| `OutcomeTests/testMultipleFailuresInNestedStep` | Pass | Fail twice per attempt | Two issues in one nested step, multiline/markup messages, helper source location, failure-associated activity |
| `OutcomeTests/testThrownError` | Pass | Fail | Unhandled Swift error with a multiline diagnostic |
| `OutcomeTests/testFailsOnceThenPasses` | Pass | Fail, then pass | Flaky status and repeated activities/attachments |
| `SnapshotTests/testChangedCard` | Matching images | Fail | Expected/actual pair without a diff; synthesized diff and changed regions |
| `SnapshotTests/testResizedCard` | Matching images | Fail | Different image dimensions (160×96 and 192×112) |
| `SnapshotTests/testProvidedDifferenceAndAliases` | Matching images | Fail | `reference`/`failure`/`difference` naming and a supplied diff |
| `SnapshotTests/testMatchingCardWithoutAttachments` | Pass | Pass | Snapshot-class success with no images |
| `ModernTests/fares(category:)` | Three passes | Three passes | Swift Testing parameterized identifiers and named suite/test display names |
| `ModernTests/modernAssertion` | Pass | Fail | Swift Testing failure and Unicode/HTML escaping |
| `JourneyUITests/testPinRoute` | Pass, screenshots | Pass, video + screenshots | Nested action/assertion activities; before/after screenshots and custom `pin-state.json` on the verification step |
| `JourneyUITests/testSearchRoutes` | Pass, automatic screenshots | Pass, video only | Nested query/assertion activities and custom `search-results.txt`; no explicit screenshots |
| `JourneyUITests/testGestureTiming` | Pass | Pass, video only | Tap, two swipes and a slow press-and-drag, plus the app's own `touch-log.json`; the oracle for touch-overlay timing |
| `JourneyUITests/testFailureWithScreenshotAndHierarchy` | Pass | Fail | UI assertion failure, screenshot, accessibility text, and XCTest diagnostic snapshots/input-event records |

Mixed retries failed tests at most twice. Its seven deliberately failing test
identifiers must remain failures; only the connection-attempt test recovers.
The validator rejects unexpected failures, missing payload types, or a missing retry.
It also checks the media distribution, custom UI attachment contents and ownership,
and the nested failure-associated activity. Every XCTest function uses
`XCTContext.runActivity`; Swift Testing cases use their named suite and parameter
structure. Logs, JSON, plists, and binary payloads are attached to their relevant
activity with `.keepAlways`, so the attachment and timeline views have real
step ownership to exercise.

The media inventory records attachment names by test and separates `videoOnly`,
`imageOnly`, `videoAndImage`, and `noMedia`. Useful examples in Mixed:

| Media | Example |
| --- | --- |
| Video only, plus a custom text log | `JourneyUITests/testSearchRoutes()` |
| Screenshots + video + custom JSON | `JourneyUITests/testPinRoute()` |
| Images only | `SnapshotTests/testChangedCard()` |
| Custom text attachment without media | `OutcomeTests/testFailsOnceThenPasses()` |
| No media or custom attachments | `OutcomeTests/testPassingAssertion()` |

There are 19 test functions. The parameterized function contributes three
argument runs, so Xcode's device statistics count 21 baseline executions.
The mixed summary has seven failures, one skip, one expected failure, and ten
passes. Repeated failures appear separately in the run details.

The images are generated with fixed pixels, without system fonts or external
assets. Test outcomes and attachment content are deterministic; timestamps,
durations, device metadata, UUIDs, recordings, and Xcode's internal schema vary
by run/Xcode version. Assert semantic features rather than byte-identical bundles.

## Performance plan

`Performance` runs only `PerformanceTests` (unit) and `PerformanceUITests`; Baseline and Mixed
skip both classes. It has two configurations, `Warm` and `Repeat`, so every test has two runs
in the metrics export. It intentionally fails four tests. Testing takes about three to four
minutes, mostly in the UI tests.

| Test | Outcome | Metrics and behavior to exercise |
| --- | --- | --- |
| `testLegacyMeasureBlock` | Pass | `measure {}`: `Time`, `com.apple.XCTPerformanceMetric_WallClockTime`, unit `seconds`, 10 values, `maxRegression` 0.1 |
| `testLegacyManualStartStop` | Pass | `measureMetrics(_:automaticallyStartMeasuring: false)` with start/stop |
| `testLegacyBaselineWithinTolerance` | Pass | Legacy metric with a baseline |
| `testHostMetricsWithCustomIterationCount` | Pass | Clock, CPU (time/cycles/instructions), memory (physical/peak), and disk logical writes; four values |
| `testManualStartStopOptions` | Pass | `invocationOptions = [.manuallyStart, .manuallyStop]` |
| `testSignpostAndCustomMetrics` | Pass | `XCTOSSignpostMetric` for the test's own interval; a custom `XCTMetric` with unit `routes/s`, "prefers larger", and a baseline it beats |
| `testBaselineRegression` | Fail | `average is N% worse (max allowed: 10%)` |
| `testBaselineImprovement` | Pass | Faster than its baseline; baseline `maxPercentRegression` 25 |
| `testHighRelativeStandardDeviation` | Fail | `standard deviation is N% (max allowed: 5%)` from the baseline's 5% limit |
| `testOutlierMeasurement` | Fail | `measurement #4 is N% worse than average (max allowed: 40%)` |
| `testAssertionFailuresInAndAfterMeasure` | Fail | An assertion in the final measured iteration and another after `measure`; metrics are still recorded |
| `testActivityWrappedMeasureWithIterationActivities` | Pass | `measure` inside an activity, with one child activity and attachment per invocation, including the discarded warm-up |
| `PerformanceUITests/testLaunchPerformance` | Pass | `XCTApplicationLaunchMetric` with and without `waitUntilResponsive`; launch baseline |
| `PerformanceUITests/testScrollDeceleration` | Pass | Scroll deceleration, dragging, and dragging-and-deceleration signposts; `XCTHitchMetric` records nothing on simulators |
| `PerformanceUITests/testNavigationWithAppMetrics` | Pass | Navigation transition, the app's own signpost, and app-targeted CPU/memory metrics named with `FixtureApp` |

The perf-only list screen opens only with the `-FixturePerformanceList` launch argument, so the
journey screens and screenshots are unchanged. Measure options ask for two to four iterations;
XCTest runs one more warm-up invocation and does not record it.

### Baselines

The baselines are in `XCResultFixture.xcodeproj/xcshareddata/xcbaselines`, one per test target.
Xcode applies a baseline only when its run destination matches the host Mac (model, CPU kind,
and core counts) and the simulator model exactly. Otherwise the test runs without a baseline
and passes. The committed destination is an Apple M5 Pro `Mac17,8` with an iPhone Air
(`iPhone18,4`). `generate.sh --performance` copies the project to `PerformanceProject` in the
output directory and runs `retarget_baselines.py`, which rewrites that copy for this Mac and
`FIXTURE_DESTINATION`. Source paths in that bundle point into the copy. To use baselines in Xcode
on another machine, run the script on the project itself, then don't commit that change:

```sh
python3 Fixtures/XCResultFixture/retarget_baselines.py \
  Fixtures/XCResultFixture/XCResultFixture.xcodeproj 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Xcode checks variance only against a baseline. Without one, any spread passes. With one, a
value outside 4× the relative standard deviation limit is reported as an outlier. Otherwise a
standard deviation above the limit fails.

## Generate reports and exercise history

From the repository root, after generating the bundles:

```sh
swift run xctestreport output/xcresult-fixtures/Baseline.xcresult \
  output/xcresult-fixtures/reports/01-baseline
swift run xctestreport output/xcresult-fixtures/Mixed.xcresult \
  output/xcresult-fixtures/reports/02-mixed \
  --baseline output/xcresult-fixtures/reports/01-baseline
python3 -m http.server 8000 --directory output/xcresult-fixtures/reports
```

Open `http://localhost:8000/02-mixed/`. These sibling report directories exercise
history; the mixed report can read the baseline's per-test details. Also inspect
`snapshots.json`, `failures.md`, `agent-tests.md`, and the per-test ZIP files.
Use `--baseline output/xcresult-fixtures/reports/01-baseline` when generating Mixed
to select history explicitly, including when Xcode gives different titles to the test plans.
HTML-only regeneration recovers packed attachments without `--keep-loose-attachments`.

The report checks require seven true failures, keep the expected-failure test out of
failure navigation/Markdown, and preserve binary/XML plist types and content. The
fixture validator checks Apple's outcomes independently of report behavior.

## Run the native report regression checks

```sh
Scripts/test-real-fixtures.sh /absolute/path/to/empty/xcresult-fixtures
XCTESTREPORT_REAL_FIXTURES=/absolute/path/to/empty/xcresult-fixtures \
  npm --prefix ui-tests test -- tests/xcresult-fixtures.spec.js
```

Run these from the repository root after installing the browser dependencies described
in its README. The script selects an available iPhone simulator with iOS 17 or newer;
`FIXTURE_DESTINATION` can select another destination. It generates and verifies both
xcresults, then uses the shipping release CLI to write `reports/baseline` and
`reports/mixed`, with an explicit baseline for history. `XCTESTREPORT_EXECUTABLE` can
point to an already-built executable with its resource bundle.

`validate_reports.py` compares report inventories, outcomes, cached arguments/retries,
attachment bytes and direct step ownership, snapshot groups, media distribution, and
history against the independent fixture contract. For touch overlays, the fixture app
logs when it actually received each touch and shows a magenta bar while a finger is
down: every overlay gesture must start and end within 80 ms of the logged touch, and in
Mixed, `sample_frames.swift` checks that the recording shows the bar where the overlay
places the touch. The script then moves the sources
away, regenerates default packed reports, repeats validation, and verifies that a corrupt
required cache fails without changing published artifacts. Source bundles are restored
on exit. Browser checks use the regenerated output and discover its actual page/bundle
links. CI requires these fixtures, runs all three browser engines, and uploads native
logs, oracle JSON, reports and xcresults separately when a check fails.

To recheck existing bundles independently:

```sh
python3 Fixtures/XCResultFixture/verify.py output/xcresult-fixtures/Baseline.xcresult Baseline
python3 Fixtures/XCResultFixture/verify.py output/xcresult-fixtures/Mixed.xcresult Mixed
python3 Fixtures/XCResultFixture/verify.py output/xcresult-fixtures-perf/Performance.xcresult Performance
PYTHONDONTWRITEBYTECODE=1 python3 Fixtures/XCResultFixture/validate_reports.py output/xcresult-fixtures
```

`validate_performance_report.py` builds a report of `Performance.xcresult` and compares it with
`xcresulttool`'s own metrics export. Every metric and iteration must appear on its test page, the
baseline checks XCTest failed must be flagged (and the ones it accepted must not), and HTML-only
regeneration without the bundle must render the same sections:

```sh
swift build
PYTHONDONTWRITEBYTECODE=1 python3 Fixtures/XCResultFixture/validate_performance_report.py \
  output/xcresult-fixtures-perf/Performance.xcresult .build/debug/xctestreport
```

Generated xcresults, reports, logs, and DerivedData live under the ignored
`output/` directory; the fixture project and sources are committed as reusable input.

## Change the project structure

Edit `project.yml` and run `xcodegen generate` in this directory if adding targets
or files. [XcodeGen's project spec](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)
documents the format. Commit the generated `.xcodeproj` alongside the spec.
If renaming targets, update the target identifiers/names in all three test plans and the
`xcbaselines` directory names, which are the test targets' identifiers.
