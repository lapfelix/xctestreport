const { test, expect } = require('@playwright/test');
const { renderReport } = require('./renderReport');

const suites = [
  { name: 'LoginTests', tests: [{ name: 'testValidLogin', status: 'passed' }] },
];

test('header note renders under the title when provided', async ({ page }) => {
  await page.goto(await renderReport({ headerNote: 'Branch: feature/new-thing', suites }));

  const note = page.locator('.header-note');
  await expect(note).toHaveText('Branch: feature/new-thing');

  // It must sit between the <h1> title and the rest of the page content.
  const order = await page.evaluate(() => {
    const h1 = document.querySelector('h1');
    const note = document.querySelector('.header-note');
    return h1.compareDocumentPosition(note) & Node.DOCUMENT_POSITION_FOLLOWING ? 'after' : 'before';
  });
  expect(order).toBe('after');
});

test('header note is absent when not provided', async ({ page }) => {
  await page.goto(await renderReport({ suites }));
  await expect(page.locator('.header-note')).toHaveCount(0);
});

test('header note is HTML-escaped', async ({ page }) => {
  await page.goto(await renderReport({ headerNote: 'Branch: <script>x</script> & "more"', suites }));
  await expect(page.locator('.header-note')).toHaveText('Branch: <script>x</script> & "more"');
  // The injected markup must not have created a real <script> element.
  await expect(page.locator('.header-note script')).toHaveCount(0);
});

test('run destinations render as wrapping pills under the title', async ({ page }) => {
  const runDestinationsHTML = '<div class="run-destinations"><span class="run-destinations-label">Destinations</span>'
    + '<ul><li>iPhone 17 Pro · iOS Simulator 27.0 (24A434)</li><li>Apple Watch Series 11 (46mm) · watchOS Simulator 27.0</li></ul></div>';
  await page.setViewportSize({ width: 375, height: 800 });
  await page.goto(await renderReport({ runDestinationsHTML, suites }));
  await expect(page.locator('.run-destinations li')).toHaveText([
    'iPhone 17 Pro · iOS Simulator 27.0 (24A434)',
    'Apple Watch Series 11 (46mm) · watchOS Simulator 27.0',
  ]);
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  expect(overflow).toBe(0);
});

for (const javaScriptEnabled of [true, false]) {
  test(`snapshot navigation appears beside test results (JavaScript ${javaScriptEnabled})`, async ({ browser }) => {
    const context = await browser.newContext({ javaScriptEnabled });
    const page = await context.newPage();
    await page.goto(await renderReport({ suites, snapshotGalleryLinkHTML: '<p class="snapshot-gallery-link"><a href="snapshots.html">Snapshot gallery (6 changed of 6)</a></p>' }));
    const nav = page.locator('.report-nav');
    await expect(nav.getByRole('link')).toHaveText(['Test results', 'Snapshots', 'Markdown']);
    await expect(nav.getByRole('link', { name: 'Snapshots', exact: true })).toHaveAttribute('href', 'snapshots.html');
    await expect(nav.getByRole('link', { name: 'Test results', exact: true })).toHaveAttribute('aria-current', 'page');
    await context.close();
  });
}

test('reports without comparisons do not show a broken snapshots tab', async ({ page }) => {
  await page.goto(await renderReport({ suites }));
  await expect(page.locator('.report-nav').getByRole('link')).toHaveText(['Test results', 'Markdown']);
});
