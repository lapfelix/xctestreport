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
      if (readU32(bytes, i) === EOCD_SIGNATURE) return i;
    }
    return -1;
  }

  function parseCentralDirectory(cd) {
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
      var name = decodeName(cd, p + 46, nameLength);
      entries[name] = {
        name: name,
        method: method,
        compressedSize: compressedSize,
        uncompressedSize: uncompressedSize,
        localHeaderOffset: localHeaderOffset
      };
      order.push(name);
      p += 46 + nameLength + extraLength + commentLength;
    }
    return { entries: entries, order: order };
  }

  function Bundle(url) {
    this.url = url;
    this.directory = null;
    this.whole = null;
    this.blobURLs = Object.create(null);
    this.pending = Object.create(null);
    this.directoryPromise = null;
  }

  Bundle.prototype._fetchRange = function(rangeHeader) {
    return fetch(this.url, { headers: { Range: rangeHeader } }).then(function(response) {
      if (!response.ok) throw new Error('HTTP ' + response.status + ' for ' + this.url);
      var total = -1;
      var contentRange = response.headers.get('Content-Range');
      if (contentRange) {
        var slash = contentRange.lastIndexOf('/');
        if (slash >= 0) {
          var parsed = parseInt(contentRange.slice(slash + 1), 10);
          if (!isNaN(parsed)) total = parsed;
        }
      }
      return response.arrayBuffer().then(function(buffer) {
        return { partial: response.status === 206, total: total, bytes: new Uint8Array(buffer) };
      });
    }.bind(this));
  };

  Bundle.prototype.load = function() {
    if (this.directoryPromise) return this.directoryPromise;
    var self = this;

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
        return fetch(self.url)
          .then(function(response) {
            if (!response.ok) throw error;
            return response.arrayBuffer();
          })
          .then(function(buffer) {
            self.whole = new Uint8Array(buffer);
            return self._directoryFromWhole();
          });
      });

    return this.directoryPromise;
  };

  Bundle.prototype._directoryFromWhole = function() {
    var eocd = findEOCD(this.whole);
    if (eocd < 0) throw new Error('Not a report bundle: ' + this.url);
    var size = readU32(this.whole, eocd + 12);
    var offset = readU32(this.whole, eocd + 16);
    this.directory = parseCentralDirectory(this.whole.subarray(offset, offset + size));
    return this.directory;
  };

  Bundle.prototype._directoryFromTail = function(tail) {
    var self = this;
    var eocd = findEOCD(tail);
    if (eocd < 0) throw new Error('Not a report bundle: ' + this.url);
    var size = readU32(tail, eocd + 12);
    var offset = readU32(tail, eocd + 16);

    // The tail usually already covers the central directory; only refetch when it does not.
    var tailStart = null;
    if (tail.length >= size + (tail.length - eocd)) {
      tailStart = eocd - size;
    }
    if (tailStart !== null && tailStart >= 0 && readU32(tail, tailStart) === 0x02014b50) {
      self.directory = parseCentralDirectory(tail.subarray(tailStart, tailStart + size));
      return self.directory;
    }

    return this._fetchRange('bytes=' + offset + '-' + (offset + size - 1)).then(function(result) {
      self.directory = parseCentralDirectory(result.bytes);
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
      var nameLength = readU16(block, local + 26);
      var extraLength = readU16(block, local + 28);
      var dataStart = local + 30 + nameLength + extraLength;
      var raw = block.subarray(dataStart, dataStart + entry.compressedSize);
      if (entry.method === 0) return Promise.resolve(raw);
      if (entry.method !== 8) {
        return Promise.reject(new Error('Unsupported compression in bundle entry ' + entry.name));
      }
      return inflateRaw(raw);
    }

    if (this.whole) {
      return extract(this.whole, 0);
    }

    var start = entry.localHeaderOffset;
    var length = 30 + LOCAL_HEADER_SLACK + entry.compressedSize;
    return this._fetchRange('bytes=' + start + '-' + (start + length - 1)).then(function(result) {
      var block = result.bytes;
      var nameLength = readU16(block, 26);
      var extraLength = readU16(block, 28);
      if (30 + nameLength + extraLength + entry.compressedSize > block.length) {
        // Unusually large extra field; refetch with the real header size known.
        var exact = 30 + nameLength + extraLength + entry.compressedSize;
        return self
          ._fetchRange('bytes=' + start + '-' + (start + exact - 1))
          .then(function(retry) {
            return extract(retry.bytes, start);
          });
      }
      return extract(block, start);
    });
  };

  Bundle.prototype.bytes = function(name) {
    var self = this;
    if (this.pending[name]) return this.pending[name];

    var promise = this.load().then(function(directory) {
      var entry = directory.entries[name];
      if (!entry) throw new Error('Missing bundle entry: ' + name);
      return self._entryBytes(entry);
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
    if (this.blobURLs[name]) return Promise.resolve(this.blobURLs[name]);
    return this.bytes(name).then(function(bytes) {
      if (self.blobURLs[name]) return self.blobURLs[name];
      var blob = new Blob([bytes], mimeType ? { type: mimeType } : undefined);
      var objectURL = URL.createObjectURL(blob);
      self.blobURLs[name] = objectURL;
      return objectURL;
    });
  };

  Bundle.prototype.release = function() {
    for (var name in this.blobURLs) {
      URL.revokeObjectURL(this.blobURLs[name]);
    }
    this.blobURLs = Object.create(null);
    this.pending = Object.create(null);
  };

  var bundles = Object.create(null);

  globalThis.ReportBundle = {
    open: function(url) {
      if (!bundles[url]) bundles[url] = new Bundle(url);
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
