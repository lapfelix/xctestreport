(function() {
  var root = document.querySelector('[data-timeline-root]');
  if (!root) return;
  var externalJSONPayloads = Object.create(null);
  var externalJSONLoaders = [];

  function decodeBase64Payload(base64Value) {
    if (!base64Value || typeof base64Value !== 'string') return null;
    if (typeof atob !== 'function') return null;
    try {
      var binary = atob(base64Value);
      var length = binary.length;
      var bytes = new Uint8Array(length);
      for (var index = 0; index < length; index += 1) {
        bytes[index] = binary.charCodeAt(index);
      }
      return bytes.buffer;
    } catch (error) {
      return null;
    }
  }

  function resolveInlineBinaryPayload(src) {
    var key = src == null ? '' : String(src);
    if (!key) return null;
    var store = window.__xctestreportTimelinePayloads;
    if (!store || typeof store !== 'object') return null;

    if (typeof store[key] === 'string') return store[key];

    try {
      var absoluteKey = new URL(key, window.location.href).href;
      if (typeof store[absoluteKey] === 'string') return store[absoluteKey];
    } catch (error) {}

    try {
      var decodedKey = decodeURIComponent(key);
      if (decodedKey !== key && typeof store[decodedKey] === 'string') return store[decodedKey];
    } catch (error) {}

    return null;
  }

  function loadExternalPayloadBuffer(src) {
    var inlinePayload = resolveInlineBinaryPayload(src);
    if (window.location.protocol === 'file:') {
      var decodedInlinePayload = decodeBase64Payload(inlinePayload);
      if (decodedInlinePayload) {
        return Promise.resolve(decodedInlinePayload);
      }
    }

    return fetch(src)
      .then(function(response) {
        if (!response.ok) {
          throw new Error('HTTP ' + response.status);
        }
        return response.arrayBuffer();
      })
      .catch(function(fetchError) {
        var decodedPayload = decodeBase64Payload(inlinePayload);
        if (!decodedPayload) {
          throw fetchError;
        }
        return decodedPayload;
      });
  }

  function parseJSONScript(selector) {
    var node = document.querySelector(selector);
    if (!node) return [];
    var inlineArray = [];
    try {
      var value = JSON.parse(node.textContent || '[]');
      inlineArray = Array.isArray(value) ? value : [];
    } catch (error) {
      console.warn('Failed to parse timeline JSON payload for selector:', selector, error);
      inlineArray = [];
    }

    var src = node.getAttribute('data-src');
    if (src) {
      externalJSONLoaders.push(
        loadExternalPayloadBuffer(src)
          .then(function(buffer) {
            return maybeDecompressGzipBuffer(buffer);
          })
          .then(function(buffer) {
            var decoded = new TextDecoder('utf-8').decode(new Uint8Array(buffer));
            var parsed = JSON.parse(decoded || '[]');
            externalJSONPayloads[selector] = Array.isArray(parsed) ? parsed : [];
          })
          .catch(function(error) {
            console.warn('Failed to load external timeline payload for', selector, src, error);
          })
      );
    }

    return inlineArray;
  }

  function asNumber(value, fallback) {
    var number = Number(value);
    return Number.isFinite(number) ? number : fallback;
  }

  function asString(value, fallback) {
    return value == null ? fallback : String(value);
  }

  function asBoolean(value) {
    return value === true || value === 1 || value === '1';
  }

  function objectOrEmpty(value) {
    return value && typeof value === 'object' && !Array.isArray(value) ? value : {};
  }

  function decodeTimelineEvent(raw) {
    if (Array.isArray(raw)) {
      var compactTime = asNumber(raw[2], 0);
      return {
        id: asString(raw[0], ''),
        title: asString(raw[1], 'Timeline event'),
        time: compactTime,
        endTime: asNumber(raw[3], compactTime),
        kind: asString(raw[4], 'event')
      };
    }

    var source = objectOrEmpty(raw);
    var time = asNumber(source.time != null ? source.time : source.s, 0);
    return {
      id: asString(source.id != null ? source.id : source.i, ''),
      title: asString(source.title != null ? source.title : source.t, 'Timeline event'),
      time: time,
      endTime: asNumber(source.endTime != null ? source.endTime : source.e, time),
      kind: asString(source.kind != null ? source.kind : source.k, 'event')
    };
  }

  function decodeTouchPoint(raw) {
    if (Array.isArray(raw)) {
      return {
        time: asNumber(raw[0], 0),
        x: asNumber(raw[1], 0),
        y: asNumber(raw[2], 0)
      };
    }

    var source = objectOrEmpty(raw);
    return {
      time: asNumber(source.time != null ? source.time : source.t, 0),
      x: asNumber(source.x, 0),
      y: asNumber(source.y, 0)
    };
  }

  function decodeTouchGesture(raw) {
    if (Array.isArray(raw)) {
      return {
        startTime: asNumber(raw[0], 0),
        endTime: asNumber(raw[1], 0),
        width: asNumber(raw[2], 0),
        height: asNumber(raw[3], 0),
        points: (Array.isArray(raw[4]) ? raw[4] : []).map(decodeTouchPoint)
      };
    }

    var source = objectOrEmpty(raw);
    return {
      startTime: asNumber(source.startTime != null ? source.startTime : source.s, 0),
      endTime: asNumber(source.endTime != null ? source.endTime : source.e, 0),
      width: asNumber(source.width != null ? source.width : source.w, 0),
      height: asNumber(source.height != null ? source.height : source.h, 0),
      points: (Array.isArray(source.points || source.p) ? (source.points || source.p) : []).map(decodeTouchPoint)
    };
  }

  function decodeHierarchyElement(raw) {
    if (Array.isArray(raw)) {
      return {
        id: asString(raw[0], ''),
        depth: asNumber(raw[1], 0),
        role: asString(raw[2], ''),
        name: raw[3] == null ? null : String(raw[3]),
        label: raw[4] == null ? null : String(raw[4]),
        identifier: raw[5] == null ? null : String(raw[5]),
        value: raw[6] == null ? null : String(raw[6]),
        x: asNumber(raw[7], 0),
        y: asNumber(raw[8], 0),
        width: asNumber(raw[9], 0),
        height: asNumber(raw[10], 0),
        properties: objectOrEmpty(raw[11])
      };
    }

    var source = objectOrEmpty(raw);
    return {
      id: asString(source.id != null ? source.id : source.i, ''),
      depth: asNumber(source.depth != null ? source.depth : source.d, 0),
      role: asString(source.role != null ? source.role : source.r, ''),
      name: source.name != null ? source.name : (source.n != null ? source.n : null),
      label: source.label != null ? source.label : (source.l != null ? source.l : null),
      identifier: source.identifier != null ? source.identifier : (source.q != null ? source.q : null),
      value: source.value != null ? source.value : (source.v != null ? source.v : null),
      x: asNumber(source.x, 0),
      y: asNumber(source.y, 0),
      width: asNumber(source.width != null ? source.width : source.w, 0),
      height: asNumber(source.height != null ? source.height : source.h, 0),
      properties: objectOrEmpty(source.properties != null ? source.properties : source.p)
    };
  }

  function decodeHierarchySnapshot(raw) {
    if (Array.isArray(raw)) {
      return {
        id: asString(raw[0], ''),
        label: asString(raw[1], ''),
        time: asNumber(raw[2], 0),
        width: asNumber(raw[3], 0),
        height: asNumber(raw[4], 0),
        failureAssociated: asBoolean(raw[5]),
        elements: (Array.isArray(raw[6]) ? raw[6] : []).map(decodeHierarchyElement)
      };
    }

    var source = objectOrEmpty(raw);
    var elements = source.elements != null ? source.elements : source.e;
    return {
      id: asString(source.id != null ? source.id : source.i, ''),
      label: asString(source.label != null ? source.label : source.l, ''),
      time: asNumber(source.time != null ? source.time : source.t, 0),
      width: asNumber(source.width != null ? source.width : source.w, 0),
      height: asNumber(source.height != null ? source.height : source.h, 0),
      failureAssociated: asBoolean(source.failureAssociated != null ? source.failureAssociated : source.f),
      elements: (Array.isArray(elements) ? elements : []).map(decodeHierarchyElement)
    };
  }

  function normalizeRunStates(rawStates) {
    if (!Array.isArray(rawStates)) return [];
    return rawStates.map(function(rawState, index) {
      if (Array.isArray(rawState)) {
        return {
          index: index,
          label: 'Run ' + (index + 1),
          timelineBase: asNumber(rawState[0], 0),
          firstEventLabel: asString(rawState[1], 'No event selected'),
          initialFailureEventIndex: asNumber(rawState[2], -1),
          events: (Array.isArray(rawState[3]) ? rawState[3] : []).map(decodeTimelineEvent),
          touchGestures: (Array.isArray(rawState[4]) ? rawState[4] : []).map(decodeTouchGesture),
          hierarchySnapshots: (Array.isArray(rawState[5]) ? rawState[5] : []).map(decodeHierarchySnapshot)
        };
      }

      var source = objectOrEmpty(rawState);
      return {
        index: asNumber(source.index != null ? source.index : source.i, index),
        label: asString(source.label != null ? source.label : source.l, 'Run ' + (index + 1)),
        timelineBase: asNumber(source.timelineBase != null ? source.timelineBase : source.b, 0),
        firstEventLabel: asString(source.firstEventLabel != null ? source.firstEventLabel : source.f, 'No event selected'),
        initialFailureEventIndex: asNumber(source.initialFailureEventIndex != null ? source.initialFailureEventIndex : source.x, -1),
        events: (Array.isArray(source.events != null ? source.events : source.e)
          ? (source.events != null ? source.events : source.e)
          : []).map(decodeTimelineEvent),
        touchGestures: (Array.isArray(source.touchGestures != null ? source.touchGestures : source.t)
          ? (source.touchGestures != null ? source.touchGestures : source.t)
          : []).map(decodeTouchGesture),
        hierarchySnapshots: (Array.isArray(source.hierarchySnapshots != null ? source.hierarchySnapshots : source.h)
          ? (source.hierarchySnapshots != null ? source.hierarchySnapshots : source.h)
          : []).map(decodeHierarchySnapshot)
      };
    });
  }

  function decodeScreenshot(raw) {
    if (Array.isArray(raw)) {
      return {
        label: asString(raw[0], ''),
        src: asString(raw[1], ''),
        time: asNumber(raw[2], 0),
        failureAssociated: asBoolean(raw[3])
      };
    }

    var source = objectOrEmpty(raw);
    return {
      label: asString(source.label != null ? source.label : source.l, ''),
      src: asString(source.src != null ? source.src : source.s, ''),
      time: asNumber(source.time != null ? source.time : source.t, 0),
      failureAssociated: asBoolean(source.failureAssociated != null ? source.failureAssociated : source.f)
    };
  }

  function normalizeScreenshots(rawScreenshots) {
    if (!Array.isArray(rawScreenshots)) return [];
    return rawScreenshots.map(decodeScreenshot);
  }

  var controls = document.querySelector('[data-timeline-controls]');
  var scrubber = controls.querySelector('[data-scrubber]');
  var scrubberMarkerLane = controls.querySelector('[data-scrubber-markers]');
  var timeLabel = controls.querySelector('[data-playback-time]');
  var totalTimeLabel = controls.querySelector('[data-total-time]');
  var runSelector = root.querySelector('[data-run-selector]');
  var runPanels = Array.prototype.slice.call(root.querySelectorAll('[data-run-panel]'));
  var eventLabel = null;
  var timelineTree = null;
  var playButton = controls.querySelector('[data-nav=\"play\"]');
  var prevButton = controls.querySelector('[data-nav=\"prev\"]');
  var nextButton = controls.querySelector('[data-nav=\"next\"]');
  var downloadVideoButton = controls.querySelector('[data-download-video]');
  var collapseAllButton = null;
  var expandAllButton = null;
  var previewModal = document.querySelector('[data-attachment-modal]');
  var previewTitle = previewModal ? previewModal.querySelector('[data-attachment-title]') : null;
  var previewOpen = previewModal ? previewModal.querySelector('[data-attachment-open]') : null;
  var previewImage = previewModal ? previewModal.querySelector('[data-attachment-image]') : null;
  var previewVideo = previewModal ? previewModal.querySelector('[data-attachment-video]') : null;
  var previewText = previewModal ? previewModal.querySelector('[data-attachment-text]') : null;
  var previewFrame = previewModal ? previewModal.querySelector('[data-attachment-frame]') : null;
  var previewEmpty = previewModal ? previewModal.querySelector('[data-attachment-empty]') : null;
  var plistPreviewRequestToken = 0;
  var hierarchyOpenToggle = root.querySelector('[data-hierarchy-open]');
  var hierarchyPanel = root.querySelector('[data-hierarchy-panel]');
  var hierarchyToggle = hierarchyPanel ? hierarchyPanel.querySelector('[data-hierarchy-toggle]') : null;
  var hierarchyBody = hierarchyPanel ? hierarchyPanel.querySelector('[data-hierarchy-body]') : null;
  var hierarchyToolbar = hierarchyPanel ? hierarchyPanel.querySelector('[data-hierarchy-toolbar]') : null;
  var hierarchyStatus = hierarchyToolbar ? hierarchyToolbar.querySelector('[data-hierarchy-status]') : null;
  var hierarchyCandidatePanel = hierarchyPanel ? hierarchyPanel.querySelector('[data-hierarchy-candidate-panel]') : null;
  var hierarchyCandidateHeading = hierarchyPanel ? hierarchyPanel.querySelector('[data-hierarchy-candidate-heading]') : null;
  var hierarchyCandidateEmpty = hierarchyPanel ? hierarchyPanel.querySelector('[data-hierarchy-candidate-empty]') : null;
  var hierarchyCandidateList = hierarchyPanel ? hierarchyPanel.querySelector('[data-hierarchy-candidate-list]') : null;
  var hierarchyInspector = hierarchyPanel ? hierarchyPanel.querySelector('[data-hierarchy-inspector]') : null;
  var hierarchySelectedTitle = hierarchyInspector ? hierarchyInspector.querySelector('[data-hierarchy-selected-title]') : null;
  var hierarchySelectedSubtitle = hierarchyInspector ? hierarchyInspector.querySelector('[data-hierarchy-selected-subtitle]') : null;
  var hierarchyProperties = hierarchyInspector ? hierarchyInspector.querySelector('[data-hierarchy-properties]') : null;
  var selector = root.querySelector('[data-video-selector]');
  var cards = Array.prototype.slice.call(root.querySelectorAll('[data-video-index]'));
  var runStates = normalizeRunStates(parseJSONScript('[data-timeline-run-states]'));
  var activeRunIndex = 0;
  var events = [];
  var initialFailureEventIndex = -1;
  var mediaMode = root.dataset.mediaMode || 'video';
  var touchGestures = [];
  var screenshots = normalizeScreenshots(parseJSONScript('[data-timeline-screenshots]'));
  var hierarchySnapshots = [];
  var timelineBase = 0;
  var fallbackVideoBase = parseFloat(root.dataset.videoBase || '0');
  var activeIndex = 0;
  var activeEventId = null;
  var activeEventIndex = -1;
  var eventByIdMap = Object.create(null);
  var eventIndexByIdMap = Object.create(null);
  var eventTimeLookup = [];
  var eventNodeById = Object.create(null);
  var activeRenderedNode = null;
  var activeProxyNode = null;
  var activeContextNodes = [];
  var scrubberMarkers = [];
  var activeScrubberMarkerIndex = -1;
  var pendingSeekTime = null;
  var pendingVideoSeekTime = null;
  var dragSeekAnimationFrame = 0;
  var dragSeekRequestedTime = null;
  var virtualCurrentTime = 0;
  var virtualDuration = 0;
  var virtualPlaying = false;
  var virtualAnimationFrame = 0;
  var virtualLastTick = 0;
  var videoTimeUpdateFrame = 0;
  var hierarchyOverlayFrame = 0;
  var pendingHierarchyOverlayForce = false;
  var scrubDragging = false;
  var scrubPreviewActive = false;
  var scrubPreviewTime = 0;
  var scrubInteractionDeadline = 0;
  var touchMarker = null;
  var touchAnimationFrame = 0;
  var TOUCH_RELEASE_DURATION = 0.18;
  var TOUCH_PLAYBACK_LEAD_WINDOW = 0.06;
  var SCRUB_PREVIEW_WINDOW = 0.22;
  var HIERARCHY_MATCH_WINDOW = 0.30;
  var SCRUBBER_MARKER_RANGE_TOLERANCE = 0.35;
  var SCRUBBER_TAP_MATCH_TOLERANCE = 0.35;
  var SCRUBBER_HIERARCHY_MATCH_TOLERANCE = 0.35;
  var currentHierarchySnapshotId = null;
  var selectedHierarchyElementId = null;
  var hoveredHierarchyElementId = null;
  var currentHierarchyCandidateIds = [];
  var hierarchyParentMapCache = Object.create(null);
  var hierarchyElementMapCache = Object.create(null);
  var hierarchySnapshotByIdMap = Object.create(null);
  var hierarchySnapshotTimeIndex = [];
  var hierarchyHintRenderKey = '';
  var hierarchyHighlightRenderKey = '';
  var hierarchyInspectorRenderKey = '';
  var hierarchyCandidateSelectionKey = '';
  var suppressTimelineToggleRefresh = false;
  var PLAY_ICON = '<svg class="timeline-icon" viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path d="M8 6V18L18 12Z"></path></svg>';
  var PAUSE_ICON = '<svg class="timeline-icon" viewBox="0 0 24 24" aria-hidden="true" focusable="false"><rect x="7" y="6" width="4" height="12" rx="1"></rect><rect x="13" y="6" width="4" height="12" rx="1"></rect></svg>';

  function fallbackEventKindFromNode(node) {
    if (!node || !node.classList) return 'event';
    if (node.classList.contains('timeline-failure')) return 'error';
    if (node.classList.contains('timeline-touch')) return 'tap';
    if (node.classList.contains('timeline-hierarchy')) return 'hierarchy';
    return 'event';
  }

  function fallbackRunLabel(index) {
    if (runSelector && runSelector.options && runSelector.options[index]) {
      var label = asString(runSelector.options[index].textContent, '').trim();
      if (label) return label;
    }
    return 'Run ' + (index + 1);
  }

  function buildFallbackRunStatesFromDOM() {
    var panelNodes = Array.prototype.slice.call(root.querySelectorAll('[data-run-panel]'));
    if (!panelNodes.length) return [];

    var defaultTimelineBase = asNumber(root.dataset.timelineBase, asNumber(root.dataset.videoBase, 0));
    return panelNodes.map(function(panel, panelIndex) {
      var eventNodes = Array.prototype.slice.call(
        panel.querySelectorAll('.timeline-event[data-event-id][data-event-time]')
      );
      var dedup = Object.create(null);
      var parsedEvents = [];

      eventNodes.forEach(function(node) {
        var rawTime = node.getAttribute('data-event-time');
        if (!rawTime) return;
        var eventTime = parseFloat(rawTime);
        if (!Number.isFinite(eventTime)) return;

        var eventId = asString(node.getAttribute('data-event-id'), '').trim();
        if (!eventId) {
          eventId = 'dom-event-' + panelIndex + '-' + parsedEvents.length;
        }
        if (dedup[eventId]) return;
        dedup[eventId] = true;

        var titleNode = node.querySelector('.timeline-title');
        var title = asString(titleNode ? titleNode.textContent : '', 'Timeline event').trim();
        if (!title) title = 'Timeline event';

        var kind = fallbackEventKindFromNode(node);
        parsedEvents.push({
          id: eventId,
          title: title,
          time: eventTime,
          endTime: eventTime,
          kind: kind,
          failureAssociated: kind === 'error'
        });
      });

      parsedEvents.sort(function(a, b) {
        if (a.time === b.time) {
          if (a.id < b.id) return -1;
          if (a.id > b.id) return 1;
          return 0;
        }
        return a.time - b.time;
      });

      var initialFailureEventIndex = -1;
      for (var i = 0; i < parsedEvents.length; i += 1) {
        if (parsedEvents[i].kind === 'error' || parsedEvents[i].failureAssociated) {
          initialFailureEventIndex = i;
          break;
        }
      }

      return {
        index: panelIndex,
        label: fallbackRunLabel(panelIndex),
        timelineBase: parsedEvents.length ? parsedEvents[0].time : defaultTimelineBase,
        firstEventLabel: parsedEvents.length ? parsedEvents[0].title : 'No event selected',
        initialFailureEventIndex: initialFailureEventIndex,
        events: parsedEvents,
        touchGestures: [],
        hierarchySnapshots: []
      };
    });
  }

  function ensureRunStatesFallback() {
    if (Array.isArray(runStates) && runStates.length) return;
    var fallbackStates = buildFallbackRunStatesFromDOM();
    if (fallbackStates.length) {
      runStates = fallbackStates;
    }
  }

  function formatSeconds(seconds) {
    var safe = Math.max(0, Math.floor(seconds));
    var h = Math.floor(safe / 3600);
    var m = Math.floor((safe % 3600) / 60);
    var s = safe % 60;
    if (h > 0) return h + ':' + String(m).padStart(2, '0') + ':' + String(s).padStart(2, '0');
    return String(m).padStart(2, '0') + ':' + String(s).padStart(2, '0');
  }

  function setPlayButtonIcon(isPlaying) {
    if (!playButton) return;
    playButton.innerHTML = isPlaying ? PAUSE_ICON : PLAY_ICON;
  }

  function updateDownloadVideoButton() {
    if (!downloadVideoButton) return;
    if (mediaMode !== 'video') {
      downloadVideoButton.hidden = true;
      downloadVideoButton.removeAttribute('href');
      downloadVideoButton.removeAttribute('download');
      return;
    }

    var video = getActiveVideo();
    var source = '';
    if (video) {
      source = video.currentSrc || '';
      if (!source) {
        var sourceNode = video.querySelector('source');
        source = sourceNode ? (sourceNode.getAttribute('src') || '') : '';
      }
    }

    if (!source) {
      downloadVideoButton.hidden = true;
      downloadVideoButton.removeAttribute('href');
      downloadVideoButton.removeAttribute('download');
      return;
    }

    var sourcePath = source.split('#')[0].split('?')[0];
    var sourceParts = sourcePath.split('/');
    var fileName = sourceParts[sourceParts.length - 1] || 'timeline-video';
    downloadVideoButton.href = source;
    downloadVideoButton.setAttribute('download', fileName);
    downloadVideoButton.hidden = false;
  }

  function currentRunPanel() {
    return runPanels[activeRunIndex] || runPanels[0] || null;
  }

  function clearRunPanelState(panel) {
    if (!panel) return;
    Array.prototype.forEach.call(
      panel.querySelectorAll('.timeline-event.timeline-active, .timeline-event.timeline-context-active, .timeline-event.timeline-active-proxy'),
      function(node) {
        node.classList.remove('timeline-active');
        node.classList.remove('timeline-context-active');
        node.classList.remove('timeline-active-proxy');
      });
  }

  function refreshRunScopedBindings() {
    var panel = currentRunPanel();
    eventLabel = panel ? panel.querySelector('[data-active-event]') : null;
    timelineTree = panel ? panel.querySelector('.timeline-tree') : null;
    collapseAllButton = panel ? panel.querySelector('[data-tree-action=\"collapse\"]') : null;
    expandAllButton = panel ? panel.querySelector('[data-tree-action=\"expand\"]') : null;
  }

  function rebuildEventDataIndexes() {
    eventByIdMap = Object.create(null);
    eventIndexByIdMap = Object.create(null);
    eventTimeLookup = [];
    for (var i = 0; i < events.length; i += 1) {
      var event = events[i];
      if (!event || !event.id) continue;
      eventByIdMap[event.id] = event;
      eventIndexByIdMap[event.id] = i;
      var startTime = Number(event.time);
      if (!Number.isFinite(startTime)) continue;
      var endTime = Number(event.endTime);
      if (!Number.isFinite(endTime) || endTime < startTime) {
        endTime = startTime;
      }
      eventTimeLookup.push({
        index: i,
        start: startTime,
        end: endTime
      });
    }
    eventTimeLookup.sort(function(a, b) {
      if (a.start === b.start) {
        return a.index - b.index;
      }
      return a.start - b.start;
    });
  }

  function clearHierarchyRenderCaches() {
    hierarchyHintRenderKey = '';
    hierarchyHighlightRenderKey = '';
    hierarchyInspectorRenderKey = '';
    hierarchyCandidateSelectionKey = '';
  }

  function rebuildHierarchySnapshotIndexes() {
    hierarchySnapshotByIdMap = Object.create(null);
    hierarchySnapshotTimeIndex = [];
    hierarchyParentMapCache = Object.create(null);
    hierarchyElementMapCache = Object.create(null);
    for (var i = 0; i < hierarchySnapshots.length; i += 1) {
      var snapshot = hierarchySnapshots[i];
      if (!snapshot) continue;
      if (snapshot.id) {
        hierarchySnapshotByIdMap[snapshot.id] = snapshot;
      }
      hierarchySnapshotTimeIndex.push({
        time: asNumber(snapshot.time, 0),
        snapshot: snapshot
      });
    }
    hierarchySnapshotTimeIndex.sort(function(a, b) {
      return a.time - b.time;
    });
  }

  function lowerBoundSnapshotTime(target) {
    var low = 0;
    var high = hierarchySnapshotTimeIndex.length;
    while (low < high) {
      var mid = (low + high) >> 1;
      if (hierarchySnapshotTimeIndex[mid].time < target) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  function rebuildEventNodeIndex() {
    eventNodeById = Object.create(null);
    var panel = currentRunPanel();
    if (!panel) return;
    Array.prototype.forEach.call(
      panel.querySelectorAll('.timeline-event[data-event-id]'),
      function(node) {
        var eventId = node.getAttribute('data-event-id');
        if (!eventId) return;
        if (!Object.prototype.hasOwnProperty.call(eventNodeById, eventId)) {
          eventNodeById[eventId] = node;
        }
      }
    );
  }

  function clearActiveEventVisualState() {
    if (activeRenderedNode) {
      activeRenderedNode.classList.remove('timeline-active');
      activeRenderedNode = null;
    }
    if (activeProxyNode) {
      activeProxyNode.classList.remove('timeline-active-proxy');
      activeProxyNode = null;
    }
    if (activeContextNodes.length) {
      activeContextNodes.forEach(function(node) {
        node.classList.remove('timeline-context-active');
      });
      activeContextNodes = [];
    }
  }

  function recalculateVirtualDuration() {
    var lastEventTime = events.length ? events[events.length - 1].time : (timelineBase || 0);
    var lastScreenshotTime = screenshots.length ? screenshots[screenshots.length - 1].time : (timelineBase || 0);
    virtualDuration = Math.max(0, Math.max(lastEventTime, lastScreenshotTime) - (timelineBase || 0));
    if (!getActiveVideo()) {
      scrubber.max = virtualDuration;
      if (virtualCurrentTime > virtualDuration) {
        virtualCurrentTime = virtualDuration;
      }
    }
  }

  function applyRunState(nextRunIndex, preserveAbsoluteTime) {
    if (!runStates.length) {
      clearScrubPreview();
      pendingVideoSeekTime = null;
      events = [];
      touchGestures = [];
      hierarchySnapshots = [];
      timelineBase = fallbackVideoBase || 0;
      initialFailureEventIndex = -1;
      rebuildEventDataIndexes();
      rebuildHierarchySnapshotIndexes();
      rebuildEventNodeIndex();
      clearActiveEventVisualState();
      closeHierarchyMenu();
      clearHierarchyRenderCaches();
      refreshRunScopedBindings();
      refreshHierarchyPanelVisibility();
      updateDownloadVideoButton();
      renderScrubberMarkers();
      return;
    }

    var absoluteTimeBefore = preserveAbsoluteTime ? currentAbsoluteTime() : null;
    var clampedIndex = Math.max(0, Math.min(runStates.length - 1, Number(nextRunIndex) || 0));
    activeRunIndex = clampedIndex;

    runPanels.forEach(function(panel, panelIndex) {
      panel.style.display = panelIndex === activeRunIndex ? '' : 'none';
      clearRunPanelState(panel);
    });
    clearScrubPreview();
    pendingVideoSeekTime = null;

    var runState = runStates[activeRunIndex] || runStates[0];
    events = runState.events || [];
    touchGestures = runState.touchGestures || [];
    hierarchySnapshots = runState.hierarchySnapshots || [];
    rebuildHierarchySnapshotIndexes();
    timelineBase = Number.isFinite(runState.timelineBase) ? runState.timelineBase : (fallbackVideoBase || 0);
    initialFailureEventIndex = Number.isFinite(runState.initialFailureEventIndex) ? runState.initialFailureEventIndex : -1;

    activeEventId = null;
    activeEventIndex = -1;
    clearActiveEventVisualState();
    currentHierarchySnapshotId = null;
    selectedHierarchyElementId = null;
    hoveredHierarchyElementId = null;
    closeHierarchyMenu();
    clearHierarchyRenderCaches();
    hideTouchMarker();
    refreshRunScopedBindings();
    rebuildEventDataIndexes();
    rebuildEventNodeIndex();
    refreshHierarchyPanelVisibility();
    updateDownloadVideoButton();
    if (eventLabel) {
      eventLabel.textContent = runState.firstEventLabel || 'No event selected';
    }
    recalculateVirtualDuration();
    renderScrubberMarkers();

    if (preserveAbsoluteTime && absoluteTimeBefore != null) {
      setAbsoluteTime(absoluteTimeBefore);
    }
    updateFromVideoTime();
  }

  function resetAttachmentPreviewContent() {
    plistPreviewRequestToken += 1;
    if (previewImage) {
      previewImage.style.display = 'none';
      previewImage.removeAttribute('src');
    }
    if (previewVideo) {
      previewVideo.pause();
      previewVideo.style.display = 'none';
      previewVideo.removeAttribute('src');
    }
    if (previewText) {
      previewText.style.display = 'none';
      previewText.textContent = '';
    }
    if (previewFrame) {
      previewFrame.style.display = 'none';
      previewFrame.removeAttribute('src');
    }
    if (previewEmpty) {
      previewEmpty.style.display = 'none';
    }
  }

  function closeAttachmentPreview() {
    if (!previewModal || previewModal.hidden) return;
    previewModal.hidden = true;
    resetAttachmentPreviewContent();
  }

  function setAttachmentTextPreview(message) {
    if (!previewText) return;
    previewText.textContent = message;
    previewText.style.display = 'block';
  }

  function maybeDecompressGzipBuffer(buffer) {
    var bytes = new Uint8Array(buffer);
    var isGzip = bytes.length >= 2 && bytes[0] === 0x1f && bytes[1] === 0x8b;
    if (!isGzip) {
      return Promise.resolve(buffer);
    }
    if (typeof DecompressionStream !== 'function') {
      return Promise.reject(new Error('This browser cannot decompress gzip plist previews.'));
    }

    try {
      var compressedBlob = new Blob([buffer]);
      var decompressedStream = compressedBlob.stream().pipeThrough(new DecompressionStream('gzip'));
      return new Response(decompressedStream).arrayBuffer();
    } catch (error) {
      return Promise.reject(error);
    }
  }

  function loadBinaryPlistPreview(href, requestToken) {
    fetch(href)
      .then(function(response) {
        if (!response.ok) {
          throw new Error('HTTP ' + response.status);
        }
        return response.arrayBuffer();
      })
      .then(function(buffer) {
        return maybeDecompressGzipBuffer(buffer);
      })
      .then(function(buffer) {
        if (!previewModal || previewModal.hidden || requestToken !== plistPreviewRequestToken) return;
        var bytes = new Uint8Array(buffer);
        var isBinaryPlist = bytes.length >= 8
          && bytes[0] === 0x62
          && bytes[1] === 0x70
          && bytes[2] === 0x6c
          && bytes[3] === 0x69
          && bytes[4] === 0x73
          && bytes[5] === 0x74
          && bytes[6] === 0x30
          && bytes[7] === 0x30;

        if (isBinaryPlist) {
          if (!globalThis.PlistPreview || typeof globalThis.PlistPreview.parseBinaryPlistToText !== 'function') {
            throw new Error('Plist parser is unavailable.');
          }
          var parsedText = globalThis.PlistPreview.parseBinaryPlistToText(buffer);
          setAttachmentTextPreview(parsedText);
          return;
        }

        var decodedText = new TextDecoder('utf-8').decode(bytes);
        if (!decodedText || !decodedText.trim()) {
          throw new Error('Preview payload is empty.');
        }
        setAttachmentTextPreview(decodedText);
      })
      .catch(function(error) {
        if (!previewModal || previewModal.hidden || requestToken !== plistPreviewRequestToken) return;
        var message = (error && error.message) ? error.message : String(error);
        setAttachmentTextPreview('Unable to parse this binary plist preview.\n\n' + message);
      });
  }

  function openAttachmentPreview(link) {
    if (!previewModal || !link) return false;
    var kind = link.dataset.previewKind || 'file';
    if (kind === 'file') return false;

    var href = link.getAttribute('href');
    if (!href) return false;
    var title = link.dataset.previewTitle || link.textContent || 'Attachment';

    if (previewTitle) previewTitle.textContent = title;
    if (previewOpen) previewOpen.href = href;
    resetAttachmentPreviewContent();

    if (kind === 'image' && previewImage) {
      previewImage.src = href;
      previewImage.style.display = 'block';
    } else if (kind === 'video' && previewVideo) {
      previewVideo.src = href;
      previewVideo.style.display = 'block';
    } else if (kind === 'plist' && previewText) {
      var requestToken = plistPreviewRequestToken + 1;
      plistPreviewRequestToken = requestToken;
      setAttachmentTextPreview('Loading plist preview...');
      loadBinaryPlistPreview(href, requestToken);
    } else if (previewFrame && (kind === 'text' || kind === 'json' || kind === 'pdf' || kind === 'html')) {
      previewFrame.src = href;
      previewFrame.style.display = 'block';
    } else if (previewEmpty) {
      previewEmpty.style.display = 'flex';
    }

    previewModal.hidden = false;
    return true;
  }

  function getActiveVideoCard() {
    return cards[activeIndex] || null;
  }

  function getActiveVideo() {
    var card = getActiveVideoCard();
    return card ? card.querySelector('video') : null;
  }

  function getActiveMediaElement() {
    var video = getActiveVideo();
    if (video) return video;
    var card = getActiveVideoCard();
    return card ? card.querySelector('[data-still-frame]') : null;
  }

  function getActiveTouchLayer() {
    var card = getActiveVideoCard();
    return card ? card.querySelector('[data-touch-overlay]') : null;
  }

  function activeMediaStartTime() {
    var video = getActiveVideo();
    if (!video) return timelineBase || fallbackVideoBase || 0;
    var value = parseFloat(video.dataset.videoStart || '');
    if (Number.isFinite(value)) return value;
    return fallbackVideoBase || timelineBase || 0;
  }

  function currentAbsoluteTime() {
    var video = getActiveVideo();
    if (video) {
      var offset = scrubPreviewActive ? scrubPreviewTime : (video.currentTime || 0);
      return activeMediaStartTime() + offset;
    }
    return (timelineBase || 0) + (virtualCurrentTime || 0);
  }

  function normalizeTimelineEventKind(event) {
    if (!event || typeof event !== 'object') return 'event';
    var rawKind = String(event.kind || '').toLowerCase();
    if (event.failureAssociated === true || rawKind === 'error') return 'error';
    if (rawKind === 'tap' || rawKind === 'hierarchy' || rawKind === 'event') return rawKind;

    var title = String(event.title || '').toLowerCase();
    if (title.indexOf('tap ') === 0 || title.indexOf('swipe ') === 0
      || title.indexOf('synthesize event') >= 0 || title.indexOf('synthesized event') >= 0) {
      return 'tap';
    }
    if (title.indexOf('ui hierarchy') >= 0) {
      return 'hierarchy';
    }
    return 'event';
  }

  function distanceToTimeRange(value, start, end) {
    if (!Number.isFinite(value) || !Number.isFinite(start) || !Number.isFinite(end)) {
      return Number.POSITIVE_INFINITY;
    }
    if (value < start) return start - value;
    if (value > end) return value - end;
    return 0;
  }

  function nearestTouchGestureForTime(absoluteTime, maxDistance) {
    if (!touchGestures.length || !Number.isFinite(absoluteTime)) return null;
    var bestMatch = null;
    for (var index = 0; index < touchGestures.length; index += 1) {
      var gesture = touchGestures[index];
      if (!gesture) continue;
      var start = Number(gesture.startTime);
      var end = Number(gesture.endTime);
      if (!Number.isFinite(start) || !Number.isFinite(end)) continue;
      var rangeStart = Math.min(start, end);
      var rangeEnd = Math.max(start, end);
      var distance = distanceToTimeRange(absoluteTime, rangeStart, rangeEnd);
      if (!bestMatch || distance < bestMatch.distance) {
        bestMatch = {
          gesture: gesture,
          start: rangeStart,
          end: rangeEnd,
          distance: distance
        };
      }
    }
    if (!bestMatch) return null;
    if (Number.isFinite(maxDistance) && bestMatch.distance > maxDistance) return null;
    return bestMatch;
  }

  function nearestHierarchySnapshotForTime(absoluteTime, maxDistance) {
    if (!hierarchySnapshotTimeIndex.length || !Number.isFinite(absoluteTime)) return null;

    var low = 0;
    var high = hierarchySnapshotTimeIndex.length;
    while (low < high) {
      var mid = (low + high) >> 1;
      if (hierarchySnapshotTimeIndex[mid].time < absoluteTime) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }

    var bestEntry = null;
    var bestDistance = Number.POSITIVE_INFINITY;

    function consider(index) {
      if (index < 0 || index >= hierarchySnapshotTimeIndex.length) return;
      var entry = hierarchySnapshotTimeIndex[index];
      if (!entry || !Number.isFinite(entry.time)) return;
      var distance = Math.abs(entry.time - absoluteTime);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestEntry = entry;
      }
    }

    consider(low);
    consider(low - 1);

    if (!bestEntry) return null;
    if (Number.isFinite(maxDistance) && bestDistance > maxDistance) return null;
    return bestEntry.snapshot || null;
  }

  function hasTouchGestureNearTime(absoluteTime) {
    return !!nearestTouchGestureForTime(absoluteTime, SCRUBBER_TAP_MATCH_TOLERANCE);
  }

  function hasHierarchySnapshotNearTime(absoluteTime) {
    return !!nearestHierarchySnapshotForTime(absoluteTime, SCRUBBER_HIERARCHY_MATCH_TOLERANCE);
  }

  function scrubberMarkerKindForEvent(event) {
    var baseKind = normalizeTimelineEventKind(event);
    if (baseKind === 'error') return 'error';

    var eventTime = Number(event && event.time);
    if (!Number.isFinite(eventTime)) return baseKind;

    var nearTouch = hasTouchGestureNearTime(eventTime);
    var nearHierarchy = hasHierarchySnapshotNearTime(eventTime);

    if (baseKind === 'tap') {
      if (nearTouch) return 'tap';
      if (nearHierarchy) return 'hierarchy';
      return 'event';
    }

    if (baseKind === 'hierarchy') {
      if (nearHierarchy) return 'hierarchy';
      if (nearTouch) return 'tap';
      return 'event';
    }

    return baseKind;
  }

  function scrubberMarkerAnchorTimeForEvent(event, markerKind) {
    if (!event) return null;
    var eventTime = Number(event.time);
    if (!Number.isFinite(eventTime)) return null;

    if (markerKind === 'tap') {
      var touchMatch = nearestTouchGestureForTime(eventTime, SCRUBBER_TAP_MATCH_TOLERANCE);
      if (touchMatch) {
        return Math.max(touchMatch.start, Math.min(touchMatch.end, eventTime));
      }
    } else if (markerKind === 'hierarchy') {
      var snapshot = nearestHierarchySnapshotForTime(eventTime, SCRUBBER_HIERARCHY_MATCH_TOLERANCE);
      var snapshotTime = Number(snapshot && snapshot.time);
      if (Number.isFinite(snapshotTime)) {
        return snapshotTime;
      }
    }

    return eventTime;
  }

  function timelineOffsetForAbsoluteTime(absoluteTime) {
    if (!Number.isFinite(absoluteTime)) return null;
    var base = getActiveVideo() ? activeMediaStartTime() : (timelineBase || 0);
    return absoluteTime - base;
  }

  function timelineOffsetForEvent(event) {
    if (!event) return null;
    var eventTime = Number(event.time);
    return timelineOffsetForAbsoluteTime(eventTime);
  }

  function updateScrubberMarkerActiveState() {
    if (!scrubberMarkers.length) {
      activeScrubberMarkerIndex = -1;
      return;
    }
    var markerIndex = (activeEventIndex >= 0 && activeEventIndex < events.length)
      ? activeEventIndex
      : eventIndexForAbsoluteTime(currentAbsoluteTime());
    if (!Number.isFinite(markerIndex) || markerIndex < 0 || markerIndex >= scrubberMarkers.length) {
      markerIndex = -1;
    }
    if (markerIndex === activeScrubberMarkerIndex) return;

    if (activeScrubberMarkerIndex >= 0 && activeScrubberMarkerIndex < scrubberMarkers.length) {
      var previousMarker = scrubberMarkers[activeScrubberMarkerIndex];
      if (previousMarker) previousMarker.classList.remove('is-active');
    }
    if (markerIndex >= 0 && markerIndex < scrubberMarkers.length) {
      var nextMarker = scrubberMarkers[markerIndex];
      if (nextMarker) {
        nextMarker.classList.add('is-active');
      } else {
        markerIndex = -1;
      }
    }
    activeScrubberMarkerIndex = markerIndex;
  }

  function renderScrubberMarkers() {
    if (!scrubberMarkerLane) return;
    scrubberMarkerLane.innerHTML = '';
    scrubberMarkers = [];
    activeScrubberMarkerIndex = -1;
    if (!events.length) return;

    var duration = Number(scrubber.max || 0);
    if (!Number.isFinite(duration) || duration < 0) duration = 0;
    if (duration <= 0) {
      duration = events.reduce(function(maxValue, event) {
        var offset = timelineOffsetForEvent(event);
        if (offset == null) return maxValue;
        return Math.max(maxValue, Math.max(0, offset));
      }, 0);
    }
    var durationForRatio = duration > 0.0001 ? duration : 1;
    var hasBoundedDuration = duration > 0.0001;
    var laneWidth = scrubberMarkerLane.clientWidth || 0;

    events.forEach(function(event, index) {
      var markerKind = scrubberMarkerKindForEvent(event);
      var markerTime = scrubberMarkerAnchorTimeForEvent(event, markerKind);
      var offset = timelineOffsetForAbsoluteTime(markerTime);
      if (offset == null) return;
      if (hasBoundedDuration) {
        if (offset < -SCRUBBER_MARKER_RANGE_TOLERANCE || offset > duration + SCRUBBER_MARKER_RANGE_TOLERANCE) {
          return;
        }
      }
      var clampedOffset = Math.max(0, Math.min(durationForRatio, offset));
      var ratio = duration > 0 ? (clampedOffset / durationForRatio) : 0;

      var marker = document.createElement('button');
      marker.type = 'button';
      marker.className = 'timeline-scrubber-marker is-' + markerKind;
      marker.style.left = (ratio * 100).toFixed(4) + '%';
      marker.setAttribute('data-event-index', String(index));
      marker.setAttribute('data-event-id', event.id || '');
      marker.setAttribute('data-marker-time', Number.isFinite(markerTime) ? String(markerTime) : '');
      marker.setAttribute('aria-label', (event.title || 'Timeline event') + ' at ' + formatSeconds(clampedOffset));
      marker.title = event.title || 'Timeline event';

      if (laneWidth > 0) {
        var markerHalfWidth = markerKind === 'error' ? 5 : (markerKind === 'tap' || markerKind === 'hierarchy' ? 3 : 2.5);
        var edgeRatio = Math.min(0.08, markerHalfWidth / laneWidth);
        if (ratio <= edgeRatio) {
          marker.classList.add('is-edge-left');
        } else if (ratio >= (1 - edgeRatio)) {
          marker.classList.add('is-edge-right');
        }
      }

      marker.addEventListener('click', function(clickEvent) {
        clickEvent.preventDefault();
        jumpToEventByIndex(index, true, markerTime);
      });

      scrubberMarkerLane.appendChild(marker);
      scrubberMarkers[index] = marker;
    });

    updateScrubberMarkerActiveState();
  }

  function getDisplayedMediaRect(mediaElement) {
    var containerWidth = mediaElement.clientWidth || 0;
    var containerHeight = mediaElement.clientHeight || 0;
    var mediaWidth = mediaElement.videoWidth || mediaElement.naturalWidth || 0;
    var mediaHeight = mediaElement.videoHeight || mediaElement.naturalHeight || 0;
    if (!containerWidth || !containerHeight || !mediaWidth || !mediaHeight) {
      return { x: 0, y: 0, width: containerWidth, height: containerHeight };
    }

    var scale = Math.min(containerWidth / mediaWidth, containerHeight / mediaHeight);
    var width = mediaWidth * scale;
    var height = mediaHeight * scale;
    return {
      x: (containerWidth - width) / 2,
      y: (containerHeight - height) / 2,
      width: width,
      height: height
    };
  }

  function updateActiveMediaAspect() {
    var card = getActiveVideoCard();
    var frame = card ? card.querySelector('.timeline-video-frame') : null;
    var media = getActiveMediaElement();
    if (!frame || !media) return;
    var width = media.videoWidth || media.naturalWidth || 0;
    var height = media.videoHeight || media.naturalHeight || 0;
    if (width > 0 && height > 0) {
      var ratioValue = width + ' / ' + height;
      frame.style.setProperty('--media-aspect', ratioValue);
      if (card) {
        card.style.setProperty('--media-aspect', ratioValue);
      }
    }
    updateActiveMediaLayout();
  }

  function aspectRatioFromFrame(frame) {
    if (!frame) return 9 / 16;
    var ratioRaw = frame.style.getPropertyValue('--media-aspect')
      || window.getComputedStyle(frame).getPropertyValue('--media-aspect')
      || '';
    var parts = ratioRaw.split('/');
    if (parts.length === 2) {
      var w = parseFloat(parts[0]);
      var h = parseFloat(parts[1]);
      if (Number.isFinite(w) && Number.isFinite(h) && w > 0 && h > 0) {
        return w / h;
      }
    }
    return 9 / 16;
  }

  function updateActiveMediaLayout() {
    var card = getActiveVideoCard();
    if (!card) return;
    var frame = card.querySelector('.timeline-video-frame');
    if (!frame) return;
    var mediaColumn = card.closest('.video-media-column');
    if (!mediaColumn) return;

    card.style.width = '';

    var columnRect = mediaColumn.getBoundingClientRect();
    if (!columnRect.width || !columnRect.height) return;

    var visibleChildren = Array.prototype.filter.call(mediaColumn.children, function(child) {
      return child.offsetParent !== null;
    });
    var reservedHeight = 0;
    var cardPosition = -1;
    visibleChildren.forEach(function(child, index) {
      if (child === card) {
        cardPosition = index;
      } else {
        reservedHeight += child.getBoundingClientRect().height;
      }
    });

    var mediaColumnStyles = window.getComputedStyle(mediaColumn);
    var rowGap = parseFloat(mediaColumnStyles.rowGap || mediaColumnStyles.gap || '0');
    if (!Number.isFinite(rowGap)) rowGap = 0;
    if (visibleChildren.length > 1) {
      reservedHeight += rowGap * (visibleChildren.length - 1);
    }

    var availableHeight = columnRect.height - reservedHeight;
    if (availableHeight <= 0) return;

    var ratio = aspectRatioFromFrame(frame);
    var widthByHeight = availableHeight * ratio * 0.94;
    var widthByContainer = columnRect.width * 0.94;
    var targetWidth = Math.max(120, Math.floor(Math.min(widthByHeight, widthByContainer)));

    if (cardPosition < 0 || !Number.isFinite(targetWidth)) return;
    card.style.width = targetWidth + 'px';
  }

  function escapeHTML(value) {
    return String(value == null ? '' : value)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/\"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function getActiveHierarchyLayer() {
    var card = getActiveVideoCard();
    return card ? card.querySelector('[data-hierarchy-overlay]') : null;
  }

  function getActiveHierarchyHighlight() {
    var layer = getActiveHierarchyLayer();
    return layer ? layer.querySelector('[data-hierarchy-highlight]') : null;
  }

  function getActiveHierarchyHintsLayer() {
    var layer = getActiveHierarchyLayer();
    return layer ? layer.querySelector('[data-hierarchy-hints]') : null;
  }

  function isHierarchyPanelExpanded() {
    return !!(hierarchyToggle && hierarchyToggle.getAttribute('aria-expanded') === 'true');
  }

  function setHierarchyPanelExpanded(expanded) {
    if (!hierarchyPanel || !hierarchyBody || !hierarchyToggle) return;
    var shouldExpand = !!expanded;
    var currentlyExpanded = isHierarchyPanelExpanded();
    var desiredOpenToggleHidden = hierarchyPanel.hidden || shouldExpand;
    var openToggleNeedsUpdate = !!(hierarchyOpenToggle && hierarchyOpenToggle.hidden !== desiredOpenToggleHidden);
    if (currentlyExpanded === shouldExpand && !openToggleNeedsUpdate) {
      return;
    }
    hierarchyPanel.classList.toggle('is-collapsed', !shouldExpand);
    hierarchyBody.setAttribute('aria-hidden', shouldExpand ? 'false' : 'true');
    hierarchyToggle.setAttribute('aria-expanded', shouldExpand ? 'true' : 'false');
    if (hierarchyOpenToggle) {
      hierarchyOpenToggle.hidden = hierarchyPanel.hidden || shouldExpand;
    }
    updateActiveMediaLayout();
    updateTouchOverlay();
    clearHierarchyRenderCaches();
    updateHierarchyOverlay();
  }

  function refreshHierarchyPanelVisibility() {
    if (!hierarchyPanel) return;
    var hasHierarchyData = hierarchySnapshots.length > 0 && mediaMode !== 'none';
    hierarchyPanel.hidden = !hasHierarchyData;
    if (hierarchyOpenToggle) {
      hierarchyOpenToggle.hidden = !hasHierarchyData || (hierarchyToggle && hierarchyToggle.getAttribute('aria-expanded') === 'true');
    }
    if (!hasHierarchyData && isHierarchyPanelExpanded()) {
      setHierarchyPanelExpanded(false);
    }
    clearHierarchyRenderCaches();
    updateActiveMediaLayout();
  }

  function updateHierarchyCandidateSelectionState() {
    if (!hierarchyCandidateList) return;
    var selectionKey = (selectedHierarchyElementId || '') + '|' + (hoveredHierarchyElementId || '');
    if (selectionKey === hierarchyCandidateSelectionKey) return;
    hierarchyCandidateSelectionKey = selectionKey;
    Array.prototype.forEach.call(hierarchyCandidateList.querySelectorAll('.hierarchy-candidate-item'), function(button) {
      var elementId = button.getAttribute('data-hierarchy-element-id');
      button.classList.toggle('is-selected', !!selectedHierarchyElementId && elementId === selectedHierarchyElementId);
      button.classList.toggle('is-hovered', !!hoveredHierarchyElementId && elementId === hoveredHierarchyElementId);
    });
  }

  function updateHierarchyHintOverlays(snapshot) {
    var hintsLayer = getActiveHierarchyHintsLayer();
    var media = getActiveMediaElement();
    if (!hintsLayer || !media || !snapshot || snapshot.width <= 0 || snapshot.height <= 0) {
      if (hintsLayer && hierarchyHintRenderKey !== 'none') {
        hintsLayer.innerHTML = '';
      }
      hierarchyHintRenderKey = 'none';
      return;
    }

    var rect = getDisplayedMediaRect(media);
    if (rect.width <= 0 || rect.height <= 0) {
      if (hierarchyHintRenderKey !== 'none') {
        hintsLayer.innerHTML = '';
      }
      hierarchyHintRenderKey = 'none';
      return;
    }

    var scaleX = rect.width / snapshot.width;
    var scaleY = rect.height / snapshot.height;
    var hintIds = [];
    if (selectedHierarchyElementId) hintIds.push(selectedHierarchyElementId);
    if (hoveredHierarchyElementId && hoveredHierarchyElementId !== selectedHierarchyElementId) {
      hintIds.push(hoveredHierarchyElementId);
    }

    if (!hintIds.length) {
      if (hierarchyHintRenderKey !== 'none') {
        hintsLayer.innerHTML = '';
      }
      hierarchyHintRenderKey = 'none';
      return;
    }

    var hintRenderKey = [
      snapshot.id || '',
      selectedHierarchyElementId || '',
      hoveredHierarchyElementId || '',
      rect.x.toFixed(2),
      rect.y.toFixed(2),
      rect.width.toFixed(2),
      rect.height.toFixed(2)
    ].join('|');
    if (hintRenderKey === hierarchyHintRenderKey) return;

    var hintsHtml = [];
    for (var i = 0; i < hintIds.length; i += 1) {
      var hintElement = hierarchyElementById(snapshot, hintIds[i]);
      if (!hintElement || hintElement.width <= 0 || hintElement.height <= 0) continue;
      var left = rect.x + (hintElement.x * scaleX);
      var top = rect.y + (hintElement.y * scaleY);
      var width = Math.max(2, hintElement.width * scaleX);
      var height = Math.max(2, hintElement.height * scaleY);
      var hintClasses = 'hierarchy-hint-box';
      if (selectedHierarchyElementId && hintElement.id === selectedHierarchyElementId) {
        hintClasses += ' is-selected';
      } else if (hoveredHierarchyElementId && hintElement.id === hoveredHierarchyElementId) {
        hintClasses += ' is-hovered';
      }
      hintsHtml.push('<div class="' + hintClasses + '" style="left:' + left + 'px;top:' + top + 'px;width:' + width + 'px;height:' + height + 'px;"></div>');
    }
    hintsLayer.innerHTML = hintsHtml.join('');
    hierarchyHintRenderKey = hintRenderKey;
  }

  function closeHierarchyMenu() {
    currentHierarchyCandidateIds = [];
    selectedHierarchyElementId = null;
    hierarchyCandidateSelectionKey = '';
    if (hierarchyCandidateList) {
      hierarchyCandidateList.innerHTML = '';
    }
    if (hierarchyCandidatePanel) {
      hierarchyCandidatePanel.hidden = true;
    }
    if (hierarchyCandidateEmpty) {
      hierarchyCandidateEmpty.hidden = false;
    }
    if (hierarchyCandidateHeading) {
      hierarchyCandidateHeading.textContent = 'Elements at point';
    }
    hoveredHierarchyElementId = null;
    updateHierarchyHintOverlays(null);
  }

  function flashHierarchyCandidatePanel() {
    if (!hierarchyCandidatePanel) return;
    hierarchyCandidatePanel.classList.remove('is-flashing');
    void hierarchyCandidatePanel.offsetWidth;
    hierarchyCandidatePanel.classList.add('is-flashing');
    window.setTimeout(function() {
      if (hierarchyCandidatePanel) hierarchyCandidatePanel.classList.remove('is-flashing');
    }, 260);
  }

  function showHierarchyCandidateEmpty(snapshot, message, pointLabel) {
    if (!hierarchyCandidatePanel || !hierarchyCandidateEmpty || !hierarchyCandidateHeading || !hierarchyCandidateList) return;
    hierarchyCandidatePanel.hidden = false;
    hierarchyCandidateHeading.textContent = pointLabel ? ('Elements at point ' + pointLabel) : 'Elements at point';
    hierarchyCandidateList.innerHTML = '';
    hierarchyCandidateEmpty.textContent = message || 'No elements at this point.';
    hierarchyCandidateEmpty.hidden = false;
    currentHierarchyCandidateIds = [];
    selectedHierarchyElementId = null;
    hoveredHierarchyElementId = null;
    hierarchyCandidateSelectionKey = '';
    updateHierarchyHintOverlays(snapshot || null);
    flashHierarchyCandidatePanel();
  }

  function hierarchySnapshotById(snapshotId) {
    if (!snapshotId) return null;
    return hierarchySnapshotByIdMap[snapshotId] || null;
  }

  function hierarchySnapshotForAbsoluteTime(absoluteTime) {
    if (!hierarchySnapshotTimeIndex.length) return null;
    var lowerTime = absoluteTime - HIERARCHY_MATCH_WINDOW;
    var upperTime = absoluteTime + HIERARCHY_MATCH_WINDOW;
    var start = lowerBoundSnapshotTime(lowerTime);
    var best = null;
    var bestDelta = HIERARCHY_MATCH_WINDOW + 1;
    for (var i = start; i < hierarchySnapshotTimeIndex.length; i += 1) {
      var entry = hierarchySnapshotTimeIndex[i];
      if (!entry || !entry.snapshot) continue;
      if (entry.time > upperTime + 0.0001) break;
      var snapshot = entry.snapshot;
      var delta = Math.abs(entry.time - absoluteTime);
      if (delta > HIERARCHY_MATCH_WINDOW) continue;
      if (delta < bestDelta - 0.0001) {
        best = snapshot;
        bestDelta = delta;
      } else if (Math.abs(delta - bestDelta) <= 0.0001 && best && entry.time > (best.time || 0)) {
        best = snapshot;
      }
    }
    return best;
  }

  function hierarchyElementMap(snapshot) {
    if (!snapshot || !snapshot.id || !snapshot.elements) return Object.create(null);
    if (hierarchyElementMapCache[snapshot.id]) return hierarchyElementMapCache[snapshot.id];
    var mapping = Object.create(null);
    for (var i = 0; i < snapshot.elements.length; i += 1) {
      var element = snapshot.elements[i];
      if (!element || !element.id) continue;
      if (!Object.prototype.hasOwnProperty.call(mapping, element.id)) {
        mapping[element.id] = element;
      }
    }
    hierarchyElementMapCache[snapshot.id] = mapping;
    return mapping;
  }

  function hierarchyElementById(snapshot, elementId) {
    if (!snapshot || !elementId) return null;
    var mapping = hierarchyElementMap(snapshot);
    return mapping[elementId] || null;
  }

  function hierarchyParentMap(snapshot) {
    if (!snapshot || !snapshot.id || !snapshot.elements) return Object.create(null);
    if (hierarchyParentMapCache[snapshot.id]) return hierarchyParentMapCache[snapshot.id];

    var mapping = Object.create(null);
    var ancestorStack = [];
    for (var i = 0; i < snapshot.elements.length; i += 1) {
      var node = snapshot.elements[i];
      if (!node || !node.id) continue;
      var depth = Number.isFinite(node.depth) ? Math.max(0, Math.floor(node.depth)) : 0;
      while (ancestorStack.length > depth) ancestorStack.pop();
      mapping[node.id] = ancestorStack.length ? ancestorStack[ancestorStack.length - 1] : null;
      ancestorStack.push(node.id);
    }
    hierarchyParentMapCache[snapshot.id] = mapping;
    return mapping;
  }

  function hierarchyAncestorChain(snapshot, element) {
    if (!snapshot || !element || !element.id) return [];
    var parentMap = hierarchyParentMap(snapshot);
    var chain = [];
    var seen = Object.create(null);
    var currentId = parentMap[element.id];
    while (currentId && !seen[currentId]) {
      seen[currentId] = true;
      var parentElement = hierarchyElementById(snapshot, currentId);
      if (!parentElement) break;
      chain.unshift(parentElement);
      currentId = parentMap[currentId];
    }
    return chain;
  }

  function compactHierarchyChain(ancestors) {
    var compact = [];
    var runningIndex = 1;
    for (var i = 0; i < ancestors.length; i += 1) {
      var title = hierarchyElementTitle(ancestors[i]);
      var last = compact.length ? compact[compact.length - 1] : null;
      if (last && last.title === title) {
        last.count += 1;
        last.end = runningIndex;
      } else {
        compact.push({ title: title, start: runningIndex, end: runningIndex, count: 1 });
      }
      runningIndex += 1;
    }
    return compact;
  }

  function hierarchyElementTitle(element) {
    if (!element) return 'UI Element';
    var descriptor = element.role || 'Element';
    if (element.label) return descriptor + ' "' + element.label + '"';
    if (element.identifier) return descriptor + ' #' + element.identifier;
    if (element.name) return descriptor + ' (' + element.name + ')';
    return descriptor;
  }

  function setHierarchyHighlight(snapshot, element) {
    var highlight = getActiveHierarchyHighlight();
    var media = getActiveMediaElement();
    if (!highlight || !media || !snapshot || !element || element.width <= 0 || element.height <= 0 || snapshot.width <= 0 || snapshot.height <= 0) {
      if (highlight) highlight.hidden = true;
      hierarchyHighlightRenderKey = 'none';
      return;
    }

    var rect = getDisplayedMediaRect(media);
    if (rect.width <= 0 || rect.height <= 0) {
      highlight.hidden = true;
      hierarchyHighlightRenderKey = 'none';
      return;
    }

    var scaleX = rect.width / snapshot.width;
    var scaleY = rect.height / snapshot.height;
    var left = rect.x + (element.x * scaleX);
    var top = rect.y + (element.y * scaleY);
    var width = Math.max(2, element.width * scaleX);
    var height = Math.max(2, element.height * scaleY);

    var highlightKey = [
      snapshot.id || '',
      element.id || '',
      left.toFixed(2),
      top.toFixed(2),
      width.toFixed(2),
      height.toFixed(2)
    ].join('|');
    if (highlightKey === hierarchyHighlightRenderKey) return;

    highlight.style.left = left + 'px';
    highlight.style.top = top + 'px';
    highlight.style.width = width + 'px';
    highlight.style.height = height + 'px';
    highlight.hidden = false;
    hierarchyHighlightRenderKey = highlightKey;
  }

  function updateHierarchyInspector(snapshot, element) {
    if (!hierarchyPanel || !hierarchyToolbar || !hierarchyStatus || !hierarchyInspector || !hierarchySelectedTitle || !hierarchySelectedSubtitle || !hierarchyProperties) return;
    refreshHierarchyPanelVisibility();
    var inspectorKey = hierarchyPanel.hidden
      ? 'hidden'
      : ((snapshot ? (snapshot.id || 'snapshot') : 'none') + '|' + (element ? (element.id || 'selected') : 'none'));
    if (inspectorKey === hierarchyInspectorRenderKey) return;
    hierarchyInspectorRenderKey = inspectorKey;
    if (hierarchyPanel.hidden) {
      hierarchyProperties.innerHTML = '';
      return;
    }

    if (!snapshot) {
      hierarchyStatus.textContent = 'No hierarchy snapshot near this moment.';
      hierarchySelectedTitle.textContent = 'Selected element';
      hierarchySelectedSubtitle.textContent = 'Scrub near a hierarchy snapshot, then click inside the media.';
      hierarchyProperties.innerHTML = '';
      if (hierarchyCandidatePanel) hierarchyCandidatePanel.hidden = true;
      if (hierarchyCandidateHeading) hierarchyCandidateHeading.textContent = 'Elements at point';
      if (hierarchyCandidateEmpty) {
        hierarchyCandidateEmpty.textContent = 'No hierarchy snapshot near this moment.';
        hierarchyCandidateEmpty.hidden = false;
      }
      if (hierarchyCandidateList) hierarchyCandidateList.innerHTML = '';
      return;
    }

    var offset = Math.max(0, (snapshot.time || 0) - (timelineBase || 0));
    var elementCount = snapshot.elements ? snapshot.elements.length : 0;
    hierarchyStatus.textContent = snapshot.label + ' @ ' + formatSeconds(offset) + ' (' + elementCount + ' nodes)';

    if (!element) {
      hierarchySelectedTitle.textContent = 'Selected element';
      hierarchySelectedSubtitle.textContent = 'Choose an item from “Elements at point”.';
      hierarchyProperties.innerHTML = '<div class="hierarchy-prop-row"><span class="hierarchy-prop-key">Selection</span><span class="hierarchy-prop-value">None</span></div>';
      return;
    }

    hierarchySelectedTitle.textContent = 'Selected element';
    hierarchySelectedSubtitle.textContent = hierarchyElementTitle(element) + ' · x ' + Number(element.x).toFixed(1) + ' · y ' + Number(element.y).toFixed(1) + ' · ' + Number(element.width).toFixed(1) + ' × ' + Number(element.height).toFixed(1);

    var rows = [];
    function pushRow(key, value, valueClassName) {
      if (value == null || value === '') return;
      var valueClass = 'hierarchy-prop-value';
      if (valueClassName) {
        valueClass += ' ' + valueClassName;
      }
      rows.push('<div class="hierarchy-prop-row"><span class="hierarchy-prop-key">' + escapeHTML(key) + '</span><span class="' + valueClass + '">' + escapeHTML(value) + '</span></div>');
    }
    function pushRowHTML(key, htmlValue, valueClassName) {
      if (!htmlValue) return;
      var valueClass = 'hierarchy-prop-value';
      if (valueClassName) {
        valueClass += ' ' + valueClassName;
      }
      rows.push('<div class="hierarchy-prop-row"><span class="hierarchy-prop-key">' + escapeHTML(key) + '</span><span class="' + valueClass + '">' + htmlValue + '</span></div>');
    }

    pushRow('Frame', '{{' + Number(element.x).toFixed(1) + ', ' + Number(element.y).toFixed(1) + '}, {' + Number(element.width).toFixed(1) + ', ' + Number(element.height).toFixed(1) + '}}', 'mono');
    pushRow('Role', element.role || '');
    pushRow('Name', element.name || '');
    pushRow('Label', element.label || '');
    pushRow('Identifier', element.identifier || '');
    pushRow('Value', element.value || '');
    pushRow('Element ID', element.id || '', 'mono');
    pushRow('Depth', String(element.depth == null ? '' : element.depth), 'mono');
    var ancestors = hierarchyAncestorChain(snapshot, element);
    if (ancestors.length) {
      var compactPath = compactHierarchyChain(ancestors);
      var containerPath = '<div class="hierarchy-container-path">' + compactPath.map(function(entry) {
        var indexLabel = entry.count > 1 ? (String(entry.start) + '-' + String(entry.end)) : String(entry.start);
        var repeatBadge = entry.count > 1 ? ('<span class="hierarchy-container-repeat">×' + String(entry.count) + '</span>') : '';
        return '<span class="hierarchy-container-item"><span class="hierarchy-container-index">' + escapeHTML(indexLabel) + '.</span><span class="hierarchy-container-name">' + escapeHTML(entry.title) + '</span>' + repeatBadge + '</span>';
      }).join('') + '</div>';
      pushRowHTML('Containers', containerPath, 'path');
    } else {
      pushRow('Containers', 'None (top-level)', 'path');
    }

    var properties = element.properties || {};
    var propertyKeys = Object.keys(properties).sort();
    propertyKeys.forEach(function(key) {
      if (key === 'depth') return;
      var normalized = key.toLowerCase();
      if (normalized === 'label' || normalized === 'identifier' || normalized === 'value') return;
      if (normalized === 'frame' || normalized === 'metadata' || normalized === 'name' || normalized === 'role') return;
      var valueClass = '';
      if (normalized.indexOf('id') >= 0 || normalized.indexOf('frame') >= 0 || normalized.indexOf('rect') >= 0 || normalized.indexOf('hash') >= 0) {
        valueClass = 'mono';
      }
      pushRow(key, properties[key], valueClass);
    });

    hierarchyProperties.innerHTML = rows.join('');
    updateHierarchyCandidateSelectionState();
  }

  function hierarchyElementsAtPoint(snapshot, x, y) {
    if (!snapshot || !snapshot.elements) return [];
    var maxElementWidth = snapshot.width * 1.35;
    var maxElementHeight = snapshot.height * 1.35;
    var seenIds = Object.create(null);
    var matches = snapshot.elements.filter(function(element) {
      if (!element || !element.id || seenIds[element.id]) return false;
      seenIds[element.id] = true;
      if (element.width <= 2 || element.height <= 2) return false;
      if (element.width > maxElementWidth || element.height > maxElementHeight) return false;
      if (element.x > snapshot.width + 20 || element.y > snapshot.height + 20) return false;
      if ((element.x + element.width) < -20 || (element.y + element.height) < -20) return false;
      return x >= element.x && y >= element.y && x <= (element.x + element.width) && y <= (element.y + element.height);
    });
    matches.sort(function(a, b) {
      var areaA = Math.max(0, a.width * a.height);
      var areaB = Math.max(0, b.width * b.height);
      if (areaA !== areaB) return areaA - areaB;
      return (b.depth || 0) - (a.depth || 0);
    });
    return matches;
  }

  function openHierarchyCandidateMenu(snapshot, candidates, pointLabel) {
    if (!hierarchyCandidateList || !candidates.length) return;

    setHierarchyPanelExpanded(true);
    var options = candidates.slice(0, 20);
    currentHierarchyCandidateIds = options.map(function(element) { return element.id; });
    selectedHierarchyElementId = options[0] ? options[0].id : null;
    hoveredHierarchyElementId = null;
    hierarchyCandidateSelectionKey = '';
    hierarchyCandidateList.innerHTML = options.map(function(element) {
      return '<button type="button" class="hierarchy-candidate-item" data-hierarchy-element-id="' + escapeHTML(element.id) + '">'
        + '<span class="hierarchy-candidate-title">' + escapeHTML(hierarchyElementTitle(element)) + '</span>'
        + '<span class="hierarchy-candidate-frame">x ' + Number(element.x).toFixed(0) + ' · y ' + Number(element.y).toFixed(0) + ' · ' + Number(element.width).toFixed(0) + ' × ' + Number(element.height).toFixed(0) + '</span>'
        + '</button>';
    }).join('');
    if (hierarchyCandidatePanel) {
      hierarchyCandidatePanel.hidden = false;
    }
    if (hierarchyCandidateHeading) {
      hierarchyCandidateHeading.textContent = pointLabel ? ('Elements at point ' + pointLabel) : 'Elements at point';
    }
    if (hierarchyCandidateEmpty) {
      hierarchyCandidateEmpty.textContent = 'Tap any item below to inspect it.';
      hierarchyCandidateEmpty.hidden = true;
    }

    Array.prototype.forEach.call(hierarchyCandidateList.querySelectorAll('.hierarchy-candidate-item'), function(button) {
      var elementId = button.getAttribute('data-hierarchy-element-id');
      button.addEventListener('mouseenter', function() {
        hoveredHierarchyElementId = elementId;
        updateHierarchyCandidateSelectionState();
        updateHierarchyOverlay();
      });
      button.addEventListener('mouseleave', function() {
        hoveredHierarchyElementId = null;
        updateHierarchyCandidateSelectionState();
        updateHierarchyOverlay();
      });
      button.addEventListener('click', function(event) {
        event.preventDefault();
        event.stopPropagation();
        selectedHierarchyElementId = elementId;
        hoveredHierarchyElementId = null;
        updateHierarchyCandidateSelectionState();
        updateHierarchyOverlay();
      });
    });
    updateHierarchyHintOverlays(snapshot);
    updateHierarchyCandidateSelectionState();
    updateHierarchyInspector(snapshot, hierarchyElementById(snapshot, selectedHierarchyElementId));
    flashHierarchyCandidatePanel();
  }

  function handleHierarchyOverlayClick(event, layer) {
    if (!layer) return;
    var snapshot = hierarchySnapshotById(currentHierarchySnapshotId);
    var media = getActiveMediaElement();
    if (!snapshot || !media || snapshot.width <= 0 || snapshot.height <= 0) return;

    var layerRect = layer.getBoundingClientRect();
    var localX = event.clientX - layerRect.left;
    var localY = event.clientY - layerRect.top;
    var mediaRect = getDisplayedMediaRect(media);

    if (localX < mediaRect.x || localY < mediaRect.y || localX > (mediaRect.x + mediaRect.width) || localY > (mediaRect.y + mediaRect.height)) {
      updateHierarchyOverlay();
      return;
    }

    var normalizedX = (localX - mediaRect.x) / Math.max(1, mediaRect.width);
    var normalizedY = (localY - mediaRect.y) / Math.max(1, mediaRect.height);
    var hierarchyX = normalizedX * snapshot.width;
    var hierarchyY = normalizedY * snapshot.height;
    var pointLabel = '(' + Number(hierarchyX).toFixed(0) + ', ' + Number(hierarchyY).toFixed(0) + ')';
    var candidates = hierarchyElementsAtPoint(snapshot, hierarchyX, hierarchyY);

    if (!candidates.length) {
      selectedHierarchyElementId = null;
      hoveredHierarchyElementId = null;
      showHierarchyCandidateEmpty(snapshot, 'No elements at this point.', pointLabel);
      updateHierarchyOverlay();
      event.preventDefault();
      event.stopPropagation();
      return;
    }

    openHierarchyCandidateMenu(snapshot, candidates, pointLabel);
    event.preventDefault();
    event.stopPropagation();
  }

  function updateHierarchyOverlay() {
    var highlight = getActiveHierarchyHighlight();
    var media = getActiveMediaElement();
    if (!highlight || !media || !hierarchySnapshots.length || mediaMode === 'none') {
      currentHierarchySnapshotId = null;
      selectedHierarchyElementId = null;
      hoveredHierarchyElementId = null;
      closeHierarchyMenu();
      if (highlight) highlight.hidden = true;
      updateHierarchyInspector(null, null);
      return;
    }

    var snapshot = hierarchySnapshotForAbsoluteTime(currentAbsoluteTime());
    if (!snapshot) {
      if (currentHierarchySnapshotId !== null) {
        closeHierarchyMenu();
      }
      currentHierarchySnapshotId = null;
      selectedHierarchyElementId = null;
      hoveredHierarchyElementId = null;
      highlight.hidden = true;
      updateHierarchyInspector(null, null);
      return;
    }

    if (snapshot.id !== currentHierarchySnapshotId) {
      currentHierarchySnapshotId = snapshot.id;
      selectedHierarchyElementId = null;
      hoveredHierarchyElementId = null;
      closeHierarchyMenu();
    }

    var selectedElement = hierarchyElementById(snapshot, selectedHierarchyElementId);
    var hoveredElement = hierarchyElementById(snapshot, hoveredHierarchyElementId);
    if (selectedHierarchyElementId && !selectedElement) {
      selectedHierarchyElementId = null;
      selectedElement = null;
    }
    if (hoveredHierarchyElementId && !hoveredElement) {
      hoveredHierarchyElementId = null;
      hoveredElement = null;
    }
    var highlightedElement = hoveredElement || selectedElement;
    updateHierarchyHintOverlays(snapshot);
    setHierarchyHighlight(snapshot, highlightedElement);
    updateHierarchyInspector(snapshot, selectedElement);
    updateHierarchyCandidateSelectionState();
  }

  function updateStillFrameForTime(absoluteTime) {
    if (mediaMode !== 'screenshot' || !screenshots.length) return;
    var frame = root.querySelector('[data-still-frame]');
    if (!frame) return;

    var idx = 0;
    while (idx + 1 < screenshots.length && screenshots[idx + 1].time <= absoluteTime + 0.05) idx += 1;
    var nextShot = screenshots[idx];
    if (!nextShot) return;

    if (frame.dataset.currentSrc !== nextShot.src) {
      frame.src = nextShot.src;
      frame.dataset.currentSrc = nextShot.src;
    }
    frame.alt = nextShot.label || 'Screenshot';
  }

  function setAbsoluteTime(absoluteTime) {
    var video = getActiveVideo();
    if (video) {
      var target = Math.max(0, absoluteTime - activeMediaStartTime());
      scrubPreviewActive = true;
      scrubPreviewTime = target;
      requestVideoSeek(target);
      return;
    }

    virtualCurrentTime = Math.max(0, Math.min(virtualDuration, absoluteTime - (timelineBase || 0)));
    updateStillFrameForTime((timelineBase || 0) + virtualCurrentTime);
  }

  function ensureTouchMarker(layer) {
    if (!layer) return null;
    if (!touchMarker || touchMarker.parentElement !== layer) {
      if (touchMarker && touchMarker.parentElement) {
        touchMarker.parentElement.removeChild(touchMarker);
      }
      touchMarker = document.createElement('div');
      touchMarker.className = 'touch-indicator';
      layer.appendChild(touchMarker);
    }
    return touchMarker;
  }

  function hideTouchMarker() {
    if (!touchMarker) return;
    touchMarker.style.opacity = '0';
  }

  function pointForGestureAtTime(gesture, absoluteTime) {
    if (!gesture || !gesture.points || !gesture.points.length) return null;
    var points = gesture.points;
    if (absoluteTime <= points[0].time) {
      return { x: points[0].x, y: points[0].y };
    }
    for (var i = 1; i < points.length; i += 1) {
      var nextPoint = points[i];
      if (absoluteTime <= nextPoint.time) {
        var prevPoint = points[i - 1];
        var span = Math.max(0.0001, nextPoint.time - prevPoint.time);
        var ratio = (absoluteTime - prevPoint.time) / span;
        return {
          x: prevPoint.x + (nextPoint.x - prevPoint.x) * ratio,
          y: prevPoint.y + (nextPoint.y - prevPoint.y) * ratio
        };
      }
    }
    var last = points[points.length - 1];
    return { x: last.x, y: last.y };
  }

  function activeGestureAtTime(absoluteTime, previewMode) {
    if (!touchGestures.length) return null;
    var lead = previewMode ? SCRUB_PREVIEW_WINDOW : TOUCH_PLAYBACK_LEAD_WINDOW;
    var tail = previewMode ? SCRUB_PREVIEW_WINDOW : TOUCH_RELEASE_DURATION;
    var best = null;
    for (var i = 0; i < touchGestures.length; i += 1) {
      var gesture = touchGestures[i];
      if (absoluteTime < gesture.startTime - lead) continue;
      if (absoluteTime > gesture.endTime + tail) continue;
      if (!best || gesture.startTime >= best.startTime) {
        best = gesture;
      }
    }
    return best;
  }

  function updateTouchOverlay() {
    var media = getActiveMediaElement();
    var layer = getActiveTouchLayer();
    if (!media || !layer || !touchGestures.length) {
      hideTouchMarker();
      return;
    }

    var absoluteTime = currentAbsoluteTime();
    var previewMode = !(mediaMode === 'video' && getActiveVideo() && !getActiveVideo().paused) && !virtualPlaying;
    var gesture = activeGestureAtTime(absoluteTime, previewMode);
    if (!gesture) {
      hideTouchMarker();
      return;
    }

    var marker = ensureTouchMarker(layer);
    if (!marker) return;
    var pointTime = absoluteTime;
    if (previewMode) {
      pointTime = Math.max(gesture.startTime, Math.min(gesture.endTime, absoluteTime));
    }
    var point = pointForGestureAtTime(gesture, pointTime);
    if (!point) {
      hideTouchMarker();
      return;
    }

    var rect = getDisplayedMediaRect(media);
    if (rect.width <= 0 || rect.height <= 0 || gesture.width <= 0 || gesture.height <= 0) {
      hideTouchMarker();
      return;
    }

    var normalizedX = Math.min(1, Math.max(0, point.x / gesture.width));
    var normalizedY = Math.min(1, Math.max(0, point.y / gesture.height));
    var x = rect.x + normalizedX * rect.width;
    var y = rect.y + normalizedY * rect.height;

    var releaseProgress = 0;
    if (absoluteTime > gesture.endTime) {
      releaseProgress = Math.min(1, (absoluteTime - gesture.endTime) / TOUCH_RELEASE_DURATION);
    }
    var scale = 1 + (releaseProgress * 0.65);
    var opacity = absoluteTime <= gesture.endTime ? 0.9 : (1 - releaseProgress) * 0.9;

    marker.style.left = x + 'px';
    marker.style.top = y + 'px';
    marker.style.opacity = String(Math.max(0, opacity));
    marker.style.transform = 'translate(-50%, -50%) scale(' + scale.toFixed(3) + ')';
  }

  function stopTouchAnimation() {
    if (!touchAnimationFrame) return;
    cancelAnimationFrame(touchAnimationFrame);
    touchAnimationFrame = 0;
  }

  function startTouchAnimation() {
    if (touchAnimationFrame) return;
    function tick() {
      touchAnimationFrame = 0;
      updateTouchOverlay();
      updateHierarchyOverlay();
      var video = getActiveVideo();
      var shouldContinue = (video && !video.paused) || (!video && virtualPlaying);
      if (shouldContinue) {
        touchAnimationFrame = requestAnimationFrame(tick);
      }
    }
    touchAnimationFrame = requestAnimationFrame(tick);
  }

  function stopVirtualPlayback() {
    if (!virtualPlaying && !virtualAnimationFrame) return;
    virtualPlaying = false;
    virtualLastTick = 0;
    if (virtualAnimationFrame) {
      cancelAnimationFrame(virtualAnimationFrame);
      virtualAnimationFrame = 0;
    }
    stopTouchAnimation();
    updateFromVideoTime();
  }

  function startVirtualPlayback() {
    if (virtualPlaying || virtualDuration <= 0) return;
    virtualPlaying = true;
    virtualLastTick = 0;

    function tick(timestamp) {
      if (!virtualPlaying) return;
      if (!virtualLastTick) virtualLastTick = timestamp;
      var delta = Math.max(0, (timestamp - virtualLastTick) / 1000);
      virtualLastTick = timestamp;
      virtualCurrentTime = Math.min(virtualDuration, virtualCurrentTime + delta);
      updateFromVideoTime();
      if (virtualCurrentTime >= virtualDuration) {
        stopVirtualPlayback();
        return;
      }
      virtualAnimationFrame = requestAnimationFrame(tick);
    }

    virtualAnimationFrame = requestAnimationFrame(tick);
    startTouchAnimation();
    updateFromVideoTime();
  }

  function eventIndexById(eventId) {
    if (!eventId) return -1;
    var mappedIndex = eventIndexByIdMap[eventId];
    return Number.isFinite(mappedIndex) ? mappedIndex : -1;
  }

  function eventNodeForId(eventId) {
    if (!eventId) return null;
    return eventNodeById[eventId] || null;
  }

  function expandAncestorDetails(node) {
    var details = node ? node.closest('details') : null;
    while (details) {
      details.open = true;
      details = details.parentElement ? details.parentElement.closest('details') : null;
    }
  }

  function collapsedAncestorSummaryEvent(node) {
    var details = node ? node.closest('details') : null;
    var visibleCollapsedSummary = null;
    while (details) {
      if (!details.open) {
        var summary = details.firstElementChild;
        var summaryEvent = summary ? summary.querySelector('.timeline-event') : null;
        if (summaryEvent) {
          // Prefer the outermost collapsed ancestor. Inner collapsed summaries can be
          // hidden when an outer ancestor is also collapsed, which breaks auto-follow.
          visibleCollapsedSummary = summaryEvent;
        }
      }
      details = details.parentElement ? details.parentElement.closest('details') : null;
    }
    return visibleCollapsedSummary;
  }

  function sameNodeSequence(a, b) {
    if (a === b) return true;
    if (!a || !b || a.length !== b.length) return false;
    for (var i = 0; i < a.length; i += 1) {
      if (a[i] !== b[i]) return false;
    }
    return true;
  }

  function contextNodesFor(node) {
    var nodes = [];
    var details = node ? node.closest('details') : null;
    while (details) {
      var summary = details.firstElementChild;
      var summaryEvent = summary ? summary.querySelector('.timeline-event') : null;
      if (summaryEvent && summaryEvent !== node) {
        if (nodes.indexOf(summaryEvent) < 0) {
          nodes.push(summaryEvent);
        }
      }
      details = details.parentElement ? details.parentElement.closest('details') : null;
    }
    return nodes;
  }

  function updateContextHighlight(node) {
    var nextContextNodes = contextNodesFor(node);
    if (sameNodeSequence(activeContextNodes, nextContextNodes)) return;

    if (activeContextNodes.length) {
      activeContextNodes.forEach(function(el) { el.classList.remove('timeline-context-active'); });
    }
    nextContextNodes.forEach(function(el) { el.classList.add('timeline-context-active'); });
    activeContextNodes = nextContextNodes;
  }

  function setCollapsedProxyActive(node) {
    if (activeProxyNode && activeProxyNode !== node) {
      activeProxyNode.classList.remove('timeline-active-proxy');
    }
    activeProxyNode = node || null;
    if (activeProxyNode) {
      activeProxyNode.classList.add('timeline-active-proxy');
    }
  }

  function scrollTimelineNodeIntoView(node, scrollBehavior) {
    if (!node) return;
    var behavior = scrollBehavior || 'auto';
    var tree = timelineTree || node.closest('.timeline-tree');
    if (!tree || tree.scrollHeight <= tree.clientHeight + 1) {
      node.scrollIntoView({ block: 'nearest', behavior: behavior });
      return;
    }

    var treeRect = tree.getBoundingClientRect();
    var nodeRect = node.getBoundingClientRect();
    var padding = 10;
    var topLimit = treeRect.top + padding;
    var bottomLimit = treeRect.bottom - padding;

    var delta = 0;
    if (nodeRect.top < topLimit) {
      delta = nodeRect.top - topLimit;
    } else if (nodeRect.bottom > bottomLimit) {
      delta = nodeRect.bottom - bottomLimit;
    }
    if (Math.abs(delta) < 0.5) return;

    var targetTop = tree.scrollTop + delta;
    if (typeof tree.scrollTo === 'function') {
      tree.scrollTo({ top: targetTop, behavior: behavior });
    } else {
      tree.scrollTop = targetTop;
    }
  }

  function setActiveEvent(eventId, shouldReveal, scrollBehavior, scrollWhenCollapsed) {
    if (!eventId) return;
    var idx = eventIndexById(eventId);
    if (idx >= 0) activeEventIndex = idx;
    var previousRenderedNode = activeRenderedNode;

    var preciseNode = eventNodeForId(eventId);
    if (preciseNode && shouldReveal) {
      expandAncestorDetails(preciseNode);
    }

    var visibleNode = preciseNode;
    if (preciseNode && !shouldReveal && scrollWhenCollapsed) {
      var collapsedSummary = collapsedAncestorSummaryEvent(preciseNode);
      if (collapsedSummary) {
        visibleNode = collapsedSummary;
      }
    }

    var renderNode = visibleNode || preciseNode;
    if (activeRenderedNode && activeRenderedNode !== renderNode) {
      activeRenderedNode.classList.remove('timeline-active');
    }
    activeRenderedNode = renderNode || null;
    if (activeRenderedNode) {
      activeRenderedNode.classList.add('timeline-active');
    }

    setCollapsedProxyActive(null);
    // Keep a single visible highlight target: either the precise node or
    // the collapsed summary proxy when the precise node is hidden.
    updateContextHighlight(null);

    if (activeRenderedNode && (shouldReveal || scrollBehavior)) {
      var shouldScrollNode = shouldReveal || activeRenderedNode !== previousRenderedNode;
      if (shouldScrollNode) {
        scrollTimelineNodeIntoView(activeRenderedNode, scrollBehavior || 'smooth');
      }
    }

    activeEventId = eventId;
    updateScrubberMarkerActiveState();
  }

  function jumpToEventByIndex(index, shouldReveal, seekAbsoluteTime) {
    if (!events.length) return;
    if (index < 0 || index >= events.length) return;
    var event = events[index];
    setActiveEvent(event.id, shouldReveal);
    if (eventLabel) eventLabel.textContent = event.title;
    var targetTime = Number(seekAbsoluteTime);
    if (!Number.isFinite(targetTime)) {
      targetTime = Number(event.time);
    }
    if (!Number.isFinite(targetTime)) {
      targetTime = currentAbsoluteTime();
    }
    setAbsoluteTime(targetTime);
    // Preserve explicit prev/next/marker selection when multiple events share a timestamp.
    scrubPreviewActive = false;
    updateFromVideoTime();
  }

  function eventIndexForAbsoluteTime(absTime) {
    if (!eventTimeLookup.length) return -1;
    var epsilon = 0.05;
    var targetTime = absTime + epsilon;
    var low = 0;
    var high = eventTimeLookup.length - 1;
    var best = -1;
    while (low <= high) {
      var mid = (low + high) >> 1;
      var midTime = eventTimeLookup[mid].start;
      if (midTime <= targetTime) {
        best = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    if (best < 0) return eventTimeLookup[0].index;

    var chosen = eventTimeLookup[best];
    if (chosen.end > chosen.start + 0.0001 && absTime > chosen.end + epsilon) {
      for (var i = best - 1; i >= 0; i -= 1) {
        var candidate = eventTimeLookup[i];
        if (candidate.end > candidate.start + 0.0001 && absTime <= candidate.end + epsilon) {
          return candidate.index;
        }
      }
    }

    return chosen.index;
  }

  function currentEventIndexForNavigation() {
    if (activeEventIndex >= 0 && activeEventIndex < events.length) return activeEventIndex;
    if (!events.length) return -1;
    var absoluteTime = currentAbsoluteTime();
    return eventIndexForAbsoluteTime(absoluteTime);
  }

  function goToPreviousEvent() {
    if (!events.length) return;
    var currentIdx = currentEventIndexForNavigation();
    if (currentIdx < 0) return;
    jumpToEventByIndex(Math.max(0, currentIdx - 1), true);
  }

  function goToNextEvent() {
    if (!events.length) return;
    var currentIdx = currentEventIndexForNavigation();
    if (currentIdx < 0) return;
    jumpToEventByIndex(Math.min(events.length - 1, currentIdx + 1), true);
  }

  function togglePlayback() {
    var video = getActiveVideo();
    if (video) {
      if (video.paused) {
        video.play().catch(function() {});
      } else {
        video.pause();
      }
      return;
    }
    if (virtualPlaying) {
      stopVirtualPlayback();
    } else {
      startVirtualPlayback();
    }
  }

  function isKeyboardEditableTarget(target) {
    if (!target || !(target instanceof Element)) return false;
    if (target.closest('[contenteditable=\"true\"]')) return true;
    var interactive = target.closest('input, textarea, select, button, a');
    if (!interactive) return false;
    if (interactive.tagName === 'INPUT' && interactive.type === 'range') return false;
    return true;
  }

  function scheduleUpdateFromVideoTime() {
    if (videoTimeUpdateFrame) return;
    videoTimeUpdateFrame = requestAnimationFrame(function() {
      videoTimeUpdateFrame = 0;
      updateFromVideoTime();
    });
  }

  function clearScrubPreview() {
    scrubDragging = false;
    scrubPreviewActive = false;
    scrubPreviewTime = 0;
    scrubInteractionDeadline = 0;
    if (dragSeekAnimationFrame) {
      cancelAnimationFrame(dragSeekAnimationFrame);
      dragSeekAnimationFrame = 0;
    }
    dragSeekRequestedTime = null;
  }

  function markScrubInteraction() {
    scrubInteractionDeadline = Date.now() + 500;
  }

  function applyPendingVideoSeek() {
    if (pendingVideoSeekTime == null) return;

    var video = getActiveVideo();
    if (!video) {
      pendingVideoSeekTime = null;
      return;
    }

    var target = pendingVideoSeekTime;
    pendingVideoSeekTime = null;
    var hasMetadata = video.readyState >= 1 && Number.isFinite(video.duration);
    if (hasMetadata) {
      target = Math.max(0, Math.min(video.duration, target));
    } else {
      target = Math.max(0, target);
    }
    try {
      if (!hasMetadata) {
        pendingSeekTime = target;
      } else {
        video.currentTime = target;
      }
    } catch (error) {
      pendingSeekTime = target;
    }
  }

  function requestVideoSeek(timeValue) {
    pendingVideoSeekTime = timeValue;
    applyPendingVideoSeek();
  }

  function scheduleDragVideoSeek(timeValue) {
    dragSeekRequestedTime = timeValue;
    if (dragSeekAnimationFrame) return;
    dragSeekAnimationFrame = requestAnimationFrame(function() {
      dragSeekAnimationFrame = 0;
      if (dragSeekRequestedTime == null) return;
      requestVideoSeek(dragSeekRequestedTime);
      dragSeekRequestedTime = null;
    });
  }

  function scheduleHierarchyOverlayUpdate(force) {
    if (force) pendingHierarchyOverlayForce = true;
    if (hierarchyOverlayFrame) return;
    hierarchyOverlayFrame = requestAnimationFrame(function() {
      hierarchyOverlayFrame = 0;
      var forceUpdate = pendingHierarchyOverlayForce;
      pendingHierarchyOverlayForce = false;
      if (forceUpdate) {
        clearHierarchyRenderCaches();
      }
      updateHierarchyOverlay();
    });
  }

  function updateFromVideoTime() {
    var video = getActiveVideo();
    var absoluteTime = 0;
    var usingScrubPreview = !!(video && scrubPreviewActive);
    var displayOffset = 0;
    if (video) {
      var videoTime = Number(video.currentTime || 0);
      if (!scrubDragging && scrubPreviewActive && Math.abs(videoTime - scrubPreviewTime) <= 0.06) {
        scrubPreviewActive = false;
      }
      usingScrubPreview = !!scrubPreviewActive;
      displayOffset = usingScrubPreview ? scrubPreviewTime : videoTime;
      scrubber.value = displayOffset;
      absoluteTime = activeMediaStartTime() + displayOffset;
    } else {
      displayOffset = virtualCurrentTime || 0;
      scrubber.value = displayOffset;
      absoluteTime = (timelineBase || 0) + displayOffset;
      updateStillFrameForTime(absoluteTime);
    }
    var idx = eventIndexForAbsoluteTime(absoluteTime);
    if (video && !usingScrubPreview && pendingSeekTime != null && activeEventIndex >= 0 && activeEventIndex < events.length) {
      idx = activeEventIndex;
    }
    if (video && !usingScrubPreview && video.paused && activeEventIndex >= 0 && activeEventIndex < events.length) {
      var selected = events[activeEventIndex];
      if (Math.abs((selected.time || 0) - absoluteTime) <= 0.06) {
        idx = activeEventIndex;
      }
    }
    if (idx >= 0) {
      var followDuringScrub =
        scrubDragging
        || scrubPreviewActive
        || Date.now() <= scrubInteractionDeadline;
      setActiveEvent(events[idx].id, false, followDuringScrub ? 'auto' : null, true);
      if (eventLabel) eventLabel.textContent = events[idx].title;
    } else {
      updateScrubberMarkerActiveState();
    }
    var currentOffset = video ? displayOffset : (virtualCurrentTime || 0);
    timeLabel.textContent = formatSeconds(currentOffset);
    var duration = video ? (Number.isFinite(video.duration) ? video.duration : 0) : virtualDuration;
    if (totalTimeLabel) totalTimeLabel.textContent = formatSeconds(duration);
    setPlayButtonIcon(video ? !video.paused : virtualPlaying);
    updateDownloadVideoButton();
    if (video && scrubDragging) {
      hideTouchMarker();
      return;
    }
    updateTouchOverlay();
    scheduleHierarchyOverlayUpdate(false);
  }

  function clampScrubber(video) {
    if (!video) {
      scrubber.max = virtualDuration;
      renderScrubberMarkers();
      updateFromVideoTime();
      return;
    }
    var hasMetadata = video.readyState >= 1 && Number.isFinite(video.duration);
    var duration = hasMetadata ? Math.max(0, video.duration) : 0;
    scrubber.max = duration;
    if (pendingSeekTime != null && hasMetadata) {
      video.currentTime = Math.min(duration, Math.max(0, pendingSeekTime));
      pendingSeekTime = null;
    }
    renderScrubberMarkers();
    updateFromVideoTime();
  }

  function attachVideoHandlers(video) {
    if (!video) return;
    video.addEventListener('loadedmetadata', function() {
      updateActiveMediaAspect();
      clampScrubber(video);
    });
    video.addEventListener('timeupdate', scheduleUpdateFromVideoTime);
    video.addEventListener('play', function() {
      clearScrubPreview();
      updateFromVideoTime();
      startTouchAnimation();
    });
    video.addEventListener('pause', function() {
      stopTouchAnimation();
      updateFromVideoTime();
    });
    video.addEventListener('seeking', scheduleUpdateFromVideoTime);
    video.addEventListener('seeked', function() {
      if (!scrubDragging && scrubPreviewActive && Math.abs((video.currentTime || 0) - scrubPreviewTime) <= 0.06) {
        scrubPreviewActive = false;
      }
      scheduleUpdateFromVideoTime();
    });
  }

  cards.forEach(function(card) {
    var video = card.querySelector('video');
    attachVideoHandlers(video);
    var still = card.querySelector('[data-still-frame]');
    if (still) {
      still.addEventListener('load', function() {
        updateActiveMediaAspect();
        updateTouchOverlay();
        scheduleHierarchyOverlayUpdate(true);
      });
      if (still.complete) {
        updateActiveMediaAspect();
      }
    }
  });

  root.addEventListener('click', function(event) {
    var treeAction = event.target.closest('.timeline-tree-action-btn[data-tree-action]');
    if (treeAction) {
      var tree = timelineTree;
      if (!tree) return;
      var shouldExpand = treeAction.getAttribute('data-tree-action') === 'expand';
      suppressTimelineToggleRefresh = true;
      try {
        Array.prototype.forEach.call(tree.querySelectorAll('details'), function(detail) {
          detail.open = shouldExpand;
        });
      } finally {
        suppressTimelineToggleRefresh = false;
      }
      if (activeEventId) {
        setActiveEvent(activeEventId, false, null, true);
      } else {
        updateScrubberMarkerActiveState();
      }
      return;
    }

    var attachmentLink = event.target.closest('.timeline-attachment-link[data-preview-kind]');
    if (attachmentLink) {
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      if (openAttachmentPreview(attachmentLink)) {
        event.preventDefault();
      }
      return;
    }

    var hierarchyToggleButton = event.target.closest('[data-hierarchy-toggle]');
    if (hierarchyToggleButton) {
      event.preventDefault();
      event.stopPropagation();
      var currentlyExpanded = hierarchyToggle && hierarchyToggle.getAttribute('aria-expanded') === 'true';
      setHierarchyPanelExpanded(!currentlyExpanded);
      return;
    }

    var hierarchyOpenButton = event.target.closest('[data-hierarchy-open]');
    if (hierarchyOpenButton) {
      event.preventDefault();
      event.stopPropagation();
      setHierarchyPanelExpanded(true);
      return;
    }

    if (event.target.closest('.hierarchy-candidate-item')) {
      return;
    }

    if (event.target.closest('[data-hierarchy-panel]')) {
      return;
    }

    var hierarchyLayer = event.target.closest('[data-hierarchy-overlay]');
    if (hierarchyLayer) {
      handleHierarchyOverlayClick(event, hierarchyLayer);
      return;
    }

    var disclosure = event.target.closest('.timeline-disclosure');
    if (disclosure) {
      var disclosureNode = disclosure.closest('.timeline-event[data-event-time]');
      if (!disclosureNode) return;
      var disclosureTimeRaw = disclosureNode.getAttribute('data-event-time');
      if (!disclosureTimeRaw) return;
      var disclosureTime = parseFloat(disclosureTimeRaw);
      if (!Number.isFinite(disclosureTime)) return;
      setAbsoluteTime(disclosureTime);
      setActiveEvent(disclosureNode.getAttribute('data-event-id'), false, 'auto', true);
      var disclosureMatched = eventByIdMap[disclosureNode.getAttribute('data-event-id')] || null;
      if (disclosureMatched && eventLabel) eventLabel.textContent = disclosureMatched.title;
      updateFromVideoTime();
      return;
    }

    closeHierarchyMenu();

    var node = event.target.closest('.timeline-event[data-event-time]');
    if (!node) return;
    var raw = node.getAttribute('data-event-time');
    if (!raw) return;
    var absoluteTime = parseFloat(raw);
    if (!Number.isFinite(absoluteTime)) return;
    setAbsoluteTime(absoluteTime);
    var clickedSummary = !!event.target.closest('summary');
    if (clickedSummary && !event.target.closest('.timeline-disclosure')) {
      event.preventDefault();
    }
    setActiveEvent(node.getAttribute('data-event-id'), false, clickedSummary ? 'auto' : null, true);
    var matched = eventByIdMap[node.getAttribute('data-event-id')] || null;
    if (matched && eventLabel) eventLabel.textContent = matched.title;
    updateFromVideoTime();
  });

  root.addEventListener('dblclick', function(event) {
    var node = event.target.closest('.timeline-event[data-event-time]');
    if (!node) return;
    if (event.target.closest('.timeline-disclosure')) return;
    var raw = node.getAttribute('data-event-time');
    if (!raw) return;
    var absoluteTime = parseFloat(raw);
    if (!Number.isFinite(absoluteTime)) return;
    event.preventDefault();
    setAbsoluteTime(absoluteTime);
    setActiveEvent(node.getAttribute('data-event-id'), true, 'auto', false);
    var matched = eventByIdMap[node.getAttribute('data-event-id')] || null;
    if (matched && eventLabel) eventLabel.textContent = matched.title;
    updateFromVideoTime();
  });

  root.addEventListener('toggle', function(event) {
    if (suppressTimelineToggleRefresh) return;
    var details = event.target;
    if (!details || details.tagName !== 'DETAILS') return;
    if (!details.closest('.timeline-tree')) return;
    if (activeEventId) {
      setActiveEvent(activeEventId, false, null, true);
    }
  }, true);

  if (previewModal) {
    Array.prototype.forEach.call(
      previewModal.querySelectorAll('[data-attachment-close]'),
      function(closeTrigger) {
        closeTrigger.addEventListener('click', function() {
          closeAttachmentPreview();
        });
      }
    );
  }

  prevButton.addEventListener('click', function() {
    goToPreviousEvent();
  });

  nextButton.addEventListener('click', function() {
    goToNextEvent();
  });

  playButton.addEventListener('click', function() {
    togglePlayback();
  });

  function finishScrubDrag() {
    if (!scrubDragging) return;
    scrubDragging = false;
    var video = getActiveVideo();
    if (video) {
      if (dragSeekAnimationFrame) {
        cancelAnimationFrame(dragSeekAnimationFrame);
        dragSeekAnimationFrame = 0;
      }
      if (dragSeekRequestedTime != null) {
        requestVideoSeek(dragSeekRequestedTime);
        dragSeekRequestedTime = null;
      }
      requestVideoSeek(scrubPreviewTime);
      scheduleUpdateFromVideoTime();
    }
  }

  scrubber.addEventListener('pointerdown', function() {
    markScrubInteraction();
    if (getActiveVideo()) {
      scrubDragging = true;
      scrubPreviewActive = true;
      scrubPreviewTime = parseFloat(scrubber.value || '0') || 0;
    }
  });

  scrubber.addEventListener('input', function() {
    markScrubInteraction();
    var video = getActiveVideo();
    var value = parseFloat(scrubber.value || '0');
    if (!Number.isFinite(value)) value = 0;
    if (video) {
      var duration = Number.isFinite(video.duration) ? video.duration : Number(scrubber.max || 0);
      var clampedValue = Math.max(0, Math.min(Number.isFinite(duration) ? duration : value, value));
      scrubPreviewActive = true;
      scrubPreviewTime = clampedValue;
      if (scrubDragging) {
        scheduleDragVideoSeek(clampedValue);
      } else {
        requestVideoSeek(clampedValue);
      }
    } else {
      virtualCurrentTime = Math.max(0, Math.min(virtualDuration, value));
    }
    scheduleUpdateFromVideoTime();
  });

  scrubber.addEventListener('change', function() {
    markScrubInteraction();
    var video = getActiveVideo();
    if (!video) return;
    scrubDragging = false;
    var value = parseFloat(scrubber.value || '0');
    if (!Number.isFinite(value)) value = 0;
    var target = Math.max(0, value);
    scrubPreviewActive = true;
    scrubPreviewTime = target;
    requestVideoSeek(target);
    scheduleUpdateFromVideoTime();
  });

  window.addEventListener('pointerup', finishScrubDrag, true);
  window.addEventListener('pointercancel', finishScrubDrag, true);

  if (selector) {
    selector.addEventListener('change', function() {
      stopTouchAnimation();
      stopVirtualPlayback();
      closeHierarchyMenu();
      clearScrubPreview();
      pendingVideoSeekTime = null;
      activeIndex = parseInt(selector.value, 10) || 0;
      cards.forEach(function(card, idx) {
        var video = card.querySelector('video');
        if (idx === activeIndex) {
          card.style.display = '';
        } else {
          card.style.display = 'none';
          if (video) video.pause();
        }
      });
      var activeVideo = getActiveVideo();
      if (activeVideo) {
        updateActiveMediaAspect();
        clampScrubber(activeVideo);
        updateFromVideoTime();
        if (!activeVideo.paused) {
          startTouchAnimation();
        }
      } else {
        updateDownloadVideoButton();
      }
    });
  }

  if (runSelector) {
    runSelector.addEventListener('change', function() {
      stopTouchAnimation();
      stopVirtualPlayback();
      closeHierarchyMenu();
      applyRunState(parseInt(runSelector.value || '0', 10), true);
    });
  }

  window.addEventListener('resize', function() {
    updateActiveMediaLayout();
    updateTouchOverlay();
    scheduleHierarchyOverlayUpdate(true);
  });

  window.addEventListener('keydown', function(event) {
    if (previewModal && !previewModal.hidden && event.key === 'Escape') {
      event.preventDefault();
      closeAttachmentPreview();
      return;
    }
    if (event.key === 'Escape') {
      if (hierarchyCandidateList && hierarchyCandidateList.children.length) {
        event.preventDefault();
        closeHierarchyMenu();
        updateHierarchyOverlay();
        return;
      }
    }
    if (event.defaultPrevented) return;
    if (isKeyboardEditableTarget(event.target)) return;
    if (event.metaKey || event.ctrlKey || event.altKey) return;

    if (event.code === 'Space' || event.key === ' ') {
      event.preventDefault();
      togglePlayback();
      return;
    }

    if (event.key === 'ArrowRight' || event.key === 'ArrowDown') {
      event.preventDefault();
      goToNextEvent();
      return;
    }

    if (event.key === 'ArrowLeft' || event.key === 'ArrowUp') {
      event.preventDefault();
      goToPreviousEvent();
    }
  });

  function initializeTimelineFromCurrentData() {
    var initialRunIndex = 0;
    for (var i = 0; i < runStates.length; i += 1) {
      if ((runStates[i] && Number(runStates[i].initialFailureEventIndex) >= 0)) {
        initialRunIndex = i;
        break;
      }
    }
    applyRunState(initialRunIndex, false);
    if (runSelector) {
      runSelector.value = String(initialRunIndex);
    }

    setPlayButtonIcon(false);
    var startingVideo = getActiveVideo();
    var didFocusFailureOnLoad = false;
    if (initialFailureEventIndex >= 0 && events.length) {
      var focusIndex = Math.min(events.length - 1, initialFailureEventIndex);
      jumpToEventByIndex(focusIndex, true);
      didFocusFailureOnLoad = true;
    }
    if (startingVideo) {
      updateActiveMediaAspect();
      clampScrubber(startingVideo);
      if (!didFocusFailureOnLoad || pendingSeekTime == null) {
        updateFromVideoTime();
      }
      if (!startingVideo.paused) {
        startTouchAnimation();
      }
    } else {
      updateActiveMediaAspect();
      clampScrubber(null);
      if (!didFocusFailureOnLoad) {
        updateFromVideoTime();
      }
    }
  }

  function applyExternalPayloadOverrides() {
    if (Object.prototype.hasOwnProperty.call(externalJSONPayloads, '[data-timeline-run-states]')) {
      runStates = normalizeRunStates(externalJSONPayloads['[data-timeline-run-states]']);
    }
    if (Object.prototype.hasOwnProperty.call(externalJSONPayloads, '[data-timeline-screenshots]')) {
      screenshots = normalizeScreenshots(externalJSONPayloads['[data-timeline-screenshots]']);
    }
    ensureRunStatesFallback();
  }

  if (externalJSONLoaders.length) {
    Promise.all(externalJSONLoaders)
      .then(function() {
        applyExternalPayloadOverrides();
      })
      .finally(function() {
        ensureRunStatesFallback();
        initializeTimelineFromCurrentData();
      });
  } else {
    ensureRunStatesFallback();
    initializeTimelineFromCurrentData();
  }
})();
