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

  const mediaRect = await page.evaluate(() => {
    function displayedMediaRect(mediaElement) {
      if (!mediaElement) return { x: 0, y: 0, width: 0, height: 0 };
      var elementWidth = mediaElement.clientWidth || mediaElement.offsetWidth || 0;
      var elementHeight = mediaElement.clientHeight || mediaElement.offsetHeight || 0;
      if (elementWidth <= 0 || elementHeight <= 0) return { x: 0, y: 0, width: 0, height: 0 };
      var intrinsicWidth = mediaElement.videoWidth || mediaElement.naturalWidth || elementWidth;
      var intrinsicHeight = mediaElement.videoHeight || mediaElement.naturalHeight || elementHeight;
      if (intrinsicWidth <= 0 || intrinsicHeight <= 0) {
        return { x: 0, y: 0, width: elementWidth, height: elementHeight };
      }
      var elementRatio = elementWidth / elementHeight;
      var mediaRatio = intrinsicWidth / intrinsicHeight;
      if (!Number.isFinite(elementRatio) || !Number.isFinite(mediaRatio) || mediaRatio <= 0) {
        return { x: 0, y: 0, width: elementWidth, height: elementHeight };
      }
      if (mediaRatio > elementRatio) {
        var renderedHeight = elementWidth / mediaRatio;
        return { x: 0, y: (elementHeight - renderedHeight) / 2, width: elementWidth, height: renderedHeight };
      }
      var renderedWidth = elementHeight * mediaRatio;
      return { x: (elementWidth - renderedWidth) / 2, y: 0, width: renderedWidth, height: elementHeight };
    }

    var cards = Array.from(document.querySelectorAll(".timeline-video-card"));
    var card = cards.find((entry) => entry.style.display !== "none") || cards[0] || null;
    if (!card) return null;
    var media = card.querySelector("video, [data-still-frame]");
    if (!media) return null;
    return displayedMediaRect(media);
  });
  await assert(
    !!mediaRect && mediaRect.width > 0 && mediaRect.height > 0,
    "Could not resolve displayed media bounds for hierarchy overlay clicks."
  );

  async function clickOverlayPoint(rx, ry) {
    await page.mouse.click(
      box.x + mediaRect.x + (mediaRect.width * rx),
      box.y + mediaRect.y + (mediaRect.height * ry)
    );
    await page.waitForTimeout(120);
  }

  async function readCandidateState() {
    return await page.evaluate(() => {
      var items = Array.from(document.querySelectorAll(".hierarchy-candidate-item")).map((element) => ({
        id: element.getAttribute("data-hierarchy-element-id") || "",
        selected: element.classList.contains("is-selected"),
      }));
      var selectedItems = items.filter((item) => item.selected);
      return {
        count: items.length,
        firstId: items[0] ? items[0].id : null,
        secondId: items[1] ? items[1].id : null,
        selectedCount: selectedItems.length,
        selectedId: selectedItems[0] ? selectedItems[0].id : null,
      };
    });
  }

  const candidatePoints = [];
  for (let y = 12; y <= 88; y += 8) {
    for (let x = 12; x <= 88; x += 8) {
      const rx = x / 100;
      const ry = y / 100;
      await clickOverlayPoint(rx, ry);
      const state = await readCandidateState();
      if (state.count >= 2 && state.firstId && state.secondId && state.firstId !== state.secondId) {
        candidatePoints.push({ rx, ry, state });
      }
    }
  }

  await assert(
    candidatePoints.length >= 2,
    `Expected at least 2 distinct on-screen points with overlapping hierarchy candidates, got ${candidatePoints.length}.`
  );
  const pointA = candidatePoints[0];
  await clickOverlayPoint(pointA.rx, pointA.ry);
  const pointAState = await readCandidateState();
  await assert(pointAState.selectedCount === 1, `Expected 1 selected candidate after overlay click, got ${pointAState.selectedCount}.`);
  await assert(
    pointAState.selectedId === pointAState.firstId,
    "Overlay click did not select the first candidate at the clicked point."
  );

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

  let screenSelectionValidated = false;
  for (const point of candidatePoints) {
    if (point === pointA) continue;
    await clickOverlayPoint(point.rx, point.ry);
    const pointState = await readCandidateState();
    if (pointState.count < 2 || !pointState.firstId || pointState.firstId === secondSelectedId) continue;
    await assert(
      pointState.selectedCount === 1,
      `Expected 1 selected candidate after overlay click, got ${pointState.selectedCount}.`
    );
    await assert(
      pointState.selectedId === pointState.firstId,
      "Overlay click did not switch selection to the first candidate at the clicked point."
    );
    await assert(
      pointState.selectedId !== secondSelectedId,
      "Selecting another on-screen element did not replace the previous inspector selection."
    );
    screenSelectionValidated = true;
    break;
  }

  await assert(
    screenSelectionValidated,
    "Could not validate on-screen re-selection; try a report with richer overlapping hierarchy at click points."
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
