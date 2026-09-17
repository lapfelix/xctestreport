const fs = require('fs');
const path = require('path');
const http = require('http');
const web = path.resolve(__dirname, '../../Sources/xctestreport/Resources/Web');
const fixtures = path.resolve(__dirname, '../fixtures/snapshots');
const source = require('../fixtures/snapshots/comparisons.json');
const withoutImages = ['Passed', 'Skipped', 'Failed'].map(result => ({suiteName:source[0].suiteName, testName:`testWithoutImages${result}()`, result, comparisons:[], testPagePath:'tests/no-images.html'}));
const escape = value => String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const slug = value => value.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

function renderSnapshots({ repeat = 1, malformed = false, noDiff = false, mixedDevices = false } = {}) {
  const tests = Array.from({length: repeat}, (_, n) => source.concat(withoutImages).map(t => ({...t, testName: t.testName + (n ? `-${n}` : '')}))).flat();
  const watch = source[0].device;
  const phone = { name: 'iPhone 17 Pro', platform: 'iOS Simulator', osVersion: '27.0', osBuildNumber: '24A123' };
  tests.forEach((t, index) => { t.device = mixedDevices && index % 2 ? phone : watch; });
  const deviceLabel = d => `${d.name} - ${d.platform} ${d.osVersion} (${d.osBuildNumber})`;
  const names = [...new Set(tests.map(t => t.suiteName))];
  const sections = names.map(name => {
    const members = tests.filter(t => t.suiteName === name);
    const items = members.map(t => {
      const id = `test-${slug(name)}-${slug(t.testName)}`;
      const comparisons = t.comparisons.map(c => ({...c, diff: noDiff ? null : c.diff}));
      const anchors = comparisons.map(c => `<span class="sg-anchor" id="cmp-${slug(name)}-${slug(t.testName)}-${slug(c.name)}"></span>`).join('');
      const failed = t.result === 'Failed';
      const payload = malformed ? 'invalid' : encodeURIComponent(JSON.stringify(comparisons));
      const fallback = comparisons.map(c => `<figure class="snapshot-comparison"><figcaption>${escape(c.name)}</figcaption><div class="snapshot-comparison-images">${['expected','actual'].map(role => `<div class="snapshot-image"><img loading="lazy" src="${escape(c[role].src)}" width="${c[role].width}" height="${c[role].height}" alt="${role} ${escape(c.name)}"></div>`).join('')}</div></figure>`).join('');
      return `<article class="sg-item" id="${id}" data-suite="${name}" data-device-label="${escape(deviceLabel(t.device))}" data-failed="${failed}" data-has-viewer="${!!comparisons.length}" data-search="${escape([name,t.testName,...comparisons.map(c=>c.name)].join(' ').toLowerCase())}">${anchors}<header class="sg-item-head"><span class="sg-item-name">${escape(t.testName)}</span><span class="sg-badge">${failed?'Changed':'Matched'}</span><span class="sg-item-meta">${comparisons.length} comparisons</span><a class="sg-item-link" href="${escape(t.testPagePath)}">Test page</a></header>${comparisons.length ? `<div class="sg-item-body"><section class="snapshot-diffs" data-snapshot-device="${encodeURIComponent(JSON.stringify(t.device))}" data-snapshot-comparisons-pending="${payload}">${fallback}</section></div>`:''}</article>`;
    }).join('');
    return `<section class="sg-suite" data-suite="${name}"><h2 class="sg-suite-head"><button class="sg-suite-toggle" aria-expanded="true"><span class="sg-caret"></span><span class="sg-suite-name">${name}</span><span data-sg-visible>${members.length}</span></button></h2><div class="sg-suite-body">${items}</div></section>`;
  }).join('');
  const values = {report_title:'WatchApp',header_note_html:'',total_comparisons:6*repeat,matched_comparisons:0,changed_comparisons:6*repeat,device_label:'Apple Watch Series 11 — watchOS 27.0',failed_only_pressed:'true',visible_items:6*repeat,total_items:tests.length,suite_chips_html:names.map(name=>`<button class="sg-chip" data-suite="${name}" aria-pressed="true">${name}</button>`).join(''),limitation_note_html:'<p class="sg-note">Images are attached on failure only.</p>',suite_sections_html:sections};
  let html = fs.readFileSync(path.join(web,'templates/snapshots.html'),'utf8');
  for (const [key,value] of Object.entries(values)) html = html.split(`{{${key}}}`).join(String(value));
  if (/{{\w+}}/.test(html)) throw new Error('Unsubstituted snapshot template placeholder');
  return html;
}

