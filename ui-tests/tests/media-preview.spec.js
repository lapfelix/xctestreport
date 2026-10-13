const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');
const http = require('http');
const zlib = require('zlib');
const { makeBundle } = require('./makeBundle');

const web = path.resolve(__dirname, '../../Sources/xctestreport/Resources/Web');
const template = fs.readFileSync(path.join(web, 'templates/timeline-section.html'), 'utf8');
const plist = Buffer.from('YnBsaXN0MDCpAQIDBAUGBwgJEIAQ/xGAABH//xKAAAAAEv////8T//////////8T/////////4ATf/////////8IEhQWGRwhJi84AAAAAAAAAQEAAAAAAAAACgAAAAAAAAAAAAAAAAAAAEE=', 'base64');

async function serveMedia({ ranges = false, missingBundle = false, inline = false, screenshots = [], runStates,
  entries = [], links = [], screenshotMode = false } = {}) {
  const states = runStates || [{ index: 0, label: 'Run 1', timelineBase: 0, firstEventLabel: 'Hydrated timeline', events: [] }];
  const assets = [
    { name: 'timeline/runstates.json', data: JSON.stringify(states) },
    { name: 'timeline/screenshots.json', data: JSON.stringify(screenshots) },
    ...entries
  ];
  if (ranges) assets.push({ name: 'filler.bin', data: Buffer.alloc(150000, 90), store: true });
  const archive = makeBundle(assets);
  const values = {
    media_mode: screenshotMode ? 'screenshot' : 'none', default_timeline_base: '0', default_video_start: '0',
    run_selector_html: states.length > 1 ? `<select data-run-selector>${states.map((_, index) => `<option value="${index}">Run ${index + 1}</option>`).join('')}</select>` : '',
    run_panels_html: states.map((_, index) => `<div data-run-panel data-run-index="${index}"><div data-active-event>Loading timeline</div>${links.map(link => `<a class="timeline-attachment-link" data-preview-kind="${link.kind}" data-bundle-src="${link.entry}" data-attachment-name="${link.entry.split('/').pop()}">${link.label}</a>`).join('')}</div>`).join(''),
    video_panel_html: screenshotMode ? '<div data-video-index="0"><img data-still-frame alt=""></div>' : '',
    run_states_json: inline ? JSON.stringify(states) : '[]', screenshot_json: inline ? JSON.stringify(screenshots) : '[]',
    run_states_src: 'timeline/runstates.json', screenshot_src: 'timeline/screenshots.json'
  };
  const html = '<!doctype html><html><head><script src="/web/bundle-reader.js"></script></head><body data-report-bundle="detail.zip">' +
    template.replace(/{{(\w+)}}/g, (_, key) => values[key] || '') + '</body></html>';
  const requests = [];
  const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://local').pathname;
    if (url === '/page.html') { res.setHeader('Content-Type', 'text/html'); res.end(html); return; }
    if (url.startsWith('/web/')) {
      const filename = path.join(web, path.basename(url));
      if (fs.existsSync(filename)) { res.setHeader('Content-Type', 'text/javascript'); res.end(fs.readFileSync(filename)); return; }
    }
    if (url === '/detail.zip' && !missingBundle) {
      requests.push(req.headers.range || null);
      const match = ranges && /^bytes=(\d*)-(\d*)$/.exec(req.headers.range || '');
      if (match) {
        const start = match[1] ? Number(match[1]) : Math.max(0, archive.length - Number(match[2]));
        const end = match[1] ? Math.min(Number(match[2]), archive.length - 1) : archive.length - 1;
        res.writeHead(206, { 'Content-Range': `bytes ${start}-${end}/${archive.length}`, 'Content-Type': 'application/zip' });
        res.end(archive.subarray(start, end + 1)); return;
      }
      res.setHeader('Content-Type', 'application/zip'); res.end(archive); return;
    }
    res.writeHead(404); res.end();
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  return { url: `http://127.0.0.1:${server.address().port}/page.html`, requests,
    close: () => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); }) };
}

for (const ranges of [false, true]) {
  test(`previews stored text, gzip text, and binary plists with ${ranges ? 'ranged' : 'whole'} ZIP responses`, async ({ page }) => {
    const expected = 'Only this attachment text';
    const server = await serveMedia({ ranges, entries: [
      { name: 'attachments/small.txt', data: expected, store: true },
      { name: 'attachments/gzip.txt', data: zlib.gzipSync(Buffer.from(expected)), store: true },
      { name: 'attachments/numbers.plist', data: plist, store: true }
    ], links: [
      { entry: 'attachments/small.txt', kind: 'text', label: 'Text attachment' },
      { entry: 'attachments/gzip.txt', kind: 'text', label: 'Gzip attachment' },
      { entry: 'attachments/numbers.plist', kind: 'plist', label: 'Plist attachment' }
    ] });
    try {
      await page.goto(server.url);
      await expect(page.locator('[data-active-event]')).toHaveText('Hydrated timeline');
      for (const label of ['Text attachment', 'Gzip attachment']) {
        await page.getByText(label, { exact: true }).click();
        await expect(page.locator('[data-attachment-text]')).toHaveText(expected);
        await page.locator('button[data-attachment-close]').click();
      }
      await page.getByText('Plist attachment', { exact: true }).click();
      await expect(page.locator('[data-attachment-text]')).toContainText('4294967295');
      await expect(page.locator('[data-attachment-text]')).toContainText('9223372036854775807');
      await page.locator('button[data-attachment-close]').click();
      await expect.poll(() => page.evaluate(() => ReportBundle.open(new URL('detail.zip', location.href).href).cacheStats().pinnedEntries)).toBe(0);
    } finally { await server.close(); }
  });
}

