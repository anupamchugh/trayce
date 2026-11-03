import SwiftUI
import TrayceCore
import UniformTypeIdentifiers

struct TripTodayView: View {
    @Environment(TripStore.self) private var store
    @Environment(BagCheckModel.self) private var bag
    @State private var showingImporter = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let trip = store.nextTrip {
                        FlightCard(trip: trip)
                        TimelineCard(trip: trip, trayCount: bag.trayCount)
                        SourcesCard(trip: trip)
                    } else {
                        ContentUnavailableView {
                            Label("No trip yet", systemImage: "airplane.circle")
                        } description: {
                            Text("Share a booking PDF or screenshot from WhatsApp, Mail or MakeMyTrip with “Open in Trayce”, or add one here.")
                        } actions: {
                            Button("Load sample trip") { Task { await store.loadSampleTrip() } }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(.top, 40)
                    }
                    if let message = store.lastMessage {
                        Text(message).font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Trip today")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Add PDF or screenshot", systemImage: "doc.badge.plus") { showingImporter = true }
                        Button("Load sample trip", systemImage: "wand.and.stars") { Task { await store.loadSampleTrip() } }
                        Button("Remove all documents", systemImage: "trash", role: .destructive) { store.removeAll() }
                    } label: {
                        Label("Add booking", systemImage: "plus")
                    }
                }
            }
            .overlay { if store.isImporting { ProgressView("Reading on this iPhone…").padding().background(.regularMaterial, in: .rect(cornerRadius: 12)) } }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                Task { for url in urls { await store.importFile(at: url, source: .files) } }
            }
        }
    }
}

private struct FlightCard: View {
    let trip: Trip
    private var b: Booking { trip.current.booking }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Flight \(b.flightLabel)").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(trip.needsReview ? "CHECK" : "CURRENT").font(.caption.weight(.bold))
                    .foregroundStyle(trip.needsReview ? .orange : .green)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background((trip.needsReview ? Color.orange : .green).opacity(0.15), in: .capsule)
            }
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading) {
                    Text(b.origin).font(.system(size: 40, weight: .bold))
                    Text(b.departure.formatted(date: .omitted, time: .shortened) + (b.terminal.map { " · \($0)" } ?? ""))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "airplane").foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing) {
                    Text(b.destination).font(.system(size: 40, weight: .bold))
                    Text(b.departure.formatted(.dateTime.weekday().day().month())).foregroundStyle(.secondary)
                }
            }
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 24) {
                GridRow {
                    Text("PNR").foregroundStyle(.secondary)
                    Text("Gate").foregroundStyle(.secondary)
                    Text("Seat").foregroundStyle(.secondary)
                }.font(.caption)
                GridRow {
                    Text(b.pnr)
                    Text(b.gate ?? "—")
                    Text(b.seat ?? "—")
                }.font(.headline)
            }
            if !trip.changes.isEmpty {
                NavigationLink {
                    ChangesView(trip: trip)
                } label: {
                    Label {
                        Text(trip.needsReview
                             ? "Your copies disagree on \(trip.changes.map(\.field).joined(separator: " and ")), and not all show an issue date. Confirm with the airline."
                             : "\(trip.changes.map(\.field).joined(separator: " and ")) changed. \(trip.stale.count) older copy marked stale.")
                            .multilineTextAlignment(.leading)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.12), in: .rect(cornerRadius: 14))
                }
            }
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
    }
}

private struct TimelineCard: View {
    let trip: Trip
    let trayCount: Int
    private var departure: Date { trip.current.booking.departure }

    var body: some View {
        VStack(spacing: 0) {
            row("Leave home", departure.addingTimeInterval(-150 * 60))
            Divider()
            row("Bag drop closes", departure.addingTimeInterval(-45 * 60))
            Divider()
            NavigationLink { TrayPlanView() } label: {
                HStack {
                    Text(trayCount > 0 ? "Security · \(trayCount) trays planned" : "Security · plan your trays")
                    Spacer()
                    Text("Plan").foregroundStyle(.tint)
                }.padding(.vertical, 12)
            }
            Divider()
            NavigationLink { BoardingView(trip: trip) } label: {
                HStack {
                    Text("Boarding")
                    Spacer()
                    Text(departure.addingTimeInterval(-35 * 60).formatted(date: .omitted, time: .shortened)).bold()
                }.padding(.vertical, 12)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 18)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
    }

    private func row(_ title: String, _ date: Date) -> some View {
        HStack { Text(title); Spacer(); Text(date.formatted(date: .omitted, time: .shortened)).bold() }
            .padding(.vertical, 12)
    }
}

/// Where each fact came from: this is what WhatsApp + MakeMyTrip can't show you.
private struct SourcesCard: View {
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BUILT FROM \(trip.all.count) DOCUMENT\(trip.all.count == 1 ? "" : "S")")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(trip.all) { doc in
                HStack {
                    Image(systemName: doc.id == trip.current.id ? "checkmark.seal.fill" : "clock.badge.xmark")
                        .foregroundStyle(doc.id == trip.current.id ? .green : .secondary)
                    VStack(alignment: .leading) {
                        Text(doc.fileName).font(.subheadline)
                        Text("\(doc.source.label) · issued \((doc.booking.issuedAt ?? doc.receivedAt).formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(doc.id == trip.current.id ? "Current" : "Stale").font(.caption.weight(.semibold))
                        .foregroundStyle(doc.id == trip.current.id ? .green : .secondary)
                }
            }
            Label("Read on this iPhone. Nothing was uploaded.", systemImage: "lock.fill").font(.caption).foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
    }
}
