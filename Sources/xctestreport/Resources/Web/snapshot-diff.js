/*
 * snapshot-diff.js
 * Interactive viewer for the snapshot comparisons emitted by xctestreport.
 *
 * Enhances every <section class="snapshot-diffs" data-snapshot-comparisons="...">.
 * If the payload is missing or unparseable the server-rendered static fallback is
 * left untouched, so the report still works without JS.
 */
(function() {
    "use strict";

    var MODES = [
        { id: "side", key: "1", label: "Side by side" },
        { id: "swipe", key: "2", label: "Swipe" },
        { id: "onion", key: "3", label: "Onion skin" },
        { id: "blink", key: "4", label: "Blink" },
        { id: "heat", key: "5", label: "Heatmap" },
        { id: "highlight", key: "6", label: "Highlight" }
    ];

    var ZOOM_PRESETS = [
        { label: "Fit", value: 0 },
        { label: "100%", value: 1 },
        { label: "200%", value: 2 },
        { label: "400%", value: 4 }
    ];

    var COLLAPSE_THRESHOLD = 3;
    var MIN_ZOOM = 0.02;
    var MAX_ZOOM = 32;
    var PIXELATE_AT = 2;
    var MAX_COMPUTE_PIXELS = 64000000;
    var RECOMPUTE_DELAY = 140;
    var PAN_STEP = 40;
    var MIN_PANE_HEIGHT = 140;
    var MAX_PANE_HEIGHT = 640;

    var HEAT_LUT = buildHeatLut();

    function buildHeatLut() {
        var stops = [
            [22, 42, 92],
            [0, 132, 255],
            [0, 214, 168],
            [255, 214, 0],
            [255, 48, 48]
        ];
        var lut = new Uint8Array(256 * 3);
        var segments = stops.length - 1;
        for (var i = 0; i < 256; i += 1) {
            var t = (i / 255) * segments;
            var seg = Math.min(segments - 1, Math.floor(t));
            var f = t - seg;
            var a = stops[seg];
            var b = stops[seg + 1];
            lut[i * 3] = Math.round(a[0] + (b[0] - a[0]) * f);
            lut[i * 3 + 1] = Math.round(a[1] + (b[1] - a[1]) * f);
            lut[i * 3 + 2] = Math.round(a[2] + (b[2] - a[2]) * f);
        }
        return lut;
    }

    // MARK: - Helpers

    function el(tag, className, text) {
        var node = document.createElement(tag);
        if (className) { node.className = className; }
        if (text !== undefined && text !== null) { node.textContent = String(text); }
        return node;
    }

    function button(className, label, ariaLabel) {
        var b = el("button", className, label);
        b.type = "button";
        if (ariaLabel) { b.setAttribute("aria-label", ariaLabel); }
        return b;
    }

    function clamp(value, low, high) {
        if (value < low) { return low; }
        if (value > high) { return high; }
        return value;
    }

    function fmtInt(value) {
        var n = Math.round(value || 0);
        try {
            return n.toLocaleString();
        } catch (error) {
            return String(n);
        }
    }

    function fmtPercent(fraction) {
        if (typeof fraction !== "number" || !isFinite(fraction)) { return "—"; }
        var pct = fraction * 100;
        if (pct > 0 && pct < 0.01) { return "<0.01%"; }
        return (pct < 10 ? pct.toFixed(2) : pct.toFixed(1)) + "%";
    }

    function signed(value) {
        if (value > 0) { return "+" + value; }
        if (value < 0) { return "−" + Math.abs(value); }
        return "0";
    }

    function positive(value, fallback) {
        return typeof value === "number" && isFinite(value) && value > 0 ? value : fallback;
    }

    function basename(src) {
        var clean = String(src || "").split("?")[0].split("#")[0];
        var parts = clean.split("/");
        var last = parts[parts.length - 1] || clean;
        try {
            return decodeURIComponent(last);
        } catch (error) {
            return last;
        }
    }

    function isArray(value) {
        return Object.prototype.toString.call(value) === "[object Array]";
    }

    function parsePayload(raw) {
        if (!raw) { return null; }
        var decoded = raw;
        try {
            decoded = decodeURIComponent(raw);
        } catch (error) {
            decoded = raw;
        }
        var parsed = null;
        try {
            parsed = JSON.parse(decoded);
        } catch (error) {
            if (decoded === raw) { return null; }
            try {
                parsed = JSON.parse(raw);
            } catch (innerError) {
                return null;
            }
        }
        if (!isArray(parsed)) { return null; }

        var usable = [];
        for (var i = 0; i < parsed.length; i += 1) {
            var item = parsed[i];
            if (!item || !item.expected || !item.actual) { continue; }
            if (!item.expected.src || !item.actual.src) { continue; }
            usable.push(item);
        }
        return usable.length ? usable : null;
    }

    function parseDevice(raw) {
        if (!raw) { return null; }
        var decoded = raw;
        try {
            decoded = decodeURIComponent(raw);
        } catch (error) {
            decoded = raw;
        }
        var parsed = null;
        try {
            parsed = JSON.parse(decoded);
        } catch (error) {
            return null;
        }
        if (!parsed || typeof parsed !== "object" || isArray(parsed)) { return null; }
        return parsed;
    }

    function text(value) {
        return typeof value === "string" && value.trim() ? value.trim() : null;
    }

    // "Apple Watch Series 11 · watchOS Simulator 27.0 (24R5355a)". Every field is optional.
    // deviceName is deliberately left out: on watchOS it names the paired iPhone.
    function deviceLabel(device) {
        if (!device) { return null; }
        var runtime = [text(device.platform), text(device.osVersion)]
            .filter(function(part) { return !!part; })
            .join(" ");
        var build = text(device.osBuildNumber);
        if (runtime && build) { runtime += " (" + build + ")"; }
        else if (!runtime && build) { runtime = "build " + build; }
        var parts = [text(device.name), runtime].filter(function(part) { return !!part; });
        return parts.length ? parts.join(" · ") : null;
    }

    function deviceTooltip(device) {
        var lines = [];
        if (text(device.deviceName)) { lines.push("Host device: " + text(device.deviceName)); }
        if (text(device.identifier)) { lines.push("Identifier: " + text(device.identifier)); }
        return lines.join("\n");
    }

    function normalizeBoxes(list) {
        var out = [];
        if (!isArray(list)) { return out; }
        for (var i = 0; i < list.length; i += 1) {
            var box = list[i];
            if (!box) { continue; }
            var w = Number(box.w) || 0;
            var h = Number(box.h) || 0;
            if (w <= 0 || h <= 0) { continue; }
            out.push({ x: Number(box.x) || 0, y: Number(box.y) || 0, w: w, h: h });
        }
        return out;
    }

    // MARK: - Construction

    function buildComparison(data, index) {
        var expectedWidth = positive(data.expected.width, 0);
        var expectedHeight = positive(data.expected.height, 0);
        var actualWidth = positive(data.actual.width, 0);
        var actualHeight = positive(data.actual.height, 0);

        var state = {
            data: data,
            mode: "side",
            zoom: 1,
            fitZoom: 1,
            panX: 0,
            panY: 0,
            userZoomed: false,
            split: 0.5,
            onion: 0.5,
            blinkOn: false,
            blinkShowsActual: false,
            blinkTimer: null,
            blinkInterval: 500,
            tolerance: 0,
            boxIndex: -1,
            showBoxes: true,
            expW: expectedWidth,
            expH: expectedHeight,
            actW: actualWidth,
            actH: actualHeight,
            unionW: Math.max(expectedWidth, actualWidth, 1),
            unionH: Math.max(expectedHeight, actualHeight, 1),
            boxes: normalizeBoxes(data.boundingBoxes),
            loaded: false,
            broken: false,
            pixelsOK: true,
            expData: null,
            actData: null,
            compCanvas: null,
            compCtx: null,
            compCache: null,
            loaderExpected: null,
            loaderActual: null,
            live: null,
            recomputeTimer: null,
            panes: [],
            zoomButtons: [],
            modeButtons: {}
        };

        var root = el("article", "snapdiff");
        root.setAttribute("tabindex", "0");
        root.setAttribute("role", "group");
        root.setAttribute("aria-label", "Snapshot comparison: " + (data.name || "#" + (index + 1)));
        state.root = root;

        root.appendChild(buildHeader(state, data, index));

        var body = el("div", "snapdiff-body");
        body.id = "snapdiff-body-" + index + "-" + Math.random().toString(36).slice(2, 8);
        state.body = body;
        root.appendChild(body);

        if (data.sizeMismatch) { body.appendChild(buildSizeBanner(state, data)); }
        body.appendChild(buildToolbar(state));
        body.appendChild(buildStage(state));
        body.appendChild(buildFooter(state, data));

        state.toggle.setAttribute("aria-controls", body.id);
        return state;
    }

    function buildHeader(state, data, index) {
        var head = el("header", "snapdiff-head");

        var toggle = button("snapdiff-toggle", null, null);
        toggle.setAttribute("aria-expanded", "false");
        var caret = el("span", "snapdiff-caret");
        caret.setAttribute("aria-hidden", "true");
        toggle.appendChild(caret);
        toggle.appendChild(el("span", "snapdiff-name", data.name || "Snapshot " + (index + 1)));
        toggle.addEventListener("click", function() {
            setExpanded(state, state.body.hasAttribute("hidden"));
        });
        state.toggle = toggle;
        head.appendChild(toggle);

        var badges = el("div", "snapdiff-badges");
        if (data.sizeMismatch) {
            badges.appendChild(el("span", "snapdiff-badge snapdiff-badge-size", "Size changed"));
        }
        if (data.failureAssociated) {
            badges.appendChild(el("span", "snapdiff-badge snapdiff-badge-fail", "Failure"));
        }
        if (typeof data.changedFraction === "number") {
            badges.appendChild(el("span", "snapdiff-badge", fmtPercent(data.changedFraction) + " changed"));
        }
        head.appendChild(badges);
        return head;
    }

    function buildSizeBanner(state, data) {
        var banner = el("div", "snapdiff-sizebanner");
        banner.setAttribute("role", "status");

        var icon = el("span", "snapdiff-sizebanner-icon", "⚠");
        icon.setAttribute("aria-hidden", "true");
        banner.appendChild(icon);

        var text = el("span", "snapdiff-sizebanner-text");
        text.appendChild(el("strong", null, state.expW + "×" + state.expH));
        text.appendChild(el("span", "snapdiff-arrow", "→"));
        text.appendChild(el("strong", null, state.actW + "×" + state.actH));
        banner.appendChild(text);

        var widthDelta = typeof data.widthDelta === "number" ? data.widthDelta : state.actW - state.expW;
        var heightDelta = typeof data.heightDelta === "number" ? data.heightDelta : state.actH - state.expH;
        var deltas = [];
        if (widthDelta) { deltas.push("width " + signed(widthDelta)); }
        if (heightDelta) { deltas.push("height " + signed(heightDelta)); }
        if (deltas.length) {
            banner.appendChild(el("span", "snapdiff-sizebanner-delta", "(" + deltas.join(", ") + ")"));
        }
        banner.appendChild(el("span", "snapdiff-sizebanner-note",
            "Aligned top-left, never scaled. Hatched areas exist in only one image."));
        return banner;
    }

    function buildToolbar(state) {
        var bar = el("div", "snapdiff-toolbar");

        var modeGroup = el("div", "snapdiff-modes");
        modeGroup.setAttribute("role", "group");
        modeGroup.setAttribute("aria-label", "Comparison mode");
        MODES.forEach(function(mode) {
            var b = button("snapdiff-mode", mode.label, mode.label + " (key " + mode.key + ")");
            b.setAttribute("aria-pressed", "false");
            b.addEventListener("click", function() { setMode(state, mode.id); });
            state.modeButtons[mode.id] = b;
            modeGroup.appendChild(b);
        });
        bar.appendChild(modeGroup);

        var options = el("div", "snapdiff-modeopts");

        var onionWrap = el("label", "snapdiff-field");
        onionWrap.appendChild(el("span", "snapdiff-fieldlabel", "Opacity"));
        var onionSlider = range("snapdiff-range", 0, 100, 1, 50, "Actual image opacity");
        var onionValue = el("span", "snapdiff-fieldvalue", "50%");
        onionSlider.addEventListener("input", function() {
            state.onion = Number(onionSlider.value) / 100;
            onionValue.textContent = onionSlider.value + "%";
            applyLayers(state);
        });
        onionWrap.appendChild(onionSlider);
        onionWrap.appendChild(onionValue);
        state.onionWrap = onionWrap;
        options.appendChild(onionWrap);

        var blinkWrap = el("div", "snapdiff-field");
        var playButton = button("snapdiff-btn", "Play", "Play or pause blinking");
        playButton.setAttribute("aria-pressed", "false");
        playButton.addEventListener("click", function() { setBlink(state, !state.blinkOn); });
        state.blinkPlayButton = playButton;
        blinkWrap.appendChild(playButton);

        var flipButton = button("snapdiff-btn", "Flip", "Manually toggle expected and actual");
        flipButton.addEventListener("click", function() {
            setBlink(state, false);
            state.blinkShowsActual = !state.blinkShowsActual;
            applyLayers(state);
        });
        blinkWrap.appendChild(flipButton);

        var blinkSlider = range("snapdiff-range snapdiff-range-short", 100, 2000, 50, 500,
            "Blink interval in milliseconds");
        var blinkValue = el("span", "snapdiff-fieldvalue", "500ms");
        blinkSlider.addEventListener("input", function() {
            state.blinkInterval = Number(blinkSlider.value);
            blinkValue.textContent = state.blinkInterval + "ms";
            if (state.blinkOn) { setBlink(state, true); }
        });
        blinkWrap.appendChild(blinkSlider);
        blinkWrap.appendChild(blinkValue);
        state.blinkWrap = blinkWrap;
        options.appendChild(blinkWrap);

        var toleranceWrap = el("label", "snapdiff-field");
        toleranceWrap.appendChild(el("span", "snapdiff-fieldlabel", "Tolerance"));
        var toleranceSlider = range("snapdiff-range", 0, 128, 1, 0, "Per-channel tolerance");
        var toleranceValue = el("span", "snapdiff-fieldvalue", "0");
        toleranceSlider.addEventListener("input", function() {
            state.tolerance = Number(toleranceSlider.value);
            toleranceValue.textContent = String(state.tolerance);
            scheduleRecompute(state, false);
        });
        toleranceWrap.appendChild(toleranceSlider);
        toleranceWrap.appendChild(toleranceValue);
        state.toleranceWrap = toleranceWrap;
        state.toleranceSlider = toleranceSlider;
        var analysis = el("details", "snapdiff-analysis");
        analysis.appendChild(el("summary", null, "Pixel analysis"));
        analysis.appendChild(toleranceWrap);
        state.analysis = analysis;

        state.swipeHint = el("span", "snapdiff-hint", "Drag the divider, or focus it and press ← →.");
        options.appendChild(state.swipeHint);
        state.sideHint = el("span", "snapdiff-hint", "Expected left, actual right. Zoom and pan stay in sync.");
        options.appendChild(state.sideHint);

        bar.appendChild(options);


        var zoomGroup = el("div", "snapdiff-zoom");
        zoomGroup.setAttribute("role", "group");
        zoomGroup.setAttribute("aria-label", "Zoom");
        ZOOM_PRESETS.forEach(function(preset) {
            var b = button("snapdiff-btn snapdiff-zoompreset", preset.label, "Zoom " + preset.label);
            b.setAttribute("aria-pressed", "false");
            b.setAttribute("data-zoom", String(preset.value));
            b.addEventListener("click", function() {
                if (preset.value === 0) { fitView(state); }
                else { setZoom(state, preset.value, null, null); }
            });
            state.zoomButtons.push(b);
            zoomGroup.appendChild(b);
        });
        var zoomOut = button("snapdiff-btn snapdiff-btn-icon", "−", "Zoom out");
        zoomOut.addEventListener("click", function() { nudgeZoom(state, 1 / 1.4); });
        zoomGroup.appendChild(zoomOut);
        var zoomIn = button("snapdiff-btn snapdiff-btn-icon", "+", "Zoom in");
        zoomIn.addEventListener("click", function() { nudgeZoom(state, 1.4); });
        zoomGroup.appendChild(zoomIn);
        state.zoomLabel = el("span", "snapdiff-zoomlabel", "100%");
        zoomGroup.appendChild(state.zoomLabel);
        bar.appendChild(zoomGroup);

        var navGroup = el("div", "snapdiff-nav");
        navGroup.setAttribute("role", "group");
        navGroup.setAttribute("aria-label", "Change navigation");
        var previous = button("snapdiff-btn", "Prev", "Previous difference");
        previous.addEventListener("click", function() { stepBox(state, -1); });
        var next = button("snapdiff-btn", "Next", "Next difference");
        next.addEventListener("click", function() { stepBox(state, 1); });
        var counter = el("span", "snapdiff-counter", "0 / 0");
        counter.setAttribute("aria-live", "polite");
        navGroup.appendChild(previous);
        navGroup.appendChild(counter);
        navGroup.appendChild(next);

        var boxToggle = button("snapdiff-btn", "Boxes", "Toggle difference outlines");
        boxToggle.setAttribute("aria-pressed", "true");
        boxToggle.addEventListener("click", function() {
            state.showBoxes = !state.showBoxes;
            boxToggle.setAttribute("aria-pressed", state.showBoxes ? "true" : "false");
            applyLayers(state);
        });
        navGroup.appendChild(boxToggle);

        state.previousButton = previous;
        state.nextButton = next;
        state.counter = counter;
        state.navigation = navGroup;
        navGroup.prepend(el("span", "snapdiff-nav-label", "Differences"));

        return bar;
    }

    function range(className, min, max, step, value, ariaLabel) {
        var input = document.createElement("input");
        input.type = "range";
        input.className = className;
        input.min = String(min);
        input.max = String(max);
        input.step = String(step);
        input.value = String(value);
        input.setAttribute("aria-label", ariaLabel);
        return input;
    }

    function buildStage(state) {
        var stage = el("div", "snapdiff-stage");
        state.stage = stage;

        state.paneA = buildPane(state, "A");
        state.paneB = buildPane(state, "B");
        state.panes = [state.paneA, state.paneB];
        stage.appendChild(state.paneA.root);
        stage.appendChild(state.paneB.root);

        var message = el("div", "snapdiff-message");
        message.setAttribute("hidden", "");
        state.message = message;
        stage.appendChild(message);

        stage.addEventListener("wheel", function(event) {
            if (!state.loaded || state.broken) { return; }
            event.preventDefault();
            if (event.shiftKey && !event.ctrlKey && !event.metaKey) {
                state.panX -= event.deltaY || event.deltaX;
                state.userZoomed = true;
                applyTransform(state);
                return;
            }
            var point = panePoint(state, event);
            setZoom(state, state.zoom * Math.pow(0.998, event.deltaY), point.x, point.y);
        }, { passive: false });

        attachPanHandlers(state, stage);
        return stage;
    }

    function buildPane(state, id) {
        var pane = { id: id };
        pane.root = el("div", "snapdiff-pane");
        pane.world = el("div", "snapdiff-world");
        pane.root.appendChild(pane.world);

        pane.imgExpected = makeImage("snapdiff-layer snapdiff-layer-expected", "Expected snapshot");
        pane.imgActual = makeImage("snapdiff-layer snapdiff-layer-actual", "Actual snapshot");
        pane.imgDiff = makeImage("snapdiff-layer snapdiff-layer-diff", "Difference image");

        pane.swipeClip = el("div", "snapdiff-swipeclip");
        pane.imgSwipe = makeImage("snapdiff-layer snapdiff-layer-swipe", "Actual snapshot");
        pane.swipeClip.appendChild(pane.imgSwipe);

        pane.stripRight = el("div", "snapdiff-oob");
        pane.stripBottom = el("div", "snapdiff-oob");
        pane.stripRight.title = "Exists in only one image";
        pane.stripBottom.title = "Exists in only one image";

        pane.canvasSlot = el("div", "snapdiff-canvasslot");
        pane.boxLayer = el("div", "snapdiff-boxlayer");

        pane.world.appendChild(pane.imgExpected);
        pane.world.appendChild(pane.imgActual);
        pane.world.appendChild(pane.swipeClip);
        pane.world.appendChild(pane.canvasSlot);
        pane.world.appendChild(pane.imgDiff);
        pane.world.appendChild(pane.stripRight);
        pane.world.appendChild(pane.stripBottom);
        pane.world.appendChild(pane.boxLayer);

        pane.label = el("span", "snapdiff-panelabel");
        pane.root.appendChild(pane.label);

        if (id === "A") {
            pane.handle = button("snapdiff-swipehandle", null, "Swipe divider");
            pane.handle.setAttribute("hidden", "");
            pane.handle.addEventListener("keydown", function(event) {
                var delta = event.key === "ArrowLeft" ? -0.02 : event.key === "ArrowRight" ? 0.02 : 0;
                if (!delta) { return; }
                event.preventDefault();
                event.stopPropagation();
                state.split = clamp(state.split + delta, 0, 1);
                applyLayers(state);
            });
            attachSwipeDrag(state, pane);
            pane.root.appendChild(pane.handle);
        }

        pane.root.addEventListener("pointermove", function(event) {
            updateInspector(state, pane, event);
        });
        pane.root.addEventListener("pointerleave", function() {
            clearInspector(state);
        });

        return pane;
    }

    function makeImage(className, alt) {
        var img = document.createElement("img");
        img.className = className;
        img.alt = alt;
        img.setAttribute("loading", "lazy");
        img.setAttribute("decoding", "async");
        img.draggable = false;
        return img;
    }

    function buildFooter(state, data) {
        var footer = el("div", "snapdiff-footer");
        footer.appendChild(state.navigation);

        var stats = el("div", "snapdiff-stats");
        state.statChanged = addStat(stats, "Changed", "—");
        state.statMax = addStat(stats, "Max Δ",
            typeof data.maxChannelDelta === "number" ? String(data.maxChannelDelta) : "—");
        addStat(stats, "Size", state.expW + "×" + state.expH
            + (data.sizeMismatch ? " → " + state.actW + "×" + state.actH : ""));
        addStat(stats, "Diff image",
            data.diff ? (data.diffSynthesized ? "synthesized" : "attached") : "none");
        state.analysis.appendChild(stats);
        footer.appendChild(state.analysis);

        state.inspector = el("div", "snapdiff-inspector");
        state.analysis.appendChild(state.inspector);
        clearInspector(state);

        state.pixelNote = el("div", "snapdiff-note",
            "Pixel-level features are unavailable: the browser refused to read these images. "
            + "Serving the report over http(s) instead of opening the file directly enables them.");
        state.pixelNote.setAttribute("hidden", "");
        footer.appendChild(state.pixelNote);

        var links = el("div", "snapdiff-links");
        addLink(links, "Expected", data.expected.src);
        addLink(links, "Actual", data.actual.src);
        if (data.diff && data.diff.src) { addLink(links, "Diff", data.diff.src); }
        links.prepend(el("span", "snapdiff-download-label", "Download originals"));
        footer.appendChild(links);

        var legend = el("details", "snapdiff-legend");
        legend.appendChild(el("summary", null, "Keyboard shortcuts"));
        var list = el("ul", "snapdiff-legend-list");
        [
            "1–6 — comparison mode",
            "+ / − — zoom · 0 — fit",
            "n / p — next / previous difference",
            "b — start or stop blinking",
            "Arrows — pan · drag to pan · scroll to zoom"
        ].forEach(function(line) {
            list.appendChild(el("li", null, line));
        });
        legend.appendChild(list);
        footer.appendChild(legend);

        return footer;
    }

    function addStat(parent, label, value) {
        var wrap = el("span", "snapdiff-stat");
        wrap.appendChild(el("span", "snapdiff-stat-label", label));
        var valueNode = el("span", "snapdiff-stat-value", value);
        wrap.appendChild(valueNode);
        parent.appendChild(wrap);
        return valueNode;
    }

    function addLink(parent, label, src) {
        var link = el("a", "snapdiff-link", label);
        link.href = src;
        link.setAttribute("download", basename(src));
        link.setAttribute("aria-label", "Download " + label.toLowerCase() + " image");
        parent.appendChild(link);
    }

    // MARK: - Expand and load

    function setExpanded(state, expand) {
        if (expand) {
            state.body.removeAttribute("hidden");
            state.root.classList.add("is-open");
            state.toggle.setAttribute("aria-expanded", "true");
            load(state);
        } else {
            state.body.setAttribute("hidden", "");
            state.root.classList.remove("is-open");
            state.toggle.setAttribute("aria-expanded", "false");
            setBlink(state, false);
            releaseBuffers(state);
        }
    }

    function load(state) {
        if (state.loaded) {
            requestAnimationFrame(function() {
                sizeStage(state);
                if (!state.userZoomed) { fitView(state); } else { applyTransform(state); }
            });
            return;
        }
        state.loaded = true;

        var data = state.data;
        var pending = 0;
        var failed = [];

        function finish() {
            if (state.disposed || !state.loaded || state.body.hidden) { return; }
            if (failed.length) {
                state.broken = true;
                state.pixelsOK = false;
                state.root.classList.add("is-broken");
                disablePixelFeatures(state);
                showMessage(state, "Could not load the " + failed.join(" and ")
                    + " image. The download links below still point at the originals.");
            } else {
                hideMessage(state);
                adoptNaturalSizes(state);
                preparePixelData(state);
            }
            applyMode(state);
            requestAnimationFrame(function() {
                sizeStage(state);
                fitView(state);
            });
        }

        // Readiness is driven by detached loaders: a hidden `loading="lazy"` layer never
        // fires load or error, so the rendered <img> elements cannot be trusted for this.
        function track(loader, src, label) {
            pending += 1;
            loader.addEventListener("load", function() {
                pending -= 1;
                if (pending === 0) { finish(); }
            });
            loader.addEventListener("error", function() {
                pending -= 1;
                failed.push(label);
                if (pending === 0) { finish(); }
            });
            loader.src = src;
        }

        state.loaderExpected = new Image();
        state.loaderActual = new Image();
        track(state.loaderExpected, data.expected.src, "expected");
        track(state.loaderActual, data.actual.src, "actual");

        state.paneA.imgExpected.src = data.expected.src;
        state.paneA.imgActual.src = data.actual.src;
        state.paneA.imgSwipe.src = data.actual.src;
        state.paneB.imgActual.src = data.actual.src;
        if (data.diff && data.diff.src) { state.paneA.imgDiff.src = data.diff.src; }

        applyMode(state);
        observeResize(state);
    }

    function adoptNaturalSizes(state) {
        var expected = state.loaderExpected;
        var actual = state.loaderActual;
        if (!expected || !actual) { return; }
        if (!state.expW && expected.naturalWidth) {
            state.expW = expected.naturalWidth;
            state.expH = expected.naturalHeight;
        }
        if (!state.actW && actual.naturalWidth) {
            state.actW = actual.naturalWidth;
            state.actH = actual.naturalHeight;
        }
        state.unionW = Math.max(state.expW, state.actW, 1);
        state.unionH = Math.max(state.expH, state.actH, 1);
    }

    // Large snapshots keep tens of megabytes of pixel data alive; drop it on collapse.
    function releaseBuffers(state) {
        if (state.recomputeTimer) {
            clearTimeout(state.recomputeTimer);
            state.recomputeTimer = null;
        }
        state.expData = null;
        state.actData = null;
        state.loaderExpected = null;
        state.loaderActual = null;
        state.compCache = null;
        state.live = null;
        if (state.compCanvas) {
            state.compCanvas.width = 1;
            state.compCanvas.height = 1;
            if (state.compCanvas.parentNode) {
                state.compCanvas.parentNode.removeChild(state.compCanvas);
            }
            state.compCanvas = null;
            state.compCtx = null;
        }
        state.loaded = false;
        state.userZoomed = false;
        if (!state.broken) { state.pixelsOK = true; }
        updateStats(state);
    }

    function preparePixelData(state) {
        if (state.unionW * state.unionH > MAX_COMPUTE_PIXELS) {
            state.pixelsOK = false;
            disablePixelFeatures(state);
            return;
        }
        try {
            state.expData = readPixels(state.loaderExpected, state.expW, state.expH);
            state.actData = readPixels(state.loaderActual, state.actW, state.actH);
            state.pixelsOK = !!(state.expData && state.actData);
        } catch (error) {
            state.expData = null;
            state.actData = null;
            state.pixelsOK = false;
        }
        if (!state.pixelsOK) { disablePixelFeatures(state); }
    }

    function readPixels(img, width, height) {
        if (!width || !height) { return null; }
        var canvas = document.createElement("canvas");
        canvas.width = width;
        canvas.height = height;
        var ctx = canvas.getContext("2d", { willReadFrequently: true });
        if (!ctx) { return null; }
        ctx.drawImage(img, 0, 0, width, height);
        return ctx.getImageData(0, 0, width, height);
    }

    function disablePixelFeatures(state) {
        if (state.toleranceSlider) { state.toleranceSlider.disabled = true; }
        if (state.toleranceWrap) { state.toleranceWrap.classList.add("is-disabled"); }
        if (state.modeButtons.heat) { state.modeButtons.heat.disabled = true; }
        if (!state.data.diff && state.modeButtons.highlight) {
            state.modeButtons.highlight.disabled = true;
        }
        if (state.broken) {
            MODES.forEach(function(mode) {
                if (state.modeButtons[mode.id]) { state.modeButtons[mode.id].disabled = true; }
            });
        }
        if (state.mode === "heat" || (state.mode === "highlight" && !state.data.diff)) {
            state.mode = "side";
        }
        if (state.pixelNote && !state.broken) { state.pixelNote.removeAttribute("hidden"); }
        clearInspector(state);
    }

    // MARK: - Modes

    function setMode(state, mode) {
        var known = false;
        for (var i = 0; i < MODES.length; i += 1) {
            if (MODES[i].id === mode) { known = true; }
        }
        if (!known) { return; }
        var btn = state.modeButtons[mode];
        if (btn && btn.disabled) { return; }
        state.mode = mode;
        if (mode !== "blink") { setBlink(state, false); }
        applyMode(state);
    }

    function applyMode(state) {
        MODES.forEach(function(mode) {
            var b = state.modeButtons[mode.id];
            if (b) { b.setAttribute("aria-pressed", mode.id === state.mode ? "true" : "false"); }
        });
        state.root.setAttribute("data-mode", state.mode);
        toggleHidden(state.onionWrap, state.mode !== "onion");
        toggleHidden(state.blinkWrap, state.mode !== "blink");
        toggleHidden(state.swipeHint, state.mode !== "swipe");
        toggleHidden(state.sideHint, state.mode !== "side");
        toggleHidden(state.toleranceWrap, state.mode !== "heat" && state.mode !== "highlight");
        applyLayers(state);
        if (needsComputedLayer(state)) { scheduleRecompute(state, true); }
        updateCounter(state);
        requestAnimationFrame(function() {
            sizeStage(state);
            if (!state.userZoomed) { fitView(state); } else { applyTransform(state); }
        });
    }

    function toggleHidden(node, hide) {
        if (!node) { return; }
        if (hide) { node.setAttribute("hidden", ""); } else { node.removeAttribute("hidden"); }
    }

    function needsComputedLayer(state) {
        if (!state.pixelsOK || !state.expData || !state.actData) { return false; }
        if (state.mode === "heat") { return true; }
        return state.mode === "highlight" && !state.data.diff;
    }

    function applyLayers(state) {
        var mode = state.mode;
        var A = state.paneA;
        var B = state.paneB;
        var sideBySide = mode === "side";
        var diff = state.data.diff;

        toggleHidden(B.root, !sideBySide);
        if (sideBySide) { state.stage.classList.add("is-split"); }
        else { state.stage.classList.remove("is-split"); }

        sizeLayer(A.imgExpected, state.expW, state.expH);
        sizeLayer(A.imgActual, state.actW, state.actH);
        sizeLayer(A.imgSwipe, state.actW, state.actH);
        sizeLayer(A.imgDiff, positive(diff && diff.width, state.unionW), positive(diff && diff.height, state.unionH));
        sizeLayer(B.imgActual, state.actW, state.actH);
        sizeWorld(A.world, state.unionW, state.unionH);
        sizeWorld(B.world, state.unionW, state.unionH);

        var showExpected = false;
        var showActual = false;
        var showSwipe = false;
        var showDiff = false;
        var showCanvas = false;
        var actualOpacity = 1;
        var computedReady = state.pixelsOK && !!state.compCanvas;

        if (mode === "side") {
            showExpected = true;
            A.label.textContent = "Expected";
            B.label.textContent = "Actual";
        } else if (mode === "swipe") {
            showExpected = true;
            showSwipe = true;
            A.label.textContent = "Expected │ Actual";
        } else if (mode === "onion") {
            showExpected = true;
            showActual = true;
            actualOpacity = state.onion;
            A.label.textContent = "Onion skin · actual " + Math.round(state.onion * 100) + "%";
        } else if (mode === "blink") {
            showExpected = !state.blinkShowsActual;
            showActual = state.blinkShowsActual;
            A.label.textContent = state.blinkShowsActual ? "Actual" : "Expected";
        } else if (mode === "heat") {
            showCanvas = computedReady;
            showExpected = !computedReady;
            A.label.textContent = computedReady ? "Difference heatmap" : "Heatmap unavailable";
        } else if (mode === "highlight") {
            if (diff) {
                showDiff = true;
                A.label.textContent = state.data.diffSynthesized ? "Diff image (generated)" : "Diff image";
            } else {
                showActual = true;
                showCanvas = computedReady;
                A.label.textContent = "Actual with highlighted changes";
            }
        }

        setVisible(A.imgExpected, showExpected, 1);
        setVisible(A.imgActual, showActual, actualOpacity);
        setVisible(A.swipeClip, showSwipe, 1);
        setVisible(A.imgDiff, showDiff, 1);
        setVisible(A.canvasSlot, showCanvas, 1);
        setVisible(B.imgActual, sideBySide, 1);
        setVisible(B.imgExpected, false, 1);
        setVisible(B.swipeClip, false, 1);
        setVisible(B.imgDiff, false, 1);
        setVisible(B.canvasSlot, false, 1);

        toggleHidden(A.handle, mode !== "swipe");
        if (mode === "swipe") {
            var clipLeft = state.split * state.unionW;
            A.swipeClip.style.left = clipLeft + "px";
            A.swipeClip.style.top = "0px";
            A.swipeClip.style.width = Math.max(0, state.unionW - clipLeft) + "px";
            A.swipeClip.style.height = state.unionH + "px";
            A.imgSwipe.style.marginLeft = (-clipLeft) + "px";
        }

        // The heatmap paints its own hatch, so only the DOM layers need strips.
        var mismatch = !!state.data.sizeMismatch || state.expW !== state.actW || state.expH !== state.actH;
        if (mismatch && !(mode === "heat" && showCanvas)) {
            if (sideBySide) {
                setStrips(A, state.expW, state.expH, state.unionW, state.unionH);
                setStrips(B, state.actW, state.actH, state.unionW, state.unionH);
            } else {
                setStrips(A, Math.min(state.expW, state.actW), Math.min(state.expH, state.actH),
                    state.unionW, state.unionH);
                setStrips(B, 0, 0, 0, 0);
            }
        } else {
            setStrips(A, 0, 0, 0, 0);
            setStrips(B, 0, 0, 0, 0);
        }

        drawBoxes(state, A);
        drawBoxes(state, sideBySide ? B : null);
        applyTransform(state);
    }

    function sizeLayer(node, width, height) {
        node.style.width = (width || 0) + "px";
        node.style.height = (height || 0) + "px";
    }

    function sizeWorld(node, width, height) {
        node.style.width = width + "px";
        node.style.height = height + "px";
    }

    function setVisible(node, visible, opacity) {
        if (visible) {
            node.removeAttribute("hidden");
            node.style.opacity = String(opacity);
        } else {
            node.setAttribute("hidden", "");
        }
    }

    function setStrips(pane, width, height, unionW, unionH) {
        if (!pane) { return; }
        if (!unionW || !unionH || (width >= unionW && height >= unionH)) {
            pane.stripRight.setAttribute("hidden", "");
            pane.stripBottom.setAttribute("hidden", "");
            return;
        }
        if (width < unionW) {
            pane.stripRight.removeAttribute("hidden");
            pane.stripRight.style.left = width + "px";
            pane.stripRight.style.top = "0px";
            pane.stripRight.style.width = (unionW - width) + "px";
            pane.stripRight.style.height = unionH + "px";
        } else {
            pane.stripRight.setAttribute("hidden", "");
        }
        if (height < unionH) {
            pane.stripBottom.removeAttribute("hidden");
            pane.stripBottom.style.left = "0px";
            pane.stripBottom.style.top = height + "px";
            pane.stripBottom.style.width = Math.min(width, unionW) + "px";
            pane.stripBottom.style.height = (unionH - height) + "px";
        } else {
            pane.stripBottom.setAttribute("hidden", "");
        }
    }

    function drawBoxes(state, pane) {
        if (!pane) { return; }
        var layer = pane.boxLayer;
        while (layer.firstChild) { layer.removeChild(layer.firstChild); }
        if (!state.showBoxes || !state.boxes.length) { return; }
        for (var i = 0; i < state.boxes.length; i += 1) {
            var box = state.boxes[i];
            var node = el("div", "snapdiff-box");
            node.style.left = box.x + "px";
            node.style.top = box.y + "px";
            node.style.width = box.w + "px";
            node.style.height = box.h + "px";
            if (i === state.boxIndex) { node.classList.add("is-active"); }
            layer.appendChild(node);
        }
    }

    // MARK: - Blink

    function setBlink(state, on) {
        if (state.blinkTimer) {
            clearInterval(state.blinkTimer);
            state.blinkTimer = null;
        }
        state.blinkOn = !!on && state.mode === "blink";
        if (state.blinkPlayButton) {
            state.blinkPlayButton.textContent = state.blinkOn ? "Pause" : "Play";
            state.blinkPlayButton.setAttribute("aria-pressed", state.blinkOn ? "true" : "false");
        }
        if (state.blinkOn) {
            state.blinkTimer = setInterval(function() {
                state.blinkShowsActual = !state.blinkShowsActual;
                applyLayers(state);
            }, state.blinkInterval);
        }
    }

    // MARK: - Zoom and pan

    function panePoint(state, event) {
        var rect = state.paneA.root.getBoundingClientRect();
        return { x: event.clientX - rect.left, y: event.clientY - rect.top };
    }

    function setZoom(state, zoom, anchorX, anchorY) {
        var next = clamp(zoom, MIN_ZOOM, MAX_ZOOM);
        var rect = state.paneA.root.getBoundingClientRect();
        var ax = (anchorX === null || anchorX === undefined) ? rect.width / 2 : anchorX;
        var ay = (anchorY === null || anchorY === undefined) ? rect.height / 2 : anchorY;
        var worldX = (ax - state.panX) / state.zoom;
        var worldY = (ay - state.panY) / state.zoom;
        state.zoom = next;
        state.panX = ax - worldX * next;
        state.panY = ay - worldY * next;
        state.userZoomed = true;
        applyTransform(state);
    }

    function nudgeZoom(state, factor) {
        setZoom(state, state.zoom * factor, null, null);
    }

    // Panes follow the snapshot's aspect ratio: a short wide watch snapshot should not
    // sit in 600px of empty checkerboard, and a tall iOS one still needs room.
    function sizeStage(state) {
        var stage = state.stage;
        var width = stage.clientWidth;
        if (!width) { return; }
        var gap = 8;
        var column = window.getComputedStyle(stage).flexDirection === "column";
        var split = state.mode === "side";
        var paneWidth = (split && !column) ? (width - gap) / 2 : width;
        var maxPane = Math.min(MAX_PANE_HEIGHT, Math.round(window.innerHeight * 0.7));
        var paneHeight = clamp(
            Math.round(Math.min(paneWidth, state.unionW) * (state.unionH / state.unionW)) + 48,
            MIN_PANE_HEIGHT,
            Math.max(MIN_PANE_HEIGHT, maxPane));
        var height = ((split && column) ? paneHeight * 2 + gap : paneHeight) + "px";
        if (stage.style.height !== height) { stage.style.height = height; }
    }

    function fitView(state) {
        var rect = state.paneA.root.getBoundingClientRect();
        if (!rect.width || !rect.height) { return; }
        var zoom = clamp(Math.min(rect.width / state.unionW, rect.height / state.unionH), MIN_ZOOM, 1);
        state.zoom = zoom;
        state.fitZoom = zoom;
        state.panX = (rect.width - state.unionW * zoom) / 2;
        state.panY = (rect.height - state.unionH * zoom) / 2;
        state.userZoomed = false;
        applyTransform(state);
    }

    function applyTransform(state) {
        var transform = "translate(" + state.panX.toFixed(2) + "px," + state.panY.toFixed(2)
            + "px) scale(" + state.zoom + ")";
        for (var i = 0; i < state.panes.length; i += 1) {
            var pane = state.panes[i];
            pane.world.style.transform = transform;
            // Outlines live in world space, so counter-scale them to keep a hairline look.
            pane.world.style.setProperty("--snapdiff-hair", (1.4 / state.zoom).toFixed(3) + "px");
            if (state.zoom >= PIXELATE_AT) { pane.root.classList.add("is-pixelated"); }
            else { pane.root.classList.remove("is-pixelated"); }
        }
        if (state.zoomLabel) { state.zoomLabel.textContent = Math.round(state.zoom * 100) + "%"; }
        for (var j = 0; j < state.zoomButtons.length; j += 1) {
            var b = state.zoomButtons[j];
            var value = Number(b.getAttribute("data-zoom"));
            var active = value === 0
                ? !state.userZoomed
                : state.userZoomed && Math.abs(state.zoom - value) < 0.005;
            b.setAttribute("aria-pressed", active ? "true" : "false");
        }
        if (state.mode === "swipe" && state.paneA.handle) {
            state.paneA.handle.style.left = (state.panX + state.split * state.unionW * state.zoom) + "px";
        }
    }

    function attachPanHandlers(state, stage) {
        var dragging = false;
        var lastX = 0;
        var lastY = 0;
        var pointerId = null;

        stage.addEventListener("pointerdown", function(event) {
            if (event.button !== 0) { return; }
            if (event.target && event.target.closest && event.target.closest(".snapdiff-swipehandle")) { return; }
            dragging = true;
            pointerId = event.pointerId;
            lastX = event.clientX;
            lastY = event.clientY;
            stage.classList.add("is-panning");
            try { stage.setPointerCapture(pointerId); } catch (error) { /* capture is best effort */ }
        });

        stage.addEventListener("pointermove", function(event) {
            if (!dragging || event.pointerId !== pointerId) { return; }
            state.panX += event.clientX - lastX;
            state.panY += event.clientY - lastY;
            lastX = event.clientX;
            lastY = event.clientY;
            state.userZoomed = true;
            applyTransform(state);
        });

        function endDrag(event) {
            if (!dragging) { return; }
            if (event && event.pointerId !== pointerId) { return; }
            dragging = false;
            stage.classList.remove("is-panning");
            try { stage.releasePointerCapture(pointerId); } catch (error) { /* already released */ }
            pointerId = null;
        }
        stage.addEventListener("pointerup", endDrag);
        stage.addEventListener("pointercancel", endDrag);
    }

    function attachSwipeDrag(state, pane) {
        var dragging = false;

        function move(event) {
            var rect = pane.root.getBoundingClientRect();
            var world = (event.clientX - rect.left - state.panX) / state.zoom;
            state.split = clamp(world / state.unionW, 0, 1);
            applyLayers(state);
        }

        pane.handle.addEventListener("pointerdown", function(event) {
            dragging = true;
            try { pane.handle.setPointerCapture(event.pointerId); } catch (error) { /* best effort */ }
            event.preventDefault();
            event.stopPropagation();
        });
        pane.handle.addEventListener("pointermove", function(event) {
            if (!dragging) { return; }
            event.stopPropagation();
            move(event);
        });
        function end() { dragging = false; }
        pane.handle.addEventListener("pointerup", end);
        pane.handle.addEventListener("pointercancel", end);
    }

    function observeResize(state) {
        if (typeof ResizeObserver !== "function" || state.resizeObserver) { return; }
        state.resizeObserver = new ResizeObserver(function() {
            sizeStage(state);
            if (!state.userZoomed) { fitView(state); } else { applyTransform(state); }
        });
        state.resizeObserver.observe(state.stage);
    }

    // MARK: - Change navigation

    function stepBox(state, direction) {
        if (!state.boxes.length) { return; }
        var next = state.boxIndex + direction;
        if (next < 0) { next = state.boxes.length - 1; }
        if (next >= state.boxes.length) { next = 0; }
        state.boxIndex = next;
        focusBox(state, state.boxes[next]);
        updateCounter(state);
        drawBoxes(state, state.paneA);
        if (state.mode === "side") { drawBoxes(state, state.paneB); }
    }

    function focusBox(state, box) {
        var rect = state.paneA.root.getBoundingClientRect();
        if (!rect.width || !rect.height) { return; }
        var padding = 28;
        var zoom = Math.min((rect.width - padding * 2) / Math.max(box.w, 1),
            (rect.height - padding * 2) / Math.max(box.h, 1));
        zoom = clamp(zoom, Math.min(state.fitZoom, 1), 8);
        state.zoom = zoom;
        state.panX = rect.width / 2 - (box.x + box.w / 2) * zoom;
        state.panY = rect.height / 2 - (box.y + box.h / 2) * zoom;
        state.userZoomed = true;
        applyTransform(state);
    }

    function updateCounter(state) {
        var total = state.boxes.length;
        var current = state.boxIndex >= 0 ? state.boxIndex + 1 : 0;
        state.counter.textContent = current + " / " + total;
        state.previousButton.disabled = total === 0;
        state.nextButton.disabled = total === 0;
    }

    // MARK: - Difference computation

    function scheduleRecompute(state, immediate) {
        if (!state.pixelsOK || !state.expData || !state.actData) { return; }
        if (state.recomputeTimer) {
            clearTimeout(state.recomputeTimer);
            state.recomputeTimer = null;
        }
        if (immediate) {
            runCompute(state);
            return;
        }
        state.recomputeTimer = setTimeout(function() {
            state.recomputeTimer = null;
            runCompute(state);
        }, RECOMPUTE_DELAY);
    }

    function runCompute(state) {
        var paint = state.mode === "heat" ? "heat" : "highlight";
        if (state.compCache && state.compCache.tolerance === state.tolerance && state.compCache.paint === paint) {
            updateStats(state);
            return;
        }
        try {
            state.live = compute(state, paint);
        } catch (error) {
            state.pixelsOK = false;
            state.live = null;
            disablePixelFeatures(state);
            applyMode(state);
            return;
        }
        state.compCache = { tolerance: state.tolerance, paint: paint };
        updateStats(state);
        applyLayers(state);
    }

    function ensureCanvas(state) {
        if (!state.compCanvas) {
            var canvas = document.createElement("canvas");
            canvas.className = "snapdiff-layer snapdiff-canvas";
            state.compCanvas = canvas;
            state.compCtx = canvas.getContext("2d", { willReadFrequently: true });
            state.paneA.canvasSlot.appendChild(canvas);
        }
        if (state.compCanvas.width !== state.unionW || state.compCanvas.height !== state.unionH) {
            state.compCanvas.width = state.unionW;
            state.compCanvas.height = state.unionH;
            state.compCanvas.style.width = state.unionW + "px";
            state.compCanvas.style.height = state.unionH + "px";
        }
        return state.compCtx;
    }

    function compute(state, paint) {
        var ctx = ensureCanvas(state);
        if (!ctx) { throw new Error("no 2d context"); }

        var W = state.unionW;
        var H = state.unionH;
        var eW = state.expW;
        var eH = state.expH;
        var aW = state.actW;
        var aH = state.actH;
        var ed = state.expData.data;
        var ad = state.actData.data;
        var tolerance = state.tolerance;
        var heat = paint === "heat";

        var out = ctx.createImageData(W, H);
        var od = out.data;
        var changed = 0;
        var outside = 0;
        var maxDelta = 0;

        for (var y = 0; y < H; y += 1) {
            var expectedRow = y < eH;
            var actualRow = y < aH;
            var eRow = expectedRow ? y * eW * 4 : 0;
            var aRow = actualRow ? y * aW * 4 : 0;
            var oRow = y * W * 4;
            for (var x = 0; x < W; x += 1) {
                var o = oRow + x * 4;

                if (!expectedRow || !actualRow || x >= eW || x >= aW) {
                    outside += 1;
                    changed += 1;
                    maxDelta = 255;
                    var stripe = ((x + y) % 12) < 6;
                    od[o] = stripe ? 236 : 122;
                    od[o + 1] = stripe ? 178 : 72;
                    od[o + 2] = stripe ? 46 : 18;
                    od[o + 3] = heat ? 255 : 210;
                    continue;
                }

                var ei = eRow + x * 4;
                var ai = aRow + x * 4;
                var dr = ed[ei] - ad[ai];
                if (dr < 0) { dr = -dr; }
                var dg = ed[ei + 1] - ad[ai + 1];
                if (dg < 0) { dg = -dg; }
                var db = ed[ei + 2] - ad[ai + 2];
                if (db < 0) { db = -db; }
                var da = ed[ei + 3] - ad[ai + 3];
                if (da < 0) { da = -da; }
                var d = dr > dg ? dr : dg;
                if (db > d) { d = db; }
                if (da > d) { d = da; }
                if (d > maxDelta) { maxDelta = d; }

                if (d <= tolerance) {
                    if (heat) {
                        var luma = (ed[ei] * 77 + ed[ei + 1] * 150 + ed[ei + 2] * 29) >> 8;
                        var dim = 14 + ((luma * 56) >> 8);
                        od[o] = dim;
                        od[o + 1] = dim + 4;
                        od[o + 2] = dim + 12;
                        od[o + 3] = 255;
                    } else {
                        od[o + 3] = 0;
                    }
                    continue;
                }

                changed += 1;
                if (heat) {
                    var li = d * 3;
                    od[o] = HEAT_LUT[li];
                    od[o + 1] = HEAT_LUT[li + 1];
                    od[o + 2] = HEAT_LUT[li + 2];
                    od[o + 3] = 255;
                } else {
                    od[o] = 255;
                    od[o + 1] = 0;
                    od[o + 2] = 210;
                    od[o + 3] = d > 85 ? 230 : 170;
                }
            }
        }

        ctx.putImageData(out, 0, 0);
        return { changed: changed, outside: outside, total: W * H, maxDelta: maxDelta };
    }

    function updateStats(state) {
        var data = state.data;
        if (state.live) {
            var fraction = state.live.total ? state.live.changed / state.live.total : 0;
            var text = fmtInt(state.live.changed) + " px · " + fmtPercent(fraction);
            if (state.live.outside) { text += " · " + fmtInt(state.live.outside) + " px out of frame"; }
            if (state.tolerance) { text += " · tolerance " + state.tolerance; }
            state.statChanged.textContent = text;
            state.statMax.textContent = String(state.live.maxDelta);
            return;
        }
        if (typeof data.changedPixels === "number") {
            var reported = typeof data.changedFraction === "number"
                ? data.changedFraction
                : (data.totalPixels ? data.changedPixels / data.totalPixels : 0);
            state.statChanged.textContent = fmtInt(data.changedPixels) + " px · " + fmtPercent(reported);
        } else {
            state.statChanged.textContent = "—";
        }
        if (typeof data.maxChannelDelta === "number") {
            state.statMax.textContent = String(data.maxChannelDelta);
        }
    }

    // MARK: - Pixel inspector

    function updateInspector(state, pane, event) {
        if (state.broken || !state.pixelsOK || !state.expData || !state.actData) { return; }
        var rect = pane.root.getBoundingClientRect();
        var x = Math.floor((event.clientX - rect.left - state.panX) / state.zoom);
        var y = Math.floor((event.clientY - rect.top - state.panY) / state.zoom);
        if (x < 0 || y < 0 || x >= state.unionW || y >= state.unionH) {
            clearInspector(state);
            return;
        }
        renderInspector(state, x, y,
            samplePixel(state.expData, state.expW, state.expH, x, y),
            samplePixel(state.actData, state.actW, state.actH, x, y));
    }

    function samplePixel(imageData, width, height, x, y) {
        if (!imageData || x >= width || y >= height) { return null; }
        var i = (y * width + x) * 4;
        var d = imageData.data;
        return [d[i], d[i + 1], d[i + 2], d[i + 3]];
    }

    function renderInspector(state, x, y, expected, actual) {
        var node = state.inspector;
        while (node.firstChild) { node.removeChild(node.firstChild); }
        node.appendChild(el("span", "snapdiff-inspector-coord", x + ", " + y));
        node.appendChild(pixelChip("Expected", expected));
        node.appendChild(pixelChip("Actual", actual));

        var deltaNode;
        if (expected && actual) {
            deltaNode = el("span", "snapdiff-inspector-delta", "Δ "
                + Math.abs(expected[0] - actual[0]) + ", "
                + Math.abs(expected[1] - actual[1]) + ", "
                + Math.abs(expected[2] - actual[2]) + ", "
                + Math.abs(expected[3] - actual[3]));
        } else {
            deltaNode = el("span", "snapdiff-inspector-delta",
                "outside the " + (expected ? "actual" : "expected") + " image");
            deltaNode.classList.add("is-outside");
        }
        node.appendChild(deltaNode);
    }

    function pixelChip(label, rgba) {
        var chip = el("span", "snapdiff-chip");
        var swatch = el("span", "snapdiff-swatch");
        swatch.setAttribute("aria-hidden", "true");
        if (rgba) {
            swatch.style.background = "rgba(" + rgba[0] + "," + rgba[1] + "," + rgba[2] + ","
                + (rgba[3] / 255) + ")";
        } else {
            swatch.classList.add("is-empty");
        }
        chip.appendChild(swatch);
        chip.appendChild(el("span", "snapdiff-chip-label", label));
        chip.appendChild(el("span", "snapdiff-chip-value", rgba ? rgba.join(", ") : "—"));
        return chip;
    }

    function clearInspector(state) {
        var node = state.inspector;
        while (node.firstChild) { node.removeChild(node.firstChild); }
        var hint = state.pixelsOK
            ? "Hover the image for pixel values"
            : "Pixel inspection unavailable";
        node.appendChild(el("span", "snapdiff-inspector-coord", hint));
    }

    function showMessage(state, text) {
        state.message.textContent = text;
        state.message.removeAttribute("hidden");
    }

    function hideMessage(state) {
        state.message.setAttribute("hidden", "");
    }

    // MARK: - Keyboard

    function attachKeyboard(state) {
        state.root.addEventListener("keydown", function(event) {
            if (event.metaKey || event.ctrlKey || event.altKey) { return; }
            var target = event.target;
            var tag = target && target.tagName ? target.tagName.toLowerCase() : "";
            if (tag === "input" || tag === "textarea" || tag === "select") { return; }
            if (state.body.hasAttribute("hidden")) { return; }

            var key = event.key;
            var modeForKey = null;
            for (var i = 0; i < MODES.length; i += 1) {
                if (MODES[i].key === key) { modeForKey = MODES[i].id; }
            }

            var handled = true;
            if (modeForKey) {
                setMode(state, modeForKey);
            } else if (key === "+" || key === "=") {
                nudgeZoom(state, 1.4);
            } else if (key === "-" || key === "_") {
                nudgeZoom(state, 1 / 1.4);
            } else if (key === "0") {
                fitView(state);
            } else if (key === "n" || key === "N") {
                stepBox(state, 1);
            } else if (key === "p" || key === "P") {
                stepBox(state, -1);
            } else if (key === "b" || key === "B") {
                if (state.mode !== "blink") { setMode(state, "blink"); }
                setBlink(state, !state.blinkOn);
            } else if (key === "ArrowLeft") {
                state.panX += PAN_STEP;
                state.userZoomed = true;
                applyTransform(state);
            } else if (key === "ArrowRight") {
                state.panX -= PAN_STEP;
                state.userZoomed = true;
                applyTransform(state);
            } else if (key === "ArrowUp") {
                state.panY += PAN_STEP;
                state.userZoomed = true;
                applyTransform(state);
            } else if (key === "ArrowDown") {
                state.panY -= PAN_STEP;
                state.userZoomed = true;
                applyTransform(state);
            } else {
                handled = false;
            }

            if (handled) { event.preventDefault(); }
        });
    }

    // MARK: - Bootstrap

    function enhance(section) {
        if (section.getAttribute("data-snapshot-enhanced") === "true") { return; }
        var comparisons = parsePayload(section.getAttribute("data-snapshot-comparisons"));
        if (!comparisons) { return; }

        var fragment = document.createDocumentFragment();
        var states = [];

        var device = parseDevice(section.getAttribute("data-snapshot-device"));
        var label = deviceLabel(device);
        if (label || comparisons.length > 1) {
            var head = el("div", "snapdiff-sectionhead");
            if (comparisons.length > 1) {
                head.appendChild(el("span", "snapdiff-sectioncount",
                    comparisons.length + " snapshot comparisons"));
            }
            if (label) {
                var deviceNode = el("span", "snapdiff-device", label);
                var tooltip = deviceTooltip(device);
                if (tooltip) { deviceNode.title = tooltip; }
                head.appendChild(deviceNode);
            }
            if (comparisons.length > 1) {
                var expandAll = button("snapdiff-btn", "Expand all", "Expand all comparisons");
                expandAll.addEventListener("click", function() {
                    states.forEach(function(s) { setExpanded(s, true); });
                });
                var collapseAll = button("snapdiff-btn", "Collapse all", "Collapse all comparisons");
                collapseAll.addEventListener("click", function() {
                    states.forEach(function(s) { setExpanded(s, false); });
                });
                head.appendChild(expandAll);
                head.appendChild(collapseAll);
            }
            fragment.appendChild(head);
        }

        for (var i = 0; i < comparisons.length; i += 1) {
            var state = buildComparison(comparisons[i], i);
            attachKeyboard(state);
            updateStats(state);
            updateCounter(state);
            state.body.setAttribute("hidden", "");
            if (section.closest("dialog")) { state.toggle.disabled = true; }
            state.analysis.open = section.getAttribute("data-snapshot-analysis-open") === "true";
            var preferredMode = section.getAttribute("data-snapshot-mode");
            if (preferredMode) { setMode(state, preferredMode); }
            states.push(state);
            fragment.appendChild(state.root);
        }

        // The server-rendered heading belongs to the section, not to the fallback.
        var title = section.querySelector(".snapshot-diffs-title");
        while (section.firstChild) { section.removeChild(section.firstChild); }
        if (title) { section.appendChild(title); }
        section.appendChild(fragment);
        section.setAttribute("data-snapshot-enhanced", "true");
        section.classList.add("snapshot-diffs-enhanced");

        if (comparisons.length < COLLAPSE_THRESHOLD) {
            states.forEach(function(s) { setExpanded(s, true); });
        }

        function pauseHidden() {
            if (document.hidden) { states.forEach(function(s) { setBlink(s, false); }); }
        }
        document.addEventListener("visibilitychange", pauseHidden);
        section.addEventListener("snapshot-dispose", function() {
            document.removeEventListener("visibilitychange", pauseHidden);
            states.forEach(function(s) {
                s.disposed = true;
                setBlink(s, false);
                if (s.resizeObserver) { s.resizeObserver.disconnect(); }
                releaseBuffers(s);
            });
        }, { once: true });
    }

    function init() {
        var sections = document.querySelectorAll("section.snapshot-diffs");
        for (var i = 0; i < sections.length; i += 1) {
            try {
                enhance(sections[i]);
            } catch (error) {
                // A broken comparison must never take down the static fallback.
                if (window.console && window.console.warn) {
                    window.console.warn("snapshot-diff: " + error);
                }
            }
        }
    }

    window.SnapshotDiff = { enhance: enhance };

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", init);
    } else {
        init();
    }
})();
