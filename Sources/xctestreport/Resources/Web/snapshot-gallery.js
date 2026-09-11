/* Contact-sheet browsing and one on-demand inspector. Static comparisons remain
 * usable without JavaScript; gallery browsing does not create canvas buffers. */
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
    var deviceFilter = null;
    var deviceLabels = Array.from(new Set(items.map(function(item) {
        return item.getAttribute("data-device-label") || "Device unknown";
    }))).sort(function(a, b) { return a.localeCompare(b); });
    if (deviceLabels.length > 1) {
        var deviceHeader = document.querySelector(".sg-device");
        deviceFilter = document.createElement("select");
        deviceFilter.id = "sg-device-filter";
        deviceFilter.setAttribute("aria-label", "Filter by device");
        deviceFilter.appendChild(new Option("All devices · " + deviceLabels.length, ""));
        deviceLabels.forEach(function(label) { deviceFilter.appendChild(new Option(label, label)); });
        if (deviceHeader) { deviceHeader.replaceChildren(deviceFilter); }
        deviceFilter.addEventListener("change", applyFilter);
        items.forEach(function(item) {
            var label = node("span", "sg-card-device", item.getAttribute("data-device-label") || "Device unknown");
            item.querySelector(".sg-item-head").appendChild(label);
        });
    }

    function toArray(list) { return Array.prototype.slice.call(list); }

    function pressed(node) {
        return !!node && node.getAttribute("aria-pressed") === "true";
    }

    function setPressed(node, value) {
        if (node) { node.setAttribute("aria-pressed", value ? "true" : "false"); }
    }

    // A contact sheet never decodes pixels or constructs a viewer. Only the selected
    // comparison enters the inspector; closing it releases observers and pixel buffers.
    var comparisons = [];
    var current = null;
    var opener = null;
    var viewerPromise;
    var dialog = document.createElement("dialog");
    dialog.className = "sg-inspector";
    dialog.setAttribute("aria-label", "Snapshot inspector");
    dialog.innerHTML = '<header class="sg-inspector-head"><div><strong>Snapshot inspector</strong><span class="sg-position" role="status"></span></div><nav aria-label="Snapshot navigation"><button type="button" data-step="-1" aria-label="Previous snapshot">Previous</button><button type="button" data-step="1" aria-label="Next snapshot">Next</button><button type="button" class="sg-close" aria-label="Close inspector">Close <kbd>Esc</kbd></button></nav></header><div class="sg-inspector-content"></div>';
    document.body.appendChild(dialog);
    var host = dialog.querySelector(".sg-inspector-content");

    function node(tag, className, text) {
        var result = document.createElement(tag);
        result.className = className;
        if (text) { result.textContent = text; }
        return result;
    }
    function loadViewer() {
        if (!viewerPromise) {
            viewerPromise = new Promise(function(resolve, reject) {
                var script = document.createElement("script");
                script.src = VIEWER_SCRIPT;
                script.onload = resolve;
                script.onerror = function() { viewerPromise = null; script.remove(); reject(new Error("Viewer unavailable")); };
                document.body.appendChild(script);
            });
        }
        return viewerPromise;
    }
    function dispose() {
        var section = host.querySelector("section");
        if (section) { section.dispatchEvent(new Event("snapshot-dispose")); }
        host.replaceChildren();
    }
    function visibleComparisons() {
        return comparisons.filter(function(entry) { return !entry.item.hidden && !isSuiteCollapsed(entry.item); });
    }
    function openComparison(entry, source) {
        if (!entry) { return; }
        if (source) { opener = source; }
        current = entry;
        var previousViewer = host.querySelector(".snapdiff");
        var mode = previousViewer ? previousViewer.getAttribute("data-mode") : "side";
        var analysisOpen = !!host.querySelector(".snapdiff-analysis[open]");
        dispose();
        var visible = visibleComparisons();
        var index = visible.indexOf(entry);
        dialog.querySelector(".sg-position").textContent = (index + 1) + " of " + visible.length;
        toArray(dialog.querySelectorAll("[data-step]")).forEach(function(button) { button.disabled = visible.length < 2; });
        var context = node("div", "sg-inspector-context", entry.item.querySelector(".sg-item-name").textContent);
        var link = entry.item.querySelector(".sg-item-link").cloneNode(true);
        link.textContent = "Open test details";
        context.appendChild(link);
        if (entry.anchor) {
            var permalink = node("a", "sg-permalink", "Link to snapshot");
            permalink.href = "#" + entry.anchor.id;
            context.appendChild(permalink);
        }
        host.appendChild(context);
        var section = node("section", "snapshot-diffs");
        if (entry.device) { section.setAttribute("data-snapshot-device", entry.device); }
        section.setAttribute("data-snapshot-mode", mode);
        section.setAttribute("data-snapshot-analysis-open", String(analysisOpen));
        section.setAttribute(LIVE_ATTRIBUTE, encodeURIComponent(JSON.stringify([entry.data])));
        host.appendChild(section);
        if (!dialog.open) { dialog.showModal(); document.body.classList.add("sg-inspecting"); }
        var loading = node("p", "sg-loading", "Loading comparison…");
        section.appendChild(loading);
        loadViewer().then(function() {
            if (!section.isConnected) { return; }
            window.SnapshotDiff.enhance(section);
            var viewer = section.querySelector(".snapdiff");
            if (viewer) { viewer.focus({ preventScroll: true }); }
        }).catch(function() {
            if (!section.isConnected) { return; }
            loading.textContent = "Could not load the inspector. Open test details or try again.";
        });
    }
    function step(direction) {
        var visible = visibleComparisons();
        var index = visible.indexOf(current);
        openComparison(visible[(index + direction + visible.length) % visible.length]);
    }
    dialog.querySelector(".sg-close").addEventListener("click", function() { dialog.close(); });
    dialog.addEventListener("close", function() {
        dispose(); current = null;
        document.body.classList.remove("sg-inspecting");
        if (opener && opener.isConnected) { opener.focus({ preventScroll: true }); }
    });
    dialog.addEventListener("click", function(event) {
        if (event.target === dialog) { dialog.close(); }
    });
    toArray(dialog.querySelectorAll("[data-step]")).forEach(function(button) {
        button.addEventListener("click", function() { step(Number(button.dataset.step)); });
    });
    dialog.addEventListener("keydown", function(event) {
        if (/input|select|textarea/i.test(event.target.tagName) || event.metaKey || event.ctrlKey || event.altKey) { return; }
        if (event.key === "[" || event.key === "]") {
            event.preventDefault(); step(event.key === "]" ? 1 : -1);
        }
    });

    items.forEach(function(item) {
        var section = item.querySelector("section.snapshot-diffs");
        if (!section) { return; }
        var data;
        try { data = JSON.parse(decodeURIComponent(section.getAttribute(PENDING_ATTRIBUTE))); }
        catch (_) { return; }
        if (!Array.isArray(data) || !data.length) { return; }
        var sheet = node("div", "sg-previews");
        data.forEach(function(comparison, index) {
            if (!comparison.expected || !comparison.actual) { return; }
            var card = node("button", "sg-preview");
            card.type = "button";
            card.setAttribute("aria-label", "Inspect " + comparison.name);
            var entry = { item: item, data: comparison, device: section.getAttribute("data-snapshot-device"), button: card, anchor: item.querySelectorAll(".sg-anchor")[index] };
            comparisons.push(entry);
            card.appendChild(node("span", "sg-preview-name", comparison.name));
            var pair = node("span", "sg-preview-pair");
            ["expected", "actual"].forEach(function(role) {
                var frame = node("span", "sg-preview-frame");
                frame.dataset.role = role;
                frame.appendChild(node("span", "sg-preview-label", role === "expected" ? "Expected" : "Actual"));
                var img = node("img", "");
                img.src = comparison[role].src;
                img.alt = role + " snapshot for " + comparison.name;
                img.loading = "lazy"; img.decoding = "async";
                img.width = comparison[role].width; img.height = comparison[role].height;
                img.addEventListener("error", function() { frame.classList.add("sg-image-error"); img.alt = "Image unavailable"; });
                frame.appendChild(img); pair.appendChild(frame);
            });
            card.appendChild(pair);
            var percent = (comparison.changedFraction * 100).toFixed(2) + "% changed";
            var caption = node("span", "sg-preview-caption");
            caption.appendChild(node("span", comparison.sizeMismatch ? "sg-size-changed" : "", comparison.sizeMismatch ? "Size changed · " + percent : percent));
            caption.appendChild(node("span", "sg-inspect-label", "Inspect"));
            card.appendChild(caption);
            card.addEventListener("click", function() { openComparison(entry, card); });
            sheet.appendChild(card);
        });
        if (sheet.childElementCount) {
            section.hidden = true;
            item.querySelector(".sg-item-body").appendChild(sheet);
        }
    });
    function enhance(item, target) {
        var entry = comparisons.find(function(candidate) { return candidate.item === item && candidate.anchor === target; })
            || comparisons.find(function(candidate) { return candidate.item === item; });
        openComparison(entry, entry && entry.button);
    }

    var diffPreviewButton = document.getElementById("sg-diff-preview");
    if (diffPreviewButton) {
        diffPreviewButton.addEventListener("click", function() {
            var showDiff = !pressed(diffPreviewButton);
            setPressed(diffPreviewButton, showDiff);
            comparisons.forEach(function(entry) {
                var frame = entry.button.querySelector('[data-role="actual"]');
                var img = frame.querySelector("img");
                var role = showDiff && entry.data.diff ? "diff" : "actual";
                frame.querySelector(".sg-preview-label").textContent = role === "diff" ? "Difference" : "Actual";
                img.src = entry.data[role].src;
                img.alt = role + " snapshot for " + entry.data.name;
            });
        });
    }

    var groupButton = document.getElementById("sg-group");
    if (groupButton) {
        document.body.classList.add("sg-contact-sheet");
        groupButton.addEventListener("click", function() {
            var grouped = !pressed(groupButton);
            setPressed(groupButton, grouped);
            document.body.classList.toggle("sg-contact-sheet", !grouped);
            toggleAllButton.hidden = !grouped;
            suites.forEach(function(suite) { setSuiteExpanded(suite, true); });
            setPressed(toggleAllButton, false);
            toggleAllButton.textContent = "Collapse all";
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
                var matchesDevice = !deviceFilter || !deviceFilter.value
                    || deviceFilter.value === (item.getAttribute("data-device-label") || "Device unknown");
                var visible = matchesSuite && matchesFailed && matchesQuery && matchesDevice;
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
            if (deviceFilter) { deviceFilter.value = ""; }
            setPressed(failedOnlyButton, false);
            chips.forEach(function(chip) { setPressed(chip, true); });
            applyFilter();
        }
        var suite = suiteOf(item);
        if (suite) { setSuiteExpanded(suite, true); }
        enhance(item, target);
        window.requestAnimationFrame(function() {
            target.scrollIntoView({ block: "start" });
        });
    }

    window.addEventListener("hashchange", revealHash);

    applyFilter();
    revealHash();
})();
