const { test, expect } = require('@playwright/test');
const { renderReport } = require('./renderReport');

const suites = [
  {
    name: 'LoginTests',
    tests: [
      { name: 'testValidLogin', status: 'passed' },
      { name: 'testInvalidLogin', status: 'failed' },
      { name: 'testSkippedLogin', status: 'skipped' },
    ],
  },
  {
    name: 'AllGreenTests',
    tests: [
      { name: 'testA', status: 'passed' },
      { name: 'testB', status: 'passed' },
    ],
  },
];

async function reportURL() {
  return renderReport({ suites });
}

test('filter button is present with the default label', async ({ page }) => {
  await page.goto(await reportURL());
  await expect(page.locator('#toggle-failed')).toHaveText('Show only failed');
});

test('clicking the filter hides passed and skipped tests, and all-passing suites', async ({ page }) => {
  await page.goto(await reportURL());

  // Everything visible up front.
  await expect(page.locator('tr.failed:visible')).toHaveCount(1);
  await expect(page.locator('.suite-tests-table tbody tr:visible')).toHaveCount(5);
  await expect(page.locator('.suite:visible')).toHaveCount(2);

  await page.locator('#toggle-failed').click();

  // Only the single failed row remains; the all-passing suite is hidden.
  await expect(page.locator('.suite-tests-table tbody tr:visible')).toHaveCount(1);
  await expect(page.locator('tr.failed:visible')).toHaveCount(1);
  await expect(page.locator('tr:visible', { hasText: 'testValidLogin' })).toHaveCount(0);
  await expect(page.locator('tr:visible', { hasText: 'testSkippedLogin' })).toHaveCount(0);
  await expect(page.locator('.suite:visible')).toHaveCount(1);
  await expect(page.locator('#toggle-failed')).toHaveText('Show all tests');
});

test('toggling the filter off restores every test and suite', async ({ page }) => {
  await page.goto(await reportURL());

  const filter = page.locator('#toggle-failed');
  await filter.click();
  await filter.click();

  await expect(page.locator('.suite-tests-table tbody tr:visible')).toHaveCount(5);
  await expect(page.locator('.suite:visible')).toHaveCount(2);
  await expect(filter).toHaveText('Show only failed');
});
