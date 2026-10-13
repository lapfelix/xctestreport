/*
 * Reads a per-test report bundle (a plain ZIP) without downloading all of it.
 *
 * A ZIP keeps its central directory at the end of the file, so one suffix Range request
 * ("bytes=-65536") yields the index, and each entry afterwards costs a single ranged GET that is
 * inflated with DecompressionStream('deflate-raw'). Servers that ignore Range answer 200 with the
 * whole archive; that response is kept and every later read is served from memory instead.
 */
(function() {
  'use strict';

  var TAIL_BYTES = 65536;
  var LOCAL_HEADER_SLACK = 256;
  var EOCD_SIGNATURE = 0x06054b50;
  var DEFAULT_CACHE_BYTES = 32 * 1024 * 1024;
  var DEFAULT_CACHE_ENTRIES = 32;

  function assert(condition, message) {
    if (!condition) throw new Error(message);
  }

  var CRC_TABLE = new Uint32Array(256);
  for (var crcIndex = 0; crcIndex < 256; crcIndex++) {
    var crcValue = crcIndex;
    for (var crcBit = 0; crcBit < 8; crcBit++) crcValue = (crcValue >>> 1) ^ ((crcValue & 1) ? 0xedb88320 : 0);
    CRC_TABLE[crcIndex] = crcValue;
  }

  function crc32(bytes) {
    var crc = 0xffffffff;
    for (var i = 0; i < bytes.length; i++) crc = (crc >>> 8) ^ CRC_TABLE[(crc ^ bytes[i]) & 0xff];
    return (crc ^ 0xffffffff) >>> 0;
  }

  function readU16(bytes, offset) {
    return bytes[offset] | (bytes[offset + 1] << 8);
  }

  function readU32(bytes, offset) {
    return (
      (bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24)) >>> 0
    );
  }

  function decodeName(bytes, offset, length) {
    return new TextDecoder('utf-8').decode(bytes.subarray(offset, offset + length));
  }

  function inflateRaw(bytes) {
    if (typeof DecompressionStream !== 'function') {
      return Promise.reject(new Error('This browser cannot inflate report bundles.'));
    }
    var stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream('deflate-raw'));
    return new Response(stream).arrayBuffer().then(function(buffer) {
      return new Uint8Array(buffer);
    });
  }

  function findEOCD(bytes) {
    // The EOCD is 22 bytes plus a comment we never write, so it sits at the very end.
    for (var i = bytes.length - 22; i >= 0; i--) {
      if (readU32(bytes, i) === EOCD_SIGNATURE && i + 22 + readU16(bytes, i + 20) === bytes.length) return i;
    }
    return -1;
  }

  function parseCentralDirectory(cd, expectedCount, directoryOffset) {
    var entries = Object.create(null);
    var order = [];
    var p = 0;
    while (p + 46 <= cd.length && readU32(cd, p) === 0x02014b50) {
      var method = readU16(cd, p + 10);
      var compressedSize = readU32(cd, p + 20);
      var uncompressedSize = readU32(cd, p + 24);
      var nameLength = readU16(cd, p + 28);
      var extraLength = readU16(cd, p + 30);
      var commentLength = readU16(cd, p + 32);
      var localHeaderOffset = readU32(cd, p + 42);
      assert(p + 46 + nameLength + extraLength + commentLength <= cd.length, 'Truncated ZIP directory entry.');
      assert((readU16(cd, p + 8) & 1) === 0, 'Encrypted report bundles are unsupported.');
      assert(method === 0 || method === 8, 'Unsupported compression in report bundle.');
      assert(localHeaderOffset + 30 + compressedSize <= directoryOffset, 'Bundle entry exceeds archive bounds.');
      var name = decodeName(cd, p + 46, nameLength);
      assert(!Object.prototype.hasOwnProperty.call(entries, name), 'Duplicate bundle entry: ' + name);
      entries[name] = {
        name: name,
        method: method,
        crc: readU32(cd, p + 16),
        compressedSize: compressedSize,
        uncompressedSize: uncompressedSize,
        localHeaderOffset: localHeaderOffset
      };
      order.push(name);
      p += 46 + nameLength + extraLength + commentLength;
    }
    assert(p === cd.length && order.length === expectedCount, 'Incomplete ZIP central directory.');
    return { entries: entries, order: order };
  }

  function Bundle(url, options) {
    this.url = url;
    this.directory = null;
    this.whole = null;
    this.byteCache = new Map();
    this.blobCache = new Map();
    this.byteCacheSize = 0;
    this.blobCacheSize = 0;
    this.pins = new Map();
    var limits = options && options.cacheLimits || {};
    this.maxCacheBytes = Number.isFinite(limits.bytes) && limits.bytes > 0 ? limits.bytes : DEFAULT_CACHE_BYTES;
    this.maxCacheEntries = Number.isInteger(limits.entries) && limits.entries > 0 ? limits.entries : DEFAULT_CACHE_ENTRIES;
    this.pending = Object.create(null);
    this.pendingURLs = Object.create(null);
    this.directoryPromise = null;
    this.generation = 0;
    this.requests = new Set();
  }

  Bundle.prototype._fetchRange = function(rangeHeader) {
    var self = this;
    var generation = this.generation;
    var controller = new AbortController();
    this.requests.add(controller);
    return fetch(this.url, { headers: rangeHeader ? { Range: rangeHeader } : {}, signal: controller.signal }).then(function(response) {
      assert(response.status === 200 || response.status === 206, 'HTTP ' + response.status + ' for ' + self.url);
      var total = -1;
      var start = null;
      var end = null;
      var contentRange = response.headers.get('Content-Range');
      if (response.status === 206 && contentRange) {
        var match = /^bytes (\d+)-(\d+)\/(\d+|\*)$/i.exec(contentRange);
        assert(match, 'Invalid Content-Range for report bundle.');
        start = Number(match[1]);
        end = Number(match[2]);
        total = match[3] === '*' ? -1 : Number(match[3]);
        assert(Number.isSafeInteger(start) && Number.isSafeInteger(end) && start <= end &&
          (total === -1 || Number.isSafeInteger(total) && end < total), 'Invalid report bundle range bounds.');
        var requested = /^bytes=(\d*)-(\d*)$/.exec(rangeHeader || '');
        assert(requested, 'Unexpected partial report bundle response.');
        if (requested[1]) {
          assert(start === Number(requested[1]) && end <= Number(requested[2]), 'Report bundle range starts at the wrong offset.');
        } else if (total >= 0) {
          assert(start === Math.max(0, total - Number(requested[2])) && end === total - 1, 'Incorrect report bundle suffix range.');
        }
      }
      return response.arrayBuffer().then(function(buffer) {
        assert(generation === self.generation, 'Report bundle was released.');
        if (start !== null) assert(buffer.byteLength === end - start + 1, 'Truncated report bundle range response.');
        return { partial: response.status === 206, total: total, start: start, bytes: new Uint8Array(buffer) };
      });
    }).finally(function() { self.requests.delete(controller); });
  };

  Bundle.prototype._fetchBlock = function(start, end) {
    var self = this;
    if (this.whole) return Promise.resolve(this.whole.subarray(start, end + 1));
    return this._fetchRange('bytes=' + start + '-' + end).then(function(result) {
      if (!result.partial) {
        self.whole = result.bytes;
        return self.whole.subarray(start, end + 1);
      }
      return result.bytes;
    });
  };

  Bundle.prototype.load = function() {
    if (this.directoryPromise) return this.directoryPromise;
    var self = this;
    var generation = this.generation;

    this.directoryPromise = this._fetchRange('bytes=-' + TAIL_BYTES)
      .then(function(result) {
        // Range ignored, or a bundle smaller than the tail window: either way it is all here.
        // A total of -1 means Content-Range was unreadable (a cross-origin host that does not
        // expose it), so the response cannot be assumed complete and has to be read as a tail.
        if (!result.partial || (result.total >= 0 && result.bytes.length >= result.total)) {
          self.whole = result.bytes;
          return self._directoryFromWhole();
        }
        return self._directoryFromTail(result.bytes);
      })
      .catch(function(error) {
        // A server that rejects Range outright still serves a plain GET.
        if (generation !== self.generation) throw error;
        return self._fetchRange(null)
          .then(function(result) {
            assert(!result.partial, 'Expected a complete report bundle.');
            self.whole = result.bytes;
            return self._directoryFromWhole();
          });
      })
      .catch(function(error) {
        // Let the next caller retry instead of replaying a transient failure forever.
        if (generation === self.generation) self.directoryPromise = null;
        throw error;
      });

    return this.directoryPromise;
  };

  Bundle.prototype._directoryFromWhole = function() {
    var eocd = findEOCD(this.whole);
    if (eocd < 0) throw new Error('Not a report bundle: ' + this.url);
    var size = readU32(this.whole, eocd + 12);
    var offset = readU32(this.whole, eocd + 16);
    var count = this._directoryCount(this.whole, eocd);
    assert(offset + size === eocd, 'Invalid report bundle directory bounds.');
    this.directory = parseCentralDirectory(this.whole.subarray(offset, offset + size), count, offset);
    return this.directory;
  };

  Bundle.prototype._directoryCount = function(bytes, eocd) {
    assert(readU16(bytes, eocd + 4) === 0 && readU16(bytes, eocd + 6) === 0, 'Multipart report bundles are unsupported.');
    var count = readU16(bytes, eocd + 10);
    assert(count !== 0xffff && readU32(bytes, eocd + 12) !== 0xffffffff && readU32(bytes, eocd + 16) !== 0xffffffff,
      'ZIP64 report bundles are unsupported.');
    assert(readU16(bytes, eocd + 8) === count, 'Invalid report bundle entry count.');
    return count;
  };

  Bundle.prototype._directoryFromTail = function(tail) {
    var self = this;
    var eocd = findEOCD(tail);
    if (eocd < 0) throw new Error('Not a report bundle: ' + this.url);
    var size = readU32(tail, eocd + 12);
    var offset = readU32(tail, eocd + 16);
    var count = this._directoryCount(tail, eocd);

    // The tail usually already covers the central directory; only refetch when it does not.
    var tailStart = null;
    if (tail.length >= size + (tail.length - eocd)) {
      tailStart = eocd - size;
    }
    if (tailStart !== null && tailStart >= 0 && readU32(tail, tailStart) === 0x02014b50) {
      self.directory = parseCentralDirectory(tail.subarray(tailStart, tailStart + size), count, offset);
      return self.directory;
    }

    return this._fetchBlock(offset, offset + size - 1).then(function(bytes) {
      self.directory = parseCentralDirectory(bytes, count, offset);
      return self.directory;
    });
  };

  Bundle.prototype.names = function() {
    return this.load().then(function(directory) {
      return directory.order.slice();
    });
  };

  Bundle.prototype.has = function(name) {
    return this.load().then(function(directory) {
      return Object.prototype.hasOwnProperty.call(directory.entries, name);
    });
  };

  Bundle.prototype._entryBytes = function(entry) {
    var self = this;

    function extract(block, blockStart) {
      var local = entry.localHeaderOffset - blockStart;
      assert(local >= 0 && local + 30 <= block.length && readU32(block, local) === 0x04034b50, 'Invalid ZIP local header for ' + entry.name);
      var nameLength = readU16(block, local + 26);
      var extraLength = readU16(block, local + 28);
      var dataStart = local + 30 + nameLength + extraLength;
      assert(dataStart + entry.compressedSize <= block.length, 'Truncated bundle entry: ' + entry.name);
      assert(readU16(block, local + 8) === entry.method && decodeName(block, local + 30, nameLength) === entry.name,
        'ZIP local header does not match directory for ' + entry.name);
      var raw = block.subarray(dataStart, dataStart + entry.compressedSize);
      return (entry.method === 0 ? Promise.resolve(raw) : inflateRaw(raw)).then(function(bytes) {
        assert(bytes.length === entry.uncompressedSize, 'Incorrect bundle entry size: ' + entry.name);
        assert(crc32(bytes) === entry.crc, 'Corrupt bundle entry: ' + entry.name);
        // Do not keep a whole ZIP or an oversized range buffer alive through a tiny stored entry.
        return bytes.byteOffset === 0 && bytes.byteLength === bytes.buffer.byteLength ? bytes : bytes.slice();
      });
    }

    if (this.whole) {
      return extract(this.whole, 0);
    }

    var start = entry.localHeaderOffset;
    var length = 30 + LOCAL_HEADER_SLACK + entry.compressedSize;
    return this._fetchBlock(start, start + length - 1).then(function(block) {
      assert(block.length >= 30 && readU32(block, 0) === 0x04034b50, 'Invalid ZIP local header for ' + entry.name);
      var nameLength = readU16(block, 26);
      var extraLength = readU16(block, 28);
      if (30 + nameLength + extraLength + entry.compressedSize > block.length) {
        // Unusually large extra field; refetch with the real header size known.
        var exact = 30 + nameLength + extraLength + entry.compressedSize;
        return self
          ._fetchBlock(start, start + exact - 1)
          .then(function(retry) {
            return extract(retry, start);
          });
      }
      return extract(block, start);
    });
  };

  Bundle.prototype.bytes = function(name) {
    var self = this;
    var cached = this.byteCache.get(name);
    if (cached) {
      this.byteCache.delete(name);
      this.byteCache.set(name, cached);
      return Promise.resolve(cached);
    }
    if (this.pending[name]) return this.pending[name];
    var generation = this.generation;

    var promise = this.load().then(function(directory) {
      var entry = directory.entries[name];
      if (!entry) throw new Error('Missing bundle entry: ' + name);
      return self._entryBytes(entry);
    }).then(function(bytes) {
      if (generation === self.generation && bytes.length <= self.maxCacheBytes) {
        self.byteCache.set(name, bytes);
        self.byteCacheSize += bytes.length;
        self._trimCaches();
      }
      return bytes;
    }).finally(function() {
      if (self.pending[name] === promise) delete self.pending[name];
    });

    this.pending[name] = promise;
    return promise;
  };

  Bundle.prototype.text = function(name) {
    return this.bytes(name).then(function(bytes) {
      return new TextDecoder('utf-8').decode(bytes);
    });
  };

  Bundle.prototype.objectURL = function(name, mimeType) {
    var self = this;
    var cached = this.blobCache.get(name);
    if (cached) {
      this.blobCache.delete(name);
      this.blobCache.set(name, cached);
      return Promise.resolve(cached.url);
    }
    if (this.pendingURLs[name]) return this.pendingURLs[name];
    var generation = this.generation;
    var promise = this.bytes(name).then(function(bytes) {
      assert(generation === self.generation, 'Report bundle was released.');
      var blob = new Blob([bytes], mimeType ? { type: mimeType } : undefined);
      var objectURL = URL.createObjectURL(blob);
      self.blobCache.set(name, { url: objectURL, size: bytes.length });
      self.blobCacheSize += bytes.length;
      // The URL returned to this caller stays usable. Consumers pin active media; an oversized
      // unpinned URL is discarded on the next cache operation or when the bundle is released.
      self._trimCaches(name);
      return objectURL;
    }).finally(function() {
      if (self.pendingURLs[name] === promise) delete self.pendingURLs[name];
    });
    this.pendingURLs[name] = promise;
    return promise;
  };

  Bundle.prototype._trimCaches = function(newURLName) {
    var self = this;
    this.byteCache.forEach(function(bytes, name) {
      if (self.byteCacheSize <= self.maxCacheBytes && self.byteCache.size <= self.maxCacheEntries) return;
      if (self.pins.has(name)) return;
      self.byteCache.delete(name);
      self.byteCacheSize -= bytes.length;
    });
    this.blobCache.forEach(function(blob, name) {
      if (self.blobCacheSize <= self.maxCacheBytes && self.blobCache.size <= self.maxCacheEntries) return;
      if (self.pins.has(name) || name === newURLName) return;
      URL.revokeObjectURL(blob.url);
      self.blobCache.delete(name);
      self.blobCacheSize -= blob.size;
    });
  };

  Bundle.prototype.pin = function(name) {
    this.pins.set(name, (this.pins.get(name) || 0) + 1);
  };

  Bundle.prototype.unpin = function(name) {
    var count = this.pins.get(name) || 0;
    if (count <= 1) this.pins.delete(name);
    else this.pins.set(name, count - 1);
    this._trimCaches();
  };

  Bundle.prototype.cacheStats = function() {
    return { bytes: this.byteCacheSize, byteEntries: this.byteCache.size,
      blobBytes: this.blobCacheSize, blobEntries: this.blobCache.size, pinnedEntries: this.pins.size };
  };

  Bundle.prototype.release = function() {
    this.generation++;
    this.requests.forEach(function(controller) { controller.abort(); });
    this.requests.clear();
    this.blobCache.forEach(function(blob) { URL.revokeObjectURL(blob.url); });
    this.blobCache.clear();
    this.byteCache.clear();
    this.byteCacheSize = this.blobCacheSize = 0;
    this.pins.clear();
    this.pending = Object.create(null);
    this.pendingURLs = Object.create(null);
    this.whole = this.directory = this.directoryPromise = null;
  };

  var bundles = Object.create(null);

  // Browsers block fetch on file://, so every bundled screenshot and attachment would fail with
  // only a console warning. Say so on the page instead.
  function showFileProtocolNotice() {
    if (location.protocol !== 'file:' || !document.body) return;
    if (!document.body.hasAttribute('data-report-bundle')) return;
    var notice = document.createElement('div');
    notice.className = 'file-protocol-notice';
    notice.setAttribute('role', 'status');
    notice.innerHTML =
      '<span>Attachment previews and UI snapshots need this report served over HTTP ' +
      '(for example <code>python3 -m http.server</code> in the report folder); ' +
      'browsers block them on <code>file://</code>.</span>' +
      '<button type="button" aria-label="Dismiss">\u00d7</button>';
    notice.querySelector('button').addEventListener('click', function() { notice.remove(); });
    document.body.appendChild(notice);
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', showFileProtocolNotice);
  } else {
    showFileProtocolNotice();
  }

  globalThis.ReportBundle = {
    open: function(url, options) {
      if (!bundles[url]) bundles[url] = new Bundle(url, options);
      return bundles[url];
    },
    releaseAll: function() {
      for (var url in bundles) bundles[url].release();
    },
    _reset: function() {
      for (var url in bundles) bundles[url].release();
      bundles = Object.create(null);
    }
  };
})();
