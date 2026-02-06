import Dispatch
import Foundation

extension XCTestReport {
    func renderTimelineVideoSection(
        for testIdentifier: String?, activities: TestActivities?,
        attachmentsByTestIdentifier: [String: [AttachmentManifestItem]],
        sourceLocationBySymbol: [String: SourceLocation] = [:],
        template: String
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
                from: activitiesForRun,
                attachmentLookup: attachmentLookup,
                sourceLocationBySymbol: sourceLocationBySymbol,
                nextId: &nextId)
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
                let startTime = node.timestamp ?? timelineBaseTime
                let endTime = max(startTime, node.endTimestamp ?? startTime)
                return TimelineEventEntry(
                    id: node.id,
                    title: timelineDisplayTitle(node, baseTime: timelineBaseTime),
                    time: startTime,
                    endTime: endTime
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

        do {
            return try renderTemplate(
                template,
                values: [
                    "layout_class": layoutClass,
                    "media_mode": mediaMode,
                    "default_timeline_base": String(format: "%.6f", defaultTimelineBase),
                    "default_video_start": String(format: "%.6f", defaultVideoStart),
                    "run_selector_html": runSelectorHTML,
                    "run_panels_html": runPanelsHTML.joined(separator: ""),
                    "video_panel_html": videoPanelHtml,
                    "run_states_json": jsonForScriptTag(runStatesJSON),
                    "screenshot_json": jsonForScriptTag(screenshotJSON),
                ],
                templateName: "timeline-section.html")
        } catch {
            print("Warning: failed to render timeline section template: \(error)")
            return "<div class=\"timeline-status\">Timeline rendering unavailable.</div>"
        }
    }
}
