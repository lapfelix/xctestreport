const { test, expect } = require('@playwright/test');
const fs = require('fs');
const http = require('http');
const path = require('path');

const WEB_DIR = path.resolve(__dirname, '..', '..', 'Sources', 'xctestreport', 'Resources', 'Web');

function fill(template, values) {
  return template.replace(/{{\s*(\w+)\s*}}/g, (_, key) => values[key] || '');
}

function indexPage() {
  const rows = [['Alpha', 'failed'], ['Beta', 'passed'], ['Gamma', 'failed'], ['Blocked', 'failed'], ['Stale', 'failed']].map(([name, status]) =>
    `<tr class="${status}" data-status="${status}" data-duration="1"><td><a href="tests/test_${name}().html">test${name}</a></td><td>${status}</td><td data-label="Duration">1s</td></tr>`).join('');
  return fill(fs.readFileSync(path.join(WEB_DIR, 'templates', 'index.html'), 'utf8'), {
    report_title: 'Shell',
    suite_sections_html: `<div class="suite"><h2 class="collapsible"><span class="suite-name">Suite</span></h2>` +
      `<div class="content"><table class="suite-tests-table"><tbody>${rows}</tbody></table></div></div>` +
      `<a id="markdown-link" href="report.md">md</a>`,
  });
}

function testPage(name, other) {
  return fill(fs.readFileSync(path.join(WEB_DIR, 'templates', 'test-detail.html'), 'utf8'), {
    page_title: name,
    test_name: name,
    timeline_and_video_section_html:
      '<video class="timeline-video" preload="none" data-deferred-preload="metadata"><source src="none.mp4" type="video/mp4"></video>',
    failure_nav_html: `<nav class="test-failure-nav"><a class="test-failure-nav-link" rel="next" href="test_${other}().html">next</a></nav>`,
  });
}

let server;
let baseURL;