function renderSnapshotDetail() {
  const comparison = JSON.parse(JSON.stringify(source[5].comparisons[0]));
  for (const role of ['expected', 'actual', 'diff']) {
    if (comparison[role]) comparison[role].src = '/' + comparison[role].src;
  }
  const values = {
    page_title: 'Snapshot detail', test_name: 'testPinButtonWrappingLabelWithALongDescriptiveName()',
    status_badge_class: 'status-failed', status_text: 'Failed', duration_text: '0.04s',
    test_subtitle: 'RouteDetailsViewSnapshotTests',
    details_panel_html: '<details class="test-meta-details"><summary>Summary</summary><div class="test-meta-content">Test metadata</div></details>',
    compact_failure_box_html: '<div class="test-error-box"><pre>Snapshot differs from its reference.</pre></div>',
    timeline_and_video_section_html: '',
    bundle_src: 'detail.zip',
    snapshot_diff_html: `<section class="snapshot-diffs" data-snapshot-device="${encodeURIComponent(JSON.stringify(source[5].device))}" data-snapshot-comparisons="${encodeURIComponent(JSON.stringify([comparison]))}"></section>`
  };
  let html = fs.readFileSync(path.join(web, 'templates/test-detail.html'), 'utf8');
  for (const [key, value] of Object.entries(values)) html = html.split(`{{${key}}}`).join(value);
  if (/{{\w+}}/.test(html)) throw new Error('Unsubstituted detail template placeholder');
  return html;
}

// Mirrors the Range behaviour of a static object store (GCS answers suffix ranges with a 206),
// which is what web/bundle-reader.js relies on to read one ZIP entry without pulling the archive.
function sendMaybeRanged(req, res, body) {
  const range = /^bytes=(\d*)-(\d*)$/.exec(req.headers.range || '');
  res.setHeader('Accept-Ranges', 'bytes');
  if (!range) {
    res.setHeader('Content-Length', body.length);
    res.end(body);
    return;
  }
  let start;
  let end;
  if (range[1] === '') {
    start = Math.max(0, body.length - Number(range[2]));
    end = body.length - 1;
  } else {
    start = Number(range[1]);
    end = range[2] === '' ? body.length - 1 : Math.min(Number(range[2]), body.length - 1);
  }
  const slice = body.subarray(start, end + 1);
  res.writeHead(206, {
    'Content-Range': `bytes ${start}-${end}/${body.length}`,
    'Content-Length': slice.length,
    'Content-Type': res.getHeader('Content-Type') || 'application/octet-stream'
  });
  res.end(slice);
}

async function serveSnapshots(options) {
  const html = renderSnapshots(options);
  const server = http.createServer((req,res) => {
    const url = decodeURIComponent(req.url.split('?')[0]);
    if (url === '/tests/detail.html') { res.setHeader('Content-Type','text/html'); res.end(renderSnapshotDetail()); return; }
    if (url === '/' || url === '/snapshots.html') { res.setHeader('Content-Type','text/html'); res.end(html); return; }
    const root = url.startsWith('/web/') ? web : fixtures;
    const relative = url.startsWith('/web/') ? url.slice(5) : url.replace(/^\/images\//,'');
    const file = path.resolve(root,relative);
    if (!file.startsWith(root + path.sep) || !fs.existsSync(file) || !fs.statSync(file).isFile()) { res.writeHead(404); res.end(); return; }
    res.setHeader('Content-Type', file.endsWith('.png') ? 'image/png' : file.endsWith('.css') ? 'text/css' : 'text/javascript');
    sendMaybeRanged(req, res, fs.readFileSync(file));
  });
  await new Promise(resolve => server.listen(0,'127.0.0.1',resolve));
  return {url:`http://127.0.0.1:${server.address().port}/snapshots.html`, close:()=>new Promise(resolve=>server.close(resolve))};
}
module.exports = {serveSnapshots};
