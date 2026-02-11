import Dispatch
import Foundation

private struct CompactScreenshotSource: Encodable {
    let value: XCTestReport.ScreenshotSource

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(value.label)
        try container.encode(value.src)
        try container.encode(value.time)
        try container.encode(value.failureAssociated)
    }
}

private struct CompactTouchGesturePoint: Encodable {
    let value: XCTestReport.TouchGesturePoint

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(value.time)
        try container.encode(value.x)
        try container.encode(value.y)
    }
}

private struct CompactTouchGestureOverlay: Encodable {
    let value: XCTestReport.TouchGestureOverlay

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(value.startTime)
        try container.encode(value.endTime)
        try container.encode(value.width)
        try container.encode(value.height)
        try container.encode(value.points.map { CompactTouchGesturePoint(value: $0) })
    }
}

private struct CompactUIHierarchyElement: Encodable {
    let value: XCTestReport.UIHierarchyElement

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(value.id)
        try container.encode(value.depth)
        try container.encode(value.role)
        try container.encode(value.name)
        try container.encode(value.label)
        try container.encode(value.identifier)
        try container.encode(value.value)
        try container.encode(value.x)
        try container.encode(value.y)
        try container.encode(value.width)
        try container.encode(value.height)
        try container.encode(value.properties)
    }
}

private struct CompactUIHierarchySnapshot: Encodable {
    let value: XCTestReport.UIHierarchySnapshot

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(value.id)
        try container.encode(value.label)
        try container.encode(value.time)
        try container.encode(value.width)
        try container.encode(value.height)
        try container.encode(value.failureAssociated)
        try container.encode(value.elements.map { CompactUIHierarchyElement(value: $0) })
    }
}

private struct CompactTimelineEventEntry: Encodable {
    let value: XCTestReport.TimelineEventEntry

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(value.id)
        try container.encode(value.title)
        try container.encode(value.time)
        try container.encode(value.endTime)
        try container.encode(value.kind.rawValue)
    }
}

private struct CompactTimelineRunState: Encodable {
    let value: XCTestReport.TimelineRunState

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(value.timelineBase)
        try container.encode(value.firstEventLabel)
        try container.encode(value.initialFailureEventIndex)
        try container.encode(value.events.map { CompactTimelineEventEntry(value: $0) })
        try container.encode(value.touchGestures.map { CompactTouchGestureOverlay(value: $0) })
        try container.encode(value.hierarchySnapshots.map { CompactUIHierarchySnapshot(value: $0) })
    }
}

extension XCTestReport {
    private func gzipCompressData(_ data: Data) -> Data? {
        let fileManager = FileManager.default
        let tempDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("xctestreport-gzip-\(UUID().uuidString)", isDirectory: true)
        let inputURL = tempDirectoryURL.appendingPathComponent("payload.json")
        let outputURL = tempDirectoryURL.appendingPathComponent("payload.json.gz")

        do {
            try fileManager.createDirectory(
                at: tempDirectoryURL,
                withIntermediateDirectories: true
            )
            try data.write(to: inputURL, options: .atomic)
            guard fileManager.createFile(atPath: outputURL.path, contents: nil) else {
                return nil
            }
        } catch {
            return nil
        }

        defer {
            try? fileManager.removeItem(at: tempDirectoryURL)
        }

        guard let outputHandle = FileHandle(forWritingAtPath: outputURL.path) else {
            return nil
        }
        defer {
            try? outputHandle.close()
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["gzip", "-9", "-c", inputURL.path]
        task.standardOutput = outputHandle
        let errorHandle = FileHandle(forWritingAtPath: "/dev/null")
        defer {
            try? errorHandle?.close()
        }
        if let errorHandle {
            task.standardError = errorHandle
        }

        do {
            try task.run()
        } catch {
            return nil
        }

        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            return nil
        }

        guard let compressedData = try? Data(contentsOf: outputURL), !compressedData.isEmpty else {
            return nil
        }
        return compressedData
    }

