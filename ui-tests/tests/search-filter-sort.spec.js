const { test, expect } = require('@playwright/test');
const { renderReport } = require('./renderReport');

const suites = [
  {
    name: 'LoginTests',
    tests: [
      { name: 'testValidLogin', status: 'passed', duration: 3 },
      { name: 'testInvalidLogin', status: 'failed', duration: 10 },
      { name: 'testSkippedLogin', status: 'skipped', duration: 1 },
    ],
  },
  {
    name: 'AllGreenTests',
    tests: [
      { name: 'testAlpha', status: 'passed', duration: 2 },
      { name: 'testBeta', status: 'passed', duration: 7 },
    ],
  },
];

async function reportURL() {
  return renderReport({ suites });
}

test('status chips render, all on by default', async ({ page }) => {
  await page.goto(await reportURL());
  await expect(page.locator('.status-chip')).toHaveCount(3);
  await expect(page.locator('.status-chip[aria-pressed="true"]')).toHaveCount(3);
  await expect(page.locator('.suite-tests-table tbody tr:visible')).toHaveCount(5);
  await expect(page.locator('.suite:visible')).toHaveCount(2);
});

test('disabling Passed and Skipped chips leaves only the failed row', async ({ page }) => {
  await page.goto(await reportURL());
  await page.locator('.status-chip[data-status="passed"]').click();
  await page.locator('.status-chip[data-status="skipped"]').click();

  await expect(page.locator('.suite-tests-table tbody tr:visible')).toHaveCount(1);
  await expect(page.locator('tr.failed:visible')).toHaveCount(1);
  await expect(page.locator('tr:visible', { hasText: 'testValidLogin' })).toHaveCount(0);
  await expect(page.locator('.suite:visible')).toHaveCount(1);
});

test('search filters rows by name and hides empty suites', async ({ page }) => {
  await page.goto(await reportURL());
  await page.locator('#test-search').fill('alpha');

  await expect(page.locator('.suite-tests-table tbody tr:visible')).toHaveCount(1);
  await expect(page.locator('tr:visible', { hasText: 'testAlpha' })).toHaveCount(1);
  await expect(page.locator('.suite:visible')).toHaveCount(1);
  await expect(page.locator('#no-match')).toBeHidden();
});

test('search with no matches shows the empty-state line', async ({ page }) => {
  await page.goto(await reportURL());
  await page.locator('#test-search').fill('zzzzz');

  await expect(page.locator('.suite-tests-table tbody tr:visible')).toHaveCount(0);
  await expect(page.locator('.suite:visible')).toHaveCount(0);
  await expect(page.locator('#no-match')).toBeVisible();
});

test('search and chips compose with AND', async ({ page }) => {
  await page.goto(await reportURL());
  await page.locator('#test-search').fill('test');
  await page.locator('.status-chip[data-status="passed"]').click();
  await page.locator('.status-chip[data-status="skipped"]').click();

  await expect(page.locator('.suite-tests-table tbody tr:visible')).toHaveCount(1);
  await expect(page.locator('tr.failed:visible')).toHaveCount(1);
});

test('clicking the Duration header sorts a suite desc, then asc, then original', async ({ page }) => {
  await page.goto(await reportURL());
  const suite = page.locator('.suite', { hasText: 'LoginTests' });
  const header = suite.locator('th.sortable-duration');
  const names = suite.locator('tbody tr td:first-child');

  await expect(names).toHaveText(['testValidLogin', 'testInvalidLogin', 'testSkippedLogin']);

  await header.click(); // desc by duration: 10, 3, 1
  await expect(names).toHaveText(['testInvalidLogin', 'testValidLogin', 'testSkippedLogin']);

  await header.click(); // asc by duration: 1, 3, 10
  await expect(names).toHaveText(['testSkippedLogin', 'testValidLogin', 'testInvalidLogin']);

  await header.click(); // back to original order
  await expect(names).toHaveText(['testValidLogin', 'testInvalidLogin', 'testSkippedLogin']);
});

test('slowest-tests lists the top tests by duration', async ({ page }) => {
  await page.goto(await reportURL());
  const items = page.locator('#slowest-tests ol li a');
  await expect(items.first()).toHaveText('testInvalidLogin'); // 10s is slowest
  await expect(items.nth(1)).toHaveText('testBeta'); // 7s next
});
