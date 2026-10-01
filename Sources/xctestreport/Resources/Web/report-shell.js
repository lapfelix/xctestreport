// Opens test pages inside the index instead of navigating away. Each test page is still a
// standalone HTML file (direct links and plain static hosting keep working); the index just
// shows it in a full-screen iframe it started loading on hover or press, so opening a test and
// going back are both instant. The same script runs inside the framed test page to route its
// Back and failure links through the index.
(function() {
  var TEST_PAGE = /^tests\/[^/?#]+\.html$/;
  var HASH_PREFIX = '#test=';
  var HOVER_DELAY_MS = 80;
  var MAX_FRAMES = 4;

  var PRELOAD_NAME = 'xctestreport-preload';

  // Test page videos ship with preload="none" so a page the index preloads in the background
  // doesn't tie up the browser's few connections per host with video downloads. They start
  // loading once the page is actually on screen.
  function loadDeferredVideos() {
    Array.prototype.forEach.call(document.querySelectorAll('video[data-deferred-preload]'), function(video) {
      video.preload = video.getAttribute('data-deferred-preload');
      video.removeAttribute('data-deferred-preload');
      reloadVideo(video, 0);
    });
  }

  // WebKit stops at metadata and leaves the player black after a late load(); a seek makes it
  // decode the frame.
  function reloadVideo(video, time) {
    video.addEventListener('loadedmetadata', function seek() {
      video.removeEventListener('loadedmetadata', seek);
      if (!video.seeking && (time > 0 || video.readyState < 2)) {
        // Seeking to where the player already is can be a no-op, hence the nudge off zero.
        video.currentTime = time > 0 ? Math.min(time, video.duration || time) : 0.001;
      }
    });
    video.load();
  }
  if (window.name !== PRELOAD_NAME) { loadDeferredVideos(); }

  // A page the index hides keeps its state but gives up its videos, so paused players don't
  // hold decoders or connections that the page on screen needs. Showing it again reloads them
  // at the same time.
  function suspendVideos() {
    Array.prototype.forEach.call(document.querySelectorAll('video.timeline-video'), function(video) {
      if (video.hasAttribute('data-suspended-time') || !video.currentSrc) { return; }
      video.pause();
      video.setAttribute('data-suspended-time', String(video.currentTime || 0));
      Array.prototype.forEach.call(video.querySelectorAll('source[src]'), function(source) {
        source.setAttribute('data-suspended-src', source.getAttribute('src'));
        source.removeAttribute('src');
      });
      video.load();
    });
  }

  function resumeVideos() {
    loadDeferredVideos();
    Array.prototype.forEach.call(document.querySelectorAll('video[data-suspended-time]'), function(video) {
      var time = parseFloat(video.getAttribute('data-suspended-time')) || 0;
      video.removeAttribute('data-suspended-time');
      Array.prototype.forEach.call(video.querySelectorAll('source[data-suspended-src]'), function(source) {
        source.setAttribute('src', source.getAttribute('data-suspended-src'));
        source.removeAttribute('data-suspended-src');
      });
      reloadVideo(video, time);
    });
  }

  // file:// pages can't reach each other's documents in most browsers, so keep plain links.
  if (window.location.protocol === 'file:') { loadDeferredVideos(); return; }

  if (document.body && document.body.classList.contains('report-index-page')) {
    initShell();
  } else if (window.parent !== window) {
    var shell = null;
    try { shell = window.parent.XCTestReportShell || null; } catch (error) { shell = null; }
    if (shell) { initFramedPage(shell); }
  }

  function reportRelativePath(href, base) {
    var url;
    try { url = new URL(href, base); } catch (error) { return null; }
    var root = new URL('.', indexURL(base)).href;
    if (url.origin !== new URL(root).origin || url.href.indexOf(root) !== 0) { return null; }
    var relative = url.href.slice(root.length).split('#')[0];
    return TEST_PAGE.test(relative) ? relative : null;
  }

  function indexURL(base) {
    // Test pages live one level down in tests/.
    var url = new URL(base);
    return /\/tests\/[^/]*$/.test(url.pathname) ? new URL('../', url).href : url.href;
  }

  function isPlainClick(event) {
    return event.button === 0 && !event.metaKey && !event.ctrlKey && !event.shiftKey && !event.altKey
      && !event.defaultPrevented;
  }

  function linkFrom(event) {
    var target = event.target;
    return target && target.closest ? target.closest('a[href]') : null;
  }

  function initShell() {
    var frames = Object.create(null);
    var order = [];
    var current = null;
    var returnFocus = null;
    var indexTitle = document.title;
    var hoverTimer = null;

    var layer = document.createElement('div');
    layer.className = 'report-shell-layer';
    document.body.appendChild(layer);

    function frameFor(path) {
      var frame = frames[path];
      if (frame) {
        order.splice(order.indexOf(path), 1);
        order.push(path);
        return frame;
      }
      frame = document.createElement('iframe');
      frame.className = 'report-shell-frame';
      frame.title = 'Test details';
      frame.setAttribute('tabindex', '-1');
      frame.name = PRELOAD_NAME;
      frame.src = path;
      frame.addEventListener('load', function() {
        // A page that can't run inside the index (blocked from framing, redirected elsewhere,
        // or an older cached copy of this script) is opened the ordinary way instead.
        var doc = frameDocument(frame);
        frame.shellUnusable = !(doc && doc.documentElement.classList.contains('report-shell-framed'));
        if (frame !== current) { return; }
        if (frame.shellUnusable) { navigateTo(frame, path); return; }
        syncTitle();
        preloadNeighbors(path);
      });
      layer.appendChild(frame);
      frames[path] = frame;
      order.push(path);
      evict();
      return frame;
    }

    function evict() {
      while (order.length > MAX_FRAMES) {
        var victimIndex = -1;
        for (var i = 0; i < order.length; i += 1) {
          if (frames[order[i]] !== current) { victimIndex = i; break; }
        }
        if (victimIndex < 0) { return; }
        var victim = order.splice(victimIndex, 1)[0];
        frames[victim].remove();
        delete frames[victim];
      }
    }

    function frameDocument(frame) {
      try { return frame.contentDocument; } catch (error) { return null; }
    }

    function syncTitle() {
      var doc = current && frameDocument(current);
      if (doc && doc.title) { document.title = doc.title; }
    }

    function activate(frame) {
      try {
        frame.contentWindow.name = '';
        if (frame.contentWindow.XCTestReportFrame) { frame.contentWindow.XCTestReportFrame.activate(); }
      } catch (error) { /* not loaded yet; the page checks its name when it does */ }
    }

    function deactivate(frame) {
      var doc = frameDocument(frame);
      if (!doc) { return; }
      Array.prototype.forEach.call(doc.querySelectorAll('video, audio'), function(media) {
        try { media.pause(); } catch (error) { /* ignore */ }
      });
      try {
        if (frame.contentWindow.XCTestReportFrame) { frame.contentWindow.XCTestReportFrame.deactivate(); }
      } catch (error) { /* ignore */ }
    }

    function navigateTo(frame, path) {
      var href = new URL(path, window.location.href).href;
      try {
        var framed = frame.contentWindow.location.href;
        if (/^https?:/.test(framed)) { href = framed; }
      } catch (error) { /* cross-origin: use the link itself */ }
      window.location.replace(href);
    }

    function rowLinks() {
      return Array.prototype.slice.call(document.querySelectorAll('.suite-tests-table tbody tr td a[href]'));
    }

    function isFilteredOut(link) {
      var row = link.closest('tr');
      var suite = link.closest('.suite');
      return (row && row.style.display === 'none') || (suite && suite.style.display === 'none');
    }

    // Describes the index's current filters, e.g. Failed or Flaky, "login".
    function filterLabel() {
      var chips = Array.prototype.map.call(document.querySelectorAll('.status-chip[aria-pressed="true"]'), function(chip) {
        return chip.getAttribute('data-label') || chip.textContent.trim();
      });
      var search = document.getElementById('test-search');
      var query = search ? search.value.trim() : '';
      var label = chips.join(' or ');
      if (query) { label += (label ? ', ' : '') + '\u201c' + query + '\u201d'; }
      return label;
    }

    // The tests before and after this one, in the order and under the filters the index shows.
    // A test the filters hide (opened from a link, say) steps through every test instead.
    function neighbors(path) {
      var all = rowLinks();
      var list = all.filter(function(link) { return !isFilteredOut(link); });
      var label = filterLabel();
      var paths = list.map(testPath);
      var index = paths.indexOf(path);
      if (index < 0) {
        list = all;
        paths = all.map(testPath);
        index = paths.indexOf(path);
        label = '';
      }
      if (index < 0) { return null; }
      function entry(i) {
        if (i < 0 || i >= list.length) { return null; }
        return { href: new URL(paths[i], window.location.href).href, path: paths[i], name: list[i].textContent.trim() };
      }
      return { position: index + 1, total: list.length, label: label, previous: entry(index - 1), next: entry(index + 1) };
    }

    // Waits until the page on screen has settled, so the neighbours don't compete with it.
    var neighborTimer = null;
    function preloadNeighbors(path) {
      clearTimeout(neighborTimer);
      neighborTimer = setTimeout(function() {
        var run = function() {
          if (!current || current !== frames[path]) { return; }
          var nav = neighbors(path);
          if (!nav) { return; }
          [nav.next, nav.previous].forEach(function(entry) {
            if (entry) { frameFor(entry.path); }
          });
        };
        if (window.requestIdleCallback) { requestIdleCallback(run, { timeout: 1000 }); } else { run(); }
      }, 600);
    }

    function markLastViewed(path) {
      Array.prototype.forEach.call(document.querySelectorAll('tr.is-last-viewed'), function(row) {
        row.classList.remove('is-last-viewed');
      });
      var link = rowLinks().filter(function(candidate) { return testPath(candidate) === path; })[0];
      if (!link) { return; }
      link.closest('tr').classList.add('is-last-viewed');
      returnFocus = link;
    }

    function show(path) {
      var frame = frameFor(path);
      if (frame.shellUnusable) { navigateTo(frame, path); return; }
      if (current && current !== frame) {
        deactivate(current);
        current.classList.remove('is-active');
      }
      current = frame;
      frame.classList.add('is-active');
      activate(frame);
      markLastViewed(path);
      var doc = frameDocument(frame);
      if (doc && doc.readyState === 'complete' && !frame.shellUnusable) { preloadNeighbors(path); }
      document.documentElement.classList.add('report-shell-open');
      layer.classList.add('is-open');
      syncTitle();
      try { frame.contentWindow.focus(); } catch (error) { frame.focus(); }
    }

    function hide() {
      if (!current) { return; }
      deactivate(current);
      current.classList.remove('is-active');
      current = null;
      layer.classList.remove('is-open');
      document.documentElement.classList.remove('report-shell-open');
      document.title = indexTitle;
      if (returnFocus && document.contains(returnFocus)) {
        // Stepping through tests can end far from where the list was left; bring the last one
        // into view.
        returnFocus.focus({ preventScroll: true });
        var row = returnFocus.closest('tr');
        if (row) { row.scrollIntoView({ block: 'nearest' }); }
      }
    }

    function pathFromHash() {
      var hash = window.location.hash;
      if (hash.indexOf(HASH_PREFIX) !== 0) { return null; }
      var path;
      try { path = decodeURIComponent(hash.slice(HASH_PREFIX.length)); } catch (error) { return null; }
      return TEST_PAGE.test(path) ? path : null;
    }

    function hashFor(path) {
      return HASH_PREFIX + encodeURI(path);
    }

    function open(path, options) {
      if (!(options && options.fromHistory)) {
        var state = { xctestreportTest: path };
        if (current && !(options && options.push)) {
          history.replaceState(state, '', hashFor(path));
        } else {
          history.pushState(state, '', hashFor(path));
        }
      }
      show(path);
    }

    function close() {
      if (!current) { return; }
      if (history.state && history.state.xctestreportTest) {
        // Pop the entry open() pushed, so Back and the page's own Back agree.
        history.back();
      } else {
        history.replaceState(null, '', window.location.pathname + window.location.search);
        hide();
      }
    }

    function syncWithLocation() {
      var path = pathFromHash();
      if (path) {
        show(path);
      } else {
        hide();
      }
    }

    window.addEventListener('popstate', syncWithLocation);
    window.addEventListener('hashchange', syncWithLocation);

    function testPath(link) {
      return link ? reportRelativePath(link.getAttribute('href'), window.location.href) : null;
    }

    document.addEventListener('pointerover', function(event) {
      var path = testPath(linkFrom(event));
      if (!path || event.pointerType === 'touch') { return; }
      clearTimeout(hoverTimer);
      hoverTimer = setTimeout(function() { frameFor(path); }, HOVER_DELAY_MS);
    });
    document.addEventListener('pointerout', function(event) {
      if (linkFrom(event)) { clearTimeout(hoverTimer); }
    });
    // A press lands 100ms or so before the click, so start loading right away.
    document.addEventListener('pointerdown', function(event) {
      var path = testPath(linkFrom(event));
      if (path && event.button === 0) { frameFor(path); }
    });
    document.addEventListener('focusin', function(event) {
      var path = testPath(linkFrom(event));
      if (path) { frameFor(path); }
    });

    document.addEventListener('click', function(event) {
      var link = linkFrom(event);
      var path = testPath(link);
      if (!path || !isPlainClick(event) || link.target) { return; }
      event.preventDefault();
      open(path, { push: true });
    });

    window.XCTestReportShell = {
      open: function(href, base) {
        var path = reportRelativePath(href, base);
        if (!path) { return false; }
        open(path);
        return true;
      },
      preload: function(href, base) {
        var path = reportRelativePath(href, base);
        if (path) { frameFor(path); }
      },
      close: close,
      navFor: function(href, base) {
        var path = reportRelativePath(href, base);
        return path ? neighbors(path) : null;
      }
    };

    syncWithLocation();

    // Warm the HTTP cache with the scripts every test page needs, so even the first open is quick.
    var warm = function() {
      ['bundle-reader.js', 'plist-preview.js', 'timeline-view.js', 'snapshot-diff.js'].forEach(function(name) {
        fetch('web/' + name).catch(function() {});
      });
    };
    if (window.requestIdleCallback) { requestIdleCallback(warm, { timeout: 2000 }); } else { setTimeout(warm, 500); }
  }

  function initFramedPage(shell) {
    document.documentElement.classList.add('report-shell-framed');
    window.XCTestReportFrame = {
      activate: function() { resumeVideos(); renderListNav(); },
      deactivate: suspendVideos
    };

    var root = indexURL(window.location.href);

    function linkURL(link) {
      try { return new URL(link.getAttribute('href'), window.location.href); } catch (error) { return null; }
    }

    document.addEventListener('click', function(event) {
      var link = linkFrom(event);
      if (!link || !isPlainClick(event) || link.target || link.hasAttribute('download')) { return; }
      var url = linkURL(link);
      if (!url || !/^https?:$/.test(url.protocol)) { return; }
      var page = url.href.split('#')[0];
      if (page === window.location.href.split('#')[0]) { return; }
      event.preventDefault();
      if (link.classList.contains('test-back-link') || page === root || page === root + 'index.html') {
        shell.close();
      } else if (!shell.open(url.href, window.location.href)) {
        // Anything else (report.md, attachments) replaces the whole report, as it did before.
        window.top.location.href = url.href;
      }
    });

    document.addEventListener('pointerover', function(event) {
      var link = linkFrom(event);
      if (link && link.classList.contains('test-failure-nav-link')) {
        shell.preload(link.getAttribute('href'), window.location.href);
      }
    });

    // Previous/next test as the index lists them, replacing the failure-only links the page
    // ships with (the index's Failed filter gives the same list).
    function renderListNav() {
      var existing = document.querySelector('.test-list-nav');
      if (existing) { existing.remove(); }
      var nav = shell.navFor(window.location.href, window.location.href);
      var anchor = document.querySelector('.test-failure-nav') || document.querySelector('.test-duration-pill');
      var hasNav = !!(nav && nav.total > 1 && anchor);
      document.documentElement.classList.toggle('report-shell-has-list-nav', hasNav);
      if (!hasNav) { return; }

      function link(entry, rel, label, key, glyph) {
        var element;
        if (entry) {
          element = document.createElement('a');
          element.href = entry.href;
          element.rel = rel;
          element.title = label + ': ' + entry.name + ' (' + key + ')';
          element.setAttribute('aria-label', element.title);
        } else {
          element = document.createElement('span');
          element.className = 'is-disabled';
          element.setAttribute('aria-hidden', 'true');
        }
        element.classList.add('test-failure-nav-link');
        element.textContent = glyph;
        return element;
      }

      var element = document.createElement('nav');
      element.className = 'test-failure-nav test-list-nav';
      element.setAttribute('aria-label', 'Tests');
      var count = document.createElement('span');
      count.className = 'test-failure-nav-count';
      count.textContent = nav.position + ' of ' + nav.total;
      if (nav.label) {
        var filter = document.createElement('span');
        filter.className = 'test-list-nav-filter';
        filter.textContent = nav.label;
        count.appendChild(filter);
      }
      count.title = nav.label ? 'Tests shown in the report: ' + nav.label : 'All tests in the report';
      element.appendChild(link(nav.previous, 'prev', 'Previous test', 'K', '\u2039'));
      element.appendChild(count);
      element.appendChild(link(nav.next, 'next', 'Next test', 'J', '\u203a'));
      anchor.insertAdjacentElement('afterend', element);
    }
    renderListNav();

    function isTyping(target) {
      return !!target && (target.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName));
    }

    window.addEventListener('keydown', function(event) {
      if (event.defaultPrevented || event.metaKey || event.ctrlKey || event.altKey) { return; }
      if (document.querySelector('dialog[open]') || isTyping(event.target)) { return; }
      if (event.key === 'Escape') {
        shell.close();
      } else if (event.key === 'j' || event.key === 'k') {
        var target = document.querySelector('.test-list-nav a[rel="' + (event.key === 'j' ? 'next' : 'prev') + '"]');
        if (target) {
          event.preventDefault();
          target.click();
        }
      }
    });
  }
})();
