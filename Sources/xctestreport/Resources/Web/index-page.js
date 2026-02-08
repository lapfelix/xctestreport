(function() {
  function isObject(value) {
    return value !== null && typeof value === 'object' && !Array.isArray(value);
  }

  function asString(value, fallback) {
    if (value == null) return fallback;
    return String(value);
  }

  function asNumber(value, fallback) {
    var number = Number(value);
    return Number.isFinite(number) ? number : fallback;
  }

  function parseInlinePayload() {
    var node = document.getElementById('index-page-payload');
    if (!node) return null;
    try {
      return JSON.parse(node.textContent || '{}');
    } catch (error) {
      console.error('Failed to parse inline index payload.', error);
      return null;
    }
  }

  function normalizeStatusIndicators(rawIndicators) {
    if (!Array.isArray(rawIndicators)) return [];
    return rawIndicators
      .map(function(rawIndicator) {
        if (!isObject(rawIndicator)) return null;
        var symbol = asString(rawIndicator.symbol, '').trim();
        if (!symbol) return null;
        return {
          symbol: symbol,
          title: asString(rawIndicator.title, '').trim()
        };
      })
      .filter(Boolean);
  }

  function normalizeTests(rawTests) {
    if (!Array.isArray(rawTests)) return [];
    return rawTests.map(function(rawTest) {
      var source = isObject(rawTest) ? rawTest : {};
      return {
        name: asString(source.name, 'Unnamed Test'),
        result: asString(source.result, 'Unknown'),
        duration: asString(source.duration, '0s'),
        pageName: asString(source.pageName, ''),
        statusIndicators: normalizeStatusIndicators(source.statusIndicators)
      };
    });
  }

  function normalizeSuites(rawSuites) {
    if (!Array.isArray(rawSuites)) return [];
    return rawSuites.map(function(rawSuite) {
      var source = isObject(rawSuite) ? rawSuite : {};
      return {
        name: asString(source.name, 'Unknown Suite'),
        totalTests: Math.max(0, asNumber(source.totalTests, 0)),
        passedTests: Math.max(0, asNumber(source.passedTests, 0)),
        failedTests: Math.max(0, asNumber(source.failedTests, 0)),
        skippedTests: Math.max(0, asNumber(source.skippedTests, 0)),
        passPercentage: Math.max(0, asNumber(source.passPercentage, 0)),
        durationText: asString(source.durationText, '0.0 sec'),
        tests: normalizeTests(source.tests)
      };
    });
  }

  function normalizePayload(rawPayload) {
    var source = isObject(rawPayload) ? rawPayload : {};
    var summarySource = isObject(source.summary) ? source.summary : {};
    var buildResultsSource = isObject(source.buildResults) ? source.buildResults : null;

    return {
      summary: {
        reportTitle: asString(summarySource.reportTitle, 'Untitled Report'),
        totalTests: Math.max(0, asNumber(summarySource.totalTests, 0)),
        passedTests: Math.max(0, asNumber(summarySource.passedTests, 0)),
        failedTests: Math.max(0, asNumber(summarySource.failedTests, 0)),
        skippedTests: Math.max(0, asNumber(summarySource.skippedTests, 0))
      },
      buildResults: buildResultsSource
        ? {
            errorCount: Math.max(0, asNumber(buildResultsSource.errorCount, 0)),
            warningCount: Math.max(0, asNumber(buildResultsSource.warningCount, 0))
          }
        : null,
      comparisonInfo: asString(source.comparisonInfo, '').trim() || null,
      suites: normalizeSuites(source.suites),
      loadError:
        isObject(rawPayload) ? '' : 'Invalid report payload. Try regenerating the report.'
    };
  }

  var root = document.getElementById('report-app');
  if (!root) return;

  var payload = parseInlinePayload();
  if (!payload) {
    root.innerHTML =
      '<div class="report-error">Failed to load report payload from this file.</div>';
    return;
  }

  if (!window.Vue || typeof window.Vue.createApp !== 'function') {
    root.innerHTML =
      '<div class="report-error">Vue runtime failed to load. Regenerate the report to restore assets.</div>';
    return;
  }

  var normalizedPayload = normalizePayload(payload);

  var app = window.Vue.createApp({
    data: function() {
      return {
        summary: normalizedPayload.summary,
        buildResults: normalizedPayload.buildResults,
        comparisonInfo: normalizedPayload.comparisonInfo,
        suites: normalizedPayload.suites,
        loadError: normalizedPayload.loadError,
        expandedSuiteMap: {},
        allSuitesExpanded: true
      };
    },
    created: function() {
      this.initializeExpandedSuites();
      var reportTitle = asString(this.summary.reportTitle, '').trim();
      if (reportTitle) {
        document.title = 'Test Report: ' + reportTitle;
      }
    },
    methods: {
      initializeExpandedSuites: function() {
        var expandedMap = {};
        for (var i = 0; i < this.suites.length; i++) {
          expandedMap[this.suites[i].name] = true;
        }
        this.expandedSuiteMap = expandedMap;
        this.syncExpandedState();
      },
      isSuiteExpanded: function(suiteName) {
        return this.expandedSuiteMap[suiteName] !== false;
      },
      toggleSuite: function(suiteName) {
        var nextMap = Object.assign({}, this.expandedSuiteMap);
        nextMap[suiteName] = !this.isSuiteExpanded(suiteName);
        this.expandedSuiteMap = nextMap;
        this.syncExpandedState();
      },
      toggleAllSuites: function() {
        if (!this.suites.length) return;
        var shouldExpand = !this.allSuitesExpanded;
        var nextMap = {};
        for (var i = 0; i < this.suites.length; i++) {
          nextMap[this.suites[i].name] = shouldExpand;
        }
        this.expandedSuiteMap = nextMap;
        this.allSuitesExpanded = shouldExpand;
      },
      syncExpandedState: function() {
        if (!this.suites.length) {
          this.allSuitesExpanded = false;
          return;
        }
        for (var i = 0; i < this.suites.length; i++) {
          if (!this.isSuiteExpanded(this.suites[i].name)) {
            this.allSuitesExpanded = false;
            return;
          }
        }
        this.allSuitesExpanded = true;
      },
      formatPercent: function(value) {
        return asNumber(value, 0).toFixed(1);
      },
      statusClass: function(result) {
        if (result === 'Passed') return 'passed';
        if (result === 'Failed') return 'failed';
        return '';
      }
    }
  });

  app.mount(root);
})();
