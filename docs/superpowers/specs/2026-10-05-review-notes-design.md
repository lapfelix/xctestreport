# Design: review notes for agent handoff

A person goes through a hosted report (usually its failed tests), writes notes
on tests and suites ("here I'd wait on X instead", "add a check for Y"), then
copies all notes in one go for an agent. Each exported note carries links back
to the test's page, Markdown and bundle so the agent can find steps, video and
screenshots.

Client-side only. Notes live in the viewer's browser and are never uploaded.
The UI change stays small: one icon, and a panel that appears only when asked
for.

## Context
- Reports are served over HTTP from a Google Cloud Storage bucket. Every report
  on that host shares one origin, so storage must be keyed per report.
- Test pages open in a same-origin frame over the index
  (`index.html#test=tests/<page>.html`) and also work as standalone pages.
- Each test already has a section in `agent-tests.md` and a zip bundle with
  `test.md`, video and screenshots.

## UI

### Test page
- One note icon button in the header, after the duration pill. When the test
  has notes, the icon shows a count.
- Clicking it toggles a notes panel docked on the right over the video column.
  The timeline stays usable while the panel is open. Esc or the icon closes it.
- Panel contents, top to bottom:
  - a text box and an **Add note** button (Cmd/Ctrl+Enter also adds);
  - a checkbox **Add current time (01:32 · <step title>)**, showing the live
    playhead and the step it falls in. Checked by default, and its last state
    is remembered;
  - the test's notes. Each note shows its time and step when it has one, plus
    its text. Clicking the time seeks the video and selects that step. Notes
    can be edited in place or deleted.
- Several notes per test. Adding a note clears the text box. The time is
  captured when the note is added, not when typing starts.
- Order: notes with a time ascending by time, then notes without one in the
  order they were added.
- When the test has several runs (retries), a timed note also records which
  run it belongs to, and seeking switches to that run.

### Index page
- Suite notes: the same icon appears on a suite header on hover/focus, and
  stays visible when the suite has notes. It opens the same panel, without the
  time checkbox, placed just under the heading so it never covers the toolbar.
  A click outside closes it. On test pages the panel stays open while the
  timeline is used.
- A test row whose test has notes gets a small note glyph after its name. Rows
  without notes are unchanged.
- A single **Copy all notes** split button appears in the existing toolbar
  only when the report has at least one note. Clicking it copies Markdown and
  briefly shows "Copied". Its ▾ menu offers Copy as JSON, Download Markdown
  (`notes-<reportId>.md`) and Download JSON (`notes-<reportId>.json`). There's
  no notes list view.
- The index updates live through the `storage` event while a framed test page
  edits notes.

Nothing else changes in the layout. A report with no notes looks the same as
today, apart from the single icon on test pages.

## Storage
- `localStorage` key `xctestreport.notes.<reportId>`, holding one JSON document:
  ```json
  {
    "version": 1,
    "suites": { "<suiteName>": [Note] },
    "tests": { "<testIdentifier>": [Note] }
  }
  ```
  `Note` = `{ id, text, created, updated, time?: { seconds, eventId, stepTitle, run } }`.
  `seconds` is relative to the run start, as the timeline displays it.
- `reportId` is generated at report time from the xcresult's identity (test
  plan run start time plus the action/invocation ID), so it stays the same when
  the same xcresult is regenerated and differs between runs. It's emitted as
  `data-report-id` on both templates.
- Every read/write is wrapped in try/catch. If storage is unavailable or full,
  the panel shows a one-line error and keeps the text in the box so nothing is
  lost silently.
- The UI text is "Notes are saved in this browser only".

## Export
Both formats are built at export time with absolute URLs resolved against the
report's `index.html` from `location`.

- **Markdown**, the default:
  ```markdown
  # Review notes: <report title>
  Report: https://storage.googleapis.com/<bucket>/<path>/index.html
  Agent index: .../report.md

  ## Suite RateMyRideUITests
  - Consider a shared replay setup helper.

  ## RateMyRideUITests/test_RMR_006_snoozeOneWeek() (Passed)
  Page: .../tests/test_RateMyRideUITests_test_RMR_006_snoozeOneWeek().html
  Details: .../agent-tests.md#<anchor>
  Bundle: .../tests/test_RateMyRideUITests_test_RMR_006_snoozeOneWeek().zip (test.md, video, screenshots)
  - [01:32, "Start another riding trip and verify questions remain snoozed"] observe for 30s, not 90s
  - Rename to mention TimeFreeze
  ```
  Suites and tests follow the index's document order, and only those with
  notes appear. Each test's notes follow the panel order.
- **JSON**: the same data plus `reportId`, `reportURL`, and per test
  `status`, `pageURL`, `detailsURL` and `bundleURL`.

Export lives only on the index. Each index row gets the facts it needs as data
attributes: test identifier, suite, status, `agent-tests.md` anchor and bundle
path. Test pages carry their own identifier and suite so their notes go under
the right keys. If a clipboard write fails, the text is shown in a selectable
box instead.

## Opting out
- On by default. `--no-notes` omits the script, the icon and the data
  attributes, so the report looks exactly as it does today.

## Implementation
- New `Resources/Web/notes.js`: storage, panel, and export formatters. It
  doesn't run when `data-report-id` is missing. Styles go in `report.css`.
- `timeline-view.js`: expose a small API (`currentTime()`, `currentStep()`,
  `currentRun()`, `seek({seconds, eventId, run})`) for the panel.
- `index-page.js`: row glyphs, suite icons, the Notes control and panel.
- Swift: `reportId`, data attributes and the `<script>` tag in
  `ReportGenerator` / `ReportGeneratorWebAssets`, `--no-notes` in `main.swift`.
  The Markdown anchor comes from the existing `agentMarkdownAnchorLink`.

## Out of scope
- Syncing or sharing notes between people or browsers.
- Importing a notes file, a notes list view, and clearing all notes at once.
- Feeding notes back into `report.md` on regeneration.

## Testing
- Playwright (`ui-tests/`), served over HTTP:
  - add timed and untimed notes; check the order; reload and they persist;
  - clicking a timed note seeks the video and selects the step;
  - editing on a framed test page updates the index glyph and count live;
  - suite note via the suite header icon;
  - the Copy all notes button appears only once a note exists; copied and
    downloaded Markdown and JSON contain suite and test entries, absolute
    page, details and bundle URLs, and the time/step;
  - two reports with different `reportId`s on one origin don't share notes;
  - storage throwing shows the error and keeps the typed text.
- Swift test: `--no-notes` output has no notes script or attributes, and
  `reportId` is stable for the same xcresult.
