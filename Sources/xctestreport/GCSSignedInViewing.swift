import Foundation

/// `--gcs-signed-in-viewing`: lets a report uploaded to a private Google Cloud Storage
/// bucket open through the signed-in `storage.cloud.google.com` link. That link redirects
/// each object to a URL with the whole object name in one encoded segment, which breaks
/// every relative URL in the report; a service worker puts them back. Browsers refuse a
/// worker whose URL contains an encoded slash, so it must be uploaded a second time as
/// the bucket-root object `workerObjectName`. Each page gets a bootstrap that registers
/// it and reloads once it is in control. Anywhere else the bootstrap does nothing.
enum GCSSignedInViewing {
    static let workerFileName = "gcs-viewer-sw.js"
    /// Versioned, so a changed worker never replaces the one older reports rely on.
    static let workerObjectName = "xctestreport-gcs-viewer-sw-v1.js"
    static let marker = "<!-- xctestreport: gcs-signed-in-viewing -->"

    static func install(inReportAt root: String, report: XCTestReport) throws {
        let rootURL = URL(fileURLWithPath: root, isDirectory: true).standardizedFileURL
        let workerSource = try report.webResourceURL(
            named: "gcs-viewer-sw", withExtension: "js", subdirectory: "Web")
        let worker = rootURL.appendingPathComponent("web/\(workerFileName)")
        try FileManager.default.createDirectory(
            at: worker.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: worker.path) {
            try FileManager.default.removeItem(at: worker)
        }
        try FileManager.default.copyItem(at: workerSource, to: worker)

        guard let enumerator = FileManager.default.enumerator(
            at: rootURL, includingPropertiesForKeys: nil) else { return }
        for case let file as URL in enumerator where file.pathExtension.lowercased() == "html" {
            let html = try String(contentsOf: file, encoding: .utf8)
            try injected(into: html)
                .write(to: file, atomically: true, encoding: .utf8)
        }
    }

    /// The page with the bootstrap as the first thing in `<head>`, so it runs before any
    /// stylesheet or script is requested. Already-injected pages are left alone.
    static func injected(into html: String) -> String {
        guard !html.contains(marker) else { return html }
        let script = marker + "<script>" + bootstrap() + "</script>"
        if let head = html.range(of: "<head>", options: .caseInsensitive) {
            var result = html
            result.insert(contentsOf: script, at: head.upperBound)
            return result
        }
        return script + html
    }

    static func bootstrap() -> String {
        // Hidden until the worker is in control: the first load's relative requests 404.
        return """
        (function(){var m=location.pathname.match(/^(\\/download\\/storage\\/v1\\/b\\/[^\\/]+\\/o\\/)([^\\/]*%2[fF][^\\/]*)$/);\
        if(!m||!navigator.serviceWorker||navigator.serviceWorker.controller)return;\
        var root=document.documentElement;root.style.visibility="hidden";\
        var show=function(){root.style.visibility="";};setTimeout(show,8000);\
        navigator.serviceWorker.addEventListener("controllerchange",function(){location.reload();});\
        navigator.serviceWorker.register(m[1]+"\(workerObjectName)",{scope:m[1]}).catch(function(e){show();console.error(e);});})();
        """
    }
}
