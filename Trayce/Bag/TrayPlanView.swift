import ActivityKit
import SwiftUI
import TrayceCore

struct TrayPlanView: View {
    @Environment(BagCheckModel.self) private var bag
    @Environment(TripStore.self) private var store
    @State private var message: String?

    var body: some View {
        List {
            if bag.items.isEmpty {
                ContentUnavailableView("No pack check yet", systemImage: "suitcase",
                                       description: Text("Photograph what you're packing in the Bag tab."))
            }
            group("Leave at home") { if case .doNotCarry = $0 { true } else { false } }
            group("Fix before you go") { if case .fix = $0 { true } else { false } }
            if !bag.trayLines.isEmpty {
                Section("At the X-ray") {
                    ForEach(bag.trayLines, id: \.self) { Text($0).bold() }
                }
            }
            group("Stays in your bag") { $0 == .stayInBag }

            Section {
                Text("This only covers the \(bag.items.count) items you showed. Security staff have the final say.")
                Link("Rules for \(bag.rules.country), as of \(bag.rules.asOf)", destination: bag.rules.source)
            }
            .font(.footnote)

            Section {
                Button("Pin tray plan to Lock Screen", systemImage: "lock.rectangle.stack") { pin() }
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Tray plan")
        .onAppear { store.publishWidgetSnapshot(packFlags: bag.flags) }
    }

    @ViewBuilder
    private func group(_ title: String, where match: @escaping (Verdict) -> Bool) -> some View {
        let items = bag.items.filter { match(bag.verdict(for: $0)) }
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { item in
                    VStack(alignment: .leading) {
                        Text(item.observation.kind.label).bold()
                        Text(VerdictText(bag.verdict(for: item)).line).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func pin() {
        guard let trip = store.nextTrip else { message = "Add a trip first."; return }
        let b = trip.current.booking
        let state = TrayceActivityAttributes.ContentState(step: "Security", trays: bag.trayLines,
                                                          boardsAt: b.departure.addingTimeInterval(-35 * 60))
        do {
            _ = try Activity.request(attributes: TrayceActivityAttributes(flight: b.flightLabel, gate: b.gate ?? "—"),
                                     content: ActivityContent(state: state, staleDate: b.departure))
            message = "Pinned to the Lock Screen and Dynamic Island."
        } catch {
            message = "Couldn't start the Live Activity: \(error.localizedDescription)"
        }
    }
}
