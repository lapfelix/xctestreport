const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');
const { serveDirectory } = require('./serveDirectory');

const reportDirectory = process.env.XCTESTREPORT_GENERATED_REPORT;
if (process.env.CI && !reportDirectory) throw new Error('CI must set XCTESTREPORT_GENERATED_REPORT to a production-generated report.');

test.describe('production-generated report', () => {
  test.skip(!reportDirectory, 'Generate a report with Scripts/test-installed-report.sh and set XCTESTREPORT_GENERATED_REPORT.');
  let server;
  test.beforeAll(async () => {
    for (const file of ['index.html', 'snapshots.html']) {
      if (!fs.existsSync(path.join(reportDirectory, file))) throw new Error(`Missing generated report fixture: ${file}`);
    }
    expect(fs.readdirSync(path.join(reportDirectory, 'tests')).filter(name => name.endsWith('.zip'))).toHaveLength(2);
    server = await serveDirectory(reportDirectory);
  });
  test.afterAll(async () => { if (server) await server.close(); });

  test('real index opens real detail pages and returns with Back', async ({ page }) => {
    await page.goto(server.url + 'index.html');
    await expect(page.locator('.header-note')).toHaveText('Production renderer fixture');
    await page.getByRole('link', { name: 'testSnapshot()', exact: true }).click();
    const detail = page.frameLocator('.report-shell-frame.is-active');
    await expect(detail.locator('.test-title-compact')).toHaveText('testSnapshot()');
    await expect(detail.locator('.test-error-box')).toContainText('Snapshot differs from its reference.');
    await detail.locator('.test-back-link').click();
    await expect(page.locator('.report-shell-layer.is-open')).toHaveCount(0);
    await expect(page).toHaveURL(server.url + 'index.html');
  });

  test('shipping ZIP writer and browser reader agree on Markdown and image bytes', async ({ page }) => {
    await page.goto(server.url + 'index.html');
    const detailPath = await page.getByRole('link', { name: 'testSnapshot()', exact: true }).getAttribute('href');
    expect(detailPath).toMatch(/^tests\/[^/]+\.html$/);
    await page.goto(new URL(detailPath, server.url).href);
    const expectedBytes = fs.readFileSync(path.join(__dirname, '../fixtures/snapshots/NearbyRow-pinned.actual.png'));
    const contents = await page.evaluate(async () => {
      const bundle = ReportBundle.open(new URL(document.body.dataset.reportBundle, location.href).href);
      return { markdown: await bundle.text('test.md'), image: Array.from(await bundle.bytes('attachments/3.png')) };
    });
    expect(contents.markdown).toContain('SmokeTests/testSnapshot()');
    expect(contents.markdown).toContain('Snapshot differs from its reference.');
    expect(Buffer.from(contents.image)).toEqual(expectedBytes);
  });

  test('real snapshot gallery can inspect the generated comparison', async ({ page }) => {
    await page.goto(server.url + 'snapshots.html');
    await page.getByRole('button', { name: 'Inspect Card', exact: true }).click();
    await expect(page.locator('.snapdiff-stage')).toBeVisible();
    await expect(page.locator('.snapdiff-name')).toHaveText('Card');
    await expect.poll(() => page.locator('.snapdiff-layer-expected').first().evaluate(image => image.complete && image.naturalWidth > 0)).toBe(true);
  });
});
