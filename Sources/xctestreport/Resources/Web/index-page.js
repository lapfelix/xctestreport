(function() {
  var coll = document.getElementsByClassName('collapsible');
  var i;

  for (i = 0; i < coll.length; i++) {
    coll[i].tabIndex = 0;
    coll[i].setAttribute('role', 'button');
    coll[i].setAttribute('aria-expanded', 'true');
    coll[i].addEventListener('keydown', function(event) {
      if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); this.click(); }
    });
    coll[i].addEventListener('click', function() {
      this.classList.toggle('collapsed');
      this.setAttribute('aria-expanded', String(!this.classList.contains('collapsed')));
    });
  }

  var toggleAllBtn = document.getElementById('toggle-all');
  if (toggleAllBtn) {
    toggleAllBtn.textContent = 'Collapse All';
    toggleAllBtn.addEventListener('click', function() {
      var expanded = toggleAllBtn.textContent === 'Collapse All';
      for (var j = 0; j < coll.length; j++) {
        if (expanded) {
          coll[j].classList.add('collapsed');
        } else {
          coll[j].classList.remove('collapsed');
        }
      }
      Array.prototype.forEach.call(coll, function(head) { head.setAttribute('aria-expanded', String(!expanded)); });
      toggleAllBtn.textContent = expanded ? 'Expand All' : 'Collapse All';
    });
  }

  var suites = Array.prototype.slice.call(document.getElementsByClassName('suite'));
  var searchInput = document.getElementById('test-search');
  var chips = Array.prototype.slice.call(document.getElementsByClassName('status-chip'));
  var noMatch = document.getElementById('no-match');

  var flakyChip = document.querySelector('.flaky-chip');
  if (flakyChip) { flakyChip.hidden = !document.querySelector('tr[data-flaky="true"]'); }

  function enabledStatuses() {
    var set = {};
    chips.forEach(function(chip) {
      if (chip.hasAttribute('data-status') && chip.getAttribute('aria-pressed') !== 'false') {
        set[chip.getAttribute('data-status')] = true;
      }
    });
    return set;
  }

  function rowName(row) {
    var link = row.querySelector('td a');
    return (link ? link.textContent : row.textContent).toLowerCase();
  }

  function setCollapsed(suite, collapsed) {
    var head = suite.querySelector('.collapsible');
    if (!head) { return; }
    head.classList.toggle('collapsed', collapsed);
    head.setAttribute('aria-expanded', String(!collapsed));
  }

  function isCollapsed(suite) {
    var head = suite.querySelector('.collapsible');
    return !!head && head.classList.contains('collapsed');
  }

  // Collapse state from before the current search, restored once the search is cleared.
  var collapsedBeforeSearch = null;

  // Row visible when its status chip is on, it passes the flaky filter, and its test or
  // suite name matches the search. A suite with no visible rows hides itself.
  function applyFilter() {
    var query = (searchInput ? searchInput.value : '').trim().toLowerCase();
    var statuses = enabledStatuses();
    var flakyOnly = !!flakyChip && !flakyChip.hidden && flakyChip.getAttribute('aria-pressed') === 'true';
    var anyVisible = false;

    if (query !== '' && collapsedBeforeSearch === null) {
      collapsedBeforeSearch = suites.map(isCollapsed);
    }

    suites.forEach(function(suite) {
      var suiteMatches = query !== '' && (suite.getAttribute('data-suite-name') || '').indexOf(query) !== -1;
      var rows = suite.querySelectorAll('.suite-tests-table tbody tr');
      var visibleInSuite = 0;
      for (var r = 0; r < rows.length; r++) {
        var row = rows[r];
        var matchesStatus = !!statuses[row.getAttribute('data-status')];
        var matchesFlaky = !flakyOnly || row.getAttribute('data-flaky') === 'true';
        var matchesQuery = query === '' || suiteMatches || rowName(row).indexOf(query) !== -1;
        var visible = matchesStatus && matchesFlaky && matchesQuery;
        row.style.display = visible ? '' : 'none';
        if (visible) { visibleInSuite++; }
      }
      suite.style.display = visibleInSuite === 0 ? 'none' : '';
      if (visibleInSuite > 0) { anyVisible = true; }
      if (query !== '' && visibleInSuite > 0) { setCollapsed(suite, false); }
    });

    if (query === '' && collapsedBeforeSearch !== null) {
      suites.forEach(function(suite, index) { setCollapsed(suite, collapsedBeforeSearch[index]); });
      collapsedBeforeSearch = null;
    }

    if (noMatch) { noMatch.style.display = anyVisible ? 'none' : ''; }
  }

  if (searchInput) {
    var debounce;
    searchInput.addEventListener('input', function() {
      clearTimeout(debounce);
      debounce = setTimeout(applyFilter, 120);
    });
  }

  chips.forEach(function(chip) {
    chip.addEventListener('click', function() {
      var pressed = chip.getAttribute('aria-pressed') !== 'false';
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
      Array.prototype.forEach.call(coll, function(head) {
        head.classList.remove('collapsed'); head.setAttribute('aria-expanded', 'true');
      });
      if (toggleAllBtn) { toggleAllBtn.textContent = 'Collapse All'; }
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
    var state = 0;

    button.addEventListener('click', function() {
      state = (state + 1) % 3;
      header.setAttribute('data-sort', state === 1 ? 'desc' : (state === 2 ? 'asc' : ''));
      header.setAttribute('aria-sort', state === 1 ? 'descending' : (state === 2 ? 'ascending' : 'none'));
      var rows = original;
      if (state !== 0) {
        rows = original.slice().sort(function(a, b) {
          var da = parseFloat(a.getAttribute('data-duration')) || 0;
          var db = parseFloat(b.getAttribute('data-duration')) || 0;
          return state === 1 ? db - da : da - db;
        });
      }
      rows.forEach(function(row) { tbody.appendChild(row); });
    });
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

    var activeKey = 'name';
    var activeDirection = 'asc';

    function applySort() {
      var extractor = extractors[activeKey];
      var direction = activeDirection;
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

    buttons.forEach(function(button) {
      button.addEventListener('click', function() {
        var key = button.getAttribute('data-sort-key');
        if (key === activeKey) {
          activeDirection = activeDirection === 'asc' ? 'desc' : 'asc';
        } else {
          activeKey = key;
          activeDirection = key === 'name' ? 'asc' : 'desc';
        }
        buttons.forEach(function(btn) {
          var isActive = btn === button;
          btn.setAttribute('aria-pressed', isActive ? 'true' : 'false');
          btn.setAttribute('data-sort', isActive ? activeDirection : '');
        });
        applySort();
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