test('renders HTML inside an isolated iframe and downloads the original without opening an active tab', async ({ page }) => {
  const payload = '<p>Attachment HTML</p><script>parent.document.body.dataset.injected="yes"</script>';
  const server = await serveMedia({ entries: [{ name: 'attachments/unsafe.html', data: payload }],
    links: [{ entry: 'attachments/unsafe.html', kind: 'html', label: 'HTML attachment' }] });
  try {
    await page.goto(server.url);
    await page.getByText('HTML attachment', { exact: true }).click();
    await expect(page.frameLocator('[data-attachment-frame]').getByText('Attachment HTML')).toBeVisible();
    expect(await page.locator('[data-attachment-frame]').getAttribute('sandbox')).toBe('');
    expect(await page.evaluate(() => document.body.dataset.injected)).toBeUndefined();
    const downloadPromise = page.waitForEvent('download');
    await page.getByRole('link', { name: 'Download file' }).click();
    expect((await downloadPromise).suggestedFilename()).toBe('unsafe.html');
    await page.locator('button[data-attachment-close]').click();
    const modifierDownload = page.waitForEvent('download');
    await page.locator('.timeline-attachment-link').filter({ hasText: 'HTML attachment' }).click({ modifiers: ['ControlOrMeta'] });
    expect((await modifierDownload).suggestedFilename()).toBe('unsafe.html');
    expect(page.context().pages()).toHaveLength(1);
  } finally { await server.close(); }
});

test('uses complete inline timeline data without fetching duplicate ZIP JSON', async ({ page }) => {
  const server = await serveMedia({ inline: true, screenshots: [['Unused screenshot', 'unused.png', 0, false]] });
  try {
    await page.goto(server.url);
    await expect(page.locator('[data-active-event]')).toHaveText('Hydrated timeline');
    expect(server.requests).toEqual([]);
  } finally { await server.close(); }
});

test('renders UTF-8 JSON attachment text correctly inside the preview iframe', async ({ page }) => {
  const payload = JSON.stringify({ city: 'Montréal', routes: ['Green', 'Orange'], online: false });
  const server = await serveMedia({ entries: [{ name: 'attachments/city.json', data: payload }],
    links: [{ entry: 'attachments/city.json', kind: 'json', label: 'JSON attachment' }] });
  try {
    await page.goto(server.url);
    await page.locator('.timeline-attachment-link').filter({ hasText: 'JSON attachment' }).click();
    await expect(page.frameLocator('[data-attachment-frame]').locator('body')).toContainText('Montréal');
    const contentType = await page.evaluate(async () => {
      const response = await fetch(document.querySelector('[data-attachment-frame]').src);
      return response.headers.get('Content-Type');
    });
    expect(contentType).toBe('application/json; charset=utf-8');
  } finally { await server.close(); }
});

test('shows an actionable timeline error when required ZIP data cannot load', async ({ page }) => {
  const server = await serveMedia({ missingBundle: true });
  try {
    await page.goto(server.url);
    await expect(page.locator('[data-timeline-root] [role=status]')).toContainText('Timeline data could not load');
  } finally { await server.close(); }
});

test('selects screenshots from the active retry and preserves old compact screenshot entries', async ({ page }) => {
  const image = 'data:image/svg+xml,%3Csvg xmlns="http://www.w3.org/2000/svg" width="10" height="10"/%3E';
  const server = await serveMedia({ inline: true, screenshotMode: true,
    runStates: [{ index: 0, timelineBase: 100, events: [] }, { index: 1, timelineBase: 200, events: [] }],
    screenshots: [['First retry', image, 100, false, null, 0], ['Second retry', image, 200, false, null, 1]] });
  try {
    await page.goto(server.url);
    await expect(page.locator('[data-still-frame]')).toHaveAttribute('alt', 'First retry');
    await page.locator('[data-run-selector]').selectOption('1');
    await expect(page.locator('[data-still-frame]')).toHaveAttribute('alt', 'Second retry');
    expect(await page.locator('[data-scrubber]').getAttribute('max')).toBe('0');
  } finally { await server.close(); }
});
