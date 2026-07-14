const { test, expect } = require('@playwright/test');
const { renderReport } = require('./renderReport');

// Suite stats, computed from the tests below:
//   AlphaTests: total=2, failed=1, percent=50%,    duration=50s, avg=25s
//   BetaTests:  total=3, failed=0, percent=100%,   duration=10s, avg=3.33s
//   GammaTests: total=3, failed=2, percent=33.33%, duration=20s, avg=6.67s
const suites = [
  {
    name: 'AlphaTests',
    tests: [
      { name: 'testAlphaPass', status: 'passed', duration: 25 },
      { name: 'testAlphaFail', status: 'failed', duration: 25 },
    ],
  },
  {
    name: 'BetaTests',
    tests: [
      { name: 'testBetaOne', status: 'passed', duration: 4 },
      { name: 'testBetaTwo', status: 'passed', duration: 3 },
      { name: 'testBetaThree', status: 'passed', duration: 3 },
    ],
  },
  {
    name: 'GammaTests',
    // Declared out of duration order on purpose, so clicking the per-suite
    // Duration column header (tested below) produces a visible reorder.
    tests: [
      { name: 'testGammaFailTwo', status: 'failed', duration: 4 },
      { name: 'testGammaPass', status: 'passed', duration: 10 },
      { name: 'testGammaFailOne', status: 'failed', duration: 6 },
    ],
  },
];

async function reportURL() {
  return renderReport({ suites });
}

function suiteNames(page) {
  return page.locator('.suite .suite-name');
}

test('default suite order is alphabetical and Name is active', async ({ page }) => {
  await page.goto(await reportURL());
  await expect(suiteNames(page)).toHaveText(['AlphaTests', 'BetaTests', 'GammaTests']);
  await expect(page.locator('.suite-sort-btn[data-sort-key="name"]')).toHaveAttribute('aria-pressed', 'true');
  await expect(page.locator('.suite-sort-btn[data-sort-key="name"]')).toHaveAttribute('data-sort', 'asc');
});

test('clicking Failed sorts suites by failed count descending', async ({ page }) => {
  await page.goto(await reportURL());
  await page.locator('.suite-sort-btn[data-sort-key="failed"]').click();

  await expect(suiteNames(page)).toHaveText(['GammaTests', 'AlphaTests', 'BetaTests']);
  await expect(page.locator('.suite-sort-btn[data-sort-key="failed"]')).toHaveAttribute('aria-pressed', 'true');
  await expect(page.locator('.suite-sort-btn[data-sort-key="failed"]')).toHaveAttribute('data-sort', 'desc');
  await expect(page.locator('.suite-sort-btn[data-sort-key="name"]')).toHaveAttribute('aria-pressed', 'false');
});

test('clicking Total sorts suites by total test count descending, ties by name', async ({ page }) => {
  await page.goto(await reportURL());
  await page.locator('.suite-sort-btn[data-sort-key="total"]').click();

  // Beta and Gamma both have 3 total tests; tie broken alphabetically.
  await expect(suiteNames(page)).toHaveText(['BetaTests', 'GammaTests', 'AlphaTests']);
});

test('clicking % Passed sorts suites by percent passed descending', async ({ page }) => {
  await page.goto(await reportURL());
  await page.locator('.suite-sort-btn[data-sort-key="percent"]').click();

  await expect(suiteNames(page)).toHaveText(['BetaTests', 'AlphaTests', 'GammaTests']);
});

test('clicking Time sorts suites by total suite duration descending', async ({ page }) => {
  await page.goto(await reportURL());
  await page.locator('.suite-sort-btn[data-sort-key="duration"]').click();

  await expect(suiteNames(page)).toHaveText(['AlphaTests', 'GammaTests', 'BetaTests']);
});

