import Foundation

public struct FieldChange: Hashable, Sendable {
    public let field: String
    public let old: String
    public let new: String
}

/// Every document for one leg of one PNR, with the newest one as the truth.
public struct Trip: Identifiable, Sendable {
    public var id: String { SupersedeResolver.legKey(current.booking) }
    public let current: TripDocument
    public let stale: [TripDocument]
    /// What the newest document changed compared with the copy just before it.
    public let changes: [FieldChange]
    /// The copies disagree and not all of them print an issue date, so "newest" is only
    /// "shared most recently". The traveller should confirm with the airline.
    public let needsReview: Bool
    public var all: [TripDocument] { [current] + stale }
}

public enum SupersedeResolver {
    /// One PNR can hold several legs (out and back); each leg resolves on its own.
    public static func legKey(_ b: Booking) -> String {
        "\(b.pnr.uppercased())-\(b.origin.uppercased())-\(b.destination.uppercased())"
    }

    public static func trips(from documents: [TripDocument],
                             timeZone: TimeZone = TimeZone(identifier: "Asia/Kolkata")!) -> [Trip] {
        Dictionary(grouping: documents, by: { legKey($0.booking) })
            .values
            .map { group in
                // Compare issue dates only when every copy prints one; otherwise arrival order.
                let allIssued = group.allSatisfy { $0.booking.issuedAt != nil }
                let sorted = group.sorted {
                    let a = allIssued ? $0.booking.issuedAt! : $0.receivedAt
                    let b = allIssued ? $1.booking.issuedAt! : $1.receivedAt
                    return a != b ? a > b : $0.id.uuidString < $1.id.uuidString
                }
                let current = sorted[0]
                let stale = Array(sorted.dropFirst())
                let changes = stale.first.map { diff(from: $0.booking, to: current.booking, timeZone: timeZone) } ?? []
                return Trip(current: current, stale: stale, changes: changes, needsReview: !allIssued && !changes.isEmpty)
            }
            .sorted { $0.current.booking.departure < $1.current.booking.departure }
    }

    static func diff(from old: Booking, to new: Booking, timeZone: TimeZone) -> [FieldChange] {
        let day = formatter("EEE d MMM", timeZone)
        let time = formatter("HH:mm", timeZone)
        let fields: [(String, String?, String?)] = [
            ("Date", day.string(from: old.departure), day.string(from: new.departure)),
            ("Departure", time.string(from: old.departure), time.string(from: new.departure)),
            ("Flight", old.flightLabel, new.flightLabel),
            ("Route", "\(old.origin) → \(old.destination)", "\(new.origin) → \(new.destination)"),
            ("Seat", old.seat, new.seat),
            ("Terminal", old.terminal, new.terminal),
            ("Gate", old.gate, new.gate),
        ]
        return fields.compactMap { name, a, b in
            a == b ? nil : FieldChange(field: name, old: a ?? "—", new: b ?? "—")
        }
    }

    private static func formatter(_ format: String, _ timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_IN")
        f.timeZone = timeZone
        f.dateFormat = format
        return f
    }
}
