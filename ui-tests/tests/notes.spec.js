const { test, expect } = require('@playwright/test');
const fs = require('fs');
const http = require('http');
const path = require('path');

const WEB_DIR = path.resolve(__dirname, '..', '..', 'Sources', 'xctestreport', 'Resources', 'Web');

function fill(template, values) {
  return template.replace(/{{\s*(\w+)\s*}}/g, (_, key) => values[key] || '');
}

const NOTES_SCRIPT = (dir) => `<script src="${dir}/notes.js" defer></script>`;

// Mirrors the notes markup ReportGenerator.swift emits on the index.
function indexPage(reportId) {
  const rows = [['Alpha', 'failed'], ['Beta', 'passed']].map(([name, status]) =>
    `<tr class="${status}" data-status="${status}" data-test-id="Suite/test${name}()" data-md="agent-tests.md#Suite_test${name}__" data-duration="1">` +
    `<td><a href="tests/test_Suite_test${name}().html">test${name}()</a></td><td>${status}</td><td data-label="Duration">1s</td></tr>`).join('');
  return fill(fs.readFileSync(path.join(WEB_DIR, 'templates', 'index.html'), 'utf8'), {
    report_title: 'Notes run',
    notes_body_attributes: ` data-report-id="${reportId}" data-report-root="./"`,
    notes_script_html: NOTES_SCRIPT('web'),
    suite_sections_html: `<div class="suite" data-suite="Suite"><h2 class="collapsible"><span class="suite-name">Suite</span><span class="suite-stats">1/2</span></h2>` +
      `<div class="content"><table class="suite-tests-table"><tbody>${rows}</tbody></table></div></div>`,
  });
}

// A stand-in for timeline-view.js: notes.js only relies on window.XCTestReportTimeline.
const FAKE_TIMELINE = `<div data-timeline-root></div><script>
  window.fakeTime = { seconds: 12.4, label: '00:12', absoluteTime: 1012.4, run: 0, runLabel: '', eventId: 'e1', step: 'Tap "OK" Button', section: 'Log in' };
  window.seeks = [];
  window.XCTestReportTimeline = {
    current: function() { return Object.assign({}, window.fakeTime); },
    seek: function(target) { window.seeks.push(target); }
  };
</script>`;

function testPage(reportId, name) {
  return fill(fs.readFileSync(path.join(WEB_DIR, 'templates', 'test-detail.html'), 'utf8'), {
    page_title: name,
    test_name: `test${name}()`,
    duration_text: '1s',
    notes_body_attributes: ` data-report-id="${reportId}" data-report-root="../" data-test-id="Suite/test${name}()" data-test-name="test${name}()" data-test-suite="Suite"`,
    notes_script_html: NOTES_SCRIPT('../web'),
    timeline_and_video_section_html: FAKE_TIMELINE,
  });
}

let server;
let baseURL;

