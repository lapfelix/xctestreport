import Dispatch
import Foundation
import Gzip
import libzstd

extension XCTestReport {
    func videoMimeType(for fileName: String) -> String {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        switch ext {
        case "mov":
            return "video/quicktime"
        case "m4v":
            return "video/x-m4v"
        default:
            return "video/mp4"
        }
    }

    func isVideoAttachment(_ attachment: AttachmentManifestItem) -> Bool {
        let ext = URL(fileURLWithPath: attachment.exportedFileName).pathExtension.lowercased()
        if ["mp4", "mov", "m4v"].contains(ext) {
            return true
        }

        if let humanReadableName = attachment.suggestedHumanReadableName?.lowercased(),
            humanReadableName.contains("screen recording")
        {
            return true
        }

        return false
    }

    func parseSnapshotTimestamp(from label: String) -> Double? {
        let patterns = [
            ("'UI Snapshot 'yyyy-MM-dd 'at' h.mm.ss a", "UI Snapshot "),
            ("'Screenshot 'yyyy-MM-dd 'at' h.mm.ss a", "Screenshot "),
        ]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current

        for (format, prefix) in patterns where label.hasPrefix(prefix) {
            formatter.dateFormat = format
            if let date = formatter.date(from: label) {
                return date.timeIntervalSince1970
            }
        }

        return nil
    }

    func isScreenshotAttachment(_ attachment: AttachmentManifestItem) -> Bool {
        let ext = URL(fileURLWithPath: attachment.exportedFileName).pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "heic", "gif", "webp", "tiff", "bmp"].contains(ext) {
            return true
        }

        if let humanReadableName = attachment.suggestedHumanReadableName?.lowercased(),
            humanReadableName.contains("snapshot")
                || humanReadableName.contains("screenshot")
        {
            return true
        }

