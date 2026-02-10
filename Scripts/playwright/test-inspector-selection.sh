#!/usr/bin/env bash
set -euo pipefail

if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
  echo "Node.js and npm are required."
  exit 1
fi

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /absolute/path/to/test_detail.html"
  exit 1
fi

HTML_PATH="$1"
if [[ ! -f "$HTML_PATH" ]]; then
  echo "Report HTML not found: $HTML_PATH"
  exit 1
fi

case "$HTML_PATH" in
  /*) ;;
  *)
    echo "Provide an absolute path to the report HTML."
    exit 1
    ;;
esac

TMP_DIR="$(mktemp -d /tmp/xctestreport-playwright.XXXXXX)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat >"$TMP_DIR/test.js" <<'JS'
const { chromium } = require('playwright');

async function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function run(htmlPath) {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 1600, height: 1000 } });
  const url = "file://" + htmlPath;
  await page.goto(url, { waitUntil: "domcontentloaded", timeout: 120000 });

  const hierarchyEvents = page.locator(".timeline-event.timeline-hierarchy:visible");
  await hierarchyEvents.first().waitFor({ timeout: 30000 });
  await hierarchyEvents.first().click();
  await page.waitForTimeout(300);

  const status = (await page.locator("[data-hierarchy-status]").innerText()).trim();
  await assert(
    !status.includes("No hierarchy snapshot near this moment."),
    "No hierarchy snapshot was available after selecting a hierarchy event."
  );

  await page.evaluate(() => {
    const button = document.querySelector("[data-hierarchy-toggle]");
    if (button && button.getAttribute("aria-expanded") !== "true") {
      button.click();
    }
  });

  const overlay = page.locator("[data-hierarchy-overlay]");
  await overlay.waitFor({ timeout: 20000 });
  const box = await overlay.boundingBox();
  await assert(!!box, "Hierarchy overlay has no bounding box.");

  const points = [
    [0.5, 0.5],
    [0.35, 0.5],
    [0.65, 0.5],
    [0.5, 0.35],
    [0.5, 0.65],
  ];
  let candidateCount = 0;
  for (const [rx, ry] of points) {
    await page.mouse.click(box.x + box.width * rx, box.y + box.height * ry);
    await page.waitForTimeout(120);
    candidateCount = await page.locator(".hierarchy-candidate-item").count();
    if (candidateCount >= 2) break;
  }
  await assert(candidateCount >= 2, `Expected at least 2 hierarchy candidates, got ${candidateCount}.`);

  const firstCandidate = page.locator(".hierarchy-candidate-item").nth(0);
  const secondCandidate = page.locator(".hierarchy-candidate-item").nth(1);

  await firstCandidate.click();
  await page.waitForTimeout(100);
  let selected = page.locator(".hierarchy-candidate-item.is-selected");
  const selectedAfterFirst = await selected.count();
  const firstSelectedId = await selected.first().getAttribute("data-hierarchy-element-id");
  await assert(selectedAfterFirst === 1, `Expected 1 selected candidate after first click, got ${selectedAfterFirst}.`);

  await secondCandidate.click();
  await page.waitForTimeout(100);
  selected = page.locator(".hierarchy-candidate-item.is-selected");
  const selectedAfterSecond = await selected.count();
  const secondSelectedId = await selected.first().getAttribute("data-hierarchy-element-id");
  await assert(selectedAfterSecond === 1, `Expected 1 selected candidate after second click, got ${selectedAfterSecond}.`);
  await assert(
    secondSelectedId && firstSelectedId && secondSelectedId !== firstSelectedId,
    "Selecting another candidate did not replace the previous candidate selection."
  );

  const visibleEvents = page.locator(".timeline-event:visible");
  await visibleEvents.nth(8).click();
  await page.waitForTimeout(100);
  let activeCount = await page.locator(".timeline-event.timeline-active").count();
  await assert(activeCount === 1, `Expected 1 active timeline event after first click, got ${activeCount}.`);
  const firstActiveId = await page.locator(".timeline-event.timeline-active").first().getAttribute("data-event-id");

  await visibleEvents.nth(16).click();
  await page.waitForTimeout(100);
  activeCount = await page.locator(".timeline-event.timeline-active").count();
  await assert(activeCount === 1, `Expected 1 active timeline event after second click, got ${activeCount}.`);
  const secondActiveId = await page.locator(".timeline-event.timeline-active").first().getAttribute("data-event-id");
  await assert(
    firstActiveId && secondActiveId && firstActiveId !== secondActiveId,
    "Selecting another timeline event did not replace the previous active event."
  );

  console.log("Playwright selection checks passed.");
  await browser.close();
}

run(process.argv[2]).catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
JS

pushd "$TMP_DIR" >/dev/null
npm init -y >/dev/null 2>&1
npm install playwright >/dev/null 2>&1
node "$TMP_DIR/test.js" "$HTML_PATH"
popd >/dev/null
