(function() {
  var toggleAllBtn = document.getElementById('toggle-all');
  var suites = Array.prototype.slice.call(document.getElementsByClassName('suite'));
  var searchInput = document.getElementById('test-search');
  var chips = Array.prototype.slice.call(document.getElementsByClassName('status-chip'));
  var noMatch = document.getElementById('no-match');
  var durationSorters = [];
  var suiteSortState = { key: 'name', direction: 'asc', apply: null };
  var restoringState = false;
  var debounce;

  var flakyChip = document.querySelector('.flaky-chip');
  if (flakyChip) { flakyChip.hidden = !document.querySelector('tr[data-flaky="true"]'); }

  function selectedStatuses() {
    var set = {};
    chips.forEach(function(chip) {
      if (chip.hasAttribute('data-status') && chip.getAttribute('aria-pressed') === 'true') {
        set[chip.getAttribute('data-status')] = true;
      }
    });
    return set;
  }

  function rowName(row) {
    var link = row.querySelector('td a');
    return (link ? link.textContent : row.textContent).toLowerCase();
  }

  function setCollapsed(suite, collapsed, userInitiated) {
    var head = suite.querySelector('.collapsible');
    if (!head) { return; }
    head.classList.toggle('collapsed', collapsed);
    var button = head.querySelector('.suite-toggle');
    if (button) { button.setAttribute('aria-expanded', String(!collapsed)); }
    if (userInitiated && collapsedBeforeSearch !== null) {
      var index = suites.indexOf(suite);
      collapsedBeforeSearch[index] = collapsed;
      searchCollapseOverrides[index] = collapsed;
    }
  }

  function isCollapsed(suite) {
    var head = suite.querySelector('.collapsible');
    return !!head && head.classList.contains('collapsed');
  }

  // Collapse state from before the current search, restored once the search is cleared.
  var collapsedBeforeSearch = null;
  var searchCollapseOverrides = {};
  var previousQuery = '';

  function visibleSuites() {
    return suites.filter(function(suite) { return suite.style.display !== 'none'; });
  }

  function syncToggleAll() {
    if (!toggleAllBtn) { return; }
    var visible = visibleSuites();
    toggleAllBtn.disabled = visible.length === 0;
    toggleAllBtn.textContent = visible.some(function(suite) { return !isCollapsed(suite); }) ? 'Collapse All' : 'Expand All';
  }

  suites.forEach(function(suite, index) {
    var head = suite.querySelector('.collapsible');
    if (!head) { return; }
    // Preserve heading navigation, including for reports generated with older markup.
    head.removeAttribute('role');
    head.removeAttribute('tabindex');
    head.removeAttribute('aria-expanded');
    var button = head.querySelector('.suite-toggle');
    if (!button) {
      button = document.createElement('button');
      button.type = 'button';
      button.className = 'suite-toggle';
      while (head.firstChild) { button.appendChild(head.firstChild); }
      head.appendChild(button);
    }
    var content = suite.querySelector('.content');
    if (content) {
      if (!content.id) { content.id = 'suite-content-' + index; }
      button.setAttribute('aria-controls', content.id);
    }
    setCollapsed(suite, isCollapsed(suite));
    button.addEventListener('click', function() {
      setCollapsed(suite, !isCollapsed(suite), true);
      syncToggleAll();
    });
  });

  if (toggleAllBtn) {
    toggleAllBtn.addEventListener('click', function() {
      var visible = visibleSuites();
      var collapse = visible.some(function(suite) { return !isCollapsed(suite); });
      visible.forEach(function(suite) { setCollapsed(suite, collapse, true); });
      syncToggleAll();
    });
  }

  function suiteName(suite) {
    var name = suite.querySelector('.suite-name');
    return name ? name.textContent.trim() : (suite.getAttribute('data-suite-name') || '');
  }

  function persistViewState() {
    if (restoringState) { return; }
    var url = new URL(window.location.href);
    ['q', 'status', 'sort', 'test-sort'].forEach(function(key) { url.searchParams.delete(key); });
    var query = searchInput ? searchInput.value.trim() : '';
    if (query) { url.searchParams.set('q', query); }
    var selected = chips.filter(function(chip) { return !chip.hidden && chip.getAttribute('aria-pressed') === 'true'; })
      .map(function(chip) { return chip.getAttribute('data-status') || chip.getAttribute('data-filter'); });
    if (selected.length) { url.searchParams.set('status', selected.join(',')); }
    if (suiteSortState.key !== 'name' || suiteSortState.direction !== 'asc') {
      url.searchParams.set('sort', suiteSortState.key + '-' + suiteSortState.direction);
    }
    durationSorters.forEach(function(sorter) {
      if (sorter.state) { url.searchParams.append('test-sort', sorter.name + ':' + (sorter.state === 1 ? 'desc' : 'asc')); }
    });
    if (url.href !== window.location.href) { history.replaceState(history.state, '', url.href); }
  }

  function restoreViewState() {
    restoringState = true;
    var params = new URL(window.location.href).searchParams;
    if (searchInput) { searchInput.value = params.get('q') || ''; }
    var selected = (params.get('status') || '').split(',');
    chips.forEach(function(chip) {
      var key = chip.getAttribute('data-status') || chip.getAttribute('data-filter');
      chip.setAttribute('aria-pressed', String(!chip.hidden && selected.indexOf(key) >= 0));
    });
    var sort = /^(name|failed|total|percent|duration|avg)-(asc|desc)$/.exec(params.get('sort') || '');
    if (suiteSortState.apply) { suiteSortState.apply(sort ? sort[1] : 'name', sort ? sort[2] : 'asc'); }
    var rowSorts = Object.create(null);
    params.getAll('test-sort').forEach(function(value) {
      var separator = value.lastIndexOf(':');
      var direction = value.slice(separator + 1);
      if (separator >= 0 && /^(asc|desc)$/.test(direction)) { rowSorts[value.slice(0, separator)] = direction; }
    });
    durationSorters.forEach(function(sorter) { sorter.apply(rowSorts[sorter.name] === 'desc' ? 1 : (rowSorts[sorter.name] === 'asc' ? 2 : 0)); });
    applyFilter();
    restoringState = false;
  }

  // The chips are "show only" filters: none selected shows every test, otherwise a row shows
  // when it matches any selected chip. The search narrows that further by test or suite name.
  // A suite with no visible rows hides itself.
  function applyFilter() {
    var query = (searchInput ? searchInput.value : '').trim().toLowerCase();
    var statuses = selectedStatuses();
    var flakySelected = !!flakyChip && !flakyChip.hidden && flakyChip.getAttribute('aria-pressed') === 'true';
    var anySelected = flakySelected || Object.keys(statuses).length > 0;
    var anyVisible = false;

    if (query !== previousQuery) { searchCollapseOverrides = {}; previousQuery = query; }

    if (query !== '' && collapsedBeforeSearch === null) {
      collapsedBeforeSearch = suites.map(isCollapsed);
    }

    suites.forEach(function(suite, index) {
      var suiteMatches = query !== '' && (suite.getAttribute('data-suite-name') || '').indexOf(query) !== -1;
      var rows = suite.querySelectorAll('.suite-tests-table tbody tr');
      var visibleInSuite = 0;
      for (var r = 0; r < rows.length; r++) {
        var row = rows[r];
        var matchesChips = !anySelected
          || !!statuses[row.getAttribute('data-status')]
          || (flakySelected && row.getAttribute('data-flaky') === 'true');
        var matchesQuery = query === '' || suiteMatches || rowName(row).indexOf(query) !== -1;
        var visible = matchesChips && matchesQuery;
        row.style.display = visible ? '' : 'none';
        if (visible) { visibleInSuite++; }
      }
      suite.style.display = visibleInSuite === 0 ? 'none' : '';
      if (visibleInSuite > 0) { anyVisible = true; }
      if (query !== '' && visibleInSuite > 0) { setCollapsed(suite, searchCollapseOverrides[index] === true); }
    });

    if (query === '' && collapsedBeforeSearch !== null) {
      suites.forEach(function(suite, index) { setCollapsed(suite, collapsedBeforeSearch[index]); });
      collapsedBeforeSearch = null;
      searchCollapseOverrides = {};
    }

    if (noMatch) { noMatch.style.display = anyVisible ? 'none' : ''; }
    syncToggleAll();
    persistViewState();
  }

  if (searchInput) {
    searchInput.addEventListener('input', function() {
      clearTimeout(debounce);
      debounce = setTimeout(applyFilter, 120);
    });
  }

  chips.forEach(function(chip) {
    chip.addEventListener('click', function() {
      var pressed = chip.getAttribute('aria-pressed') === 'true';
      chip.setAttribute('aria-pressed', pressed ? 'false' : 'true');
      applyFilter();
    });
  });

  var reviewFailures = document.getElementById('review-failures');
  if (reviewFailures) {
    reviewFailures.hidden = !document.querySelector('tr[data-status="failed"]');
    reviewFailures.addEventListener('click', function() {
      if (searchInput) { searchInput.value = ''; }
      collapsedBeforeSearch = null;
      chips.forEach(function(chip) { chip.setAttribute('aria-pressed', String(chip.dataset.status === 'failed')); });
      suites.forEach(function(suite) { setCollapsed(suite, false); });
      applyFilter();
    });
  }

  // The Duration header button sorts that suite's rows: desc -> asc -> original.
  suites.forEach(function(suite) {
    var table = suite.querySelector('.suite-tests-table');
    if (!table) { return; }
    var header = table.querySelector('thead th.sortable-duration');
    var button = header && header.querySelector('button');
    var tbody = table.querySelector('tbody');
    if (!button || !tbody) { return; }
    var original = Array.prototype.slice.call(tbody.querySelectorAll('tr'));
    var mobileButton = document.createElement('button');
    mobileButton.type = 'button';
    mobileButton.className = 'mobile-sort-duration';
    table.parentNode.insertBefore(mobileButton, table);
    var sorter = { name: suiteName(suite), state: 0, apply: applyDurationSort };
    durationSorters.push(sorter);

    function applyDurationSort(state) {
      sorter.state = state;
      header.setAttribute('data-sort', state === 1 ? 'desc' : (state === 2 ? 'asc' : ''));
      header.setAttribute('aria-sort', state === 1 ? 'descending' : (state === 2 ? 'ascending' : 'none'));
      mobileButton.textContent = 'Duration' + (state === 1 ? ' \u2193' : (state === 2 ? ' \u2191' : ''));
      mobileButton.setAttribute('aria-label', 'Sort tests by duration: ' + (state === 1 ? 'longest first' : (state === 2 ? 'shortest first' : 'original order')));
      var rows = original;
      if (state !== 0) {
        rows = original.slice().sort(function(a, b) {
          var da = parseFloat(a.getAttribute('data-duration')) || 0;
          var db = parseFloat(b.getAttribute('data-duration')) || 0;
          return state === 1 ? db - da : da - db;
        });
      }
      rows.forEach(function(row) { tbody.appendChild(row); });
    }
    function cycleDurationSort() {
      applyDurationSort((sorter.state + 1) % 3);
      persistViewState();
    }
    button.addEventListener('click', cycleDurationSort);
    mobileButton.addEventListener('click', cycleDurationSort);
    applyDurationSort(0);
  });

  // Sort the top-level list of suites by name/failed/total/percent/duration/avg.
  (function suiteSort() {
    if (suites.length === 0) { return; }
    var container = suites[0].parentNode;
    var buttons = Array.prototype.slice.call(document.getElementsByClassName('suite-sort-btn'));
    if (buttons.length === 0) { return; }

    var extractors = {
      name: function(suite) { return (suite.getAttribute('data-suite-name') || '').toLowerCase(); },
      failed: function(suite) { return parseFloat(suite.getAttribute('data-failed-tests')) || 0; },
      total: function(suite) { return parseFloat(suite.getAttribute('data-total-tests')) || 0; },
      percent: function(suite) { return parseFloat(suite.getAttribute('data-percent-passed')) || 0; },
      duration: function(suite) { return parseFloat(suite.getAttribute('data-suite-duration')) || 0; },
      avg: function(suite) { return parseFloat(suite.getAttribute('data-avg-duration')) || 0; }
    };

    function applySort() {
      var extractor = extractors[suiteSortState.key];
      var direction = suiteSortState.direction;
      var sorted = suites.slice().sort(function(a, b) {
        var va = extractor(a);
        var vb = extractor(b);
        var cmp;
        if (typeof va === 'string') {
          cmp = va < vb ? -1 : (va > vb ? 1 : 0);
        } else {
          cmp = va - vb;
        }
        if (cmp === 0) {
          var na = extractors.name(a);
          var nb = extractors.name(b);
          cmp = na < nb ? -1 : (na > nb ? 1 : 0);
        } else if (direction === 'desc') {
          cmp = -cmp;
        }
        return cmp;
      });
      sorted.forEach(function(suite) { container.appendChild(suite); });
    }

    suiteSortState.apply = function(key, direction) {
      suiteSortState.key = key;
      suiteSortState.direction = direction;
      buttons.forEach(function(button) {
        var isActive = button.getAttribute('data-sort-key') === key;
        button.setAttribute('aria-pressed', String(isActive));
        button.setAttribute('data-sort', isActive ? direction : '');
      });
      applySort();
    };

    buttons.forEach(function(button) {
      button.addEventListener('click', function() {
        var key = button.getAttribute('data-sort-key');
        var direction = key === suiteSortState.key ? (suiteSortState.direction === 'asc' ? 'desc' : 'asc') : (key === 'name' ? 'asc' : 'desc');
        suiteSortState.apply(key, direction);
        persistViewState();
      });
    });
  })();

  // Top 10 slowest tests across all suites, in a collapsed section.
  (function buildSlowest() {
    var container = document.getElementById('slowest-tests');
    if (!container) { return; }
    var rows = Array.prototype.slice.call(
      document.querySelectorAll('.suite-tests-table tbody tr'));
    var items = rows.map(function(row) {
      var link = row.querySelector('td a');
      return {
        name: link ? link.textContent : '',
        href: link ? link.getAttribute('href') : null,
        duration: parseFloat(row.getAttribute('data-duration')) || 0
      };
    }).filter(function(it) { return it.href; });
    if (items.length === 0) { return; }
    items.sort(function(a, b) { return b.duration - a.duration; });

    var details = document.createElement('details');
    var summary = document.createElement('summary');
    summary.textContent = 'Slowest tests';
    details.appendChild(summary);
    var ol = document.createElement('ol');
    items.slice(0, 10).forEach(function(it) {
      var li = document.createElement('li');
      var a = document.createElement('a');
      a.href = it.href;
      a.textContent = it.name;
      li.appendChild(a);
      var span = document.createElement('span');
      span.className = 'slowest-duration';
      span.textContent = ' - ' + formatDuration(it.duration);
      li.appendChild(span);
      ol.appendChild(li);
    });
    details.appendChild(ol);
    container.appendChild(details);
  })();

  // Each chip shows how many tests it would match.
  chips.forEach(function(chip) {
    var selector = chip.hasAttribute('data-status')
      ? 'tr[data-status="' + chip.getAttribute('data-status') + '"]'
      : 'tr[data-flaky="true"]';
    var count = document.querySelectorAll('.suite-tests-table tbody ' + selector).length;
    chip.setAttribute('data-label', chip.textContent.trim());
    var badge = document.createElement('span');
    badge.className = 'status-chip-count';
    badge.textContent = String(count);
    chip.appendChild(badge);
    chip.classList.toggle('is-empty', count === 0);
  });

  window.XCTestReportIndex = {
    flushFilters: function() { clearTimeout(debounce); applyFilter(); },
    revealTest: function(link) {
      var suite = link.closest('.suite');
      var row = link.closest('tr');
      if (!suite || !row || suite.style.display === 'none' || row.style.display === 'none') { return false; }
      setCollapsed(suite, false, true);
      syncToggleAll();
      return true;
    }
  };
  window.addEventListener('popstate', function() { clearTimeout(debounce); restoreViewState(); });
  restoreViewState();

  // The whole row opens its test, not just the name.
  Array.prototype.forEach.call(document.querySelectorAll('.suite-tests-table tbody'), function(tbody) {
    tbody.addEventListener('click', function(event) {
      if (event.defaultPrevented || event.button !== 0) { return; }
      if (event.target.closest('a, button, input, summary')) { return; }
      if (String(window.getSelection ? window.getSelection() : '') !== '') { return; }
      var row = event.target.closest('tr');
      var link = row && row.querySelector('td a[href]');
      if (!link) { return; }
      if (event.metaKey || event.ctrlKey) {
        window.open(link.href, '_blank');
      } else {
        link.click();
      }
    });
  });

  // Keyboard: / searches, J/K move through the tests on screen.
  function visibleTestLinks() {
    return Array.prototype.filter.call(document.querySelectorAll('.suite-tests-table tbody tr td a[href]'), function(link) {
      return link.offsetParent !== null;
    });
  }

  document.addEventListener('keydown', function(event) {
    if (event.defaultPrevented || event.metaKey || event.ctrlKey || event.altKey) { return; }
    var target = event.target;
    var typing = !!target && (target.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName));
    if (typing) {
      if (event.key === 'Escape' && target === searchInput && searchInput.value !== '') {
        searchInput.value = '';
        applyFilter();
      }
      return;
    }
    if (event.key === '/' && searchInput) {
      event.preventDefault();
      searchInput.focus();
      searchInput.select();
    } else if (event.key === 'j' || event.key === 'k') {
      var links = visibleTestLinks();
      if (links.length === 0) { return; }
      event.preventDefault();
      var index = links.indexOf(document.activeElement);
      if (index < 0) {
        var last = document.querySelector('tr.is-last-viewed td a[href]');
        index = last ? links.indexOf(last) : -1;
        if (index < 0) { index = event.key === 'j' ? -1 : links.length; }
      }
      index = Math.max(0, Math.min(links.length - 1, index + (event.key === 'j' ? 1 : -1)));
      links[index].focus();
      links[index].closest('tr').scrollIntoView({ block: 'nearest' });
    }
  });

  // Mirrors formatCompactDuration in ReportIndexHelpers.swift.
  function formatDuration(seconds) {
    if (!(seconds > 0) || !isFinite(seconds)) { return '0s'; }
    var ms = Math.round(seconds * 1000);
    if (ms < 1) { return '<1ms'; }
    if (ms < 1000) { return ms + 'ms'; }
    var tenths = Math.round(seconds * 10);
    if (tenths < 600) { return (tenths % 10 === 0 ? String(tenths / 10) : (tenths / 10).toFixed(1)) + 's'; }
    var total = Math.round(seconds);
    var h = Math.floor(total / 3600);
    var m = Math.floor((total % 3600) / 60);
    var s = total % 60;
    var parts = [];
    if (h > 0) { parts.push(h + 'h'); }
    if (m > 0 || (h > 0 && s > 0)) { parts.push(m + 'm'); }
    if (s > 0) { parts.push(s + 's'); }
    return parts.join(' ');
  }
})();
