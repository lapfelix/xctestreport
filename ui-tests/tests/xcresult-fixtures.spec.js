const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');
const { serveDirectory } = require('./serveDirectory');

const fixtureRoot = process.env.XCTESTREPORT_REAL_FIXTURES;
if (process.env.CI && !fixtureRoot) throw new Error('CI must set XCTESTREPORT_REAL_FIXTURES to verified actual xcresult reports.');
const canonical = identifier => {
  const [suite, method] = identifier.split('/').slice(-2);
  return `${suite.split('.').pop()}/${method}`;
};
const walk = nodes => nodes.flatMap(node => [node, ...walk(node.children || [])]);
const json = name => JSON.parse(fs.readFileSync(path.join(fixtureRoot, name), 'utf8'));

test.describe('actual xcresult fixture reports', () => {
  test.skip(!fixtureRoot, 'Run Scripts/test-real-fixtures.sh and set XCTESTREPORT_REAL_FIXTURES.');
  let server;
  test.beforeAll(async () => {
    for (const plan of ['Baseline', 'Mixed']) {
      for (const name of [`${plan}.tests.json`, `${plan}.summary.json`, `${plan}.media.json`, `reports/${plan.toLowerCase()}/index.html`, `reports/${plan.toLowerCase()}/snapshots.json`]) {
        if (!fs.existsSync(path.join(fixtureRoot, name))) throw new Error(`Missing actual fixture artifact: ${name}`);
      }
    }
    server = await serveDirectory(path.join(fixtureRoot, 'reports'));
  });
  test.afterAll(async () => { if (server) await server.close(); });

  async function openTest(page, key, plan = 'mixed') {
    await page.goto(server.url + plan + '/index.html');
    const href = await page.locator('tr[data-test-id]').evaluateAll((rows, identity) => {
      const canonicalID = id => {
        const [suite, method] = id.split('/').slice(-2);
        return `${suite.split('.').pop()}/${method}`;
      };
      return rows.find(row => canonicalID(row.dataset.testId) === identity)?.querySelector('a[href^="tests/"]')?.getAttribute('href');
    }, key);
    expect(href, `Index link for ${key}`).toMatch(/^tests\/[^/]+\.html$/);
    await page.goto(new URL(href, server.url + plan + '/').href);
    await expect.poll(() => page.locator('body').getAttribute('data-report-bundle')).toMatch(/\.zip$/);
  }

  for (const plan of ['Baseline', 'Mixed']) {
    test(`${plan} displays source outcomes, expected failures and parameterized/retry status`, async ({ page }) => {
      const cases = walk(json(`${plan}.tests.json`).testNodes).filter(node => node.nodeType === 'Test Case');
      const failures = cases.filter(node => node.result === 'Failed').map(node => canonical(node.nodeIdentifier)).sort();
      await page.goto(server.url + plan.toLowerCase() + '/index.html');
      const rows = await page.locator('tr[data-test-id]').evaluateAll(nodes => nodes.map(node => ({ id: node.dataset.testId, status: node.dataset.status, flaky: node.dataset.flaky === 'true' })));
      expect(rows.map(row => canonical(row.id)).sort()).toEqual(cases.map(node => canonical(node.nodeIdentifier)).sort());
      expect(rows.filter(row => row.status === 'failed').map(row => canonical(row.id)).sort()).toEqual(failures);
      expect(rows.find(row => canonical(row.id) === 'OutcomeTests/testExpectedFailure()').status).toBe('passed');
      expect(rows.find(row => canonical(row.id) === 'ModernTests/fares(category:)').flaky).toBe(false);
      expect(rows.filter(row => row.flaky).map(row => canonical(row.id))).toEqual(plan === 'Mixed' ? ['OutcomeTests/testFailsOnceThenPasses()'] : []);
      if (failures.length) {
        await page.locator('.status-chip[data-status="failed"]').click();
        await expect(page.locator('tr[data-test-id]:visible')).toHaveCount(failures.length);
      }
    });
  }

  test('bundled opaque/empty/duplicate payloads and genuine JSON/plist previews survive regeneration', async ({ page }) => {
    const key = 'ActivityTests/testNestedActivitiesAndAttachments()';
    await openTest(page, key);
    await page.getByRole('button', { name: 'Expand all', exact: true }).click();
    const manifest = json('reports/mixed/attachments/manifest.json').find(entry => canonical(entry.testIdentifier) === key);
    const attachmentName = item => item.suggestedHumanReadableName.replace(/_\d+_[0-9a-f-]{36}(?=\.[^.]+$|$)/gi, '');
    const entries = manifest.attachments.filter(item => ['opaque.bin', 'empty.txt', 'duplicate-name.txt'].includes(attachmentName(item)));
    const content = await page.evaluate(async names => {
      const bundle = ReportBundle.open(new URL(document.body.dataset.reportBundle, location.href).href);
      return Promise.all(names.map(async name => ({ name, bytes: Array.from(await bundle.bytes('attachments/' + name)) })));
    }, entries.map(item => item.exportedFileName));
    const values = name => entries.filter(item => attachmentName(item) === name).map(item => Buffer.from(content.find(value => value.name === item.exportedFileName).bytes));
    expect(values('empty.txt')[0]).toEqual(Buffer.alloc(0));
    expect(values('opaque.bin')[0]).toEqual(Buffer.from([0, 1, 2, 127, 128, 254, 255]));
    expect(values('duplicate-name.txt').map(value => value.toString()).sort()).toEqual(['nested payload one', 'nested payload two']);
    for (const [name, text] of [['response.json', 'Montréal'], ['route-state.plist', 'Green'], ['route-state-xml.plist', 'Green']]) {
      await page.locator('.timeline-attachment-link').filter({ hasText: name }).first().click();
      await expect(page.locator('[data-attachment-text]')).toContainText(text);
      await page.locator('.attachment-preview-close').click();
    }
    for (const [title, expected] of [['Decode → validate → render', 'nested payload one'], ['Finish journey', 'nested payload two']]) {
      const step = page.locator('.timeline-title').filter({ hasText: title }).first().locator('xpath=ancestor::li[contains(@class,"timeline-node")][1]');
      await step.locator(':scope > .timeline-attachments .timeline-attachment-link, :scope > details > .timeline-attachments .timeline-attachment-link').filter({ hasText: 'duplicate-name.txt' }).click();
      await expect(page.locator('[data-attachment-text]')).toHaveText(expected);
      await page.locator('.attachment-preview-close').click();
    }
  });

  test('real retry controls select the recovered run and preserve prior-run history', async ({ page }) => {
    const key = 'OutcomeTests/testFailsOnceThenPasses()';
    const cached = json('reports/mixed/test_details.json');
    const details = Object.entries(cached).find(([identifier]) => canonical(identifier) === key)[1];
    await openTest(page, key);
    await expect(page.locator('[data-run-selector] option')).toHaveCount(details.testRuns.length);
    await page.locator('[data-run-selector]').selectOption('1');
    await expect(page.locator('[data-run-panel]:visible')).toContainText('Connection attempt 2');
    await expect(page.locator('.previous-runs-table')).toContainText('Passed');
    await page.goto(server.url + 'mixed/index.html');
    await expect(page.locator('body')).toContainText(`Newly failing (${json('Mixed.summary.json').failedTests})`);
  });

  test('actual UI recordings stream by ranges and video-only/combined tests keep their media', async ({ page }) => {
    for (const key of ['JourneyUITests/testSearchRoutes()', 'JourneyUITests/testPinRoute()']) {
      await openTest(page, key);
      await expect(page.locator('video.timeline-video').first()).toBeAttached();
      const source = await page.locator('video.timeline-video source').first().getAttribute('src');
      const response = await page.request.get(new URL(source, page.url()).href, { headers: { Range: 'bytes=0-31' } });
      expect(response.status()).toBe(206);
      expect(response.headers()['content-range']).toMatch(/^bytes 0-31\/\d+$/);
      expect((await response.body()).length).toBe(32);
      const screenshots = await page.evaluate(async () => {
        const bundle = ReportBundle.open(new URL(document.body.dataset.reportBundle, location.href).href);
        return JSON.parse(await bundle.text('timeline/screenshots.json'));
      });
      expect(screenshots.length > 0).toBe(key.includes('testPinRoute'));
    }
    await openTest(page, 'OutcomeTests/testPassingAssertion()');
    await expect(page.locator('video, [data-still-frame], .snapshot-diffs')).toHaveCount(0);
  });

  test('real snapshots expose aliases, matched/changed images, resizing and supplied diffs', async ({ page }) => {
    const snapshots = json('reports/mixed/snapshots.json');
    const comparisons = snapshots.tests.flatMap(entry => entry.comparisons);
    await page.goto(server.url + 'mixed/snapshots.html');
    for (const comparison of comparisons) {
      await page.getByRole('button', { name: `Inspect ${comparison.name}`, exact: true }).click();
      await expect(page.locator('.snapdiff-name')).toHaveText(comparison.name);
      await expect.poll(() => page.locator('.snapdiff-layer-expected').first().evaluate(image => image.complete && image.naturalWidth > 0)).toBe(true);
      if (comparison.sizeMismatch) {
        await expect(page.locator('.snapdiff-sizebanner')).toContainText(String(comparison.widthDelta));
        await expect(page.locator('.snapdiff-sizebanner')).toContainText(String(comparison.heightDelta));
      }
      await page.keyboard.press('Escape');
    }
    await page.locator('#sg-failed-only').click();
    await expect(page.locator('.sg-item').filter({ hasText: 'testMatchingCardWithoutAttachments' })).toContainText('Passed');
    await page.goto(server.url + 'baseline/snapshots.html');
    await expect(page.locator('.sg-badge-matched')).toHaveCount(json('reports/baseline/snapshots.json').totalComparisons);
  });

  test('real Swift Testing diagnostics retain Unicode and escaped markup', async ({ page }) => {
    await openTest(page, 'ModernTests/modernAssertion()');
    await expect(page.locator('.test-error-box')).toContainText('Montréal → Downtown <rail> & bus');
    expect(await page.locator('.test-error-box rail').count()).toBe(0);
  });
});
