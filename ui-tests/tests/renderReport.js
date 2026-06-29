// Build a report index.html in a temp dir using the REAL shipping template,
// CSS, and JS, with the same row/suite markup the Swift generator emits. This
// lets the UI tests exercise the actual front-end without needing an .xcresult.
const fs = require('fs');
const os = require('os');
const path = require('path');

const REPO_ROOT = path.resolve(__dirname, '..', '..');
const WEB_DIR = path.join(REPO_ROOT, 'Sources', 'xctestreport', 'Resources', 'Web');
const TEMPLATE_PATH = path.join(WEB_DIR, 'templates', 'index.html');

function htmlEscape(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// Mirrors the test-row markup in ReportGenerator.swift.
function testRow(test) {
  const statusClass = test.status; // "passed" | "failed" | "skipped"
  const rowClass = statusClass === 'passed' ? '' : ` class="${statusClass}"`;
  const result = statusClass.charAt(0).toUpperCase() + statusClass.slice(1);
  const seconds = test.duration == null ? 1 : test.duration;
  return `<tr${rowClass} data-status="${statusClass}" data-duration="${seconds}"><td data-label="Test Name"><a href="tests/test_${htmlEscape(test.name)}.html">${htmlEscape(test.name)}</a></td>` +
    `<td data-label="Status" class="${statusClass}">${result}</td>` +
    `<td data-label="Duration">${seconds} sec</td></tr>`;
}

// Mirrors the suite-section markup in ReportGenerator.swift.
function suiteSection(suite) {
  const total = suite.tests.length;
  const passed = suite.tests.filter((t) => t.status === 'passed').length;
  const rows = suite.tests.map(testRow).join('\n');
  return `<div class="suite"><h2 class="collapsible">
    <span class="suite-name">${htmlEscape(suite.name)}</span>
    <span class="suite-stats">
        <span class="stats-number">${passed}/${total}</span> Passed
        <span class="stats-percent">(0.0%)</span>
        <span class="suite-duration">1.0 sec</span>
    </span>
</h2><div class="content">
<table class="data-table suite-tests-table" style="margin-top:0px">
<thead><tr><th scope="col">Test Name</th><th scope="col">Status</th><th scope="col" class="sortable-duration">Duration</th></tr></thead>
<tbody>
${rows}
</tbody></table></div></div>`;
}

/**
 * @param {{ title?: string, headerNote?: string, suites?: Array<{name: string, tests: Array<{name: string, status: string}>}> }} opts
 * @returns {string} file:// URL to the rendered index.html
 */
function renderReport(opts = {}) {
  const title = opts.title || 'MyScheme';
  const suites = opts.suites || [];
  const headerNoteHTML = opts.headerNote
    ? `<p class="header-note">${htmlEscape(opts.headerNote)}</p>`
    : '';

  const counts = suites.flatMap((s) => s.tests);
  const values = {
    report_title: htmlEscape(title),
    header_note_html: headerNoteHTML,
    total_tests: String(counts.filter((t) => t.status !== 'skipped').length),
    passed_tests: String(counts.filter((t) => t.status === 'passed').length),
    failed_tests: String(counts.filter((t) => t.status === 'failed').length),
    skipped_tests: String(counts.filter((t) => t.status === 'skipped').length),
    build_results_html: '',
    comparison_info_html: '',
    suite_sections_html: suites.map(suiteSection).join('\n'),
  };

  let html = fs.readFileSync(TEMPLATE_PATH, 'utf8');
  for (const key of Object.keys(values)) {
    html = html.split(`{{${key}}}`).join(values[key]);
  }

  const leftover = html.match(/{{\s*[\w]+\s*}}/g);
  if (leftover) {
    throw new Error(`Template has unsubstituted placeholders: ${leftover.join(', ')}`);
  }

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'xctestreport-ui-'));
  fs.mkdirSync(path.join(dir, 'web'));
  fs.copyFileSync(path.join(WEB_DIR, 'report.css'), path.join(dir, 'web', 'report.css'));
  fs.copyFileSync(path.join(WEB_DIR, 'index-page.js'), path.join(dir, 'web', 'index-page.js'));
  const indexPath = path.join(dir, 'index.html');
  fs.writeFileSync(indexPath, html);
  return 'file://' + indexPath;
}

module.exports = { renderReport };
