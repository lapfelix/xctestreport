const { test, expect } = require('@playwright/test');
const http = require('http');
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const { makeBundle } = require('./makeBundle');

const web = path.resolve(__dirname, '../../Sources/xctestreport/Resources/Web');
const readerSource = fs.readFileSync(path.join(web, 'bundle-reader.js'), 'utf8');

const RUN_STATES = JSON.stringify([{ index: 0, label: 'Run 1', events: [] }]);
const BIG_TEXT = 'timeline payload body. '.repeat(4000);
const PNG_BYTES = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  Buffer.alloc(9000, 0x5a)
]);

// `large` pushes the archive past the reader's 64 KB tail window, which is what forces it to
// range-fetch individual entries instead of keeping the whole thing in memory.
function bundleFixture({ large = false } = {}) {
  const entries = [
    { name: 'timeline/runstates.json', data: RUN_STATES },
    { name: 'timeline/screenshots.json', data: JSON.stringify([['Shot', '../attachments/1.png', 1.5, false, 'attachments/1.png']]) },
    { name: 'attachments/1.png', data: PNG_BYTES, store: true },
    { name: 'attachments/big.txt', data: BIG_TEXT },
    { name: 'test.md', data: '# Test detail\n' }
  ];
  if (large) {
    // Stored, and pseudo-random so it cannot be deflated away.
    let seed = 1;
    const filler = Buffer.alloc(400 * 1024);
    for (let i = 0; i < filler.length; i += 1) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      filler[i] = seed >>> 16;
    }
    entries.push({ name: 'attachments/filler.bin', data: filler, store: true });
  }
  return makeBundle(entries);
}

// `supportsRange: false` stands in for a host that ignores Range and returns the whole object.
async function serveBundle({ supportsRange = true, large = false } = {}) {
  const archive = bundleFixture({ large });
  const requests = [];
  let bytesServed = 0;

  const server = http.createServer((req, res) => {
    const url = req.url.split('?')[0];
    if (url === '/page.html') {
      res.setHeader('Content-Type', 'text/html');
      res.end(`<!DOCTYPE html><html><head><script src="/web/bundle-reader.js"></script></head><body data-report-bundle="detail.zip"></body></html>`);
      return;
    }
    if (url === '/web/bundle-reader.js') {
      res.setHeader('Content-Type', 'text/javascript');
      res.end(readerSource);
      return;
    }
    if (url === '/detail.zip') {
      requests.push(req.headers.range || null);
      const range = supportsRange && /^bytes=(\d*)-(\d*)$/.exec(req.headers.range || '');
      if (range) {
        let start;
        let end;
        if (range[1] === '') { start = Math.max(0, archive.length - Number(range[2])); end = archive.length - 1; }
        else { start = Number(range[1]); end = range[2] === '' ? archive.length - 1 : Math.min(Number(range[2]), archive.length - 1); }
        const slice = archive.subarray(start, end + 1);
        bytesServed += slice.length;
        res.writeHead(206, {
          'Content-Range': `bytes ${start}-${end}/${archive.length}`,
          'Content-Length': slice.length,
          'Accept-Ranges': 'bytes',
          'Content-Type': 'application/zip'
        });
        res.end(slice);
        return;
      }
      bytesServed += archive.length;
      res.writeHead(200, { 'Content-Length': archive.length, 'Content-Type': 'application/zip' });
      res.end(archive);
      return;
    }
    res.writeHead(404);
    res.end();
  });

  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  return {
    url: `http://127.0.0.1:${server.address().port}/page.html`,
    archiveLength: archive.length,
    stats: () => ({ requests: requests.slice(), bytesServed }),
    close: () => new Promise(resolve => server.close(resolve))
  };
}

async function openBundle(page) {
  return page.evaluate(async () => {
    const href = document.body.getAttribute('data-report-bundle');
    const bundle = globalThis.ReportBundle.open(new URL(href, window.location.href).href);
    const names = await bundle.names();
    return names;
  });
}

