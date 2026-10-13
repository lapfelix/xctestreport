import SwiftUI

// This app has no network, permissions, clock-dependent content, or persisted state.
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
                Spacer()
                Text("xcresult fixture • offline • deterministic")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .navigationTitle("Result Fixture")
        }
    }
}