test.beforeAll(async () => {
  const pages = {
    '/index.html': indexPage(),
    '/tests/test_Alpha().html': testPage('Alpha', 'Beta'),
    '/tests/test_Beta().html': testPage('Beta', 'Alpha'),
    '/tests/test_Gamma().html': testPage('Gamma', 'Alpha'),
    '/report.md': '# report',
    '/tests/test_Blocked().html': testPage('Blocked', 'Alpha'),
    // A test page from an older report whose shell script doesn't know about framing.
    '/tests/test_Stale().html': testPage('Stale', 'Alpha').replace(/<script src="..\/web\/report-shell.js" defer><\/script>/, ''),
  };
  server = http.createServer((req, res) => {
    const url = decodeURIComponent(new URL(req.url, 'http://x').pathname);
    if (pages[url] != null) {
      const headers = { 'Content-Type': url.endsWith('.md') ? 'text/plain' : 'text/html' };
      if (url.includes('Blocked')) headers['X-Frame-Options'] = 'DENY';
      res.writeHead(200, headers);
      return res.end(pages[url]);
    }
    const file = path.join(WEB_DIR, url.replace(/^\/web\//, ''));
    if (url.startsWith('/web/') && fs.existsSync(file)) {
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

const layerOpen = (page) => page.locator('.report-shell-layer.is-open');
const activeFrame = (page) => page.frameLocator('.report-shell-frame.is-active');

test('a test opens over the index without leaving it, and Back returns', async ({ page }) => {
  await page.goto(baseURL + 'index.html');
  await page.locator('#test-search').fill('test');
  await page.getByRole('link', { name: 'testAlpha' }).click();

  await expect(layerOpen(page)).toHaveCount(1);
  await expect(page).toHaveURL(/index\.html#test=tests\/test_Alpha\(\)\.html$/);
  await expect(page).toHaveTitle('Test Detail: Alpha');
  await expect(activeFrame(page).locator('.test-title-compact')).toHaveText('Alpha');

  await activeFrame(page).locator('.test-back-link').click();
  await expect(layerOpen(page)).toHaveCount(0);
  await expect(page).toHaveURL(/index\.html$/);
  await expect(page).toHaveTitle('Test Report');
  // The index kept its state underneath.
  await expect(page.locator('#test-search')).toHaveValue('test');
});

test('hovering a test link preloads its page', async ({ page }) => {
  await page.goto(baseURL + 'index.html');
  await expect(page.locator('.report-shell-frame')).toHaveCount(0);
  await page.getByRole('link', { name: 'testBeta' }).hover();
  await expect(page.locator('.report-shell-frame')).toHaveCount(1);
  await expect(layerOpen(page)).toHaveCount(0);
});

test('preloaded pages hold their videos until shown, and give them up when hidden', async ({ page }) => {
  await page.goto(baseURL + 'index.html');
  await page.getByRole('link', { name: 'testBeta' }).hover();
  const frame = page.frameLocator('.report-shell-frame[src*="Beta"]');
  await expect(frame.locator('video')).toHaveJSProperty('preload', 'none');
  await page.getByRole('link', { name: 'testBeta' }).click();
  await expect(activeFrame(page).locator('video')).toHaveJSProperty('preload', 'metadata');
  await activeFrame(page).locator('.test-back-link').click();
  await expect(frame.locator('video source')).not.toHaveAttribute('src', /./);
  await page.getByRole('link', { name: 'testBeta' }).click();
  await expect(activeFrame(page).locator('video source')).toHaveAttribute('src', 'none.mp4');
});

test('every frame covers the viewport, however many are preloaded', async ({ page }) => {
  await page.goto(baseURL + 'index.html');
  await page.getByRole('link', { name: 'testAlpha' }).hover();
  await expect(page.locator('.report-shell-frame')).toHaveCount(1);
  await page.getByRole('link', { name: 'testBeta' }).hover();
  await expect(page.locator('.report-shell-frame')).toHaveCount(2);
  await page.getByRole('link', { name: 'testBeta' }).click();
  const box = await page.locator('.report-shell-frame.is-active').boundingBox();
  expect(box).toMatchObject({ x: 0, y: 0 });
});

test('the browser Back button closes the test', async ({ page }) => {
  await page.goto(baseURL + 'index.html');
  await page.getByRole('link', { name: 'testAlpha' }).click();
  await expect(layerOpen(page)).toHaveCount(1);
  await page.goBack();
  await expect(layerOpen(page)).toHaveCount(0);
  await page.goForward();
  await expect(layerOpen(page)).toHaveCount(1);
});

const listNav = (page) => activeFrame(page).locator('.test-list-nav');

test('next/previous follow the index list, and Back still goes to the index', async ({ page }) => {
  await page.goto(baseURL + 'index.html');
  await page.getByRole('link', { name: 'testAlpha' }).click();
  await expect(listNav(page).locator('.test-failure-nav-count')).toHaveText('1 of 5');
  // The page's own failure-only links give way to the list.
  await expect(activeFrame(page).locator('.test-failure-nav:not(.test-list-nav)')).toBeHidden();
  await expect(listNav(page).locator('[rel="prev"]')).toHaveCount(0);
  await listNav(page).locator('a[rel="next"]').click();
  await expect(page).toHaveURL(/#test=tests\/test_Beta\(\)\.html$/);
  await expect(activeFrame(page).locator('.test-title-compact')).toHaveText('Beta');
  await expect(listNav(page).locator('.test-failure-nav-count')).toHaveText('2 of 5');
  await page.goBack();
  await expect(layerOpen(page)).toHaveCount(0);
  await expect(page).toHaveURL(/index\.html$/);
});

test('next/previous respect the index filters, and J/K step through them', async ({ page }) => {
  await page.goto(baseURL + 'index.html');
  await page.locator('.status-chip[data-status="failed"]').click();
  await page.getByRole('link', { name: 'testAlpha' }).click();
  await expect(listNav(page).locator('.test-failure-nav-count')).toHaveText('1 of 4Failed');
  await expect(listNav(page).locator('.test-list-nav-filter')).toHaveText('Failed');
  await activeFrame(page).locator('body').press('j');
  // Beta passed, so the Failed filter skips it.
  await expect(activeFrame(page).locator('.test-title-compact')).toHaveText('Gamma');
  await activeFrame(page).locator('body').press('k');
  await expect(activeFrame(page).locator('.test-title-compact')).toHaveText('Alpha');
});

test('neighbouring tests preload, and the index marks the last test viewed', async ({ page }) => {
  await page.goto(baseURL + 'index.html');
  await page.getByRole('link', { name: 'testBeta' }).click();
  await expect(page.locator('.report-shell-frame[src*="Alpha"]')).toHaveCount(1);
  await expect(page.locator('.report-shell-frame[src*="Gamma"]')).toHaveCount(1);
  await activeFrame(page).locator('body').press('j');
  await expect(activeFrame(page).locator('.test-title-compact')).toHaveText('Gamma');
  await activeFrame(page).locator('body').press('Escape');
  await expect(page.locator('tr.is-last-viewed')).toHaveCount(1);
  await expect(page.locator('tr.is-last-viewed')).toContainText('testGamma');
  await expect(page.getByRole('link', { name: 'testGamma' })).toBeFocused();
});

test('clicking anywhere on a row opens its test', async ({ page }) => {
  await page.goto(baseURL + 'index.html');
  await page.locator('tr', { hasText: 'testGamma' }).locator('td[data-label="Duration"]').click();
  await expect(activeFrame(page).locator('.test-title-compact')).toHaveText('Gamma');
});

test('a #test= link opens that test directly, and Escape closes it', async ({ page }) => {
  await page.goto(baseURL + 'index.html#test=tests/test_Beta().html');
  await expect(activeFrame(page).locator('.test-title-compact')).toHaveText('Beta');
  await activeFrame(page).locator('body').press('Escape');
  await expect(layerOpen(page)).toHaveCount(0);
  await expect(page).toHaveURL(/index\.html$/);
});

test('modified clicks and other links keep normal navigation', async ({ page, context }) => {
  await page.goto(baseURL + 'index.html');
  const [popup] = await Promise.all([
    context.waitForEvent('page'),
    page.getByRole('link', { name: 'testAlpha' }).click({ modifiers: [process.platform === 'darwin' ? 'Meta' : 'Control'] }),
  ]);
  await popup.waitForLoadState();
  expect(popup.url()).toMatch(/tests\/test_Alpha\(\)\.html$/);
  await expect(layerOpen(page)).toHaveCount(0);

  await page.locator('#markdown-link').click();
  await expect(page).toHaveURL(/report\.md$/);
});

for (const name of ['Blocked', 'Stale']) {
  test(`a ${name.toLowerCase()} test page falls back to ordinary navigation`, async ({ page }) => {
    await page.goto(baseURL + 'index.html');
    await page.getByRole('link', { name: `test${name}` }).click();
    await expect(page).toHaveURL(new RegExp(`/tests/test_${name}\\(\\)\\.html$`));
    await expect(page.locator('.test-title-compact')).toHaveText(name);
    await page.goBack();
    await expect(page).toHaveURL(/index\.html$/);
    await expect(layerOpen(page)).toHaveCount(0);
  });
}

test('test pages still work on their own', async ({ page }) => {
  await page.goto(baseURL + 'tests/test_Alpha().html');
  await page.locator('.test-back-link').click();
  await expect(page).toHaveURL(/\/index\.html$/);
});
