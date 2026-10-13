// @ts-check
const { defineConfig, devices } = require('@playwright/test');

const projects = [
  {
    name: 'chromium',
    use: {
      ...devices['Desktop Chrome'],
      ...(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH ? {
        launchOptions: { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH },
      } : {}),
    },
  },
  { name: 'webkit', use: { ...devices['Desktop Safari'] } },
  { name: 'firefox', use: { ...devices['Desktop Firefox'] } },
];
const selected = process.env.PLAYWRIGHT_PROJECTS?.split(',').map(name => name.trim());
if (selected?.some(name => !projects.some(project => project.name === name))) {
  throw new Error('PLAYWRIGHT_PROJECTS must contain chromium, webkit, or firefox.');
}

module.exports = defineConfig({
  testDir: './tests',
  fullyParallel: true,
  reporter: process.env.CI ? [['list'], ['html', { open: 'never' }]] : 'list',
  use: {
    headless: true,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  projects: selected ? projects.filter(project => selected.includes(project.name)) : projects,
});
