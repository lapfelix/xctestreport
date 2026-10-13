(function(global) {
  'use strict';

  var HEADER = 'bplist00';
  var TRAILER_LENGTH = 32;
  var EPOCH_2001_MS = Date.UTC(2001, 0, 1, 0, 0, 0, 0);
  var MAX_DEPTH = 14;
  var MAX_ARRAY_ITEMS = 240;
  var MAX_OBJECT_KEYS = 240;
  var MAX_STRING_LENGTH = 8000;
  var MAX_OUTPUT_CHARS = 220000;
  var MAX_DATA_HEX_BYTES = 64;
  var MAX_PARSE_OBJECTS = 100000;
  var MAX_PARSE_REFERENCES = 1000000;
  var MAX_PARSE_DEPTH = 128;
  var MAX_PARSE_STRING_BYTES = 32 * 1024 * 1024;
  var utf8Decoder = new TextDecoder('utf-8');

  function assert(condition, message) {
    if (!condition) throw new Error(message);
  }

  function readUInt(bytes, start, byteCount) {
    assert(Number.isSafeInteger(start) && byteCount > 0 && byteCount <= 16 && start >= 0 &&
      start + byteCount <= bytes.length, 'Integer exceeds plist bounds');
    var value = 0n;
    for (var i = 0; i < byteCount; i += 1) {
      value = (value << 8n) | BigInt(bytes[start + i]);
    }
    return value;
  }

  function readUIntAsNumber(bytes, start, byteCount, label) {
    var value = readUInt(bytes, start, byteCount);
    var maxSafe = BigInt(Number.MAX_SAFE_INTEGER);
    assert(value <= maxSafe, label + ' exceeds Number.MAX_SAFE_INTEGER');
    return Number(value);
  }

  function readSignedInteger(bytes, start, byteCount) {
    var raw = readUInt(bytes, start, byteCount);
    var bits = BigInt(byteCount * 8);
    var signMask = 1n << (bits - 1n);
    // Binary plists encode 1-, 2-, and 4-byte integer objects as unsigned. Negative integers
    // use at least eight bytes, even when their magnitude would fit in a shorter signed value.
    if (byteCount >= 8 && (raw & signMask) !== 0n) {
      raw = raw - (1n << bits);
    }
    var minSafe = BigInt(Number.MIN_SAFE_INTEGER);
    var maxSafe = BigInt(Number.MAX_SAFE_INTEGER);
    if (raw >= minSafe && raw <= maxSafe) {
      return Number(raw);
    }
    return raw.toString();
  }

  function decodeUtf16BE(bytes, start, charCount) {
    var chars = new Array(charCount);
    for (var i = 0; i < charCount; i += 1) {
      var byteOffset = start + (i * 2);
      var codeUnit = (bytes[byteOffset] << 8) | bytes[byteOffset + 1];
      chars[i] = String.fromCharCode(codeUnit);
    }
    return chars.join('');
  }

  function dataToHex(bytes, start, length, maxBytes) {
    var limit = Math.min(length, maxBytes);
    var out = new Array(limit);
    for (var i = 0; i < limit; i += 1) {
      out[i] = bytes[start + i].toString(16).padStart(2, '0');
    }
    var joined = out.join(' ');
    if (length > limit) {
      joined += ' ...';
    }
    return joined;
  }

  function parseBinaryPlist(arrayBuffer) {
    var bytes = ArrayBuffer.isView(arrayBuffer)
      ? new Uint8Array(arrayBuffer.buffer, arrayBuffer.byteOffset, arrayBuffer.byteLength)
      : new Uint8Array(arrayBuffer);
    assert(bytes.length >= HEADER.length + TRAILER_LENGTH, 'Input is too small to be a binary plist');
    var header = utf8Decoder.decode(bytes.subarray(0, HEADER.length));
    assert(header === HEADER, 'Unsupported plist header: ' + header);

    var trailerOffset = bytes.length - TRAILER_LENGTH;
    var offsetIntSize = bytes[trailerOffset + 6];
    var objectRefSize = bytes[trailerOffset + 7];
    assert(offsetIntSize > 0 && offsetIntSize <= 8, 'Invalid offset integer size');
    assert(objectRefSize > 0 && objectRefSize <= 8, 'Invalid object reference size');

    var numObjects = readUIntAsNumber(bytes, trailerOffset + 8, 8, 'numObjects');
    var topObject = readUIntAsNumber(bytes, trailerOffset + 16, 8, 'topObject');
    var offsetTableOffset = readUIntAsNumber(bytes, trailerOffset + 24, 8, 'offsetTableOffset');

    assert(numObjects > 0, 'Binary plist has no objects');
    assert(topObject >= 0 && topObject < numObjects, 'topObject index is out of bounds');
    assert(offsetTableOffset >= HEADER.length, 'offset table overlaps header');
    assert(numObjects <= MAX_PARSE_OBJECTS, 'Binary plist exceeds the object limit');
    assert(offsetTableOffset <= trailerOffset && numObjects <= Math.floor((trailerOffset - offsetTableOffset) / offsetIntSize),
      'Offset table exceeds plist bounds');

    var offsets = new Array(numObjects);
    for (var i = 0; i < numObjects; i += 1) {
      var tableEntryOffset = offsetTableOffset + (i * offsetIntSize);
      assert(tableEntryOffset + offsetIntSize <= trailerOffset, 'Offset table entry out of bounds');
      offsets[i] = readUIntAsNumber(bytes, tableEntryOffset, offsetIntSize, 'objectOffset');
    }

    var objectCache = new Array(numObjects);
    var parsingStack = new Set();
    var floatView = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    var referenceCount = 0;
    var stringBytes = 0;

    function parseLength(markerOffset, markerInfo) {
      if (markerInfo < 0x0f) {
        return { length: markerInfo, bytesConsumed: 0 };
      }

      assert(markerOffset + 2 <= offsetTableOffset, 'Missing length integer');
      var intMarker = bytes[markerOffset + 1];
      var intType = intMarker >> 4;
      var intInfo = intMarker & 0x0f;
      assert(intType === 0x1, 'Length object is not an integer');
      var lengthByteCount = 1 << intInfo;
      var valueOffset = markerOffset + 2;
      assert(lengthByteCount <= 8 && valueOffset + lengthByteCount <= offsetTableOffset, 'Length integer exceeds object bounds');

      return {
        length: readUIntAsNumber(bytes, valueOffset, lengthByteCount, 'objectLength'),
        bytesConsumed: 1 + lengthByteCount,
      };
    }

    function parseObjectRef(start) {
      assert(++referenceCount <= MAX_PARSE_REFERENCES, 'Binary plist exceeds the reference limit');
      assert(start + objectRefSize <= offsetTableOffset, 'Object reference exceeds object bounds');
      var ref = readUIntAsNumber(bytes, start, objectRefSize, 'objectRef');
      assert(ref >= 0 && ref < numObjects, 'Object reference out of bounds');
      return ref;
    }

    function parseObject(objectIndex, depth) {
      if (objectCache[objectIndex] !== undefined) {
        return objectCache[objectIndex];
      }
      if (parsingStack.has(objectIndex)) {
        return '[Circular #' + objectIndex + ']';
      }
      assert(depth <= MAX_PARSE_DEPTH, 'Binary plist exceeds the nesting limit');

      parsingStack.add(objectIndex);
      var objectOffset = offsets[objectIndex];
      assert(objectOffset >= HEADER.length && objectOffset < offsetTableOffset, 'Object offset out of bounds');

      var marker = bytes[objectOffset];
      var objectType = marker >> 4;
      var objectInfo = marker & 0x0f;
      var value;

      if (objectType === 0x0) {
        if (objectInfo === 0x0 || objectInfo === 0x0f) value = null;
        else if (objectInfo === 0x8) value = false;
        else if (objectInfo === 0x9) value = true;
        else value = '[Unknown simple object 0x' + objectInfo.toString(16) + ']';
      } else if (objectType === 0x1) {
        var intByteCount = 1 << objectInfo;
        assert(intByteCount <= 16 && objectOffset + 1 + intByteCount <= offsetTableOffset, 'Integer exceeds object bounds');
        value = readSignedInteger(bytes, objectOffset + 1, intByteCount);
      } else if (objectType === 0x2) {
        var realByteCount = 1 << objectInfo;
        var realOffset = objectOffset + 1;
        assert(realByteCount <= 8 && realOffset + realByteCount <= offsetTableOffset, 'Real exceeds object bounds');
        if (realByteCount === 4) {
          value = floatView.getFloat32(realOffset, false);
        } else if (realByteCount === 8) {
          value = floatView.getFloat64(realOffset, false);
        } else {
          value = '[Unsupported real width: ' + realByteCount + ']';
        }
      } else if (objectType === 0x3) {
        assert(objectInfo === 0x3, 'Unexpected date marker width');
        var dateOffset = objectOffset + 1;
        assert(dateOffset + 8 <= offsetTableOffset, 'Date exceeds object bounds');
        var secondsSince2001 = floatView.getFloat64(dateOffset, false);
        var msSinceUnixEpoch = EPOCH_2001_MS + (secondsSince2001 * 1000);
        var date = new Date(msSinceUnixEpoch);
        value = Number.isFinite(date.getTime()) ? date.toISOString() : '[Invalid date]';
      } else if (objectType === 0x4) {
        var dataLengthInfo = parseLength(objectOffset, objectInfo);
        var dataStart = objectOffset + 1 + dataLengthInfo.bytesConsumed;
        var dataLength = dataLengthInfo.length;
        assert(dataStart + dataLength <= offsetTableOffset, 'Data object exceeds object bounds');
        value = {
          __plistType: 'data',
          bytes: dataLength,
          hexPreview: dataToHex(bytes, dataStart, dataLength, MAX_DATA_HEX_BYTES),
        };
      } else if (objectType === 0x5) {
        var asciiLengthInfo = parseLength(objectOffset, objectInfo);
        var asciiStart = objectOffset + 1 + asciiLengthInfo.bytesConsumed;
        var asciiLength = asciiLengthInfo.length;
        assert(asciiStart + asciiLength <= offsetTableOffset, 'ASCII string exceeds object bounds');
        stringBytes += asciiLength;
        assert(stringBytes <= MAX_PARSE_STRING_BYTES, 'Binary plist exceeds the string limit');
        value = utf8Decoder.decode(bytes.subarray(asciiStart, asciiStart + asciiLength));
      } else if (objectType === 0x6) {
        var utf16LengthInfo = parseLength(objectOffset, objectInfo);
        var utf16Start = objectOffset + 1 + utf16LengthInfo.bytesConsumed;
        var charCount = utf16LengthInfo.length;
        var byteCount = charCount * 2;
        assert(utf16Start + byteCount <= offsetTableOffset, 'UTF-16 string exceeds object bounds');
        stringBytes += byteCount;
        assert(stringBytes <= MAX_PARSE_STRING_BYTES, 'Binary plist exceeds the string limit');
        value = decodeUtf16BE(bytes, utf16Start, charCount);
      } else if (objectType === 0x8) {
        var uidByteCount = objectInfo + 1;
        var uidStart = objectOffset + 1;
        assert(uidStart + uidByteCount <= offsetTableOffset, 'UID exceeds object bounds');
        value = {
          __plistType: 'uid',
          value: readUInt(bytes, uidStart, uidByteCount).toString(),
        };
      } else if (objectType === 0xa) {
        var arrayLengthInfo = parseLength(objectOffset, objectInfo);
        var arrayLength = arrayLengthInfo.length;
        var arrayStart = objectOffset + 1 + arrayLengthInfo.bytesConsumed;
        assert(arrayLength <= MAX_PARSE_REFERENCES - referenceCount && arrayLength <= Math.floor((offsetTableOffset - arrayStart) / objectRefSize),
          'Array references exceed plist bounds or reference limit');
        value = new Array(arrayLength);
        for (var a = 0; a < arrayLength; a += 1) {
          var itemRef = parseObjectRef(arrayStart + (a * objectRefSize));
          value[a] = parseObject(itemRef, depth + 1);
        }
      } else if (objectType === 0xd) {
        var dictLengthInfo = parseLength(objectOffset, objectInfo);
        var dictLength = dictLengthInfo.length;
        var dictRefsStart = objectOffset + 1 + dictLengthInfo.bytesConsumed;
        var keysStart = dictRefsStart;
        var valuesStart = keysStart + (dictLength * objectRefSize);
        assert(dictLength * 2 <= MAX_PARSE_REFERENCES - referenceCount &&
          dictLength <= Math.floor((offsetTableOffset - dictRefsStart) / (2 * objectRefSize)),
          'Dictionary references exceed plist bounds or reference limit');
        value = Object.create(null);
        for (var d = 0; d < dictLength; d += 1) {
          var keyRef = parseObjectRef(keysStart + (d * objectRefSize));
          var valRef = parseObjectRef(valuesStart + (d * objectRefSize));
          var keyValue = parseObject(keyRef, depth + 1);
          var keyName = typeof keyValue === 'string' ? keyValue : String(keyValue);
          value[keyName] = parseObject(valRef, depth + 1);
        }
      } else {
        value = '[Unsupported object type 0x' + objectType.toString(16) + ']';
      }

      parsingStack.delete(objectIndex);
      objectCache[objectIndex] = value;
      return value;
    }

    return parseObject(topObject, 0);
  }

  function normalizeValue(value, depth, stack, budget) {
    budget.nodes += 1;
    if (budget.nodes > 10000 || budget.characters > MAX_OUTPUT_CHARS) return '[Preview limit reached]';
    if (depth > MAX_DEPTH) {
      return '[Max depth reached]';
    }
    if (value == null || typeof value === 'boolean' || typeof value === 'number') {
      return value;
    }
    if (typeof value === 'string') {
      budget.characters += Math.min(value.length, MAX_STRING_LENGTH);
      if (value.length > MAX_STRING_LENGTH) {
        return value.slice(0, MAX_STRING_LENGTH) + '\n...[truncated]';
      }
      return value;
    }
    if (Array.isArray(value)) {
      var itemCount = Math.min(value.length, MAX_ARRAY_ITEMS);
      var normalizedArray = new Array(itemCount);
      for (var i = 0; i < itemCount; i += 1) {
        normalizedArray[i] = normalizeValue(value[i], depth + 1, stack, budget);
      }
      if (value.length > itemCount) {
        normalizedArray.push('[... ' + (value.length - itemCount) + ' more items]');
      }
      return normalizedArray;
    }
    if (typeof value === 'object') {
      if (value.__plistType === 'uid') {
        return { type: 'UID', value: value.value };
      }
      if (value.__plistType === 'data') {
        return {
          type: 'Data',
          bytes: value.bytes,
          hexPreview: value.hexPreview,
        };
      }

      if (stack.has(value)) {
        return '[Circular]';
      }
      stack.add(value);

      var keys = Object.keys(value);
      var normalized = Object.create(null);
      var keyCount = Math.min(keys.length, MAX_OBJECT_KEYS);
      for (var k = 0; k < keyCount; k += 1) {
        var key = keys[k];
        var displayKey = key.length > MAX_STRING_LENGTH ? key.slice(0, MAX_STRING_LENGTH) + '...[truncated]' : key;
        budget.characters += displayKey.length;
        normalized[displayKey] = normalizeValue(value[key], depth + 1, stack, budget);
      }
      if (keys.length > keyCount) {
        normalized['...'] = '(' + (keys.length - keyCount) + ' more keys)';
      }
      stack.delete(value);
      return normalized;
    }

    return String(value);
  }

  function parseBinaryPlistToText(arrayBuffer) {
    var parsed = parseBinaryPlist(arrayBuffer);
    var normalized = normalizeValue(parsed, 0, new WeakSet(), { nodes: 0, characters: 0 });
    var text = JSON.stringify(normalized, null, 2);
    if (!text) {
      text = String(normalized);
    }
    if (text.length > MAX_OUTPUT_CHARS) {
      text = text.slice(0, MAX_OUTPUT_CHARS) + '\n...[truncated]';
    }
    return text;
  }

  global.PlistPreview = {
    parseBinaryPlist: parseBinaryPlist,
    parseBinaryPlistToText: parseBinaryPlistToText,
  };
})(window);
