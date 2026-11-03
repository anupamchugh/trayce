import Foundation

/// Reads a booking out of plain ticket text with regular expressions.
/// The fallback when Apple Intelligence is unavailable, and a cross-check when it is.
public enum BookingTextParser {
    public static func parse(_ text: String, issuedFallback: Date?,
                             timeZone: TimeZone = TimeZone(identifier: "Asia/Kolkata")!) -> Booking? {
        guard let pnr = first(#"(?:PNR|Booking\s+Ref(?:erence)?)\s*[:#]?\s*([A-Z0-9]{6})\b"#, in: text)?[0],
              let flight = first(#"Flight\s*(?:No\.?)?\s*:?\s*([A-Z0-9]{2})\s*-?\s*(\d{1,4})\b"#, in: text),
              let route = first(#"\b([A-Z]{3})\s*(?:→|->|–|-|to)\s*([A-Z]{3})\b"#, in: text),
              let dep = first(#"(?:Departure|Departs|Dep)\b[^\d]*(\d{1,2}\s+[A-Za-z]{3}\s+\d{4})\s+(\d{1,2}:\d{2})"#, in: text),
              let departure = date(dep[0], dep[1], timeZone)
        else { return nil }

        let issued = first(#"Issued\b[^\d]*(\d{1,2}\s+[A-Za-z]{3}\s+\d{4})\s+(\d{1,2}:\d{2})"#, in: text)
            .flatMap { date($0[0], $0[1], timeZone) }
        let terminal = first(#"Terminal\s*:?\s*T?(\d)"#, in: text).map { "T" + $0[0] }

        return Booking(
            pnr: pnr, carrier: flight[0], flightNumber: flight[1], origin: route[0], destination: route[1],
            departure: departure,
            seat: first(#"Seat\s*:?\s*(\d{1,2}[A-K])\b"#, in: text)?[0],
            gate: first(#"Gate\s*:?\s*([A-Z]?\d{1,3}[A-Z]?)\b"#, in: text)?[0],
            terminal: terminal,
            passenger: first(#"Passenger\s*:?\s*([^\n]+)"#, in: text)?[0].trimmingCharacters(in: .whitespaces),
            issuedAt: issued ?? issuedFallback)
    }

    /// Capture groups of the first match.
    static func first(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (1..<m.numberOfRanges).compactMap { Range(m.range(at: $0), in: text).map { String(text[$0]) } }
    }

    static func date(_ day: String, _ time: String, _ timeZone: TimeZone) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "d MMM yyyy H:mm"
        return f.date(from: "\(day) \(time)")
    }
}
