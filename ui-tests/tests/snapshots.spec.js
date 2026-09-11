const {test,expect} = require('@playwright/test');
const {serveSnapshots} = require('./renderSnapshots');
let server;
test.beforeEach(async () => { server = await serveSnapshots(); });
test.afterEach(async () => { await server.close(); });

async function inspect(page, name = 'NearbyRouteDisplayName-text') {
  await page.goto(server.url);
  await page.getByRole('button',{name:`Inspect ${name}`,exact:true}).click();
  await expect(page.locator('.snapdiff-stage')).toBeVisible();
  await expect.poll(()=>page.locator('.snapdiff-layer-expected').first().evaluate(img=>img.complete && img.naturalWidth>0)).toBe(true);
}

test('contact sheet shows all failures without booting a viewer or reading pixels', async ({page}) => {
  const requests=[];
  page.on('request',r=>requests.push(r.url()));
  await page.addInitScript(()=>{ window.pixelReads=0; const read=CanvasRenderingContext2D.prototype.getImageData; CanvasRenderingContext2D.prototype.getImageData=function(...args){window.pixelReads++;return read.apply(this,args);}; });
  await page.goto(server.url);
  await expect(page.locator('.sg-preview:visible')).toHaveCount(6);
  await expect(page.locator('.snapdiff')).toHaveCount(0);
  expect(requests.some(url=>url.endsWith('/snapshot-diff.js'))).toBe(false);
  expect(await page.evaluate(()=>window.pixelReads)).toBe(0);
  const positions=await page.locator('.sg-preview:visible').evaluateAll(nodes=>nodes.map(n=>Math.round(n.getBoundingClientRect().top)));
  expect(new Set(positions).size).toBeLessThan(6);
});

test('inspector navigates every failure, closes with Escape and restores focus', async ({page}) => {
  await inspect(page);
  await expect(page.locator('.sg-position')).toHaveText('1 of 6');
  await page.getByRole('button',{name:'Next snapshot',exact:true}).click();
  await expect(page.locator('.snapdiff-name')).toHaveText('NearbyRow-pinned');
  await expect(page.locator('.snapdiff')).toHaveCount(1);
  await page.keyboard.press(']');
  await expect(page.locator('.snapdiff-name')).toHaveText('RouteDetailsDepartures-noSeparators');
  await page.keyboard.press('Escape');
  await expect(page.getByRole('dialog')).not.toBeVisible();
  await expect(page.locator('.snapdiff')).toHaveCount(0);
  await expect(page.getByRole('button',{name:'Inspect NearbyRouteDisplayName-text',exact:true})).toBeFocused();
});

test('all six modes, live tolerance, zoom, change navigation and downloads work', async ({page}) => {
  await inspect(page);
  for (const [key,mode] of [['2','swipe'],['3','onion'],['4','blink'],['5','heat'],['6','highlight'],['1','side']]) {
    await page.locator('.snapdiff').focus(); await page.keyboard.press(key);
    await expect(page.locator('.snapdiff')).toHaveAttribute('data-mode',mode);
  }
  await page.getByRole('button',{name:'Heatmap (key 5)',exact:true}).click();
  await page.getByText('Pixel analysis',{exact:true}).click();
  await expect(page.locator('.snapdiff-canvas')).toBeVisible();
  const before=await page.locator('.snapdiff-stat-value').first().textContent();
  await page.getByRole('slider',{name:'Per-channel tolerance'}).fill('128');
  await expect(page.locator('.snapdiff-stat-value').first()).not.toHaveText(before);
  await expect(page.locator('.snapdiff-stat-value').first()).toContainText('tolerance 128');
  await page.getByRole('button',{name:'Zoom 200%',exact:true}).click();
  await expect(page.locator('.snapdiff-zoomlabel')).toHaveText('200%');
  await page.getByRole('button',{name:'Next difference',exact:true}).click();
  await expect(page.locator('.snapdiff-counter')).toHaveText('1 / 1');
  await expect(page.getByRole('link',{name:'Download expected image'})).toHaveAttribute('download',/expected.png$/);
});

test('size mismatch keeps its dimensions and generates a heatmap', async ({page}) => {
  await inspect(page,'RouteDetailsDepartures-noSeparators');
  await expect(page.locator('.snapdiff-sizebanner')).toContainText('height −4');
  await page.getByRole('button',{name:'Heatmap (key 5)',exact:true}).click();
  await expect(page.locator('.snapdiff-canvas')).toBeVisible();
  const dimensions=await page.locator('.snapdiff-canvas').evaluate(c=>[c.width,c.height]);
  expect(dimensions).toEqual([438,221]);
});

test('filtering, empty state, grouping and collapse compose', async ({page}) => {
  await page.goto(server.url);
  await page.getByRole('searchbox').fill('pinbutton');
  await expect(page.locator('.sg-preview:visible')).toHaveCount(3);
  await page.locator('.sg-preview:visible').first().click();
  await expect(page.locator('.sg-position')).toHaveText('1 of 3');
  await page.keyboard.press('Escape');
  await page.getByRole('searchbox').fill('nothingmatches');
  await expect(page.locator('#sg-empty')).toBeVisible();
  await page.getByRole('searchbox').fill('');
  await page.getByRole('button',{name:'Group by class'}).click();
  await expect(page.locator('.sg-suite-head:visible')).toHaveCount(2);
  await page.getByRole('button',{name:'Collapse all',exact:true}).click();
  await expect(page.locator('.sg-preview:visible')).toHaveCount(0);
  await page.getByRole('button',{name:'Group by class'}).click();
  await expect(page.locator('.sg-preview:visible')).toHaveCount(6);
});

