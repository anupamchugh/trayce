import Foundation
import Observation
import UIKit
import TrayceCore

/// Every document the traveller shared in, kept on the device, and the trips they resolve to.
@Observable
final class TripStore {
    private(set) var documents: [TripDocument] = []
    private(set) var isImporting = false
    var lastMessage: String?

    var trips: [Trip] { SupersedeResolver.trips(from: documents) }
    /// The next flight that hasn't left yet (with a 1-hour grace for delays), or none.
    var nextTrip: Trip? { trips.first { $0.current.booking.departure > .now.addingTimeInterval(-3600) } }
    private var packFlags: [String] = []

    private let folder: URL
    private var indexURL: URL { folder.appending(path: "documents.json") }

    init() {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id)
            ?? URL.documentsDirectory
        folder = base.appending(path: "Trips", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL) {
            documents = (try? JSONDecoder().decode([TripDocument].self, from: data)) ?? []
        }
    }

    func fileURL(for document: TripDocument) -> URL {
        folder.appending(path: "\(document.id.uuidString).\((document.fileName as NSString).pathExtension.lowercased())")
    }

    func barcodeImage(for document: TripDocument) -> UIImage? {
        UIImage(contentsOfFile: folder.appending(path: "\(document.id.uuidString)-barcode.png").path)
    }

    /// Reads a shared PDF or screenshot on the device and adds it to its trip.
    func importFile(at url: URL, source: DocumentSource, receivedAt: Date = .now) async {
        isImporting = true
        defer { isImporting = false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let read = try await DocumentReader.read(url)
            guard let extraction = await BookingExtractor.extract(from: read.text) else {
                lastMessage = "Couldn't find a PNR, flight and date in \(url.lastPathComponent)."
                return
            }
            // The same booking shared again (same facts, same issue date) is not a new copy.
            if documents.contains(where: { $0.booking == extraction.booking }) {
                lastMessage = "Already saved: \(extraction.booking.pnr) \(extraction.booking.flightLabel), nothing changed."
                return
            }
            let id = UUID()
            // Keep a barcode only if it belongs to this booking.
            let payload = read.barcodePayload.flatMap { p in
                BCBPParser.parse(p).map { $0.pnr == extraction.booking.pnr } == true ? p : nil
            }
            let document = TripDocument(id: id, fileName: url.lastPathComponent, source: source,
                                        receivedAt: receivedAt, booking: extraction.booking,
                                        barcodePayload: payload)
            try FileManager.default.copyItem(at: url, to: fileURL(for: document))
            if payload != nil, let crop = read.barcodeImage {
                try UIImage(cgImage: crop).pngData()?.write(to: folder.appending(path: "\(id.uuidString)-barcode.png"))
            }
            documents.append(document)
            save()
            let trip = trips.first { $0.id == SupersedeResolver.legKey(document.booking) }
            if let trip, trip.needsReview {
                lastMessage = "These copies disagree and don't all show an issue date. Check \(document.booking.pnr) with the airline."
            } else if let trip, trip.current.id != id {
                lastMessage = "Saved as an older copy. A newer document for \(document.booking.pnr) already exists."
            } else if let trip, !trip.changes.isEmpty {
                lastMessage = "This replaces an older copy: " + trip.changes.map { "\($0.field) \($0.old) → \($0.new)" }.joined(separator: ", ")
            } else {
                lastMessage = "Read \(extraction.method). Added \(document.booking.flightLabel)."
            }
        } catch {
            lastMessage = "Couldn't read \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// Imports the two synthetic sample tickets: an older WhatsApp copy and the newer re-issue.
    func loadSampleTrip() async {
        for sample in SampleDocuments.make() {
            await importFile(at: sample.url, source: sample.source, receivedAt: sample.receivedAt)
        }
    }

    func removeAll() {
        for d in documents {
            try? FileManager.default.removeItem(at: fileURL(for: d))
            try? FileManager.default.removeItem(at: folder.appending(path: "\(d.id.uuidString)-barcode.png"))
        }
        documents = []
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(documents) { try? data.write(to: indexURL) }
        publishWidgetSnapshot()
    }

    /// Pass new pack flags from the tray plan; leave nil to keep the last ones.
    func publishWidgetSnapshot(packFlags flags: [String]? = nil) {
        if let flags { packFlags = flags }
        guard let trip = nextTrip else {
            AppGroup.defaults.removeObject(forKey: WidgetSnapshot.key)
            return
        }
        let b = trip.current.booking
        WidgetSnapshot(route: "\(b.origin) → \(b.destination)",
                       dayText: b.departure.formatted(.dateTime.weekday().day().month()),
                       departureText: b.departure.formatted(date: .omitted, time: .shortened),
                       gate: b.gate, seat: b.seat, isCurrent: !trip.needsReview, packFlags: packFlags).save()
    }
}
