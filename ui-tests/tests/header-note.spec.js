const { test, expect } = require('@playwright/test');
const { renderReport } = require('./renderReport');

const suites = [
  { name: 'LoginTests', tests: [{ name: 'testValidLogin', status: 'passed' }] },
];

test('header note renders under the title when provided', async ({ page }) => {
  await page.goto(renderReport({ headerNote: 'Branch: feature/new-thing', suites }));

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
  await page.goto(renderReport({ suites }));
  await expect(page.locator('.header-note')).toHaveCount(0);
});

test('header note is HTML-escaped', async ({ page }) => {
  await page.goto(renderReport({ headerNote: 'Branch: <script>x</script> & "more"', suites }));
  await expect(page.locator('.header-note')).toHaveText('Branch: <script>x</script> & "more"');
  // The injected markup must not have created a real <script> element.
  await expect(page.locator('.header-note script')).toHaveCount(0);
});