test('deep links open the named comparison', async ({page}) => {
  await page.goto(server.url+'#cmp-routedetailsviewsnapshottests-testdepartureswithoutseparators-routedetailsdepartures-noseparators');
  await expect(page.getByRole('dialog')).toBeVisible();
  await expect(page.locator('.snapdiff-name')).toHaveText('RouteDetailsDepartures-noSeparators');
});

test('closing a blinking inspector releases timers and resize observers', async ({page}) => {
  await page.addInitScript(()=>{
    window.activeIntervals=new Set(); const set=window.setInterval, clear=window.clearInterval;
    window.setInterval=(...args)=>{const id=set(...args);window.activeIntervals.add(id);return id;};
    window.clearInterval=id=>{window.activeIntervals.delete(id);clear(id);};
    window.activeObservers=0; const RO=window.ResizeObserver;
    window.ResizeObserver=class extends RO {observe(...args){if(!this.active){window.activeObservers++;this.active=true;}super.observe(...args);}disconnect(){if(this.active){window.activeObservers--;this.active=false;}super.disconnect();}};
  });
  await inspect(page);
  for(let i=0;i<4;i++) {
    await page.getByRole('button',{name:'Blink (key 4)',exact:true}).click();
    await page.getByRole('button',{name:'Play or pause blinking'}).click();
    expect(await page.evaluate(()=>window.activeIntervals.size)).toBe(1);
    await page.getByRole('button',{name:'Next snapshot',exact:true}).click();
    await expect(page.locator('.snapdiff-stage')).toBeVisible();
  }
  await page.keyboard.press('Escape');
  await expect.poll(()=>page.evaluate(()=>[window.activeIntervals.size,window.activeObservers])).toEqual([0,0]);
});

for (const colorScheme of ['light','dark']) {
  test(`mobile ${colorScheme} gallery and inspector fit the viewport`, async ({page}) => {
    await page.setViewportSize({width:390,height:844}); await page.emulateMedia({colorScheme});
    await inspect(page,'RouteDetailsDepartures-noSeparators');
    expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
    expect(await page.getByRole('dialog').evaluate(d=>d.scrollWidth<=d.clientWidth)).toBe(true);
    await page.getByRole('button',{name:'Close inspector'}).click();
    await expect(page.locator('.sg-preview:visible')).toHaveCount(6);
  });
}

test('missing images show a useful error and preserve download links', async ({page}) => {
  await page.route('**/images/*.expected.png',route=>route.abort());
  await inspectMissing();
  async function inspectMissing(){await page.goto(server.url);await page.locator('.sg-preview').first().click();}
  await expect(page.locator('.snapdiff-message')).toContainText('Could not load the expected image');
  await expect(page.getByRole('link',{name:'Download expected image'})).toBeVisible();
});

test('static fallback remains readable with JavaScript disabled', async ({browser}) => {
  const context=await browser.newContext({javaScriptEnabled:false}); const page=await context.newPage();
  await page.goto(server.url);
  await expect(page.locator('.snapshot-comparison:visible')).toHaveCount(6);
  await context.close();
});

test('large contact sheets stay canvas-free and can filter promptly', async ({page}) => {
  await server.close(); server=await serveSnapshots({repeat:30});
  await page.goto(server.url);
  await expect(page.locator('.sg-preview:visible')).toHaveCount(180);
  await expect(page.locator('canvas')).toHaveCount(0);
  await page.getByRole('searchbox').fill('testPinButtonPinned()-29');
  await expect(page.locator('.sg-preview:visible')).toHaveCount(1,{timeout:1500});
});

test('difference previews are optional and comparison mode survives next/previous', async ({page}) => {
  await page.goto(server.url);
  await page.getByRole('button',{name:'Show differences',exact:true}).click();
  await expect(page.locator('.sg-preview-label').filter({hasText:'Difference'})).toHaveCount(6);
  await expect(page.locator('.sg-preview').first().locator('[data-role="actual"] img')).toHaveAttribute('src',/\.diff.png$/);
  await page.locator('.sg-preview').first().click();
  await page.getByRole('button',{name:'Heatmap (key 5)',exact:true}).click();
  await page.getByRole('button',{name:'Next snapshot',exact:true}).click();
  await expect(page.locator('.snapdiff')).toHaveAttribute('data-mode','heat');
  await expect(page.locator('.snapdiff-canvas')).toBeVisible();
});

test('tests without images remain available and class filters can recover from no selection', async ({page}) => {
  await page.goto(server.url);
  await expect(page.locator('.sg-item[data-has-viewer="false"]:visible')).toHaveCount(1);
  await page.getByRole('button',{name:'Failed only',exact:true}).click();
  await expect(page.locator('.sg-item[data-has-viewer="false"]:visible')).toHaveCount(3);
  await page.getByText('Filter test classes',{exact:true}).click();
  for (const chip of await page.locator('.sg-chip[data-suite]').all()) await chip.click();
  await expect(page.locator('#sg-empty')).toBeVisible();
  await page.locator('#sg-chip-all').click();
  await expect(page.locator('.sg-preview:visible')).toHaveCount(6);
});

test('malformed payload preserves the static comparison and missing diff can be computed', async ({page}) => {
  await server.close(); server=await serveSnapshots({malformed:true});
  await page.goto(server.url);
  await expect(page.locator('.snapshot-comparison:visible')).toHaveCount(6);
  await expect(page.locator('.sg-preview')).toHaveCount(0);
  await server.close(); server=await serveSnapshots({noDiff:true});
  await inspect(page);
  await page.getByRole('button',{name:'Highlight (key 6)',exact:true}).click();
  await expect(page.locator('.snapdiff-canvas')).toBeVisible();
});