test.describe('report bundle reader', () => {
  test('lists entries and inflates deflated ones', async ({ page }) => {
    const server = await serveBundle();
    try {
      await page.goto(server.url);
      const names = await openBundle(page);
      expect(names).toEqual([
        'timeline/runstates.json',
        'timeline/screenshots.json',
        'attachments/1.png',
        'attachments/big.txt',
        'test.md'
      ]);

      const runStates = await page.evaluate(async () => {
        const bundle = globalThis.ReportBundle.open(new URL('detail.zip', location.href).href);
        return bundle.text('timeline/runstates.json');
      });
      expect(JSON.parse(runStates)).toEqual([{ index: 0, label: 'Run 1', events: [] }]);
    } finally {
      await server.close();
    }
  });

  test('reads a stored entry back byte for byte', async ({ page }) => {
    const server = await serveBundle();
    try {
      await page.goto(server.url);
      const result = await page.evaluate(async () => {
        const bundle = globalThis.ReportBundle.open(new URL('detail.zip', location.href).href);
        const bytes = await bundle.bytes('attachments/1.png');
        return { length: bytes.length, magic: Array.from(bytes.slice(0, 8)) };
      });
      expect(result.length).toBe(9008);
      expect(result.magic).toEqual([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    } finally {
      await server.close();
    }
  });

  test('hands back a same-origin blob URL an <img> can load', async ({ page }) => {
    const server = await serveBundle();
    try {
      await page.goto(server.url);
      const objectURL = await page.evaluate(async () => {
        const bundle = globalThis.ReportBundle.open(new URL('detail.zip', location.href).href);
        return bundle.objectURL('attachments/1.png', 'image/png');
      });
      expect(objectURL).toMatch(/^blob:/);

      const cached = await page.evaluate(async () => {
        const bundle = globalThis.ReportBundle.open(new URL('detail.zip', location.href).href);
        const first = await bundle.objectURL('attachments/1.png', 'image/png');
        const second = await bundle.objectURL('attachments/1.png', 'image/png');
        return first === second;
      });
      expect(cached, 'repeat lookups reuse one blob URL').toBe(true);
    } finally {
      await server.close();
    }
  });

  test('pulls only part of a large archive when the host honours Range', async ({ page }) => {
    const server = await serveBundle({ large: true });
    try {
      await page.goto(server.url);
      await page.evaluate(async () => {
        const bundle = globalThis.ReportBundle.open(new URL('detail.zip', location.href).href);
        await bundle.text('timeline/runstates.json');
      });
      const { requests, bytesServed } = server.stats();
      expect(server.archiveLength).toBeGreaterThan(400 * 1024);
      expect(requests.length).toBeGreaterThan(0);
      expect(requests[0], 'first request asks for the archive tail').toMatch(/^bytes=-\d+$/);
      expect(requests.every(range => range !== null), 'every request is ranged').toBe(true);
      expect(bytesServed, 'reading one entry must not pull the whole archive')
        .toBeLessThan(server.archiveLength / 2);
    } finally {
      await server.close();
    }
  });

  test('falls back to the whole archive when the host ignores Range', async ({ page }) => {
    const server = await serveBundle({ supportsRange: false });
    try {
      await page.goto(server.url);
      const names = await openBundle(page);
      expect(names).toContain('attachments/big.txt');

      const text = await page.evaluate(async () => {
        const bundle = globalThis.ReportBundle.open(new URL('detail.zip', location.href).href);
        return bundle.text('attachments/big.txt');
      });
      expect(text.startsWith('timeline payload body.')).toBe(true);
      expect(text.length).toBe(23 * 4000);

      const { requests } = server.stats();
      expect(requests.length, 'a Range-blind host is fetched once, then served from memory').toBe(1);
    } finally {
      await server.close();
    }
  });

  test('reports a missing entry instead of hanging', async ({ page }) => {
    const server = await serveBundle();
    try {
      await page.goto(server.url);
      const result = await page.evaluate(async () => {
        const bundle = globalThis.ReportBundle.open(new URL('detail.zip', location.href).href);
        const present = await bundle.has('attachments/1.png');
        const absent = await bundle.has('attachments/nope.png');
        let message = null;
        try { await bundle.bytes('attachments/nope.png'); } catch (error) { message = error.message; }
        return { present, absent, message };
      });
      expect(result.present).toBe(true);
      expect(result.absent).toBe(false);
      expect(result.message).toContain('Missing bundle entry');
    } finally {
      await server.close();
    }
  });
});
