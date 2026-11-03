import Foundation

public struct FieldChange: Hashable, Sendable {
    public let field: String
    public let old: String
    public let new: String
}

/// Every document for one PNR, with the newest one as the truth.
public struct Trip: Identifiable, Sendable {
    public var id: String { current.booking.pnr }
    public let current: TripDocument
    public let stale: [TripDocument]
    /// What the newest document changed compared with the copy just before it.
    public let changes: [FieldChange]
    public var all: [TripDocument] { [current] + stale }
}

public enum SupersedeResolver {
    public static func trips(from documents: [TripDocument],
                             timeZone: TimeZone = TimeZone(identifier: "Asia/Kolkata")!) -> [Trip] {
        Dictionary(grouping: documents, by: { $0.booking.pnr.uppercased() })
            .values
            .map { group in
                let sorted = group.sorted { $0.recency > $1.recency }
                let current = sorted[0]
                let stale = Array(sorted.dropFirst())
                let changes = stale.first.map { diff(from: $0.booking, to: current.booking, timeZone: timeZone) } ?? []
                return Trip(current: current, stale: stale, changes: changes)
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
