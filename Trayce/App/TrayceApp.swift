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
    @Environment(TripStore.self) private var store
    @Environment(BagCheckModel.self) private var bag
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            Tab("Trip", systemImage: "airplane.departure", value: 0) { TripTodayView() }
            Tab("Bag", systemImage: "suitcase", value: 1) { BagCheckView() }
            Tab("Showcase", systemImage: "sparkles", value: 2) { ShowcaseView() }
        }
        .task { await runDemoArguments() }
        .fullScreenCover(item: $demoScreen) { screen in
            NavigationStack { demoView(screen) }
        }
    }

    @State private var demoScreen: DemoScreen?

    enum DemoScreen: String, Identifiable {
        case changes, boarding, tray, plane, markup, ask, size, traffic
        var id: String { rawValue }
    }

    @ViewBuilder
    private func demoView(_ screen: DemoScreen) -> some View {
        switch screen {
        case .changes: if let trip = store.nextTrip { ChangesView(trip: trip) }
        case .boarding: if let trip = store.nextTrip { BoardingView(trip: trip) }
        case .tray: TrayPlanView()
        case .plane: PlaneView()
        case .markup: MarkupView()
        case .ask: AskView()
        case .size: BagMeasureView()
        case .traffic: TrafficView()
        }
    }

    /// Launch arguments for screenshots and UI checks:
    /// `-demoSample` loads the sample trip, `-demoBag` runs the sample pack check, `-demoTab N` picks a tab.
    private func runDemoArguments() async {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-demoTab"), i + 1 < args.count, let n = Int(args[i + 1]) { tab = n }
        if args.contains("-demoSample"), store.documents.isEmpty { await store.loadSampleTrip() }
        if args.contains("-demoBag") { await bag.analyse(SampleFlatLay.render()) }
        if let i = args.firstIndex(of: "-demoScreen"), i + 1 < args.count { demoScreen = DemoScreen(rawValue: args[i + 1]) }
    }
}
