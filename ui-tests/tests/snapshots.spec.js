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


test('single-device reports keep the compact header and inspector device details', async ({page}) => {
  await inspect(page);
  await expect(page.locator('#sg-device-filter')).toHaveCount(0);
  await expect(page.locator('.sg-card-device')).toHaveCount(0);
  await expect(page.locator('.sg-inspector .snapdiff-device')).toContainText('Apple Watch Series 11');
  await expect(page.locator('.sg-inspector .snapdiff-device')).toContainText('watchOS Simulator 27.0');
});

test('mixed devices filter cards and inspector navigation, and deep links reveal another device', async ({page}) => {
  await server.close(); server = await serveSnapshots({mixedDevices:true});
  await page.goto(server.url);
  const filter = page.getByRole('combobox', {name:'Filter by device'});
  await expect(filter.locator('option')).toHaveCount(3);
  await expect(filter).toHaveValue('');
  await expect(page.locator('.sg-card-device:visible').first()).toContainText('Apple Watch');
  await filter.selectOption({label:'iPhone 17 Pro - iOS Simulator 27.0 (24A123)'});
  await expect(page.locator('.sg-preview:visible')).toHaveCount(3);
  await page.locator('.sg-preview:visible').first().click();
  await expect(page.locator('.sg-position')).toHaveText('1 of 3');
  await expect(page.locator('.sg-inspector .snapdiff-device')).toContainText('iPhone 17 Pro');
  await page.getByRole('button',{name:'Next snapshot',exact:true}).click();
  await expect(page.locator('.sg-inspector .snapdiff-device')).toContainText('iOS Simulator');
  await page.keyboard.press('Escape');
  await page.getByRole('searchbox').fill('pinbutton');
  await expect(page.locator('.sg-preview:visible')).toHaveCount(2);
  await page.evaluate(() => { location.hash = 'cmp-routedetailsviewsnapshottests-testdepartureswithoutseparators-routedetailsdepartures-noseparators'; });
  await expect(page.getByRole('dialog')).toBeVisible();
  await expect(filter).toHaveValue('');
  await expect(page.locator('.sg-inspector .snapdiff-device')).toContainText('Apple Watch');
});

test('mixed-device labels fit a narrow viewport', async ({page}) => {
  await server.close(); server = await serveSnapshots({mixedDevices:true});
  await page.setViewportSize({width:390,height:844});
  await page.goto(server.url);
  await expect(page.getByRole('combobox', {name:'Filter by device'})).toBeVisible();
  expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
});

for (const width of [320, 390, 667]) {
  test(`compact inspector defaults and touch controls at ${width}px`, async ({page}) => {
    await page.setViewportSize({width,height:width === 667 ? 375 : 844});
    await inspect(page);
    await expect(page.locator('.snapdiff')).toHaveAttribute('data-mode','swipe');
    await page.getByRole('combobox',{name:'Zoom level'}).selectOption('2');
    await expect(page.locator('.snapdiff-zoomlabel')).toHaveText('200%');
    await page.getByRole('combobox',{name:'Zoom level'}).selectOption('0');
    for (const control of await page.locator('.snapdiff-mode, .sg-close, .sg-inspector-head [data-step]').all()) {
      expect((await control.boundingBox()).height).toBeGreaterThanOrEqual(44);
    }
    expect(await page.getByRole('dialog').evaluate(d=>d.scrollWidth<=d.clientWidth)).toBe(true);
    await page.getByRole('button',{name:'Next snapshot',exact:true}).click();
    await expect(page.locator('.snapdiff')).toHaveAttribute('data-mode','swipe');
    await page.getByRole('button',{name:'Close inspector'}).click();
    expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
  });
}

test('dark secondary text and selected modes have readable contrast', async ({page}) => {
  await page.emulateMedia({colorScheme:'dark'});
  await inspect(page);
  const contrast = await page.locator('.snapdiff-mode[aria-pressed="true"]').evaluate(element => {
    function luminance(color) {
      const rgb=color.match(/[\d.]+/g).slice(0,3).map(Number).map(n=>{n/=255;return n<=.04045?n/12.92:((n+.055)/1.055)**2.4;});
      return rgb[0]*.2126+rgb[1]*.7152+rgb[2]*.0722;
    }
    function ratio(a,b) {a=luminance(a);b=luminance(b);return (Math.max(a,b)+.05)/(Math.min(a,b)+.05);}
    const selected=getComputedStyle(element);
    const label=getComputedStyle(document.querySelector('.sg-preview-label'));
    const frame=getComputedStyle(document.querySelector('.sg-preview-frame'));
    return [ratio(selected.color,selected.backgroundColor),ratio(label.color,frame.backgroundColor)];
  });
  for (const ratio of contrast) expect(ratio).toBeGreaterThanOrEqual(4.5);
});

test('two-finger pinch zooms an image without zooming the page', async ({browser}) => {
  const context=await browser.newContext({viewport:{width:390,height:844},isMobile:true,hasTouch:true});
  const page=await context.newPage();
  await inspect(page);
  await page.locator('.snapdiff-stage').scrollIntoViewIfNeeded();
  const bounds=await page.locator('.snapdiff-stage').boundingBox();
  const y=bounds.y+bounds.height/2;
  const session=await context.newCDPSession(page);
  const before=await page.locator('.snapdiff-zoomlabel').textContent();
  await session.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x:bounds.x+30,y,id:1},{x:bounds.x+100,y,id:2}]});
  await session.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{x:bounds.x+10,y,id:1},{x:bounds.x+160,y,id:2}]});
  await session.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
  await expect(page.locator('.snapdiff-zoomlabel')).not.toHaveText(before);
  expect(await page.evaluate(()=>visualViewport.scale)).toBe(1);
  await page.getByRole('combobox',{name:'Zoom level'}).selectOption('0');
  await expect(page.locator('.snapdiff-zoomlabel')).toHaveText(before);
  await context.close();
});

for (const width of [320, 390, 667]) {
  test(`test detail stays readable and scrollable at ${width}px`, async ({page}) => {
    await page.setViewportSize({width,height:width === 667 ? 375 : 844});
    await page.emulateMedia({colorScheme:'dark'});
    await page.goto(new URL('/tests/detail.html',server.url).href);
    await expect(page.locator('.snapdiff')).toHaveAttribute('data-mode','swipe');
    expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
    await expect(page.locator('.test-title-compact')).toHaveCSS('white-space','normal');
    await page.getByRole('combobox',{name:'Zoom level'}).selectOption('4');
    await expect(page.locator('.snapdiff-zoomlabel')).toHaveText('400%');
    await page.getByText('Pixel analysis',{exact:true}).click();
    await expect(page.locator('.snapdiff-inspector')).toBeVisible();
    await page.getByRole('link',{name:'Download actual image'}).scrollIntoViewIfNeeded();
    expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
  });
}