        return false
    }

    func attachmentFileExtension(from relativePath: String?) -> String {
        guard let relativePath else { return "" }
        let fileName = attachmentFileName(fromRelativePath: relativePath)
        let extensionValue = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        guard extensionValue == "gz" else { return extensionValue }
        let uncompressedFileName = (fileName as NSString).deletingPathExtension
        return URL(fileURLWithPath: uncompressedFileName).pathExtension.lowercased()
    }

    func attachmentPreviewKind(name: String, relativePath: String?) -> String {
        let ext = attachmentFileExtension(from: relativePath)
        if ["png", "jpg", "jpeg", "heic", "gif", "webp", "tiff", "bmp"].contains(ext) {
            return "image"
        }
        if ["mp4", "mov", "m4v"].contains(ext) {
            return "video"
        }
        if ext == "pdf" {
            return "pdf"
        }
        if ["json"].contains(ext) {
            return "json"
        }
        if ["txt", "log", "crash", "ips", "plist"].contains(ext) {
            return "text"
        }
        if ["html", "htm"].contains(ext) {
            return "html"
        }

        let lowered = name.lowercased()
        if lowered.contains("screen recording") {
            return "video"
        }
        if lowered.contains("screenshot") {
            return "image"
        }
        if lowered.contains("ui snapshot")
            || lowered.contains("kxctattachmentlegacysnapshot")
            || lowered.contains("synthesized event")
            || lowered.contains("kxctattachmentlegacysynthesizedevent")
            || lowered.contains("app ui hierarchy")
        {
            return "plist"
        }

        return "file"
    }

    func preferredAttachmentPreviewPath(name: String, relativePath: String?) -> String? {
        _ = name
        return relativePath
    }

    func inlineAttachmentPreviewHTML(name: String, previewRelativePath: String?) -> String {
        _ = name
        _ = previewRelativePath
        return ""
    }

    func cleanedAttachmentLabel(_ rawName: String) -> String {
        let lowered = rawName.lowercased()

        if lowered.contains("kxctattachmentlegacysnapshot") || lowered.contains("ui snapshot")
            || lowered.contains("screenshot")
        {
            return "UI Snapshot"
        }
        if lowered.contains("kxctattachmentlegacysynthesizedevent")
            || lowered.contains("synthesized event")
        {
            return "Synthesized Event"
        }
        if lowered.contains("app ui hierarchy") {
            return "UI Hierarchy"
        }
        if lowered.contains("debug description") {
            return "Debug Description"
        }
        if lowered.contains("screen recording") {
            return "Screen Recording"
        }

        let withoutDate = rawName.replacingOccurrences(
            of: #" \d{4}-\d{2}-\d{2} at \d{1,2}\.\d{2}\.\d{2} [AP]M"#,
            with: "",
            options: .regularExpression
        )
        let trimmed = withoutDate.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? rawName : trimmed
    }

    func isSynthesizedEventAttachmentName(_ rawName: String) -> Bool {
        let lowered = rawName.lowercased()
        return lowered.contains("synthesized event")
            || lowered.contains("kxctattachmentlegacysynthesizedevent")
            || lowered.contains("synthesizedevent")
    }

    func attachmentIconLabel(for previewKind: String) -> String {
        switch previewKind {
        case "image":
            return "IMG"
        case "video":
            return "VID"
        case "pdf":
            return "PDF"
        case "json":
            return "JSON"
        case "text":
            return "TXT"
        case "plist":
            return "TXT"
        case "html":
            return "WEB"
        default:
            return "FILE"
        }
    }

    func hierarchySnapshotDisplayLabel(from attachmentName: String) -> String {
        let prefix = "app ui hierarchy for "
        let lowered = attachmentName.lowercased()
        guard let range = lowered.range(of: prefix) else { return "UI Hierarchy" }

        let startIndex = range.upperBound
        let originalSuffix = attachmentName[startIndex...].trimmingCharacters(
            in: .whitespacesAndNewlines)
        guard !originalSuffix.isEmpty else { return "UI Hierarchy" }

        let components = originalSuffix.split(separator: ".").map { String($0) }
        if let last = components.last, !last.isEmpty {
            return "UI Hierarchy (\(last))"
        }
        return "UI Hierarchy (\(originalSuffix))"
    }

    func parseHierarchyInlineProperties(_ metadata: String) -> [String: String] {
        let pattern =
            #"(identifier|label|value|title|placeholderValue|hint|traits):\s*(?:'([^']*)'|([^,]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }
        let nsRange = NSRange(metadata.startIndex..<metadata.endIndex, in: metadata)
        let matches = regex.matches(in: metadata, range: nsRange)
        guard !matches.isEmpty else { return [:] }

        var properties = [String: String]()
        for match in matches {
            guard let keyRange = Range(match.range(at: 1), in: metadata) else { continue }
            let key = String(metadata[keyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            var value = ""
            if let quotedRange = Range(match.range(at: 2), in: metadata) {
                value = String(metadata[quotedRange])
            } else if let plainRange = Range(match.range(at: 3), in: metadata) {
                if plainRange.lowerBound != plainRange.upperBound {
                    value = String(metadata[plainRange])
                }
            }

            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty, !trimmedValue.isEmpty {
                properties[key] = trimmedValue
            }
        }

        return properties
    }

    func splitHierarchyRoleAndName(_ value: String) -> (role: String, name: String?) {
        guard let openParen = value.lastIndex(of: "("), value.hasSuffix(")"),
            openParen > value.startIndex
        else { return (value, nil) }

        let rolePart = value[..<openParen].trimmingCharacters(in: .whitespacesAndNewlines)
        let namePart = value[value.index(after: openParen)..<value.index(before: value.endIndex)]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rolePart.isEmpty else { return (value, nil) }
        return (rolePart, namePart.isEmpty ? nil : namePart)
    }

    func parseHierarchyElementIdentifier(from line: String) -> String? {
        let pattern = #"elementOrHash\.elementID:\s*([0-9.]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: nsRange),
            let valueRange = Range(match.range(at: 1), in: line)
        else { return nil }
        return String(line[valueRange])
    }

    func parseUIHierarchySnapshot(
        at filePath: String, snapshotId: String, label: String, timestamp: Double,
        failureAssociated: Bool
    ) -> UIHierarchySnapshot? {
        guard let data = readAttachmentData(at: filePath),
            let content = String(data: data, encoding: .utf8)
        else { return nil }

        let linePattern =
            #"^(\s*)(.+?),\s*0x[0-9A-Fa-f]+,\s*\{\{(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)\},\s*\{(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)\}\}(?:,\s*(.*?))?\s*<.*$"#
        guard let lineRegex = try? NSRegularExpression(pattern: linePattern) else { return nil }

        var elements = [UIHierarchyElement]()
        elements.reserveCapacity(128)
        var snapshotWidth: Double = 0
        var snapshotHeight: Double = 0
        var maxRight: Double = 0
        var maxBottom: Double = 0

        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for (index, line) in lines.enumerated() {
            let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = lineRegex.firstMatch(in: line, range: nsRange) else { continue }

            func capture(_ group: Int) -> String? {
                guard let range = Range(match.range(at: group), in: line) else { return nil }
                return String(line[range])
            }

            let indent = capture(1) ?? ""
            let rawRole = (capture(2) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawRole.isEmpty else { continue }
            guard let x = Double(capture(3) ?? ""), let y = Double(capture(4) ?? ""),
                let width = Double(capture(5) ?? ""), let height = Double(capture(6) ?? "")
            else { continue }

            let metadata = (capture(7) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let depth = max(0, indent.count / 2)
            let (role, name) = splitHierarchyRoleAndName(rawRole)
            var properties = parseHierarchyInlineProperties(metadata)
            let labelValue = properties["label"]
            let identifierValue = properties["identifier"]
            let valueValue = properties["value"]
            let elementIdentifier =
                parseHierarchyElementIdentifier(from: line)
                ?? "\(snapshotId)-\(index + 1)"

            if !metadata.isEmpty {
                properties["metadata"] = metadata
            }
            properties["frame"] = "{{\(x), \(y)}, {\(width), \(height)}}"
            properties["depth"] = String(depth)

            if snapshotWidth <= 0, snapshotHeight <= 0, role.lowercased().hasPrefix("window"),
                width > 1, height > 1
            {
                snapshotWidth = width
                snapshotHeight = height
            }
            maxRight = max(maxRight, x + width)
            maxBottom = max(maxBottom, y + height)

            elements.append(
                UIHierarchyElement(
                    id: elementIdentifier,
                    depth: depth,
                    role: role,
                    name: name,
                    label: labelValue,
                    identifier: identifierValue,
                    value: valueValue,
                    x: x,
                    y: y,
                    width: width,
                    height: height,
                    properties: properties
                ))
        }

        guard !elements.isEmpty else { return nil }

        let normalizedWidth = snapshotWidth > 1 ? snapshotWidth : maxRight
        let normalizedHeight = snapshotHeight > 1 ? snapshotHeight : maxBottom
        guard normalizedWidth > 1, normalizedHeight > 1 else { return nil }

        return UIHierarchySnapshot(
            id: snapshotId,
            label: label,
            time: timestamp,
            width: normalizedWidth,
            height: normalizedHeight,
            failureAssociated: failureAssociated,
            elements: elements
        )
    }

    func jsStringEscape(_ input: String) -> String {
        return input
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
    }

    func formatTimelineOffset(_ offset: Double) -> String {
        let safeSeconds = max(0, Int(offset.rounded()))
        let hours = safeSeconds / 3600
        let minutes = (safeSeconds % 3600) / 60
        let seconds = safeSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    struct ActivityAttachmentReference {
        let name: String
        let payloadId: String?
        let timestamp: Double?
        let runIndex: Int
    }

    func collectActivityAttachmentReferences(
        from activities: [TestActivity],
        runIndex: Int,
        into storage: inout [ActivityAttachmentReference]
    ) {
        for activity in activities {
            for attachment in activity.attachments ?? [] {
                storage.append(
                    ActivityAttachmentReference(
                        name: attachment.name,
                        payloadId: attachment.payloadId,
                        timestamp: attachment.timestamp,
                        runIndex: runIndex
                    )
                )
            }
            if let children = activity.childActivities {
                collectActivityAttachmentReferences(
                    from: children,
                    runIndex: runIndex,
                    into: &storage
                )
            }
        }
    }

    func collectActivityAttachmentTimestamps(
        from activities: [TestActivity], into storage: inout [String: [Double]]
    ) {
        for activity in activities {
            for attachment in activity.attachments ?? [] {
                guard let timestamp = attachment.timestamp else { continue }
                storage[attachment.name, default: []].append(timestamp)
            }
            if let children = activity.childActivities {
                collectActivityAttachmentTimestamps(from: children, into: &storage)
            }
        }
    }

    func collectEarliestActivityTimestamp(from activities: [TestActivity]) -> Double? {
        var earliest: Double?

        func traverse(_ nodes: [TestActivity]) {
            for node in nodes {
                if let start = node.startTime {
                    if earliest == nil || start < earliest! {
                        earliest = start
                    }
                }

                for attachment in node.attachments ?? [] {
                    if let timestamp = attachment.timestamp {
                        if earliest == nil || timestamp < earliest! {
                            earliest = timestamp
                        }
                    }
                }

                if let children = node.childActivities {
                    traverse(children)
                }
            }
        }

        traverse(activities)
        return earliest
    }

    func keyedArchiveUIDIndex(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if let directInt = value as? Int { return directInt }

        let description = String(describing: value)
        guard let markerRange = description.range(of: "value = ") else { return nil }
        let suffix = description[markerRange.upperBound...]
        let digits = suffix.prefix { $0.isWholeNumber }
        return digits.isEmpty ? nil : Int(digits)
    }

    func keyedArchiveObject(_ reference: Any?, objects: [Any]) -> Any? {
        guard let reference else { return nil }
        if let index = keyedArchiveUIDIndex(reference), index >= 0, index < objects.count {
            return objects[index]
        }
        return reference
    }

    func keyedArchiveArray(_ reference: Any?, objects: [Any]) -> [Any] {
        guard
            let archiveObject = keyedArchiveObject(reference, objects: objects) as? [String: Any],
            let itemRefs = archiveObject["NS.objects"] as? [Any]
        else { return [] }

        return itemRefs.compactMap { keyedArchiveObject($0, objects: objects) }
    }

    func keyedArchiveDictionary(_ reference: Any?, objects: [Any]) -> [String: Any] {
        guard let archiveObject = keyedArchiveObject(reference, objects: objects) as? [String: Any] else {
            return [:]
        }

        guard
            let keyRefs = archiveObject["NS.keys"] as? [Any],
            let valueRefs = archiveObject["NS.objects"] as? [Any]
        else {
            return archiveObject
        }

        var dictionary = [String: Any](minimumCapacity: min(keyRefs.count, valueRefs.count))
        for index in 0..<min(keyRefs.count, valueRefs.count) {
            guard
                let keyObject = keyedArchiveObject(keyRefs[index], objects: objects),
                let key = keyObject as? String
            else { continue }

            dictionary[key] = keyedArchiveObject(valueRefs[index], objects: objects)
        }
        return dictionary
    }

    func keyedArchiveDouble(_ reference: Any?, objects: [Any]) -> Double? {
        guard let value = keyedArchiveObject(reference, objects: objects) else { return nil }
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            return Double(string)
        }
        return nil
    }

    func decompressGzipData(_ compressedData: Data) -> Data? {
        do {
            return try compressedData.gunzipped()
        } catch {
            return nil
        }
    }

    func decompressZstdData(_ compressedData: Data) -> Data? {
        guard !compressedData.isEmpty else { return Data() }
        guard let stream = ZSTD_createDStream() else { return nil }
        defer { ZSTD_freeDStream(stream) }

        let initResult = ZSTD_initDStream(stream)
        guard ZSTD_isError(initResult) == 0 else { return nil }

        let outputChunkSize = max(1, Int(ZSTD_DStreamOutSize()))
        var outputChunk = [UInt8](repeating: 0, count: outputChunkSize)
        var decompressed = Data()

        let decompressedData: Data? = compressedData.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return Data() }

            var input = ZSTD_inBuffer(
                src: baseAddress,
                size: rawBuffer.count,
                pos: 0
            )

            while input.pos < input.size {
                var producedBytes = 0
                let decodeResult = outputChunk.withUnsafeMutableBytes { outputBytes in
                    var output = ZSTD_outBuffer(
                        dst: outputBytes.baseAddress,
                        size: outputBytes.count,
                        pos: 0
                    )
                    let result = ZSTD_decompressStream(stream, &output, &input)
                    producedBytes = Int(output.pos)
                    return result
                }
                if ZSTD_isError(decodeResult) != 0 {
                    return nil
                }
                if producedBytes > 0 {
                    decompressed.append(contentsOf: outputChunk.prefix(producedBytes))
                }
            }

            return decompressed
        }

        return decompressedData
    }

    func isZstdCompressedData(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        return data[data.startIndex] == 0x28
            && data[data.startIndex.advanced(by: 1)] == 0xB5
            && data[data.startIndex.advanced(by: 2)] == 0x2F
            && data[data.startIndex.advanced(by: 3)] == 0xFD
    }

    func readAttachmentData(at filePath: String) -> Data? {
        let fileURL = URL(fileURLWithPath: filePath)
        if fileURL.pathExtension.caseInsensitiveCompare("gz") == .orderedSame {
            guard let compressed = FileManager.default.contents(atPath: filePath) else {
                return nil
            }
            return decompressGzipData(compressed)
        }

        guard let data = FileManager.default.contents(atPath: filePath) else {
            return nil
        }

        if isZstdCompressedData(data) {
            return decompressZstdData(data)
        }

        return data
    }

    func parseSynthesizedEventGesture(
        at filePath: String, baseTimestamp: Double
    ) -> TouchGestureOverlay? {
        guard let data = readAttachmentData(at: filePath) else { return nil }
        let plistObject = (try? PropertyListSerialization.propertyList(
            from: data, options: [], format: nil))
        guard let plistObject else { return nil }

        guard
            let root = plistObject as? [String: Any],
            let objects = root["$objects"] as? [Any],
            let top = root["$top"] as? [String: Any],
            let rootArchiveObject = keyedArchiveObject(top["root"], objects: objects) as? [String: Any]
        else { return nil }

        let parentWindow = keyedArchiveDictionary(
            rootArchiveObject["parentWindowSize"], objects: objects)
        let width = (parentWindow["Width"] as? NSNumber)?.doubleValue ?? 0
        let height = (parentWindow["Height"] as? NSNumber)?.doubleValue ?? 0
        let hasUsableWindowBounds = width > 1 && height > 1

        let eventPaths = keyedArchiveArray(rootArchiveObject["eventPaths"], objects: objects)
        guard !eventPaths.isEmpty else { return nil }

        var points = [TouchGesturePoint]()
        points.reserveCapacity(16)

        for eventPathObject in eventPaths {
            guard let eventPath = eventPathObject as? [String: Any] else { continue }
            let pointerEvents = keyedArchiveArray(eventPath["pointerEvents"], objects: objects)

            for pointerEventObject in pointerEvents {
                guard let pointerEvent = pointerEventObject as? [String: Any] else { continue }
                guard
                    let x = keyedArchiveDouble(pointerEvent["coordinate.x"], objects: objects),
                    let y = keyedArchiveDouble(pointerEvent["coordinate.y"], objects: objects)
                else { continue }

                let offset = keyedArchiveDouble(pointerEvent["offset"], objects: objects) ?? 0
                let pointX =
                    hasUsableWindowBounds
                    ? min(max(0, x), width)
                    : max(0, x)
                let pointY =
                    hasUsableWindowBounds
                    ? min(max(0, y), height)
                    : max(0, y)
                let absoluteTime = baseTimestamp + max(0, offset)
                points.append(TouchGesturePoint(time: absoluteTime, x: pointX, y: pointY))
            }
        }

        guard !points.isEmpty else { return nil }
        let hasMeaningfulPoint = points.contains { point in
            abs(point.x) > 0.5 || abs(point.y) > 0.5
        }
        guard hasMeaningfulPoint else { return nil }
        points.sort { $0.time < $1.time }

        guard let first = points.first, let last = points.last else { return nil }
        return TouchGestureOverlay(
            startTime: first.time,
            endTime: last.time,
            width: width,
            height: height,
            points: points
        )
    }

    func parseSynthesizedEventTimestamp(from label: String) -> Double? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "'Synthesized Event 'yyyy-MM-dd 'at' h.mm.ss a"
        return formatter.date(from: label)?.timeIntervalSince1970
    }

    func buildTouchGestures(
        from nodes: [TimelineNode],
        testIdentifier: String,
        attachmentsByTestIdentifier: [String: [AttachmentManifestItem]],
        includeManifestFallback: Bool = true
    ) -> [TouchGestureOverlay] {
        var flatNodes = [TimelineNode]()
        flattenTimelineNodes(nodes, into: &flatNodes)

        let attachmentRoot = (outputDir as NSString).appendingPathComponent("attachments")
        var parsedCache = [String: TouchGestureOverlay?]()
        var gestures = [TouchGestureOverlay]()
        var seenGestureKeys = Set<String>()
        var seenExportedFiles = Set<String>()
        let synthesizedEventTimestamps = flatNodes.compactMap { node -> Double? in
            guard node.title.localizedCaseInsensitiveContains("synthesize event") else { return nil }
            return node.timestamp
        }

        func nearestSynthesizedEventTimestamp(for timestamp: Double) -> Double? {
            guard !synthesizedEventTimestamps.isEmpty else { return nil }
            var bestTimestamp: Double?
            var bestDistance = Double.greatestFiniteMagnitude
            for candidate in synthesizedEventTimestamps {
                let distance = abs(candidate - timestamp)
                if distance < bestDistance {
                    bestDistance = distance
                    bestTimestamp = candidate
                }
            }

            let maxSynthesizedAnchorSkew: Double = 1.2
            if bestDistance > maxSynthesizedAnchorSkew {
                return nil
            }
            return bestTimestamp
        }

        for node in flatNodes {
            for attachment in node.attachments {
                guard
                    isSynthesizedEventAttachmentName(attachment.name),
                    let relativePath = attachment.relativePath
                else { continue }

                let fileName = attachmentFileName(fromRelativePath: relativePath)
                let filePath = (attachmentRoot as NSString).appendingPathComponent(fileName)
                let baseTimestamp = attachment.timestamp ?? node.timestamp
                guard let baseTimestamp else { continue }

                seenExportedFiles.insert(fileName)
                let cacheKey = "\(filePath)|\(String(format: "%.6f", baseTimestamp))"
                let overlay: TouchGestureOverlay?
                if let cached = parsedCache[cacheKey] {
                    overlay = cached
                } else {
                    let parsed = parseSynthesizedEventGesture(
                        at: filePath, baseTimestamp: baseTimestamp)
                    parsedCache[cacheKey] = parsed
                    overlay = parsed
                }

                guard let overlay else { continue }
                guard !seenGestureKeys.contains(cacheKey) else { continue }
                seenGestureKeys.insert(cacheKey)
                gestures.append(overlay)
            }
        }

        if includeManifestFallback {
            for attachment in attachmentsByTestIdentifier[testIdentifier] ?? [] {
                let label = attachment.suggestedHumanReadableName ?? attachment.exportedFileName
                guard isSynthesizedEventAttachmentName(label) else { continue }
                guard !seenExportedFiles.contains(attachment.exportedFileName) else { continue }
                guard
                    let baseTimestamp =
                        attachment.timestamp ?? parseSynthesizedEventTimestamp(from: label)
                else { continue }

                let filePath = (attachmentRoot as NSString).appendingPathComponent(
                    attachment.exportedFileName)
                let cacheKey = "\(filePath)|\(String(format: "%.6f", baseTimestamp))"
                let overlay: TouchGestureOverlay?
                if let cached = parsedCache[cacheKey] {
                    overlay = cached
                } else {
                    let parsed = parseSynthesizedEventGesture(
                        at: filePath, baseTimestamp: baseTimestamp)
                    parsedCache[cacheKey] = parsed
                    overlay = parsed
                }

                guard let overlay else { continue }
                guard !seenGestureKeys.contains(cacheKey) else { continue }
                seenGestureKeys.insert(cacheKey)
                gestures.append(overlay)
                seenExportedFiles.insert(attachment.exportedFileName)
            }
        }

        let alignedGestures = gestures.map { gesture -> TouchGestureOverlay in
            let duration = max(0, gesture.endTime - gesture.startTime)
            let pathDistance = gesture.points.enumerated().reduce(0.0) {
                partial, entry in
                let index = entry.offset
                guard index > 0 else { return partial }
                let current = entry.element
                let previous = gesture.points[index - 1]
                return partial + hypot(current.x - previous.x, current.y - previous.y)
            }
            let displacement: Double = {
                guard let first = gesture.points.first, let last = gesture.points.last else { return 0 }
                return hypot(last.x - first.x, last.y - first.y)
            }()
            let isTapLike =
                duration <= 0.09
                && displacement <= 12
                && pathDistance <= 12
                && gesture.points.count <= 3
            guard isTapLike else { return gesture }

            guard let synthesizedAnchor = nearestSynthesizedEventTimestamp(for: gesture.startTime)
            else { return gesture }

            // Attachments often timestamp synthesized events at completion.
            // Pull tap gestures back to the synthesized event activity start when the skew is plausible.
            let skew = gesture.startTime - synthesizedAnchor
            let maxBackshift: Double = 1.2
            guard skew > 0.08, skew <= maxBackshift else { return gesture }
            let shift = -skew

            let shiftedPoints = gesture.points.map { point in
                TouchGesturePoint(time: point.time + shift, x: point.x, y: point.y)
            }

            return TouchGestureOverlay(
                startTime: gesture.startTime + shift,
                endTime: gesture.endTime + shift,
                width: gesture.width,
                height: gesture.height,
                points: shiftedPoints
            )
        }

        let fallbackSizeGesture = alignedGestures.first { $0.width > 1 && $0.height > 1 }
        let fallbackWidth = fallbackSizeGesture?.width ?? 402
        let fallbackHeight = fallbackSizeGesture?.height ?? 874

        let normalizedGestures = alignedGestures.map { gesture -> TouchGestureOverlay in
            guard gesture.width <= 1 || gesture.height <= 1 else { return gesture }

            let maxX = gesture.points.map(\.x).max() ?? 0
            let maxY = gesture.points.map(\.y).max() ?? 0
            let inferredWidth = max(fallbackWidth, maxX + 1)
            let inferredHeight = max(fallbackHeight, maxY + 1)

            return TouchGestureOverlay(
                startTime: gesture.startTime,
                endTime: gesture.endTime,
                width: inferredWidth,
                height: inferredHeight,
                points: gesture.points
            )
        }

        let sortedGestures = normalizedGestures.sorted { $0.startTime < $1.startTime }
        return sortedGestures
    }

    func buildUIHierarchySnapshots(from nodes: [TimelineNode]) -> [UIHierarchySnapshot] {
        var flatNodes = [TimelineNode]()
        flattenTimelineNodes(nodes, into: &flatNodes)

        let attachmentRoot = (outputDir as NSString).appendingPathComponent("attachments")
        var snapshots = [UIHierarchySnapshot]()
        var seenSnapshotKeys = Set<String>()

        for node in flatNodes {
            for attachment in node.attachments {
                guard attachment.name.localizedCaseInsensitiveContains("app ui hierarchy"),
                    let relativePath = attachment.relativePath
                else { continue }

                let fileName = attachmentFileName(fromRelativePath: relativePath)
                let filePath = (attachmentRoot as NSString).appendingPathComponent(fileName)
                guard let timestamp = attachment.timestamp ?? node.timestamp else { continue }

                let snapshotKey = "\(fileName)|\(String(format: "%.6f", timestamp))"
                guard !seenSnapshotKeys.contains(snapshotKey) else { continue }
                seenSnapshotKeys.insert(snapshotKey)

                let label = hierarchySnapshotDisplayLabel(from: attachment.name)
                guard
                    let snapshot = parseUIHierarchySnapshot(
                        at: filePath,
                        snapshotId: snapshotKey.replacingOccurrences(of: "|", with: "_"),
                        label: label,
                        timestamp: timestamp,
                        failureAssociated: attachment.failureAssociated)
                else { continue }
                snapshots.append(snapshot)
            }
        }

        return snapshots.sorted { lhs, rhs in
            if lhs.time == rhs.time { return lhs.label < rhs.label }
            return lhs.time < rhs.time
        }
    }

    func buildAttachmentLookup(
        for testIdentifier: String,
        attachmentsByTestIdentifier: [String: [AttachmentManifestItem]],
        activityTimestampRange: ClosedRange<Double>? = nil
    ) -> [String: [AttachmentManifestItem]] {
        var lookup = [String: [AttachmentManifestItem]]()
        var dedupe = Set<String>()

        func append(_ attachment: AttachmentManifestItem, for key: String) {
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let dedupeKey = "\(trimmed)|\(attachment.exportedFileName)"
            guard !dedupe.contains(dedupeKey) else { return }
            dedupe.insert(dedupeKey)
            lookup[trimmed, default: []].append(attachment)
        }

        let globalAttachmentPadding: Double = 5.0
        for sourceKey in [testIdentifier, ""] {
            for attachment in attachmentsByTestIdentifier[sourceKey] ?? [] {
                if sourceKey.isEmpty, let activityTimestampRange {
                    guard let timestamp = attachment.timestamp else { continue }
                    let paddedRange =
                        (activityTimestampRange.lowerBound - globalAttachmentPadding)
                        ... (activityTimestampRange.upperBound + globalAttachmentPadding)
                    guard paddedRange.contains(timestamp) else { continue }
                }

                if let name = attachment.suggestedHumanReadableName {
                    append(attachment, for: name)
                    append(attachment, for: cleanedAttachmentLabel(name))
                }
            }
        }

        for key in lookup.keys {
            lookup[key]?.sort { lhs, rhs in
                let leftTime = lhs.timestamp ?? .greatestFiniteMagnitude
                let rightTime = rhs.timestamp ?? .greatestFiniteMagnitude
                if leftTime != rightTime { return leftTime < rightTime }
                return lhs.exportedFileName < rhs.exportedFileName
            }
        }

        return lookup
    }

    func buildAttachmentPayloadLookup(
        for testIdentifier: String,
        attachmentsByTestIdentifier: [String: [AttachmentManifestItem]],
        activityTimestampRange: ClosedRange<Double>? = nil
    ) -> [String: AttachmentManifestItem] {
        var lookup = [String: AttachmentManifestItem]()
        let globalAttachmentPadding: Double = 5.0

        for sourceKey in [testIdentifier, ""] {
            for attachment in attachmentsByTestIdentifier[sourceKey] ?? [] {
                if sourceKey.isEmpty, let activityTimestampRange {
                    guard let timestamp = attachment.timestamp else { continue }
                    let paddedRange =
                        (activityTimestampRange.lowerBound - globalAttachmentPadding)
                        ... (activityTimestampRange.upperBound + globalAttachmentPadding)
                    guard paddedRange.contains(timestamp) else { continue }
                }

                guard let payloadRefId = attachment.payloadRefId,
                    !payloadRefId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { continue }
                if lookup[payloadRefId] == nil {
                    lookup[payloadRefId] = attachment
                }
            }
        }

        return lookup
    }

    func resolveAttachmentLookupMatch(
        attachmentName: String,
        attachmentTimestamp: Double?,
        attachmentPayloadId: String?,
        attachmentLookup: [String: [AttachmentManifestItem]],
        attachmentPayloadLookup: [String: AttachmentManifestItem]
    ) -> AttachmentManifestItem? {
        if let attachmentPayloadId,
            let directMatch = attachmentPayloadLookup[attachmentPayloadId]
        {
            return directMatch
        }

        var candidateKeys = [attachmentName]
        let cleanedName = cleanedAttachmentLabel(attachmentName)
        if cleanedName != attachmentName {
            candidateKeys.append(cleanedName)
        }

        let maxTimestampSkew: Double = 1.5

        for key in candidateKeys {
            guard let candidates = attachmentLookup[key], !candidates.isEmpty else { continue }

            if let attachmentTimestamp {
                var bestIndex: Int?
                var bestDistance = Double.greatestFiniteMagnitude
                for index in 0..<candidates.count {
                    let candidate = candidates[index]
                    let candidateTimestamp = candidate.timestamp ?? attachmentTimestamp
                    let distance = abs(candidateTimestamp - attachmentTimestamp)
                    if distance < bestDistance {
                        bestDistance = distance
                        bestIndex = index
                    }
                }

                guard let bestIndex else { continue }
                guard bestDistance <= maxTimestampSkew else { continue }

                return candidates[bestIndex]
            }

            return candidates.first
        }

        return nil
    }

    func buildVideoSources(
        for testIdentifier: String, activities: TestActivities?,
        attachmentsByTestIdentifier: [String: [AttachmentManifestItem]]
    ) -> [VideoSource] {
        let allAttachments = attachmentsByTestIdentifier[testIdentifier] ?? []
        let videoAttachments = allAttachments.filter { isVideoAttachment($0) }
        guard !videoAttachments.isEmpty else { return [] }

        let activityRuns = activities?.testRuns ?? []
        let rootActivities = activityRuns.flatMap { $0.activities }
        let fallbackStartTime = collectEarliestActivityTimestamp(from: rootActivities)

        var attachmentReferences = [ActivityAttachmentReference]()
        attachmentReferences.reserveCapacity(256)
        if activityRuns.isEmpty {
            collectActivityAttachmentReferences(
                from: rootActivities,
                runIndex: 0,
                into: &attachmentReferences
            )
        } else {
            for (runIndex, run) in activityRuns.enumerated() {
                collectActivityAttachmentReferences(
                    from: run.activities,
                    runIndex: runIndex,
                    into: &attachmentReferences
                )
            }
        }

        var payloadTimestamps = [String: [Double]]()
        var payloadRunIndex = [String: Int]()
        var nameReferences = [String: [ActivityAttachmentReference]]()

        for reference in attachmentReferences {
            nameReferences[reference.name, default: []].append(reference)
            guard let payloadId = reference.payloadId,
                !payloadId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }

            if let timestamp = reference.timestamp {
                payloadTimestamps[payloadId, default: []].append(timestamp)
            }
            if payloadRunIndex[payloadId] == nil {
                payloadRunIndex[payloadId] = reference.runIndex
            }
        }

        func bestNameReference(
            for label: String,
            around timestamp: Double?
        ) -> ActivityAttachmentReference? {
            guard let candidates = nameReferences[label], !candidates.isEmpty else { return nil }
            guard let timestamp else { return candidates.first }

            var bestMatch: ActivityAttachmentReference?
            var bestDistance = Double.greatestFiniteMagnitude
            for candidate in candidates {
                guard let candidateTimestamp = candidate.timestamp else { continue }
                let distance = abs(candidateTimestamp - timestamp)
                if distance < bestDistance {
                    bestDistance = distance
                    bestMatch = candidate
                }
            }
            return bestMatch ?? candidates.first
        }

        return videoAttachments.map { attachment in
            let label = attachment.suggestedHumanReadableName ?? attachment.exportedFileName
            let payloadId = attachment.payloadRefId?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedPayloadId = payloadId?.isEmpty == true ? nil : payloadId

            var resolvedRunIndex: Int? = nil
            var resolvedStartTime: Double? = nil

            if let payloadId = normalizedPayloadId {
                resolvedRunIndex = payloadRunIndex[payloadId]
                resolvedStartTime = payloadTimestamps[payloadId]?.min()
            }

            if let nameMatch = bestNameReference(for: label, around: attachment.timestamp) {
                if resolvedRunIndex == nil {
                    resolvedRunIndex = nameMatch.runIndex
                }
                if resolvedStartTime == nil {
                    resolvedStartTime = nameMatch.timestamp
                }
            }

            let startTime = resolvedStartTime ?? attachment.timestamp ?? fallbackStartTime

            return VideoSource(
                label: label,
                fileName: attachment.exportedFileName,
                mimeType: videoMimeType(for: attachment.exportedFileName),
                startTime: startTime,
                failureAssociated: attachment.isAssociatedWithFailure ?? false,
                runIndex: resolvedRunIndex
            )
        }
    }

    func buildScreenshotSources(
        for testIdentifier: String, activities: TestActivities?,
        attachmentsByTestIdentifier: [String: [AttachmentManifestItem]]
    ) -> [ScreenshotSource] {
        let allAttachments = attachmentsByTestIdentifier[testIdentifier] ?? []
        let screenshotAttachments = allAttachments.filter { isScreenshotAttachment($0) }
        guard !screenshotAttachments.isEmpty else { return [] }

        let rootActivities = activities?.testRuns.flatMap { $0.activities } ?? []
        var attachmentTimestamps = [String: [Double]]()
        collectActivityAttachmentTimestamps(from: rootActivities, into: &attachmentTimestamps)
        let fallbackStartTime = collectEarliestActivityTimestamp(from: rootActivities)

        var seenSources = Set<String>()
        let mapped = screenshotAttachments.compactMap { attachment -> ScreenshotSource? in
            let label = attachment.suggestedHumanReadableName ?? attachment.exportedFileName
            let timestamp =
                attachmentTimestamps[label]?.min() ?? parseSnapshotTimestamp(from: label)
                ?? fallbackStartTime
            guard let timestamp else { return nil }

            let src = attachmentRelativePathForTestPage(fileName: attachment.exportedFileName)
            guard !seenSources.contains(src) else { return nil }
            seenSources.insert(src)

            return ScreenshotSource(
                label: label,
                src: src,
                time: timestamp,
                failureAssociated: attachment.isAssociatedWithFailure ?? false
            )
        }

        return mapped.sorted { lhs, rhs in
            if lhs.time == rhs.time { return lhs.label < rhs.label }
            return lhs.time < rhs.time
        }
    }

    func buildTimelineNodes(
        from activities: [TestActivity],
        attachmentLookup: [String: [AttachmentManifestItem]],
        attachmentPayloadLookup: [String: AttachmentManifestItem],
        sourceLocationBySymbol: [String: SourceLocation],
        nextId: inout Int
    ) -> [TimelineNode] {
        return activities.map { activity in
            let nodeId = "timeline_event_\(nextId)"
            nextId += 1

            var seenAttachments = Set<String>()
            let attachments: [TimelineAttachment] = (activity.attachments ?? []).compactMap {
                attachment -> TimelineAttachment? in
                let matching = resolveAttachmentLookupMatch(
                    attachmentName: attachment.name,
                    attachmentTimestamp: attachment.timestamp,
                    attachmentPayloadId: attachment.payloadId,
                    attachmentLookup: attachmentLookup,
                    attachmentPayloadLookup: attachmentPayloadLookup
                )
                let relativePath =
                    matching != nil
                    ? attachmentRelativePathForTestPage(fileName: matching!.exportedFileName)
                    : nil
                let dedupeKey =
                    relativePath ?? "\(attachment.name)|\(attachment.timestamp ?? -1)"
                guard !seenAttachments.contains(dedupeKey) else { return nil }
                seenAttachments.insert(dedupeKey)

                return TimelineAttachment(
                    name: attachment.name,
                    timestamp: attachment.timestamp,
                    relativePath: relativePath,
                    failureAssociated: matching?.isAssociatedWithFailure ?? false
                )
            }

            let children = buildTimelineNodes(
                from: activity.childActivities ?? [],
                attachmentLookup: attachmentLookup,
                attachmentPayloadLookup: attachmentPayloadLookup,
                sourceLocationBySymbol: sourceLocationBySymbol,
                nextId: &nextId)
            let childStartTimestamp = children.compactMap { $0.timestamp }.min()
            let timestamp =
                activity.startTime ?? attachments.compactMap { $0.timestamp }.min()
                ?? childStartTimestamp
            let childEndTimestamp = children.compactMap { $0.endTimestamp ?? $0.timestamp }.max()
            let attachmentEndTimestamp = attachments.compactMap { $0.timestamp }.max()
            let endTimestamp = [timestamp, childEndTimestamp, attachmentEndTimestamp].compactMap { $0 }
                .max()
            let failureAssociated =
                activity.isAssociatedWithFailure ?? attachments.contains { $0.failureAssociated }
            let sourceLocationLabel = sourceLocationLabelForTimelineTitle(
                activity.title, sourceLocationBySymbol: sourceLocationBySymbol)

            return TimelineNode(
                id: nodeId,
                title: activity.title,
                sourceLocationLabel: sourceLocationLabel,
                timestamp: timestamp,
                endTimestamp: endTimestamp,
                failureAssociated: failureAssociated,
                failureBranchStyle: activity.failureBranchStyle ?? false,
                attachments: attachments,
                children: children,
                repeatCount: 1
            )
        }
    }

    func canMergeTimelineNodes(_ lhs: TimelineNode, _ rhs: TimelineNode) -> Bool {
        return lhs.title == rhs.title
            && lhs.sourceLocationLabel == rhs.sourceLocationLabel
            && lhs.attachments.isEmpty
            && rhs.attachments.isEmpty
            && lhs.children.isEmpty
            && rhs.children.isEmpty
            && lhs.failureAssociated == rhs.failureAssociated
            && lhs.failureBranchStyle == rhs.failureBranchStyle
    }

    func collapseRepeatedTimelineNodes(_ nodes: [TimelineNode]) -> [TimelineNode] {
        let normalizedNodes = nodes.map { node in
            let collapsedChildren = collapseRepeatedTimelineNodes(node.children)
            return TimelineNode(
                id: node.id,
                title: node.title,
                sourceLocationLabel: node.sourceLocationLabel,
                timestamp: node.timestamp,
                endTimestamp: node.endTimestamp ?? node.timestamp,
                failureAssociated: node.failureAssociated,
                failureBranchStyle: node.failureBranchStyle,
                attachments: node.attachments,
                children: collapsedChildren,
                repeatCount: max(node.repeatCount, 1)
            )
        }

        var collapsed = [TimelineNode]()
        var index = 0

        while index < normalizedNodes.count {
            var current = normalizedNodes[index]
            var lookahead = index + 1

            while lookahead < normalizedNodes.count,
                canMergeTimelineNodes(current, normalizedNodes[lookahead])
            {
                let next = normalizedNodes[lookahead]
                current = TimelineNode(
                    id: current.id,
                    title: current.title,
                    sourceLocationLabel: current.sourceLocationLabel,
                    timestamp: current.timestamp ?? next.timestamp,
                    endTimestamp: next.endTimestamp ?? next.timestamp ?? current.endTimestamp,
                    failureAssociated: current.failureAssociated || next.failureAssociated,
                    failureBranchStyle: current.failureBranchStyle || next.failureBranchStyle,
                    attachments: current.attachments,
                    children: current.children,
                    repeatCount: current.repeatCount + next.repeatCount
                )
                lookahead += 1
            }

            collapsed.append(current)
            index = lookahead
        }

        return collapsed
    }

    func flattenTimelineNodes(_ nodes: [TimelineNode], into flat: inout [TimelineNode]) {
        for node in nodes {
            flat.append(node)
            flattenTimelineNodes(node.children, into: &flat)
        }
    }

    func timelineDisplayTitle(_ node: TimelineNode, baseTime: Double?) -> String {
        let sourceLocationLabel = node.sourceLocationLabel
        let baseTitle: String
        if node.repeatCount > 1 {
            if let start = node.timestamp, let end = node.endTimestamp, let baseTime {
                let startText = formatTimelineOffset(start - baseTime)
                let endText = formatTimelineOffset(end - baseTime)
                if let sourceLocationLabel, !sourceLocationLabel.isEmpty {
                    baseTitle = "\(node.title) (\(sourceLocationLabel)) ×\(node.repeatCount) (\(startText)-\(endText))"
                } else {
                    baseTitle = "\(node.title) ×\(node.repeatCount) (\(startText)-\(endText))"
                }
            } else {
                if let sourceLocationLabel, !sourceLocationLabel.isEmpty {
                    baseTitle = "\(node.title) (\(sourceLocationLabel)) ×\(node.repeatCount)"
                } else {
                    baseTitle = "\(node.title) ×\(node.repeatCount)"
                }
            }
        } else {
            if let sourceLocationLabel, !sourceLocationLabel.isEmpty {
                baseTitle = "\(node.title) (\(sourceLocationLabel))"
            } else {
                baseTitle = node.title
            }
        }

        return baseTitle
    }

    func timelineNodeHasInteraction(_ node: TimelineNode) -> Bool {
        let loweredTitle = node.title.lowercased()
        let hasInteractionAttachment = node.attachments.contains {
            $0.name.lowercased().contains("synthesized event")
        }
        return loweredTitle.hasPrefix("tap ")
            || loweredTitle.hasPrefix("swipe ")
            || loweredTitle.contains("synthesize event")
            || hasInteractionAttachment
    }

    func timelineNodeHasHierarchy(_ node: TimelineNode) -> Bool {
        let loweredTitle = node.title.lowercased()
        let hasHierarchyAttachment = node.attachments.contains {
            $0.name.lowercased().contains("app ui hierarchy")
        }
        return loweredTitle.contains("ui hierarchy") || hasHierarchyAttachment
    }

    func timelineEventKind(for node: TimelineNode) -> TimelineEventKind {
        if node.failureAssociated {
            return .error
        }
        if timelineNodeHasInteraction(node) {
            return .tap
        }
        if timelineNodeHasHierarchy(node) {
            return .hierarchy
        }
        return .event
    }

    func renderTimelineNodesHTML(_ nodes: [TimelineNode], baseTime: Double?, depth: Int) -> String {
        let renderedNodes = nodes.map { node -> String in
            let timeLabel: String
            if let timestamp = node.timestamp, let baseTime {
                timeLabel = formatTimelineOffset(timestamp - baseTime)
            } else {
                timeLabel = "--:--"
            }

            let timeAttribute = node.timestamp.map { String(format: "%.6f", $0) } ?? ""
            let hasChildren = !node.children.isEmpty
            let nodeClass = node.failureBranchStyle ? "timeline-node timeline-node-failure-branch" : "timeline-node"
            var eventClassList = ["timeline-event"]
            if node.failureAssociated {
                eventClassList.append("timeline-failure")
            }
            if timelineNodeHasInteraction(node) {
                eventClassList.append("timeline-interaction")
            }
            if timelineNodeHasHierarchy(node) {
                eventClassList.append("timeline-hierarchy")
            }
            if hasChildren {
                eventClassList.append("timeline-has-children")
            }
            let eventClasses = eventClassList.joined(separator: " ")
            let displayTitle = htmlEscape(timelineDisplayTitle(node, baseTime: baseTime))
            let disclosure = hasChildren
                ? "<span class=\"timeline-disclosure\" aria-hidden=\"true\"></span>"
                : "<span class=\"timeline-disclosure timeline-disclosure-placeholder\" aria-hidden=\"true\"></span>"
            let row = """
                <div class="\(eventClasses)" data-event-id="\(node.id)" data-event-time="\(timeAttribute)">
                    \(disclosure)
                    <span class="timeline-title">\(displayTitle)</span>
                    <span class="timeline-time">\(timeLabel)</span>
                </div>
                """

            let attachmentList: String
            if node.attachments.isEmpty {
                attachmentList = ""
            } else {
                let renderedAttachments = node.attachments.map { attachment -> String in
                    let cleanedLabel = cleanedAttachmentLabel(attachment.name)
                    let attachmentName = htmlEscape(cleanedLabel)
                    let previewRelativePath = preferredAttachmentPreviewPath(
                        name: attachment.name, relativePath: attachment.relativePath)
                    let previewKind = attachmentPreviewKind(
                        name: attachment.name, relativePath: previewRelativePath)
                    let iconLabel = attachmentIconLabel(for: previewKind)
                    let linkOrText: String
                    if let relativePath = previewRelativePath {
                        linkOrText = """
                            <a class="timeline-attachment-link" href="\(relativePath)" target="_blank" rel="noopener" data-preview-kind="\(previewKind)" data-preview-title="\(attachmentName)">
                                <span class="timeline-attachment-icon">\(iconLabel)</span>
                                <span class="timeline-attachment-label">\(attachmentName)</span>
                            </a>
                            """
                    } else {
                        linkOrText =
                            "<span class=\"timeline-attachment-link\"><span class=\"timeline-attachment-icon\">\(iconLabel)</span><span class=\"timeline-attachment-label\">\(attachmentName)</span></span>"
                    }

                    let inlinePreview = inlineAttachmentPreviewHTML(
                        name: attachment.name, previewRelativePath: previewRelativePath)
                    return "<li class=\"timeline-attachment\">\(linkOrText)\(inlinePreview)</li>"
                }.joined(separator: "")
                attachmentList = "<ul class=\"timeline-attachments\">\(renderedAttachments)</ul>"
            }

            if node.children.isEmpty {
                return "<li class=\"\(nodeClass)\" style=\"--timeline-depth: \(depth);\">\(row)\(attachmentList)</li>"
            }

            let childHTML = renderTimelineNodesHTML(node.children, baseTime: baseTime, depth: depth + 1)
            return """
                <li class="\(nodeClass)" style="--timeline-depth: \(depth);">
                    <details>
                        <summary>\(row)</summary>
                        \(attachmentList)
                        <ul>\(childHTML)</ul>
                    </details>
                </li>
                """
        }.joined(separator: "")

        return renderedNodes
    }

}
