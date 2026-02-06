import Dispatch
import Foundation

extension XCTestReport {
    private func timelineViewScriptTag(runStatesJSON: String, screenshotJSON: String) -> String {
        guard let scriptURL = Bundle.module.url(forResource: "timeline-view", withExtension: "js"),
            var scriptTemplate = try? String(contentsOf: scriptURL, encoding: .utf8)
        else {
            print("Warning: timeline-view.js resource was not found. Timeline interactivity is disabled.")
            return ""
        }

        scriptTemplate = scriptTemplate.replacingOccurrences(
            of: "__RUN_STATES_JSON__", with: runStatesJSON)
        scriptTemplate = scriptTemplate.replacingOccurrences(
            of: "__SCREENSHOT_JSON__", with: screenshotJSON)
        return "<script>\n\(scriptTemplate)\n</script>"
    }

    func renderTimelineVideoSection(
        for testIdentifier: String?, activities: TestActivities?,
        attachmentsByTestIdentifier: [String: [AttachmentManifestItem]]
    ) -> String {
        guard let testIdentifier else { return "" }

        let availableRuns = activities?.testRuns ?? []
        let runActivityLists: [[TestActivity]]
        if availableRuns.isEmpty {
            runActivityLists = [[]]
        } else {
            runActivityLists = availableRuns.map { $0.activities }
        }
        let videoSources = buildVideoSources(
            for: testIdentifier, activities: activities,
            attachmentsByTestIdentifier: attachmentsByTestIdentifier)
        let screenshotSources = buildScreenshotSources(
            for: testIdentifier, activities: activities,
            attachmentsByTestIdentifier: attachmentsByTestIdentifier)
        let attachmentLookup = buildAttachmentLookup(
            for: testIdentifier, attachmentsByTestIdentifier: attachmentsByTestIdentifier)

        var nextId = 1
        let fallbackTimelineBase =
            videoSources.first?.startTime ?? screenshotSources.first?.time ?? Date()
            .timeIntervalSince1970

        let screenshotJSON: String = {
            guard !screenshotSources.isEmpty else { return "[]" }
            guard let encoded = try? JSONEncoder().encode(screenshotSources) else { return "[]" }
            return String(data: encoded, encoding: .utf8) ?? "[]"
        }()
        let includeManifestTouchFallback = runActivityLists.count <= 1
        var runStates = [TimelineRunState]()
        var runPanelsHTML = [String]()

        for (runIndex, activitiesForRun) in runActivityLists.enumerated() {
            let timelineNodes = buildTimelineNodes(
                from: activitiesForRun, attachmentLookup: attachmentLookup, nextId: &nextId)
            let collapsedTimelineNodes = collapseRepeatedTimelineNodes(timelineNodes)

            var flatNodes = [TimelineNode]()
            flattenTimelineNodes(collapsedTimelineNodes, into: &flatNodes)
            let timestampedNodes = flatNodes.filter { $0.timestamp != nil }.sorted {
                ($0.timestamp ?? 0) < ($1.timestamp ?? 0)
            }
            let timelineBaseTime =
                timestampedNodes.first?.timestamp ?? videoSources.first?.startTime
                ?? screenshotSources.first?.time ?? fallbackTimelineBase

            let touchGestures = buildTouchGestures(
                from: collapsedTimelineNodes,
                testIdentifier: testIdentifier,
                attachmentsByTestIdentifier: attachmentsByTestIdentifier,
                includeManifestFallback: includeManifestTouchFallback
            )
            let hierarchySnapshots = buildUIHierarchySnapshots(from: collapsedTimelineNodes)
            let events = timestampedNodes.map { node in
                TimelineEventEntry(
                    id: node.id,
                    title: timelineDisplayTitle(node, baseTime: timelineBaseTime),
                    time: node.timestamp ?? timelineBaseTime
                )
            }
            let initialFailureEventIndex = timestampedNodes.firstIndex { $0.failureAssociated } ?? -1
            let firstEventLabel =
                events.first?.title ?? "No event selected"

            let timelineTree: String
            if collapsedTimelineNodes.isEmpty {
                timelineTree =
                    "<div class=\"timeline-status\">No activity timeline was found for this run.</div>"
            } else {
                timelineTree =
                    "<div class=\"timeline-tree\"><ul class=\"timeline-root\">\(renderTimelineNodesHTML(collapsedTimelineNodes, baseTime: timelineBaseTime, depth: 0))</ul></div>"
            }
            let timelineTreeControls = collapsedTimelineNodes.isEmpty
                ? ""
                : """
                    <div class="timeline-tree-actions">
                        <button type="button" class="timeline-tree-action-btn" data-tree-action="collapse">Collapse all</button>
                        <button type="button" class="timeline-tree-action-btn" data-tree-action="expand">Expand all</button>
                    </div>
                    """

            runStates.append(
                TimelineRunState(
                    index: runIndex,
                    label: "Run \(runIndex + 1)",
                    timelineBase: timelineBaseTime,
                    firstEventLabel: firstEventLabel,
                    initialFailureEventIndex: initialFailureEventIndex,
                    events: events,
                    touchGestures: touchGestures,
                    hierarchySnapshots: hierarchySnapshots
                ))

            let hiddenStyle = runIndex == 0 ? "" : " style=\"display:none;\""
            runPanelsHTML.append(
                """
                <div class="timeline-panel" data-run-panel data-run-index="\(runIndex)"\(hiddenStyle)>
                    <div class="timeline-current" data-active-event>\(htmlEscape(firstEventLabel))</div>
                    \(timelineTree)
                    \(timelineTreeControls)
                </div>
                """
            )
        }

        if runStates.isEmpty {
            runStates = [
                TimelineRunState(
                    index: 0,
                    label: "Run 1",
                    timelineBase: fallbackTimelineBase,
                    firstEventLabel: "No event selected",
                    initialFailureEventIndex: -1,
                    events: [],
                    touchGestures: [],
                    hierarchySnapshots: []
                )
            ]
            runPanelsHTML = [
                """
                <div class="timeline-panel" data-run-panel data-run-index="0">
                    <div class="timeline-current" data-active-event>No event selected</div>
                    <div class="timeline-status">No activity timeline was found for this test.</div>
                </div>
                """
            ]
        }

        let runStatesJSON: String = {
            guard let encoded = try? JSONEncoder().encode(runStates) else { return "[]" }
            return String(data: encoded, encoding: .utf8) ?? "[]"
        }()
        let runSelectorHTML: String = {
            guard runStates.count > 1 else { return "" }
            let options = runStates.map { runState in
                "<option value=\"\(runState.index)\">\(htmlEscape(runState.label))</option>"
            }.joined(separator: "")
            return """
                <div class="timeline-run-selector">
                    <label for="timeline-run-select">Run:</label>
                    <select id="timeline-run-select" class="timeline-run-select" data-run-selector>\(options)</select>
                </div>
                """
        }()

        let defaultTimelineBase = runStates.first?.timelineBase ?? fallbackTimelineBase
        let defaultVideoStart =
            videoSources.first?.startTime ?? screenshotSources.first?.time ?? defaultTimelineBase

        let videoSelector: String
        let videoElements: String
        let mediaMode: String
        let layoutClass: String
        if !videoSources.isEmpty {
            mediaMode = "video"
            layoutClass = ""
            if videoSources.count > 1 {
                let options = videoSources.enumerated().map { index, source in
                    "<option value=\"\(index)\">\(htmlEscape(source.label))</option>"
                }.joined(separator: "")
                videoSelector = "<select class=\"video-selector\" data-video-selector>\(options)</select>"
            } else {
                videoSelector = ""
            }

            videoElements = videoSources.enumerated().map { index, source in
                let relativePath = "attachments/\(urlEncodePath(source.fileName))"
                let startTime = source.startTime ?? defaultTimelineBase
                let hiddenStyle = index == 0 ? "" : " style=\"display:none;\""
                return """
                    <div class="video-card timeline-video-card"\(hiddenStyle) data-video-index="\(index)">
                        <div class="timeline-video-frame">
                            <video class="timeline-video" preload="metadata" data-video-start="\(startTime)">
                                <source src="\(relativePath)" type="\(source.mimeType)">
                                <a href="\(relativePath)">Download video</a>
                            </video>
                            <div class="touch-overlay-layer" data-touch-overlay></div>
                            <div class="hierarchy-overlay-layer" data-hierarchy-overlay>
                                <div class="hierarchy-hints-layer" data-hierarchy-hints></div>
                                <div class="hierarchy-highlight-box" data-hierarchy-highlight hidden></div>
                            </div>
                        </div>
                    </div>
                    """
            }.joined(separator: "")
        } else if !screenshotSources.isEmpty {
            mediaMode = "screenshot"
            layoutClass = ""
            videoSelector = ""
            let firstScreenshot = screenshotSources.first!
            let firstAlt = htmlEscape(firstScreenshot.label)
            videoElements = """
                <div class="video-card timeline-video-card" data-video-index="0">
                    <div class="timeline-video-frame">
                        <img class="timeline-still" data-still-frame src="\(firstScreenshot.src)" alt="\(firstAlt)">
                        <div class="touch-overlay-layer" data-touch-overlay></div>
                        <div class="hierarchy-overlay-layer" data-hierarchy-overlay>
                            <div class="hierarchy-hints-layer" data-hierarchy-hints></div>
                            <div class="hierarchy-highlight-box" data-hierarchy-highlight hidden></div>
                        </div>
                    </div>
                </div>
                """
        } else {
            mediaMode = "none"
            layoutClass = " timeline-layout-single"
            videoSelector = ""
            videoElements = ""
        }

        let videoPanelHtml: String =
            mediaMode == "none"
            ? ""
            : """
                <div class="video-panel">
                    <div class="video-media-column">
                        \(videoSelector)
                        \(videoElements)
                    </div>
                    <button type="button" class="hierarchy-open-toggle" data-hierarchy-open aria-label="Show hierarchy inspector" hidden>
                        <svg class="hierarchy-open-toggle-icon" viewBox="0 0 20 20" aria-hidden="true" focusable="false">
                            <path d="M7.4 4.6L12.8 10L7.4 15.4L8.8 16.8L15.6 10L8.8 3.2Z"></path>
                        </svg>
                    </button>
                    <aside class="hierarchy-side-panel is-collapsed" data-hierarchy-panel hidden>
                        <button type="button" class="hierarchy-side-toggle" data-hierarchy-toggle aria-expanded="false" aria-label="Toggle hierarchy inspector">
                            <svg class="hierarchy-side-toggle-icon" viewBox="0 0 20 20" aria-hidden="true" focusable="false">
                                <path d="M12.6 4.6L7.2 10L12.6 15.4L11.2 16.8L4.4 10L11.2 3.2Z"></path>
                            </svg>
                        </button>
                        <div class="hierarchy-side-body" data-hierarchy-body aria-hidden="true">
                            <div class="hierarchy-side-title">Inspector</div>
                            <div class="hierarchy-toolbar" data-hierarchy-toolbar>
                                <span class="hierarchy-toolbar-dot" aria-hidden="true"></span>
                                <span data-hierarchy-status>No hierarchy snapshot near this moment.</span>
                            </div>
                            <div class="hierarchy-candidate-panel" data-hierarchy-candidate-panel hidden>
                                <div class="hierarchy-candidate-heading" data-hierarchy-candidate-heading>Elements at point</div>
                                <div class="hierarchy-candidate-empty" data-hierarchy-candidate-empty>Click inside the media to list overlapping elements.</div>
                                <div class="hierarchy-candidate-list" data-hierarchy-candidate-list></div>
                            </div>
                            <div class="hierarchy-inspector" data-hierarchy-inspector>
                                <div class="hierarchy-inspector-title" data-hierarchy-selected-title>Selected element</div>
                                <div class="hierarchy-inspector-subtitle" data-hierarchy-selected-subtitle>Click inside the media to inspect overlapping elements.</div>
                                <div class="hierarchy-inspector-properties" data-hierarchy-properties></div>
                            </div>
                        </div>
                    </aside>
                </div>
                """

        return """
            <div class="timeline-video-section">
                <div class="timeline-video-layout\(layoutClass)" data-timeline-root data-media-mode="\(mediaMode)" data-timeline-base="\(defaultTimelineBase)" data-video-base="\(defaultVideoStart)">
                    <div class="timeline-panel-stack">
                        \(runSelectorHTML)
                        \(runPanelsHTML.joined(separator: ""))
                    </div>
                    \(videoPanelHtml)
                </div>
                <div class="timeline-controls" data-timeline-controls>
                    <input type="range" class="timeline-scrubber" min="0" max="0" step="0.05" value="0" data-scrubber>
                    <div class="timeline-timebar">
                        <span data-playback-time>00:00</span>
                        <span data-total-time>00:00</span>
                    </div>
                    <div class="timeline-buttons">
                        <button type="button" class="timeline-button" data-nav="prev" aria-label="Previous event">
                            <svg class="timeline-icon" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
                                <path d="M15.5 6L9.5 12L15.5 18L17 16.5L12.5 12L17 7.5Z"></path>
                            </svg>
                        </button>
                        <button type="button" class="timeline-button timeline-button-play" data-nav="play" aria-label="Play or pause">
                            <svg class="timeline-icon" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
                                <path d="M8 6V18L18 12Z"></path>
                            </svg>
                        </button>
                        <button type="button" class="timeline-button" data-nav="next" aria-label="Next event">
                            <svg class="timeline-icon" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
                                <path d="M8.5 6L14.5 12L8.5 18L7 16.5L11.5 12L7 7.5Z"></path>
                            </svg>
                        </button>
                        <a class="timeline-button timeline-button-download" data-download-video aria-label="Download active video" title="Download active video" hidden>
                            <svg class="timeline-icon" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
                                <path d="M12 4A1 1 0 0 1 13 5V13.59L15.3 11.29A1 1 0 1 1 16.7 12.7L12.7 16.7A1 1 0 0 1 11.3 16.7L7.3 12.7A1 1 0 1 1 8.7 11.29L11 13.59V5A1 1 0 0 1 12 4ZM5 18A1 1 0 0 1 6 17H18A1 1 0 1 1 18 19H6A1 1 0 0 1 5 18Z"></path>
                            </svg>
                        </a>
                    </div>
                </div>
            </div>
            <div class="attachment-preview-modal" data-attachment-modal hidden>
                <div class="attachment-preview-backdrop" data-attachment-close></div>
                <div class="attachment-preview-dialog" role="dialog" aria-modal="true" aria-label="Attachment preview">
                    <div class="attachment-preview-header">
                        <div class="attachment-preview-title" data-attachment-title>Attachment Preview</div>
                        <div class="attachment-preview-actions">
                            <a class="attachment-preview-open" data-attachment-open href="#" target="_blank" rel="noopener">Open file</a>
                            <button type="button" class="attachment-preview-close" data-attachment-close>Close</button>
                        </div>
                    </div>
                    <div class="attachment-preview-body">
                        <img class="attachment-preview-image" data-attachment-image alt="">
                        <video class="attachment-preview-video" data-attachment-video controls preload="metadata"></video>
                        <iframe class="attachment-preview-frame" data-attachment-frame title="Attachment preview"></iframe>
                        <div class="attachment-preview-empty" data-attachment-empty>Preview unavailable for this attachment.</div>
                    </div>
                </div>
            </div>
            \(timelineViewScriptTag(runStatesJSON: runStatesJSON, screenshotJSON: screenshotJSON))
            """
    }

}