test('clicking Avg Time sorts suites by average test duration descending', async ({ page }) => {
  await page.goto(await reportURL());
  await page.locator('.suite-sort-btn[data-sort-key="avg"]').click();

  await expect(suiteNames(page)).toHaveText(['AlphaTests', 'GammaTests', 'BetaTests']);
  await expect(page.locator('.suite-sort-btn[data-sort-key="avg"]')).toHaveAttribute('aria-pressed', 'true');
  await expect(page.locator('.suite-sort-btn[data-sort-key="avg"]')).toHaveAttribute('data-sort', 'desc');
});

test('clicking the same sort button twice reverses to ascending', async ({ page }) => {
  await page.goto(await reportURL());
  const failedBtn = page.locator('.suite-sort-btn[data-sort-key="failed"]');

  await failedBtn.click();
  await expect(suiteNames(page)).toHaveText(['GammaTests', 'AlphaTests', 'BetaTests']);
  await expect(failedBtn).toHaveAttribute('data-sort', 'desc');

  await failedBtn.click();
  await expect(suiteNames(page)).toHaveText(['BetaTests', 'AlphaTests', 'GammaTests']);
  await expect(failedBtn).toHaveAttribute('data-sort', 'asc');
});

test('clicking Name after another key is active returns to alphabetical', async ({ page }) => {
  await page.goto(await reportURL());
  const nameBtn = page.locator('.suite-sort-btn[data-sort-key="name"]');
  const failedBtn = page.locator('.suite-sort-btn[data-sort-key="failed"]');

  await failedBtn.click();
  await expect(suiteNames(page)).toHaveText(['GammaTests', 'AlphaTests', 'BetaTests']);

  await nameBtn.click();
  await expect(suiteNames(page)).toHaveText(['AlphaTests', 'BetaTests', 'GammaTests']);
  await expect(nameBtn).toHaveAttribute('aria-pressed', 'true');
  await expect(nameBtn).toHaveAttribute('data-sort', 'asc');
  await expect(failedBtn).toHaveAttribute('aria-pressed', 'false');
});

test('sorting suites does not break status-chip/search filtering', async ({ page }) => {
  await page.goto(await reportURL());
  await page.locator('.suite-sort-btn[data-sort-key="failed"]').click();
  await expect(suiteNames(page)).toHaveText(['GammaTests', 'AlphaTests', 'BetaTests']);

  await page.locator('.status-chip[data-status="passed"]').click();
  await page.locator('.status-chip[data-status="skipped"]').click();

  // Only failed rows remain visible: 1 in AlphaTests, 2 in GammaTests.
  await expect(page.locator('.suite-tests-table tbody tr:visible')).toHaveCount(3);
  await expect(page.locator('tr.failed:visible')).toHaveCount(3);
  await expect(page.locator('.suite:visible')).toHaveCount(2);

  // BetaTests has zero failed rows, so it should be hidden by the filter,
  // even though the suite-level sort still placed it in the DOM.
  await expect(page.locator('.suite', { hasText: 'BetaTests' })).toBeHidden();
});

test('sorting suites does not break the per-suite Duration column sort', async ({ page }) => {
  await page.goto(await reportURL());
  await page.locator('.suite-sort-btn[data-sort-key="duration"]').click();
  await expect(suiteNames(page)).toHaveText(['AlphaTests', 'GammaTests', 'BetaTests']);

  const gamma = page.locator('.suite', { hasText: 'GammaTests' });
  const header = gamma.locator('th.sortable-duration');
  const names = gamma.locator('tbody tr td:first-child');

  await expect(names).toHaveText(['testGammaFailTwo', 'testGammaPass', 'testGammaFailOne']);

  await header.click(); // desc by duration: 10, 6, 4
  await expect(names).toHaveText(['testGammaPass', 'testGammaFailOne', 'testGammaFailTwo']);

  await header.click(); // asc by duration: 4, 6, 10
  await expect(names).toHaveText(['testGammaFailTwo', 'testGammaFailOne', 'testGammaPass']);

  await header.click(); // back to original order
  await expect(names).toHaveText(['testGammaFailTwo', 'testGammaPass', 'testGammaFailOne']);
});
