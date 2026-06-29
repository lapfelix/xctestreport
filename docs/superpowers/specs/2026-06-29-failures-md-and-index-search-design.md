# Design: `failures.md` + index search/filter/sort

Two independent additions to the `.xcresult` -> static report generator. Both
reuse existing machinery; neither introduces persistent state or a centralized
store (trend/flakiness/diff-across-runs were explicitly ruled out of scope —
they need a server/API this tool isn't).

## Feature 1 — `failures.md`

A single self-contained Markdown file at `<output-dir>/failures.md`, written on
every run, meant as the cheap entry point for an agent: read one file, never
follow a link unless it wants media.

### Content
- **Header block:** same top section as `report.md` — run result, counts, pass
  rate, and build errors/warnings when present.
- **Body:** for each failed test, the *full* `agent-tests/<test>.md` content
  inlined: result, identifier, device, failure message, source locations,
  stack-trace preview, the activity steps tree (with `[FAIL]` marking the
  failing step), previous-run history, and attachment links.
  - Textual content is inlined. Attachment links stay links (binaries can't
    inline into Markdown).
- **Ordering:** failed tests in the same order they appear in `report.md`'s
  failed-tests table.
- **Zero failures:** the file is still written, containing one line —
  `No failed tests. N tests passed.` — so agents can rely on the file existing.

### Wiring
- `report.md` gains a pointer near the top: "For failures only, see
  `failures.md`."
- ASCII-only, same folding rules as the existing Markdown output.

### Implementation
- Built by the existing Markdown builder (`ReportGeneratorMarkdown.swift`) that
  already emits `agent-tests/<test>.md`. `failures.md` filters to failed tests
  and concatenates their per-test Markdown under the shared header. No new
  extraction logic.

## Feature 2 — Index search / filter / sort

Client-side only. Logic in `index-page.js`; a small toolbar added to the index
template; per-row data attributes added in `ReportGenerator.swift`. No new
output files.

### Controls (in the existing `.summary-actions` toolbar)
- **Search box:** live-filters test rows by name substring as typed,
  case-insensitive, debounced. A suite with no matching rows hides itself.
- **Status chips:** three toggle chips — Passed / Failed / Skipped — all on by
  default (= current view). These *replace* the single "Show only failed"
  button. Failed-only is achieved by leaving just the Failed chip on.
- **Filters compose** with the search box via AND.
- **Collapse All / Expand All:** unchanged.

### Sort by duration
- Clicking the **Duration column header** in a suite table sorts that suite's
  rows by duration (toggles desc -> asc -> reset to original order).
- **Slowest tests section:** a collapsible top-level section near the top of the
  page listing the **top 10** tests by duration across all suites, each linking
  to its test page. Collapsed by default to stay out of the way.

### Data attributes
Each test `<tr>` gets:
- `data-status="passed|failed|skipped"` (explicit, since passed rows currently
  carry no class).
- `data-duration="<seconds>"` — numeric, from the existing `parseDuration`
  helper — so JS sorts/filters without parsing display strings.

### Empty state
If the active search + filters match nothing, show a "No tests match" line.

## Out of scope (explicit)
- Cross-run diff / "what changed" / flakiness / trend charts — require a
  centralized store keyed by branch/commit, which this stateless generator
  isn't the place for.
- Device filtering — runs are typically single-device.
- Inline source snippets and failure clustering/classification — interesting,
  deferred; not part of this change.

## Testing
- `failures.md`: extend `AgentMarkdownTests` — assert the file exists, contains
  each failed test's section, omits passed tests, and emits the zero-failure
  line when there are no failures.
- Index search/sort: the existing Playwright harness under `ui-tests/` exercises
  client-side behavior; add a check that chips/search/sort filter and reorder
  rows as expected.
