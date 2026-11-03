import Foundation

/// Reads a booking out of plain ticket text with regular expressions. This is the
/// deterministic reader: when it succeeds, its fields win over the on-device model's.
public enum BookingTextParser {
    public static func parse(_ text: String, issuedFallback: Date?,
                             timeZone: TimeZone = TimeZone(identifier: "Asia/Kolkata")!) -> Booking? {
        let dateTime = #"(\d{1,2})[\s-]+([A-Za-z]{3,9})[\s,-]+(\d{4}),?\s+(\d{1,2}:\d{2})\s*([AaPp][Mm])?"#
        guard let pnr = first(#"(?i)\b(?:PNR|Booking\s+Ref(?:erence)?)(?:\s*(?:No\.?|Number))?\s*[:#]?\s*([A-Z0-9]{6})\b"#, in: text)?[0],
              let flight = first(#"(?i)\bFlight(?:\s*(?:No\.?|Number))?\s*[:#]?\s*([A-Z]\d|\d[A-Z]|[A-Z]{2})\s*-?\s*(\d{1,4})\b"#, in: text),
              let route = first(#"\(?\b([A-Z]{3})\b\)?\s*(?:→|->|–|-|to)\s*(?:[A-Za-z .]+?\s*\()?\b([A-Z]{3})\b"#, in: text),
              let dep = first(#"(?i)\b(?:Departure|Departs|Dep)\b[^\d\n]*"# + dateTime, in: text),
              let departure = date(dep, timeZone)
        else { return nil }

        let issued = first(#"(?i)\bIssued\b[^\d\n]*"# + dateTime, in: text).flatMap { date($0, timeZone) }
        let terminal = first(#"(?i)\bTerminal\s*:?\s*T?(\d)\b"#, in: text).map { "T" + $0[0] }

        return Booking(
            pnr: pnr.uppercased(), carrier: flight[0].uppercased(), flightNumber: flight[1],
            origin: route[0], destination: route[1], departure: departure,
            seat: first(#"(?i)\bSeat\s*(?:No\.?)?\s*:?\s*(\d{1,2}[A-K])\b"#, in: text)?[0].uppercased(),
            gate: first(#"(?i)\bGate\s*:?\s*([A-Z]?\d{1,3}[A-Z]?)\b"#, in: text)?[0].uppercased(),
            terminal: terminal,
            // A name runs until a run of spaces, a tab or another "Field:".
            passenger: first(#"(?i)\bPassenger(?:\s+Name)?\s*:?\s*([A-Za-z][A-Za-z .'/-]*?)(?=\s{2,}|\t|\n|$|\s+\w+\s*:)"#, in: text)?[0],
            issuedAt: issued ?? issuedFallback)
    }

    /// Capture groups of the first match; an unmatched optional group comes back as "".
    static func first(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (1..<m.numberOfRanges).map { Range(m.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
    }

    /// [day, month name, year, h:mm, am/pm or ""] → a date in the airport's time zone.
    static func date(_ parts: [String], _ timeZone: TimeZone) -> Date? {
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        guard parts.count >= 4,
              let day = Int(parts[0]), let year = Int(parts[2]),
              let month = months.firstIndex(of: String(parts[1].lowercased().prefix(3)))
        else { return nil }
        let hm = parts[3].split(separator: ":").compactMap { Int($0) }
        guard hm.count == 2, var hour = Optional(hm[0]) else { return nil }
        switch parts.count > 4 ? parts[4].lowercased() : "" {
        case "pm" where hour < 12: hour += 12
        case "am" where hour == 12: hour = 0
        default: break
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month + 1, day: day, hour: hour, minute: hm[1]))
    }
}

/// Numbers printed on a battery or bottle label, such as "20,000mAh 3.7V 74Wh" or "150 ml".
public struct LabelNumbers: Sendable {
    public var mAh: Double?
    public var volts: Double?
    public var wattHours: Double?
    public var millilitres: Double?

    public init(_ text: String) {
        func values(_ unit: String) -> [Double] {
            guard let regex = try? NSRegularExpression(pattern: #"(\d[\d,]*(?:\.\d+)?)\s*"# + unit) else { return [] }
            return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { m in
                Range(m.range(at: 1), in: text).flatMap { Double(text[$0].replacingOccurrences(of: ",", with: "")) }
            }
        }
        mAh = values(#"(?i:mAh)\b"#).first
        // Labels print charger "Input 5V" first; the cell voltage is the one between 3.0 and 4.4 V.
        volts = values(#"V\b"#).first { (3.0...4.4).contains($0) }
        wattHours = values(#"Wh\b"#).first
        millilitres = values(#"(?i:ml)\b"#).first
    }
}
