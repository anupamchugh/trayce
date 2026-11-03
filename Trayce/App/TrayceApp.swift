import SwiftUI
import TrayceCore

@main
struct TrayceApp: App {
    @State private var store = TripStore()
    @State private var bag = BagCheckModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(bag)
                // "Open in Trayce" from the WhatsApp or Mail share sheet lands here.
                .onOpenURL { url in
                    Task { await store.importFile(at: url, source: .files) }
                }
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Trip", systemImage: "airplane.departure") { TripTodayView() }
            Tab("Bag", systemImage: "suitcase") { BagCheckView() }
            Tab("Showcase", systemImage: "sparkles") { ShowcaseView() }
        }
    }
}
