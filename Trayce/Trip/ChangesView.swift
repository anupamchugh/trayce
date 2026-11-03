import QuickLook
import SwiftUI
import TrayceCore

struct ChangesView: View {
    @Environment(TripStore.self) private var store
    let trip: Trip
    @State private var preview: URL?

    var body: some View {
        List {
            Section {
                ForEach(trip.changes, id: \.field) { change in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(change.field).font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Text(change.old).strikethrough().foregroundStyle(.secondary)
                            Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                            Text(change.new).bold().foregroundStyle(.orange)
                        }
                    }
                }
            } header: {
                Text("PNR \(trip.current.booking.pnr) · \(trip.current.booking.origin) → \(trip.current.booking.destination) · \(trip.all.count) documents")
            }

            Section("Documents") {
                ForEach(trip.all) { doc in
                    Button {
                        preview = store.fileURL(for: doc)
                    } label: {
                        LabeledContent {
                            Text(doc.id == trip.current.id ? "Current" : "Stale")
                                .foregroundStyle(doc.id == trip.current.id ? .green : .secondary)
                        } label: {
                            Text(doc.fileName)
                            Text("\(doc.source.label) · issued \((doc.booking.issuedAt ?? doc.receivedAt).formatted(date: .abbreviated, time: .shortened))")
                        }
                    }
                }
            }

            Section {
                Label("Before you leave, check the date with the airline's app or website too. Trayce only compares the documents you gave it.",
                      systemImage: "info.circle")
                    .font(.footnote)
            }
        }
        .navigationTitle("What changed")
        .quickLookPreview($preview)
    }
}
