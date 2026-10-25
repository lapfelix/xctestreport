import SwiftUI
import UIKit

// This app has no network, permissions, visible clock-dependent content, or persisted state.
// Its only job is to give UI tests real interactions and recognizable screenshots.
@main
struct FixtureApp: App {
    var body: some Scene {
        WindowGroup { FixtureScreen() }
    }
}

private struct FixtureScreen: View {
    @State private var pinned = false
    @State private var query = ""
    @StateObject private var touches = TouchLog()
    private let routes = ["Green line", "Orange line", "Blue line"]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Text("Montréal → Downtown")
                    .font(.title2.bold())
                    .accessibilityIdentifier("journey-title")
                TextField("Search routes", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("route-search")
                ForEach(routes.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }, id: \.self) { route in
                    HStack {
                        Image(systemName: "tram.fill")
                        Text(route).font(.headline)
                        Spacer()
                        Text("3 min")
                    }
                    .padding()
                    .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("route-\(route)")
                }
                Button(pinned ? "Unpin route" : "Pin route") { pinned.toggle() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("pin-route")
                Text(pinned ? "Pinned" : "Not pinned")
                    .accessibilityIdentifier("pin-state")
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.12))
                    .frame(height: 120)
                    .accessibilityElement()
                    .accessibilityLabel("Gesture pad")
                    .accessibilityIdentifier("gesture-pad")
                Spacer()
                Text("xcresult fixture • offline • deterministic")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("touch-log")
                    .accessibilityValue(touches.json)
            }
            .padding(24)
            .navigationTitle("Result Fixture")
        }
        // Ground truth for the report's touch overlay: the video shows this bar exactly while
        // a finger is down, and the log records when the app actually received each touch.
        .overlay(alignment: .top) {
            if touches.isTouching {
                Color(red: 1, green: 0, blue: 1).frame(height: 120).ignoresSafeArea()
            }
        }
        .background(TouchObserverInstaller(log: touches))
    }
}

final class TouchLog: ObservableObject {
    struct Touch: Encodable {
        var down: Double
        var up: Double?
        var downPoint: [Double]
        var upPoint: [Double]?
    }

    @Published private(set) var isTouching = false
    @Published private(set) var json = "[]"
    private var touches = [Touch]()

    // UITouch timestamps use system uptime; xcresult timestamps use wall-clock time.
    private func wallClock(_ uptime: TimeInterval) -> Double {
        Date().timeIntervalSince1970 - (ProcessInfo.processInfo.systemUptime - uptime)
    }

    func began(at point: CGPoint, uptime: TimeInterval) {
        touches.append(Touch(down: wallClock(uptime), downPoint: [point.x, point.y]))
        isTouching = true
        publish()
    }

    func ended(at point: CGPoint, uptime: TimeInterval) {
        guard let index = touches.indices.last, touches[index].up == nil else { return }
        touches[index].up = wallClock(uptime)
        touches[index].upPoint = [point.x, point.y]
        isTouching = false
        publish()
    }

    private func publish() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        json = (try? encoder.encode(touches)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }
}

/// Watches every touch in the window without recognizing or delaying any of them.
private final class TouchObserver: UIGestureRecognizer {
    weak var log: TouchLog?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first {
            log?.began(at: touch.location(in: view), uptime: touch.timestamp)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first {
            log?.ended(at: touch.location(in: view), uptime: touch.timestamp)
        }
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        touchesEnded(touches, with: event)
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    // Otherwise a recognizing button fails this observer before its touch-up arrives.
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}

private struct TouchObserverInstaller: UIViewRepresentable {
    let log: TouchLog

    func makeUIView(context: Context) -> InstallerView {
        InstallerView(log: log)
    }

    func updateUIView(_ uiView: InstallerView, context: Context) {}

    final class InstallerView: UIView {
        private let log: TouchLog
        private var installed = false

        init(log: TouchLog) {
            self.log = log
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, !installed else { return }
            let observer = TouchObserver(target: nil, action: nil)
            observer.log = log
            window.addGestureRecognizer(observer)
            installed = true
        }
    }
}
