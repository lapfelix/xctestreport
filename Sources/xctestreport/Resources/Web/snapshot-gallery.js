/*
 * snapshot-gallery.js
 * Filtering, suite grouping and lazy viewer boot for snapshots.html.
 *
 * Every comparison is server-rendered as the usual <section class="snapshot-diffs"> contract, but
 * with the payload parked in data-snapshot-comparisons-pending. This page renames the attribute
 * and re-runs snapshot-diff.js only for the items that scroll into view, so a gallery holding
 * dozens of comparisons does not build every viewer up front.
 */
(function() {
    "use strict";

    var PENDING_ATTRIBUTE = "data-snapshot-comparisons-pending";
    var LIVE_ATTRIBUTE = "data-snapshot-comparisons";
    var VIEWER_SCRIPT = "web/snapshot-diff.js";

    var items = toArray(document.querySelectorAll(".sg-item"));
    if (items.length === 0) { return; }

    var suites = toArray(document.querySelectorAll(".sg-suite"));
    var chips = toArray(document.querySelectorAll("#sg-suite-chips .sg-chip[data-suite]"));
    var chipAll = document.getElementById("sg-chip-all");
    var searchInput = document.getElementById("sg-search");
    var failedOnlyButton = document.getElementById("sg-failed-only");
    var toggleAllButton = document.getElementById("sg-toggle-all");
    var readout = document.getElementById("sg-readout");
    var empty = document.getElementById("sg-empty");

    function toArray(list) { return Array.prototype.slice.call(list); }

    function pressed(node) {
        return !!node && node.getAttribute("aria-pressed") === "true";
    }

    function setPressed(node, value) {
        if (node) { node.setAttribute("aria-pressed", value ? "true" : "false"); }
    }

    // MARK: - Lazy viewer boot

    var runnerQueued = false;
    var runnerRunning = false;

    function runViewerScript() {
        runnerQueued = false;
        if (runnerRunning) { queueViewerScript(60); return; }
        runnerRunning = true;
        var script = document.createElement("script");
        script.src = VIEWER_SCRIPT;
        script.setAttribute("data-sg-runner", "");
        script.onload = script.onerror = function() {
            runnerRunning = false;
            if (script.parentNode) { script.parentNode.removeChild(script); }
        };
        document.body.appendChild(script);
    }

    // Re-executing the viewer script runs its own init(), which enhances every section that now
    // carries a payload and skips the ones already enhanced.
    function queueViewerScript(delay) {
        if (runnerQueued) { return; }
        runnerQueued = true;
        setTimeout(runViewerScript, delay || 0);
    }

    function enhance(item) {
        if (!item || item.getAttribute("data-sg-enhanced") === "true") { return; }
        var section = item.querySelector("section.snapshot-diffs");
        if (!section) { return; }
        var payload = section.getAttribute(PENDING_ATTRIBUTE);
        if (payload !== null) {
            section.setAttribute(LIVE_ATTRIBUTE, payload);
            section.removeAttribute(PENDING_ATTRIBUTE);
        }
        item.setAttribute("data-sg-enhanced", "true");
        queueViewerScript(0);
    }

    var observer = null;
    if (typeof IntersectionObserver === "function") {
        observer = new IntersectionObserver(function(entries) {
            entries.forEach(function(entry) {
                if (!entry.isIntersecting) { return; }
                observer.unobserve(entry.target);
                enhance(entry.target);
            });
        }, { rootMargin: "300px 0px" });
    }

    function observeVisible() {
        items.forEach(function(item) {
            if (item.getAttribute("data-has-viewer") !== "true") { return; }
            if (item.getAttribute("data-sg-enhanced") === "true") { return; }
            if (item.hidden || isSuiteCollapsed(item)) { return; }
            if (observer) {
                observer.observe(item);
            } else {
                enhance(item);
            }
        });
    }

    // MARK: - Suite collapse

    function suiteOf(item) {
        if (item.closest) { return item.closest(".sg-suite"); }
        var node = item.parentNode;
        while (node && !(node.classList && node.classList.contains("sg-suite"))) {
            node = node.parentNode;
        }
        return node;
    }

    function isSuiteCollapsed(item) {
        var suite = suiteOf(item);
        var toggle = suite && suite.querySelector(".sg-suite-toggle");
        return !!toggle && toggle.getAttribute("aria-expanded") === "false";
    }

    function setSuiteExpanded(suite, expandedValue) {
        var toggle = suite.querySelector(".sg-suite-toggle");
        var body = suite.querySelector(".sg-suite-body");
        if (!toggle || !body) { return; }
        toggle.setAttribute("aria-expanded", expandedValue ? "true" : "false");
        body.hidden = !expandedValue;
        if (expandedValue) { observeVisible(); }
    }

    suites.forEach(function(suite) {
        var toggle = suite.querySelector(".sg-suite-toggle");
        if (!toggle) { return; }
        toggle.addEventListener("click", function() {
            setSuiteExpanded(suite, toggle.getAttribute("aria-expanded") === "false");
        });
    });

    if (toggleAllButton) {
        toggleAllButton.addEventListener("click", function() {
            var collapse = !pressed(toggleAllButton);
            suites.forEach(function(suite) { setSuiteExpanded(suite, !collapse); });
            setPressed(toggleAllButton, collapse);
            toggleAllButton.textContent = collapse ? "Expand all" : "Collapse all";
        });
    }

    // MARK: - Filtering

    function enabledSuites() {
        var set = {};
        chips.forEach(function(chip) {
            if (pressed(chip)) { set[chip.getAttribute("data-suite")] = true; }
        });
        return set;
    }

    function applyFilter() {
        var query = (searchInput ? searchInput.value : "").trim().toLowerCase();
        var failedOnly = pressed(failedOnlyButton);
        var allowedSuites = enabledSuites();
        var visibleTotal = 0;

        suites.forEach(function(suite) {
            var suiteItems = toArray(suite.querySelectorAll(".sg-item"));
            var visibleInSuite = 0;
            suiteItems.forEach(function(item) {
                var matchesSuite = !!allowedSuites[item.getAttribute("data-suite")];
                var matchesFailed = !failedOnly || item.getAttribute("data-failed") === "true";
                var matchesQuery = query === ""
                    || (item.getAttribute("data-search") || "").indexOf(query) !== -1;
                var visible = matchesSuite && matchesFailed && matchesQuery;
                item.hidden = !visible;
                if (visible) { visibleInSuite += 1; }
            });
            suite.hidden = visibleInSuite === 0;
            var counter = suite.querySelector("[data-sg-visible]");
            if (counter) { counter.textContent = String(visibleInSuite); }
            visibleTotal += visibleInSuite;
        });

        if (readout) {
            readout.textContent = "Showing " + visibleTotal + " of " + items.length + " tests";
        }
        if (empty) { empty.hidden = visibleTotal !== 0; }
        observeVisible();
    }

    if (searchInput) {
        var debounce;
        searchInput.addEventListener("input", function() {
            clearTimeout(debounce);
            debounce = setTimeout(applyFilter, 120);
        });
    }

    if (failedOnlyButton) {
        failedOnlyButton.addEventListener("click", function() {
            setPressed(failedOnlyButton, !pressed(failedOnlyButton));
            applyFilter();
        });
    }

    chips.forEach(function(chip) {
        chip.addEventListener("click", function() {
            setPressed(chip, !pressed(chip));
            applyFilter();
        });
    });

    if (chipAll) {
        chipAll.addEventListener("click", function() {
            chips.forEach(function(chip) { setPressed(chip, true); });
            applyFilter();
        });
    }

    // MARK: - Deep links

    function revealHash() {
        var id = (window.location.hash || "").replace("#", "");
        if (!id) { return; }
        var target = document.getElementById(id);
        if (!target) { return; }
        var item = target.classList && target.classList.contains("sg-item")
            ? target
            : (target.closest ? target.closest(".sg-item") : null);
        if (!item) { return; }

        // A deep-linked comparison must win over whatever the filters are currently hiding.
        if (item.hidden) {
            if (searchInput) { searchInput.value = ""; }
            setPressed(failedOnlyButton, false);
            chips.forEach(function(chip) { setPressed(chip, true); });
            applyFilter();
        }
        var suite = suiteOf(item);
        if (suite) { setSuiteExpanded(suite, true); }
        enhance(item);
        window.requestAnimationFrame(function() {
            target.scrollIntoView({ block: "start" });
        });
    }

    window.addEventListener("hashchange", revealHash);

    applyFilter();
    revealHash();
})();
