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

test('status chips are "show only" filters, none selected by default', async ({ page }) => {
  await page.goto(await reportURL());
  await expect(page.locator('#status-chips-label')).toHaveText('Show only:');
  await expect(page.getByRole('group', { name: 'Show only:' })).toBeVisible();
  await expect(page.locator('.status-chip:visible')).toHaveCount(3);
  await expect(page.locator('.status-chip[aria-pressed="true"]')).toHaveCount(0);
  // The Flaky chip only shows when some row is flaky.
  await expect(page.locator('.flaky-chip')).toBeHidden();
  await expect(page.locator('.suite-tests-table tbody tr:visible')).toHaveCount(5);
  await expect(page.locator('.suite:visible')).toHaveCount(2);
});

test('the Flaky chip appears for flaky rows and narrows to them', async ({ page }) => {
  const withFlaky = suites.map((suite) => ({
    ...suite,
    tests: suite.tests.map((t) => (t.name === 'testBeta' ? { ...t, flaky: true } : t)),
  }));
  await page.goto(renderReport({ suites: withFlaky }));
  const flaky = page.locator('.flaky-chip');
  await expect(flaky).toBeVisible();
  await expect(flaky).toHaveAttribute('aria-pressed', 'false');
  await flaky.click();
  await expect(page.locator('.suite-tests-table tbody tr:visible')).toHaveCount(1);
  await expect(page.locator('tr:visible', { hasText: 'testBeta' })).toHaveCount(1);
  await expect(page.locator('.suite:visible')).toHaveCount(1);
  await flaky.click();
  await expect(page.locator('.suite-tests-table tbody tr:visible')).toHaveCount(5);
});

test('selecting several chips shows the union', async ({ page }) => {
  const withFlaky = suites.map((suite) => ({
    ...suite,
    tests: suite.tests.map((t) => (t.name === 'testBeta' ? { ...t, flaky: true } : t)),
  }));
  await page.goto(renderReport({ suites: withFlaky }));
  await page.locator('.status-chip[data-status="failed"]').click();
  await expect(page.locator('.suite-tests-table tbody tr:visible')).toHaveCount(1);
  await page.locator('.flaky-chip').click();
  await expect(page.locator('.suite-tests-table tbody tr:visible')).toHaveCount(2);
  await expect(page.locator('tr:visible', { hasText: 'testBeta' })).toHaveCount(1);
  await expect(page.locator('tr.failed:visible')).toHaveCount(1);
  await page.locator('.status-chip[data-status="failed"]').click();
  await page.locator('.flaky-chip').click();
  await expect(page.locator('.suite-tests-table tbody tr:visible')).toHaveCount(5);
});

test('durations use the compact format', async ({ page }) => {
  await page.goto(renderReport({ suites: [{ name: 'TimingTests', tests: [
    { name: 'testLong', status: 'passed', duration: 219 },
    { name: 'testMedium', status: 'passed', duration: 12.3 },
    { name: 'testShort', status: 'passed', duration: 0.006 },
  ] }] }));
  await expect(page.locator('td[data-label="Duration"]')).toHaveText(['3m 39s', '12.3s', '6ms']);
});

test('selecting Failed leaves only the failed row', async ({ page }) => {
  await page.goto(await reportURL());
  await page.locator('.status-chip[data-status="failed"]').click();
  await expect(page.locator('.status-chip[data-status="failed"]')).toHaveAttribute('aria-pressed', 'true');

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
  await page.locator('.status-chip[data-status="failed"]').click();

  await expect(page.locator('.suite-tests-table tbody tr:visible')).toHaveCount(1);
  await expect(page.locator('tr.failed:visible')).toHaveCount(1);
});

test('clicking the Duration header sorts a suite desc, then asc, then original', async ({ page }) => {
  await page.goto(await reportURL());
  const suite = page.locator('.suite', { hasText: 'LoginTests' });
  const header = suite.locator('th.sortable-duration');
  const button = header.getByRole('button', { name: 'Duration' });
  const names = suite.locator('tbody tr td:first-child');

  await expect(names).toHaveText(['testValidLogin', 'testInvalidLogin', 'testSkippedLogin']);
  await expect(header).toHaveAttribute('aria-sort', 'none');

  await button.click(); // desc by duration: 10, 3, 1
  await expect(names).toHaveText(['testInvalidLogin', 'testValidLogin', 'testSkippedLogin']);
  await expect(header).toHaveAttribute('aria-sort', 'descending');

  await button.click(); // asc by duration: 1, 3, 10
  await expect(names).toHaveText(['testSkippedLogin', 'testValidLogin', 'testInvalidLogin']);
  await expect(header).toHaveAttribute('aria-sort', 'ascending');

  await button.press('Enter'); // back to original order, from the keyboard
  await expect(names).toHaveText(['testValidLogin', 'testInvalidLogin', 'testSkippedLogin']);
  await expect(header).toHaveAttribute('aria-sort', 'none');
});

test('slowest-tests lists the top tests by duration', async ({ page }) => {
  await page.goto(await reportURL());
  const items = page.locator('#slowest-tests ol li a');
  await expect(items.first()).toHaveText('testInvalidLogin'); // 10s is slowest
  await expect(items.nth(1)).toHaveText('testBeta'); // 7s next
});

test('review failures clears search and opens only failing suites', async ({page}) => {
  await page.goto(renderReport({suites}));
  await page.locator('#toggle-all').click();
  await page.locator('#test-search').fill('nothing');
  await page.getByRole('button',{name:'Review failures',exact:true}).click();
  await expect(page.locator('#test-search')).toHaveValue('');
  await expect(page.locator('tr[data-status="passed"]:visible')).toHaveCount(0);
  await expect(page.locator('tr[data-status="failed"]:visible')).toHaveCount(1);
});

test('suite headings can be collapsed and expanded with the keyboard', async ({page}) => {
  await page.goto(renderReport({suites}));
  const head=page.locator('.collapsible').first();
  await head.focus(); await page.keyboard.press('Enter');
  await expect(head).toHaveAttribute('aria-expanded','false');
  await page.keyboard.press('Space');
  await expect(head).toHaveAttribute('aria-expanded','true');
});

test('chips show how many tests they match', async ({ page }) => {
  await page.goto(await reportURL());
  await expect(page.locator('.status-chip[data-status="passed"] .status-chip-count')).toHaveText('3');
  await expect(page.locator('.status-chip[data-status="failed"] .status-chip-count')).toHaveText('1');
  await expect(page.locator('.status-chip[data-status="skipped"] .status-chip-count')).toHaveText('1');
});

test('slash focuses search, Escape clears it, and J/K move through visible tests', async ({ page }) => {
  await page.goto(await reportURL());
  await page.keyboard.press('/');
  await expect(page.locator('#test-search')).toBeFocused();
  await page.keyboard.type('login');
  await expect(page.locator('.suite-tests-table tbody tr:visible')).toHaveCount(3);
  await page.keyboard.press('Escape');
  await expect(page.locator('#test-search')).toHaveValue('');
  await expect(page.locator('.suite-tests-table tbody tr:visible')).toHaveCount(5);

  await page.locator('.status-chip[data-status="passed"]').click();
  await page.locator('body').press('j');
  await expect(page.getByRole('link', { name: 'testValidLogin' })).toBeFocused();
  await page.locator('body').press('j');
  await expect(page.getByRole('link', { name: 'testAlpha' })).toBeFocused();
  await page.locator('body').press('k');
  await expect(page.getByRole('link', { name: 'testValidLogin' })).toBeFocused();
});