test.beforeAll(async () => {
  const pages = {
    '/a/index.html': indexPage('report-a'),
    '/a/tests/test_Suite_testAlpha().html': testPage('report-a', 'Alpha'),
    '/a/tests/test_Suite_testBeta().html': testPage('report-a', 'Beta'),
    '/b/index.html': indexPage('report-b'),
    '/b/tests/test_Suite_testAlpha().html': testPage('report-b', 'Alpha'),
  };
  server = http.createServer((req, res) => {
    const url = decodeURIComponent(new URL(req.url, 'http://x').pathname);
    if (pages[url] != null) {
      res.writeHead(200, { 'Content-Type': 'text/html' });
      return res.end(pages[url]);
    }
    const asset = url.replace(/^\/[ab]\/web\//, '');
    const file = path.join(WEB_DIR, asset);
    if (asset !== url && fs.existsSync(file)) {
      res.writeHead(200, { 'Content-Type': file.endsWith('.css') ? 'text/css' : 'text/javascript' });
      return res.end(fs.readFileSync(file));
    }
    res.writeHead(404);
    res.end();
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  baseURL = `http://127.0.0.1:${server.address().port}/`;
});

test.afterAll(async () => {
  server.closeAllConnections();
  await new Promise((resolve) => server.close(resolve));
});

test.use({ permissions: ['clipboard-read', 'clipboard-write'] });

const activeFrame = (page) => page.frameLocator('.report-shell-frame.is-active');
const clipboard = (page) => page.evaluate(() => navigator.clipboard.readText());

async function addNote(scope, text) {
  await scope.locator('.notes-input').fill(text);
  await scope.locator('.notes-add').click();
}

test('timed and untimed notes on a test, in playback order, kept across reloads', async ({ page }) => {
  await page.goto(baseURL + 'a/tests/test_Suite_testAlpha().html');
  const button = page.locator('.note-btn-header');
  await expect(button).not.toHaveClass(/has-notes/);
  await button.click();

  const toggle = page.locator('.notes-time-toggle');
  await expect(toggle.locator('input')).toBeChecked();
  await expect(toggle).toContainText('Add current time (00:12 · Tap "OK" Button)');

  await addNote(page, 'second by time');
  await page.evaluate(() => { window.fakeTime = Object.assign({}, window.fakeTime, { seconds: 3, label: '00:03', eventId: 'e0', step: 'Launch' }); });
  await addNote(page, 'first by time');
  await toggle.locator('input').uncheck();
  await page.locator('.notes-input').fill('untimed');
  await page.locator('.notes-input').press('Control+Enter');

  const items = page.locator('.notes-item');
  await expect(items).toHaveCount(3);
  await expect(items.nth(0)).toContainText('00:03');
  await expect(items.nth(0)).toContainText('first by time');
  await expect(items.nth(1)).toContainText('00:12');
  await expect(items.nth(2)).toContainText('untimed');
  await expect(items.nth(2).locator('.notes-item-time')).toHaveCount(0);
  await expect(button).toHaveAttribute('title', 'Notes on this test (3 notes)');

  await items.nth(1).locator('.notes-item-time').click();
  expect(await page.evaluate(() => window.seeks)).toEqual([
    expect.objectContaining({ eventId: 'e1', absoluteTime: 1012.4, run: 0 }),
  ]);

  await page.reload();
  await page.locator('.note-btn-header').click();
  await expect(page.locator('.notes-item')).toHaveCount(3);
  // The unchecked box is remembered.
  await expect(page.locator('.notes-time-toggle input')).not.toBeChecked();
});

test('notes can be edited and deleted', async ({ page }) => {
  await page.goto(baseURL + 'a/tests/test_Suite_testBeta().html');
  await page.locator('.note-btn-header').click();
  await addNote(page, 'draft');
  const item = page.locator('.notes-item');
  await item.hover();
  await item.getByRole('button', { name: 'Edit' }).click();
  await page.locator('.notes-edit-input').fill('final');
  await page.locator('.notes-edit-input').press('Meta+Enter');
  await expect(item.locator('.notes-item-text')).toHaveText('final');
  await item.hover();
  await item.getByRole('button', { name: 'Delete' }).click();
  await expect(page.locator('.notes-item')).toHaveCount(0);
  await expect(page.locator('.note-btn-header')).not.toHaveClass(/has-notes/);
});

test('suite notes from the index, without collapsing the suite or offering a time', async ({ page }) => {
  await page.goto(baseURL + 'a/index.html');
  await expect(page.locator('.notes-export')).toBeHidden();
  await page.locator('.suite h2').hover();
  await page.locator('.note-btn-suite').click();
  await expect(page.locator('.suite h2')).not.toHaveClass(/collapsed/);
  await expect(page.locator('.notes-time-toggle')).toBeHidden();
  await addNote(page, 'whole suite note');
  await page.locator('.notes-input').press('Escape');
  await expect(page.locator('.notes-panel')).toBeHidden();
  await expect(page.locator('.note-btn-suite .note-btn-count')).toHaveText('1');
  await expect(page.locator('.notes-export')).toBeVisible();
});

test('notes added on a framed test page show up on the index right away', async ({ page }) => {
  await page.goto(baseURL + 'a/index.html');
  await page.getByRole('link', { name: 'testAlpha()' }).click();
  const frame = activeFrame(page);
  await frame.locator('.note-btn-header').click();
  await addNote(frame, 'from the framed page');
  await expect(page.locator('tr[data-test-id="Suite/testAlpha()"] .note-glyph')).toHaveAttribute('title', '1 note');
  await expect(page.locator('tr[data-test-id="Suite/testBeta()"] .note-glyph')).toHaveCount(0);
  // Escape in the panel closes the panel, not the test.
  await frame.locator('.notes-input').press('Escape');
  await expect(frame.locator('.notes-panel')).toBeHidden();
  await expect(page.locator('.report-shell-layer.is-open')).toHaveCount(1);
  // The footnote's link back to the list closes the test rather than reloading the index.
  await frame.locator('.note-btn-header').click();
  await frame.getByRole('link', { name: 'Test results' }).click();
  await expect(page.locator('.report-shell-layer.is-open')).toHaveCount(0);
  await expect(page.locator('.notes-export')).toBeVisible();
});

test('Copy all notes gives Markdown with links back to each test; JSON and downloads too', async ({ page }) => {
  await page.goto(baseURL + 'a/tests/test_Suite_testAlpha().html');
  await page.locator('.note-btn-header').click();
  await addNote(page, 'wait on the sheet\ninstead of sleeping');
  await page.goto(baseURL + 'a/index.html');
  await page.locator('.suite h2').hover();
  await page.locator('.note-btn-suite').click();
  await addNote(page, 'suite-wide');

  await page.locator('.notes-copy').click();
  await expect(page.locator('.notes-copy')).toHaveText('Copied');
  const markdown = await clipboard(page);
  const root = baseURL + 'a/';
  expect(markdown).toContain('# Review notes: Notes run');
  expect(markdown).toContain(`Report: ${root}index.html`);
  expect(markdown).toContain('## Suite Suite\n\n- suite-wide');
  expect(markdown).toContain('## Suite/testAlpha() (Failed)');
  expect(markdown).toContain(`Page: ${root}tests/test_Suite_testAlpha().html`);
  expect(markdown).toContain(`Details: ${root}agent-tests.md#Suite_testAlpha__`);
  expect(markdown).toContain(`Bundle: ${root}tests/test_Suite_testAlpha().zip`);
  expect(markdown).toContain('- **00:12** (Log in › Tap "OK" Button): wait on the sheet\n  instead of sleeping');
  expect(markdown).not.toContain('testBeta');

  await page.locator('.notes-export-more').click();
  await page.getByRole('menuitem', { name: 'Copy as JSON' }).click();
  const json = JSON.parse(await clipboard(page));
  expect(json.report).toMatchObject({ id: 'report-a', url: `${root}index.html` });
  expect(json.suites[0].notes[0].text).toBe('suite-wide');
  expect(json.suites[0].tests[0]).toMatchObject({
    id: 'Suite/testAlpha()',
    status: 'Failed',
    pageURL: `${root}tests/test_Suite_testAlpha().html`,
    notes: [expect.objectContaining({ time: expect.objectContaining({ label: '00:12', step: 'Tap "OK" Button' }) })],
  });

  for (const [item, fileName] of [['Download Markdown', 'notes-report-a.md'], ['Download JSON', 'notes-report-a.json']]) {
    await page.locator('.notes-export-more').click();
    const [download] = await Promise.all([page.waitForEvent('download'), page.getByRole('menuitem', { name: item }).click()]);
    expect(download.suggestedFilename()).toBe(fileName);
  }
});

test('reports on the same host keep separate notes', async ({ page }) => {
  await page.goto(baseURL + 'a/tests/test_Suite_testAlpha().html');
  await page.locator('.note-btn-header').click();
  await addNote(page, 'only in report a');
  await page.goto(baseURL + 'b/tests/test_Suite_testAlpha().html');
  await page.locator('.note-btn-header').click();
  await expect(page.locator('.notes-item')).toHaveCount(0);
  await page.goto(baseURL + 'b/index.html');
  await expect(page.locator('.notes-export')).toBeHidden();
});

test('a storage failure is reported and the typed note is kept', async ({ page }) => {
  await page.addInitScript(() => {
    Storage.prototype.setItem = function() { throw new DOMException('full', 'QuotaExceededError'); };
  });
  await page.goto(baseURL + 'a/tests/test_Suite_testAlpha().html');
  await page.locator('.note-btn-header').click();
  await addNote(page, 'do not lose me');
  await expect(page.locator('.notes-error')).toContainText('unavailable or full');
  await expect(page.locator('.notes-input')).toHaveValue('do not lose me');
  await expect(page.locator('.notes-item')).toHaveCount(0);
});
