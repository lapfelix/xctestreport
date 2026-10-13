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

There are 18 test functions. The parameterized function contributes three
argument runs, so Xcode's device statistics count 20 baseline executions.
The mixed summary has seven failures, one skip, one expected failure, and nine
passes. Repeated failures appear separately in the run details.

The images are generated with fixed pixels, without system fonts or external
assets. Test outcomes and attachment content are deterministic; timestamps,
durations, device metadata, UUIDs, recordings, and Xcode's internal schema vary
by run/Xcode version. Assert semantic features rather than byte-identical bundles.

## Generate reports and exercise history

From the repository root, after generating the bundles:

```sh
swift run xctestreport output/xcresult-fixtures/Baseline.xcresult \
  output/xcresult-fixtures/reports/01-baseline
swift run xctestreport output/xcresult-fixtures/Mixed.xcresult \
  output/xcresult-fixtures/reports/02-mixed
python3 -m http.server 8000 --directory output/xcresult-fixtures/reports
```

Open `http://localhost:8000/02-mixed/`. These sibling report directories exercise
history; the mixed report can read the baseline's per-test details. Also inspect
`snapshots.json`, `failures.md`, `agent-tests.md`, and the per-test ZIP files.
Use `--keep-loose-attachments` when testing HTML-only regeneration.

Two useful regression targets are visible in the current report generator:
it treats `Expected Failure` as an ordinary failure (the mixed Markdown lists
eight failures despite Xcode's seven), and the fast export path stores the
custom binary/XML plist types as `.dat`. The fixture validator checks the true
Xcode outcomes and exported payloads independently of report behavior, so these
bundles can be used to test fixes without changing the fixture to match a bug.

To recheck existing bundles independently:

```sh
python3 Fixtures/XCResultFixture/verify.py output/xcresult-fixtures/Baseline.xcresult Baseline
python3 Fixtures/XCResultFixture/verify.py output/xcresult-fixtures/Mixed.xcresult Mixed
```

Generated xcresults, reports, logs, and DerivedData live under the ignored
`output/` directory; the fixture project and sources are committed as reusable input.

## Change the project structure

Edit `project.yml` and run `xcodegen generate` in this directory if adding targets
or files. [XcodeGen's project spec](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)
documents the format. Commit the generated `.xcodeproj` alongside the spec.
If renaming targets, update the target identifiers/names in both test plans.
