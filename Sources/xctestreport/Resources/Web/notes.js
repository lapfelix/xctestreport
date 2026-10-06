// Review notes: a reviewer jots notes on tests and suites while going through a report, then
// copies them all for an agent. Notes stay in this browser's localStorage, one key per report.
(function() {
  var body = document.body;
  var reportId = body && body.getAttribute('data-report-id');
  if (!reportId) return;

  var STORAGE_KEY = 'xctestreport.notes.' + reportId;
  var INCLUDE_TIME_KEY = 'xctestreport.notes.includeTime';
  var reportRoot = new URL(body.getAttribute('data-report-root') || './', window.location.href);
  var isIndex = body.classList.contains('report-index-page');

  var ICON = '<svg viewBox="0 0 20 20" aria-hidden="true" focusable="false">' +
    '<path d="M5 2.75h7.25L16 6.5v10.75H5z" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/>' +
    '<path d="M12 2.75V6.75h4" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/>' +
    '<path d="M7.75 10.5h5.5M7.75 13.5h3.5" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>';

  // MARK: Storage

  function emptyStore() { return { version: 1, suites: {}, tests: {} }; }

  function load() {
    try {
      var parsed = JSON.parse(window.localStorage.getItem(STORAGE_KEY) || 'null');
      if (parsed && parsed.suites && parsed.tests) return parsed;
    } catch (error) { /* unavailable or corrupt: start empty */ }
    return emptyStore();
  }

  // Throws when storage is unavailable or full; callers keep the typed text and show the error.
  function save(store) {
    var isEmpty = !Object.keys(store.suites).length && !Object.keys(store.tests).length;
    if (isEmpty) {
      window.localStorage.removeItem(STORAGE_KEY);
    } else {
      window.localStorage.setItem(STORAGE_KEY, JSON.stringify(store));
    }
  }

  function notesFor(store, scope, key) {
    return (store[scope === 'suite' ? 'suites' : 'tests'][key] || []).slice();
  }

  function setNotes(store, scope, key, notes) {
    var bucket = store[scope === 'suite' ? 'suites' : 'tests'];
    if (notes.length) { bucket[key] = notes; } else { delete bucket[key]; }
  }

  function readPreference(key, fallback) {
    try {
      var value = window.localStorage.getItem(key);
      return value == null ? fallback : value === 'true';
    } catch (error) { return fallback; }
  }

  function writePreference(key, value) {
    try { window.localStorage.setItem(key, String(value)); } catch (error) { /* not worth surfacing */ }
  }

  // Timed notes in playback order (run, then time), then untimed notes in the order added.
  function sortedNotes(notes) {
    return notes.slice().sort(function(a, b) {
      if (a.time && b.time) {
        return (a.time.run - b.time.run) || (a.time.seconds - b.time.seconds) || (a.created - b.created);
      }
      if (a.time) return -1;
      if (b.time) return 1;
      return a.created - b.created;
    });
  }

  function newId() {
    return Date.now().toString(36) + Math.random().toString(36).slice(2, 7);
  }

  function noteLabel(count) { return count + (count === 1 ? ' note' : ' notes'); }

  // MARK: Note button

  function makeNoteButton(label) {
    var button = document.createElement('button');
    button.type = 'button';
    button.className = 'note-btn';
    button.innerHTML = ICON + '<span class="note-btn-count" hidden></span>';
    button.dataset.label = label;
    return button;
  }

  function updateNoteButton(button, count) {
    var badge = button.querySelector('.note-btn-count');
    badge.hidden = count === 0;
    badge.textContent = String(count);
    button.classList.toggle('has-notes', count > 0);
    var title = count ? button.dataset.label + ' (' + noteLabel(count) + ')' : button.dataset.label;
    button.title = title;
    button.setAttribute('aria-label', title);
  }

  // MARK: Panel

  var panel = null;
  var panelState = null; // { scope, key, title, withTime, button }
  var timeRefresh = 0;

  function timeline() { return window.XCTestReportTimeline || null; }

  function describeTime(time) {
    var parts = [];
    if (time.runLabel) parts.push(time.runLabel);
    parts.push(time.label);
    return parts.join(' · ');
  }

  function stepText(time) {
    if (!time.step) return '';
    return time.section && time.section !== time.step ? time.section + ' › ' + time.step : time.step;
  }

  function ensurePanel() {
    if (panel) return panel;
    panel = document.createElement('aside');
    panel.className = 'notes-panel';
    panel.hidden = true;
    panel.setAttribute('aria-labelledby', 'notes-panel-title');
    panel.innerHTML =
      '<div class="notes-panel-head"><h2 id="notes-panel-title" class="notes-panel-title"></h2>' +
      '<button type="button" class="notes-panel-close" aria-label="Close notes" title="Close (Esc)">×</button></div>' +
      '<textarea class="notes-input" rows="3" placeholder="Add a note…" aria-label="New note"></textarea>' +
      '<label class="notes-time-toggle"><input type="checkbox"> <span>Add current time</span></label>' +
      '<div class="notes-actions"><span class="notes-error" role="alert"></span>' +
      '<button type="button" class="notes-add">Add note</button></div>' +
      '<ol class="notes-list"></ol>' +
      '<p class="notes-footnote">Saved in this browser only.' +
      // Opened over the index, the index link closes the test instead of navigating.
      (isIndex ? '' : ' Export them with Copy all notes on <a href="' + new URL('index.html', reportRoot).href + '">Test results</a>.') +
      '</p>';
    document.body.appendChild(panel);

    panel.querySelector('.notes-panel-close').addEventListener('click', function() { closePanel(); });
    panel.querySelector('.notes-add').addEventListener('click', addNote);
    panel.querySelector('.notes-input').addEventListener('keydown', function(event) {
      if (event.key === 'Enter' && (event.metaKey || event.ctrlKey)) {
        event.preventDefault();
        addNote();
      }
    });
    panel.querySelector('.notes-time-toggle input').addEventListener('change', function(event) {
      writePreference(INCLUDE_TIME_KEY, event.target.checked);
    });
    panel.addEventListener('keydown', function(event) {
      if (event.key === 'Escape' && !event.target.classList.contains('notes-edit-input')) {
        // Handled here so the framed page's Escape doesn't also close the test.
        event.preventDefault();
        event.stopPropagation();
        closePanel();
      }
    });
    return panel;
  }

  function showError(message) {
    if (panel) panel.querySelector('.notes-error').textContent = message || '';
  }

  function refreshTimeLabel() {
    if (!panel || !panelState || !panelState.withTime) return;
    var span = panel.querySelector('.notes-time-toggle span');
    var api = timeline();
    var current = api ? api.current() : null;
    var text = 'Add current time';
    if (current) {
      text += ' (' + describeTime(current) + (current.step ? ' · ' + current.step : '') + ')';
    }
    if (span.textContent !== text) span.textContent = text;
  }

  function openPanel(state) {
    ensurePanel();
    panelState = state;
    panel.querySelector('.notes-panel-title').textContent = 'Notes · ' + state.title;
    var toggle = panel.querySelector('.notes-time-toggle');
    toggle.hidden = !state.withTime;
    toggle.querySelector('input').checked = readPreference(INCLUDE_TIME_KEY, true);
    showError('');
    panel.hidden = false;
    placePanel(state.button);
    document.documentElement.classList.add('notes-panel-open');
    if (state.button) state.button.setAttribute('aria-expanded', 'true');
    renderList();
    refreshTimeLabel();
    window.clearInterval(timeRefresh);
    if (state.withTime) timeRefresh = window.setInterval(refreshTimeLabel, 250);
    panel.querySelector('.notes-input').focus();
  }

  // On the index the panel opens under the suite heading that asked for it, leaving the toolbar
  // (and Copy all notes) uncovered. Test pages dock it at the top right, over the video.
  function placePanel(button) {
    panel.classList.toggle('notes-panel-anchored', isIndex && !!button);
    panel.style.top = '';
    panel.style.left = '';
    if (!isIndex || !button) return;
    var rect = button.getBoundingClientRect();
    var width = panel.offsetWidth;
    var left = Math.max(16, Math.min(rect.left, document.documentElement.clientWidth - width - 16));
    panel.style.top = (rect.bottom + window.scrollY + 6) + 'px';
    panel.style.left = (left + window.scrollX) + 'px';
  }

  function closePanel(restoreFocus) {
    if (!panel || panel.hidden) return;
    panel.hidden = true;
    document.documentElement.classList.remove('notes-panel-open');
    window.clearInterval(timeRefresh);
    var button = panelState && panelState.button;
    panelState = null;
    if (button) {
      button.setAttribute('aria-expanded', 'false');
      if (restoreFocus !== false) button.focus();
    }
  }

  function togglePanel(state) {
    var sameTarget = panel && !panel.hidden && panelState &&
      panelState.scope === state.scope && panelState.key === state.key;
    if (sameTarget) { closePanel(); } else { openPanel(state); }
  }

  function mutate(change) {
    var store = load();
    var notes = notesFor(store, panelState.scope, panelState.key);
    change(notes);
    setNotes(store, panelState.scope, panelState.key, notes);
    save(store);
  }

  function addNote() {
    var input = panel.querySelector('.notes-input');
    var text = input.value.trim();
    if (!text) { input.focus(); return; }
    var note = { id: newId(), text: text, created: Date.now(), updated: Date.now() };
    var api = timeline();
    if (panelState.withTime && api && panel.querySelector('.notes-time-toggle input').checked) {
      var current = api.current();
      note.time = {
        seconds: Math.round(current.seconds * 1000) / 1000,
        label: current.label,
        absoluteTime: current.absoluteTime,
        run: current.run,
        runLabel: current.runLabel,
        eventId: current.eventId,
        step: current.step,
        section: current.section
      };
    }
    try {
      mutate(function(notes) { notes.push(note); });
    } catch (error) {
      showError('Couldn’t save the note: browser storage is unavailable or full.');
      return;
    }
    showError('');
    input.value = '';
    input.focus();
    refreshAll();
  }

  function deleteNote(id) {
    try {
      mutate(function(notes) {
        var index = notes.findIndex(function(note) { return note.id === id; });
        if (index >= 0) notes.splice(index, 1);
      });
    } catch (error) {
      showError('Couldn’t delete the note: browser storage is unavailable.');
      return;
    }
    refreshAll();
    panel.querySelector('.notes-input').focus();
  }

  function editNote(item, note) {
    var textElement = item.querySelector('.notes-item-text');
    var editor = document.createElement('textarea');
    editor.className = 'notes-edit-input';
    editor.value = note.text;
    editor.rows = Math.min(8, Math.max(2, note.text.split('\n').length));
    editor.setAttribute('aria-label', 'Edit note');
    textElement.replaceWith(editor);
    editor.focus();
    editor.setSelectionRange(editor.value.length, editor.value.length);

    var finished = false;
    function finish(commit) {
      if (finished) return;
      finished = true;
      var text = editor.value.trim();
      if (commit && text && text !== note.text) {
        try {
          mutate(function(notes) {
            var match = notes.find(function(candidate) { return candidate.id === note.id; });
            if (match) { match.text = text; match.updated = Date.now(); }
          });
        } catch (error) {
          finished = false;
          showError('Couldn’t save the edit: browser storage is unavailable or full.');
          return;
        }
      }
      showError('');
      refreshAll();
    }
    editor.addEventListener('keydown', function(event) {
      if (event.key === 'Enter' && (event.metaKey || event.ctrlKey)) {
        event.preventDefault();
        finish(true);
      } else if (event.key === 'Escape') {
        event.preventDefault();
        event.stopPropagation();
        finish(false);
      }
    });
    editor.addEventListener('blur', function() { finish(true); });
  }

  function renderList() {
    if (!panel || !panelState) return;
    var list = panel.querySelector('.notes-list');
    list.textContent = '';
    sortedNotes(notesFor(load(), panelState.scope, panelState.key)).forEach(function(note) {
      var item = document.createElement('li');
      item.className = 'notes-item';
      if (note.time) {
        var jump = document.createElement('button');
        jump.type = 'button';
        jump.className = 'notes-item-time';
        jump.textContent = describeTime(note.time);
        var step = stepText(note.time);
        jump.title = step ? 'Go to ' + step : 'Go to this time';
        jump.disabled = !timeline();
        jump.addEventListener('click', function() {
          var api = timeline();
          if (api) api.seek(note.time);
        });
        item.appendChild(jump);
        if (note.time.step) {
          var stepElement = document.createElement('span');
          stepElement.className = 'notes-item-step';
          stepElement.textContent = note.time.step;
          item.appendChild(stepElement);
        }
      }
      var text = document.createElement('p');
      text.className = 'notes-item-text';
      text.textContent = note.text;
      item.appendChild(text);

      var tools = document.createElement('span');
      tools.className = 'notes-item-tools';
      var edit = document.createElement('button');
      edit.type = 'button';
      edit.textContent = 'Edit';
      edit.addEventListener('click', function() { editNote(item, note); });
      var remove = document.createElement('button');
      remove.type = 'button';
      remove.textContent = 'Delete';
      remove.addEventListener('click', function() { deleteNote(note.id); });
      tools.appendChild(edit);
      tools.appendChild(remove);
      item.appendChild(tools);
      list.appendChild(item);
    });
  }

  // MARK: Test page

  var testButton = null;
  var testKey = body.getAttribute('data-test-id');

  function setUpTestPage() {
    if (!testKey) return;
    testButton = makeNoteButton('Notes on this test');
    testButton.classList.add('note-btn-header');
    testButton.setAttribute('aria-expanded', 'false');
    testButton.addEventListener('click', function() {
      togglePanel({
        scope: 'test',
        key: testKey,
        title: body.getAttribute('data-test-name') || testKey,
        withTime: !!document.querySelector('[data-timeline-root]'),
        button: testButton
      });
    });
    var row = document.querySelector('.test-title-row');
    if (row) {
      row.insertBefore(testButton, row.querySelector('.test-subtitle'));
    }
  }

  // MARK: Index page

  var exportControl = null;

  function suiteKey(suite) { return suite.getAttribute('data-suite'); }

  function setUpIndexPage() {
    Array.prototype.forEach.call(document.querySelectorAll('.suite[data-suite]'), function(suite) {
      var heading = suite.querySelector('h2');
      if (!heading) return;
      var key = suiteKey(suite);
      var button = makeNoteButton('Notes on suite ' + key);
      button.classList.add('note-btn-suite');
      button.setAttribute('aria-expanded', 'false');
      // The heading toggles its suite on click and Enter/Space; the button must not.
      button.addEventListener('keydown', function(event) { event.stopPropagation(); });
      button.addEventListener('click', function(event) {
        event.stopPropagation();
        togglePanel({ scope: 'suite', key: key, title: key, withTime: false, button: button });
      });
      // Inside the name so it sits beside it; the heading spreads its children apart.
      (heading.querySelector('.suite-name') || heading).appendChild(button);
    });

    var actions = document.querySelector('.summary-actions');
    if (!actions) return;
    exportControl = document.createElement('span');
    exportControl.className = 'notes-export';
    exportControl.hidden = true;
    exportControl.innerHTML =
      '<button type="button" class="notes-copy">Copy all notes</button>' +
      '<button type="button" class="notes-export-more" aria-haspopup="menu" aria-expanded="false" aria-label="More ways to export notes">' +
      '<svg viewBox="0 0 12 12" aria-hidden="true" focusable="false"><path d="M3 4.5l3 3 3-3" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg></button>' +
      '<span class="notes-export-menu" role="menu" hidden>' +
      '<button type="button" role="menuitem" data-export="copy-json">Copy as JSON</button>' +
      '<button type="button" role="menuitem" data-export="download-md">Download Markdown</button>' +
      '<button type="button" role="menuitem" data-export="download-json">Download JSON</button>' +
      '</span>';
    actions.appendChild(exportControl);

    var copyButton = exportControl.querySelector('.notes-copy');
    var moreButton = exportControl.querySelector('.notes-export-more');
    var menu = exportControl.querySelector('.notes-export-menu');

    function setMenuOpen(open) {
      menu.hidden = !open;
      moreButton.setAttribute('aria-expanded', String(open));
    }

    copyButton.addEventListener('click', function() {
      copyText(buildMarkdown(), copyButton, 'Copy all notes');
    });
    moreButton.addEventListener('click', function(event) {
      event.stopPropagation();
      setMenuOpen(menu.hidden);
      if (!menu.hidden) menu.querySelector('button').focus();
    });
    menu.addEventListener('click', function(event) {
      var item = event.target.closest('[data-export]');
      if (!item) return;
      setMenuOpen(false);
      var kind = item.getAttribute('data-export');
      if (kind === 'copy-json') {
        copyText(JSON.stringify(buildJSON(), null, 2), copyButton, 'Copy all notes');
      } else if (kind === 'download-md') {
        download(buildMarkdown(), 'notes-' + reportId + '.md', 'text/markdown');
      } else {
        download(JSON.stringify(buildJSON(), null, 2), 'notes-' + reportId + '.json', 'application/json');
      }
    });
    menu.addEventListener('keydown', function(event) {
      if (event.key === 'Escape') {
        setMenuOpen(false);
        moreButton.focus();
      }
    });
    document.addEventListener('click', function(event) {
      if (!exportControl.contains(event.target)) setMenuOpen(false);
    });
    // On test pages the panel stays open so the timeline can be scrubbed while writing; on the
    // index there's nothing to do beside it, so it closes like a popover.
    document.addEventListener('pointerdown', function(event) {
      if (!panel || panel.hidden || panel.contains(event.target)) return;
      if (panelState && panelState.button && panelState.button.contains(event.target)) return;
      closePanel(false);
    });
  }

  function testRows() {
    return Array.prototype.slice.call(document.querySelectorAll('tr[data-test-id]'));
  }

  function refreshIndex(store) {
    Array.prototype.forEach.call(document.querySelectorAll('.note-btn-suite'), function(button) {
      var suite = button.closest('.suite');
      updateNoteButton(button, (store.suites[suiteKey(suite)] || []).length);
    });
    testRows().forEach(function(row) {
      var count = (store.tests[row.getAttribute('data-test-id')] || []).length;
      var cell = row.querySelector('td');
      var glyph = cell && cell.querySelector('.note-glyph');
      if (!count) {
        if (glyph) glyph.remove();
        return;
      }
      if (!glyph && cell) {
        glyph = document.createElement('span');
        glyph.className = 'note-glyph';
        glyph.innerHTML = ICON;
        cell.appendChild(glyph);
      }
      if (glyph) {
        glyph.title = noteLabel(count);
        glyph.setAttribute('aria-label', noteLabel(count));
        glyph.setAttribute('role', 'img');
      }
    });
    if (exportControl) {
      exportControl.hidden = !Object.keys(store.suites).length && !Object.keys(store.tests).length;
    }
  }

  // MARK: Export

  function absolute(path) {
    try { return new URL(path, reportRoot).href; } catch (error) { return path; }
  }

  function reportTitle() {
    var span = document.querySelector('.report-heading h1 span');
    return (span && span.textContent.trim()) || document.title;
  }

  function testInfo(id, row) {
    var link = row && row.querySelector('td a');
    var info = { id: id, name: link ? link.textContent.trim() : id, suite: id.split('/')[0] };
    if (row) {
      var status = row.getAttribute('data-status') || '';
      info.status = status.charAt(0).toUpperCase() + status.slice(1);
      var suite = row.closest('.suite');
      if (suite && suiteKey(suite)) info.suite = suiteKey(suite);
    }
    if (link) {
      info.pageURL = new URL(link.getAttribute('href'), window.location.href).href;
      info.bundleURL = info.pageURL.replace(/\.html$/, '.zip');
    }
    if (row && row.getAttribute('data-md')) info.detailsURL = absolute(row.getAttribute('data-md'));
    return info;
  }

  // Suites and tests in the index's current order; anything no longer on the page goes last.
  function collect() {
    var store = load();
    var suites = [];
    var seenSuites = {};
    var tests = [];
    var seenTests = {};

    function addSuite(name) {
      if (seenSuites[name]) return seenSuites[name];
      var entry = { name: name, notes: sortedNotes(store.suites[name] || []), tests: [] };
      seenSuites[name] = entry;
      suites.push(entry);
      return entry;
    }

    Array.prototype.forEach.call(document.querySelectorAll('.suite[data-suite]'), function(suite) {
      var name = suiteKey(suite);
      var rows = Array.prototype.slice.call(suite.querySelectorAll('tr[data-test-id]'));
      var hasNotes = (store.suites[name] || []).length ||
        rows.some(function(row) { return (store.tests[row.getAttribute('data-test-id')] || []).length; });
      if (!hasNotes) return;
      var entry = addSuite(name);
      rows.forEach(function(row) {
        var id = row.getAttribute('data-test-id');
        var notes = store.tests[id] || [];
        if (!notes.length || seenTests[id]) return;
        seenTests[id] = true;
        var test = testInfo(id, row);
        test.notes = sortedNotes(notes);
        entry.tests.push(test);
        tests.push(test);
      });
    });
    Object.keys(store.suites).forEach(addSuite);
    Object.keys(store.tests).forEach(function(id) {
      if (seenTests[id] || !store.tests[id].length) return;
      var test = testInfo(id, null);
      test.notes = sortedNotes(store.tests[id]);
      addSuite(test.suite).tests.push(test);
      tests.push(test);
    });
    return suites;
  }

  function indent(text) {
    return text.split('\n').map(function(line, index) { return index ? '  ' + line : line; }).join('\n');
  }

  function markdownNote(note) {
    if (!note.time) return '- ' + indent(note.text);
    var where = describeTime(note.time);
    var step = stepText(note.time);
    return '- **' + where + '**' + (step ? ' (' + step + ')' : '') + ': ' + indent(note.text);
  }

  function buildMarkdown() {
    var suites = collect();
    var lines = [
      '# Review notes: ' + reportTitle(),
      '',
      'Report: ' + absolute('index.html'),
      'Agent summary: ' + absolute('report.md') + ' (all test details: ' + absolute('agent-tests.md') + ')',
      '',
      'Times are offsets into the test’s screen recording (mm:ss), followed by the step running at that moment.'
    ];
    suites.forEach(function(suite) {
      if (suite.notes.length) {
        lines.push('', '## Suite ' + suite.name, '');
        suite.notes.forEach(function(note) { lines.push(markdownNote(note)); });
      }
      suite.tests.forEach(function(test) {
        lines.push('', '## ' + test.id + (test.status ? ' (' + test.status + ')' : ''), '');
        if (test.pageURL) lines.push('Page: ' + test.pageURL);
        if (test.detailsURL) lines.push('Details: ' + test.detailsURL);
        if (test.bundleURL) lines.push('Bundle: ' + test.bundleURL + ' (test.md, video, screenshots)');
        if (test.pageURL || test.detailsURL) lines.push('');
        test.notes.forEach(function(note) { lines.push(markdownNote(note)); });
      });
    });
    return lines.join('\n') + '\n';
  }

  function jsonNote(note) {
    var result = { text: note.text, created: new Date(note.created).toISOString() };
    if (note.updated && note.updated !== note.created) result.updated = new Date(note.updated).toISOString();
    if (note.time) {
      result.time = {
        seconds: note.time.seconds,
        label: note.time.label,
        run: note.time.run,
        step: note.time.step || null,
        section: note.time.section || null
      };
      if (note.time.runLabel) result.time.runLabel = note.time.runLabel;
    }
    return result;
  }

  function buildJSON() {
    return {
      version: 1,
      report: {
        id: reportId,
        title: reportTitle(),
        url: absolute('index.html'),
        summaryURL: absolute('report.md'),
        detailsURL: absolute('agent-tests.md')
      },
      suites: collect().map(function(suite) {
        return {
          name: suite.name,
          notes: suite.notes.map(jsonNote),
          tests: suite.tests.map(function(test) {
            return {
              id: test.id,
              name: test.name,
              status: test.status || null,
              pageURL: test.pageURL || null,
              detailsURL: test.detailsURL || null,
              bundleURL: test.bundleURL || null,
              notes: test.notes.map(jsonNote)
            };
          })
        };
      })
    };
  }

  function flash(button, text, resetText) {
    button.textContent = text;
    window.clearTimeout(button._notesReset);
    button._notesReset = window.setTimeout(function() { button.textContent = resetText; }, 1500);
  }

  function copyText(text, button, resetText) {
    var done = function() { flash(button, 'Copied', resetText); };
    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(text).then(done, function() { showCopyFallback(text); });
    } else {
      showCopyFallback(text);
    }
  }

  // Clipboard access can be denied (or missing on plain HTTP); hand over the text to copy by hand.
  function showCopyFallback(text) {
    var dialog = document.createElement('dialog');
    dialog.className = 'notes-copy-dialog';
    dialog.innerHTML = '<p>Copy the notes below.</p><textarea readonly></textarea>' +
      '<form method="dialog"><button>Done</button></form>';
    dialog.querySelector('textarea').value = text;
    dialog.addEventListener('close', function() { dialog.remove(); });
    document.body.appendChild(dialog);
    dialog.showModal();
    var area = dialog.querySelector('textarea');
    area.focus();
    area.select();
  }

  function download(text, fileName, type) {
    var url = URL.createObjectURL(new Blob([text], { type: type + ';charset=utf-8' }));
    var link = document.createElement('a');
    link.href = url;
    link.download = fileName;
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.setTimeout(function() { URL.revokeObjectURL(url); }, 1000);
  }

  // MARK: Wiring

  function refreshAll() {
    var store = load();
    if (testButton) updateNoteButton(testButton, (store.tests[testKey] || []).length);
    if (isIndex) refreshIndex(store);
    renderList();
  }

  if (isIndex) { setUpIndexPage(); } else { setUpTestPage(); }
  refreshAll();

  // A test page framed over the index (or another tab) edited notes.
  window.addEventListener('storage', function(event) {
    if (event.key === STORAGE_KEY || event.key === null) refreshAll();
  });
})();