    private func writeCompressedTimelinePayloads(
        runStatesJSON: String,
        screenshotJSON: String,
        payloadBaseName: String
    ) -> (runStatesSrc: String, screenshotSrc: String)? {
        guard let runStatesData = runStatesJSON.data(using: .utf8),
            let screenshotData = screenshotJSON.data(using: .utf8),
            let compressedRunStates = gzipCompressData(runStatesData),
            let compressedScreenshots = gzipCompressData(screenshotData)
        else {
            return nil
        }

        let payloadDir = (outputDir as NSString).appendingPathComponent("timeline_payloads")
        do {
            try FileManager.default.createDirectory(
                atPath: payloadDir, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let runStatesFileName = payloadBaseName + ".runstates.bin"
        let screenshotFileName = payloadBaseName + ".screenshots.bin"
        let runStatesPath = (payloadDir as NSString).appendingPathComponent(runStatesFileName)
        let screenshotPath = (payloadDir as NSString).appendingPathComponent(screenshotFileName)

        do {
            try compressedRunStates.write(to: URL(fileURLWithPath: runStatesPath), options: .atomic)
            try compressedScreenshots.write(
                to: URL(fileURLWithPath: screenshotPath), options: .atomic)
        } catch {
            return nil
        }

        let runStatesSrc = timelinePayloadRelativePathForTestPage(fileName: runStatesFileName)
        let screenshotSrc = timelinePayloadRelativePathForTestPage(fileName: screenshotFileName)
        return (runStatesSrc, screenshotSrc)
    }

    private func encodeCompactRunStatesJSON(_ runStates: [TimelineRunState]) -> String {
        let encoder = JSONEncoder()
        let payload = runStates.map { CompactTimelineRunState(value: $0) }
        guard let encoded = try? encoder.encode(payload) else { return "[]" }
        return String(data: encoded, encoding: .utf8) ?? "[]"
    }

    private func encodeCompactScreenshotsJSON(_ screenshotSources: [ScreenshotSource]) -> String {
        let encoder = JSONEncoder()
        let payload = screenshotSources.map { CompactScreenshotSource(value: $0) }
        guard let encoded = try? encoder.encode(payload) else { return "[]" }
        return String(data: encoded, encoding: .utf8) ?? "[]"
    }

    func renderTimelineVideoSection(
        for testIdentifier: String?, activities: TestActivities?,
        attachmentsByTestIdentifier: [String: [AttachmentManifestItem]],
        sourceLocationBySymbol: [String: SourceLocation] = [:],
        template: String,
        payloadBaseName: String?
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
        var activityTimestamps = [Double]()
        activityTimestamps.reserveCapacity(256)

        func collectActivityTimestamps(from nodes: [TestActivity]) {
            for node in nodes {
                if let startTime = node.startTime {
                    activityTimestamps.append(startTime)
                }
                if let attachments = node.attachments {
                    for attachment in attachments {
                        if let timestamp = attachment.timestamp {
                            activityTimestamps.append(timestamp)
                        }
                    }
                }
                collectActivityTimestamps(from: node.childActivities ?? [])
            }
        }

        for activitiesForRun in runActivityLists {
            collectActivityTimestamps(from: activitiesForRun)
        }

        let activityTimestampRange: ClosedRange<Double>? = {
            guard let minValue = activityTimestamps.min(),
                let maxValue = activityTimestamps.max()
            else { return nil }
            return minValue...maxValue
        }()

        let attachmentLookup = buildAttachmentLookup(
            for: testIdentifier,
            attachmentsByTestIdentifier: attachmentsByTestIdentifier,
            activityTimestampRange: activityTimestampRange)
        let attachmentPayloadLookup = buildAttachmentPayloadLookup(
            for: testIdentifier,
            attachmentsByTestIdentifier: attachmentsByTestIdentifier,
            activityTimestampRange: activityTimestampRange)

        var nextId = 1
        let fallbackTimelineBase =
            videoSources.first?.startTime ?? screenshotSources.first?.time ?? Date()
            .timeIntervalSince1970

        let screenshotJSON: String = {
            guard !screenshotSources.isEmpty else { return "[]" }
            return encodeCompactScreenshotsJSON(screenshotSources)
        }()
        let includeManifestTouchFallback = runActivityLists.count <= 1
        var runStates = [TimelineRunState]()
        var runPanelsHTML = [String]()

        for (runIndex, activitiesForRun) in runActivityLists.enumerated() {
            let timelineNodes = buildTimelineNodes(
                from: activitiesForRun,
                attachmentLookup: attachmentLookup,
                attachmentPayloadLookup: attachmentPayloadLookup,
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
                let kind = timelineEventKind(for: node)
                return TimelineEventEntry(
                    id: node.id,
                    title: timelineDisplayTitle(node, baseTime: timelineBaseTime),
                    time: startTime,
                    endTime: endTime,
                    kind: kind
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
            return encodeCompactRunStatesJSON(runStates)
        }()
        let runStatesInlineJSON = runStatesJSON
        let screenshotInlineJSON = screenshotJSON
        var runStatesSrc = ""
        var screenshotSrc = ""

        if let payloadBaseName, !payloadBaseName.isEmpty,
            let payloadPaths = writeCompressedTimelinePayloads(
                runStatesJSON: runStatesJSON,
                screenshotJSON: screenshotJSON,
                payloadBaseName: payloadBaseName)
        {
            runStatesSrc = payloadPaths.runStatesSrc
            screenshotSrc = payloadPaths.screenshotSrc
        }

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
            let runBoundVideos = videoSources.count > 1
                && videoSources.allSatisfy { $0.runIndex != nil }
            if videoSources.count > 1 && !runBoundVideos {
                let options = videoSources.enumerated().map { index, source in
                    "<option value=\"\(index)\">\(htmlEscape(source.label))</option>"
                }.joined(separator: "")
                videoSelector = "<select class=\"video-selector\" data-video-selector>\(options)</select>"
            } else {
                videoSelector = ""
            }

            videoElements = videoSources.enumerated().map { index, source in
                let relativePath = attachmentRelativePathForTestPage(fileName: source.fileName)
                let startTime = source.startTime ?? defaultTimelineBase
                let hiddenStyle = index == 0 ? "" : " style=\"display:none;\""
                let runIndexAttribute = source.runIndex.map { " data-run-index=\"\($0)\"" } ?? ""
                return """
                    <div class="video-card timeline-video-card"\(hiddenStyle) data-video-index="\(index)"\(runIndexAttribute)>
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
                    "run_states_json": jsonForScriptTag(runStatesInlineJSON),
                    "screenshot_json": jsonForScriptTag(screenshotInlineJSON),
                    "run_states_src": htmlEscape(runStatesSrc),
                    "screenshot_src": htmlEscape(screenshotSrc),
                    "payload_loader_script": "",
                ],
                templateName: "timeline-section.html")
        } catch {
            print("Warning: failed to render timeline section template: \(error)")
            return "<div class=\"timeline-status\">Timeline rendering unavailable.</div>"
        }
    }
}
