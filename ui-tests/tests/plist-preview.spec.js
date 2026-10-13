const { test, expect } = require('@playwright/test');
const path = require('path');

const parserPath = path.resolve(__dirname, '../../Sources/xctestreport/Resources/Web/plist-preview.js');

// Generated with Python's plistlib.dumps(..., fmt=plistlib.FMT_BINARY). These cover the unsigned
// short integer encodings produced by Foundation, signed 64-bit values, and a real/UTF-16 string.
const integers = 'YnBsaXN0MDCpAQIDBAUGBwgJEIAQ/xGAABH//xKAAAAAEv////8T//////////8T/////////4ATf/////////8IEhQWGRwhJi84AAAAAAAAAQEAAAAAAAAACgAAAAAAAAAAAAAAAAAAAEE=';
const dictionary = 'YnBsaXN0MDDTAQIDBAUGWV9fcHJvdG9fX1VmbG9hdFR0ZXh0V3Zpc2libGUjP/gAAAAAAABlAGgA6QBsAGwAbwgPGR8kLDUAAAAAAAABAQAAAAAAAAAHAAAAAAAAAAAAAAAAAAAAQA==';

function oneObject(bytes) {
  const object = Buffer.from(bytes);
  const trailer = Buffer.alloc(32);
  trailer[6] = trailer[7] = 1;
  trailer.writeBigUInt64BE(1n, 8);
  trailer.writeBigUInt64BE(BigInt(8 + object.length), 24);
  return Buffer.concat([Buffer.from('bplist00'), object, Buffer.from([8]), trailer]);
}

test.beforeEach(async ({ page }) => {
  await page.setContent('<!doctype html><title>Plist parser</title>');
  await page.addScriptTag({ path: parserPath });
});

test('reads short integers unsigned and negative 64-bit integers signed', async ({ page }) => {
  const parsed = await page.evaluate(encoded => {
    const bytes = Uint8Array.from(atob(encoded), value => value.charCodeAt(0));
    return PlistPreview.parseBinaryPlist(bytes.buffer);
  }, integers);
  expect(parsed).toEqual([128, 255, 32768, 65535, 2147483648, 4294967295, -1, -128, '9223372036854775807']);
});

test('respects a typed-array view and preserves dictionary keys such as __proto__', async ({ page }) => {
  const parsed = await page.evaluate(encoded => {
    const payload = Uint8Array.from(atob(encoded), value => value.charCodeAt(0));
    const outer = new Uint8Array(payload.length + 20);
    outer.set(payload, 11);
    const parsed = JSON.parse(PlistPreview.parseBinaryPlistToText(outer.subarray(11, 11 + payload.length)));
    return { keys: Object.keys(parsed), protoValue: parsed.__proto__, float: parsed.float, text: parsed.text };
  }, dictionary);
  expect(parsed.keys).toContain('__proto__');
  expect(parsed.protoValue).toBe('visible');
  expect(parsed.float).toBe(1.5);
  expect(parsed.text).toBe('héllo');
});

test('rejects declared object counts before allocating an oversized object table', async ({ page }) => {
  const payload = oneObject([0]);
  payload.writeBigUInt64BE(100001n, payload.length - 24);
  const message = await page.evaluate(bytes => {
    try { PlistPreview.parseBinaryPlist(Uint8Array.from(bytes)); } catch (error) { return error.message; }
  }, Array.from(payload));
  expect(message).toContain('object limit');
});

test('rejects oversized collection lengths before allocating an array', async ({ page }) => {
  const payload = oneObject([0xaf, 0x13, 0, 0, 0, 1, 0, 0, 0, 0]);
  const message = await page.evaluate(bytes => {
    try { PlistPreview.parseBinaryPlist(Uint8Array.from(bytes)); } catch (error) { return error.message; }
  }, Array.from(payload));
  expect(message).toContain('Array references exceed');
});

test('rejects deeply nested object graphs with a useful error', async ({ page }) => {
  const depth = 150;
  const objects = Array.from({ length: depth }, (_, index) => {
    const object = Buffer.alloc(3); object[0] = 0xa1; object.writeUInt16BE(index + 1, 1); return object;
  });
  objects.push(Buffer.from([0]));
  const offsets = Buffer.alloc(objects.length * 2);
  let offset = 8;
  objects.forEach((object, index) => { offsets.writeUInt16BE(offset, index * 2); offset += object.length; });
  const trailer = Buffer.alloc(32); trailer[6] = trailer[7] = 2;
  trailer.writeBigUInt64BE(BigInt(objects.length), 8); trailer.writeBigUInt64BE(BigInt(offset), 24);
  const payload = Buffer.concat([Buffer.from('bplist00'), ...objects, offsets, trailer]);
  const message = await page.evaluate(bytes => {
    try { PlistPreview.parseBinaryPlist(Uint8Array.from(bytes)); } catch (error) { return error.message; }
  }, Array.from(payload));
  expect(message).toContain('nesting limit');
});
