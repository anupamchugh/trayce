import Foundation
import FoundationModels
import TrayceCore

/// The fields the on-device model fills in. Dates come back as text and are parsed in code.
@Generable
struct ExtractedBooking {
    @Guide(description: "The six-character airline booking reference (PNR), letters and digits")
    var pnr: String
    @Guide(description: "Two-character airline code, for example 6E or AI")
    var carrier: String
    @Guide(description: "Flight number digits only, for example 2134")
    var flightNumber: String
    @Guide(description: "Three-letter IATA code of the departure airport")
    var origin: String
    @Guide(description: "Three-letter IATA code of the arrival airport")
    var destination: String
    @Guide(description: "Scheduled departure in local time, formatted yyyy-MM-dd HH:mm")
    var departure: String
    @Guide(description: "Seat such as 12C, or empty")
    var seat: String
    @Guide(description: "Departure terminal such as T1, or empty")
    var terminal: String
    @Guide(description: "When this document was issued, formatted yyyy-MM-dd HH:mm, or empty")
    var issued: String
}

nonisolated enum BookingExtractor {
    struct Extraction: Sendable {
        let booking: Booking
        /// Shown to the traveller, so they know what read the document.
        let method: String
    }

    static var modelIsAvailable: Bool { SystemLanguageModel.default.availability == .available }

    /// The pattern reader is the umpire: when it finds the booking, its fields are used as they are.
    /// The model only reads layouts the patterns can't, and its answer is checked against the text.
    static func extract(from text: String) async -> Extraction? {
        if let booking = BookingTextParser.parse(text, issuedFallback: nil) {
            return Extraction(booking: booking, method: "with pattern rules on this iPhone")
        }
        if modelIsAvailable, let booking = try? await extractWithModel(text) {
            return Extraction(booking: booking, method: "with Apple Intelligence on this iPhone, checked against the text")
        }
        return nil
    }

    static func extractWithModel(_ text: String) async throws -> Booking? {
        let session = LanguageModelSession(instructions: """
            You read airline e-tickets and itineraries. Copy values exactly as printed. \
            Never invent a value; leave a field empty when the document does not show it.
            """)
        // The on-device context is 4096 tokens; the first page or two of a ticket fits.
        let response = try await session.respond(to: String(text.prefix(5000)),
                                                 generating: ExtractedBooking.self,
                                                 options: GenerationOptions(sampling: .greedy))
        let e = response.content
        // The model fills fields; code checks them. A PNR the text doesn't contain is rejected.
        guard e.pnr.count == 6, hasWord(e.pnr, in: text),
              !e.flightNumber.isEmpty, hasWord(e.flightNumber, in: text),
              let o = wordRange(e.origin, in: text), let d = wordRange(e.destination, in: text), o.lowerBound < d.lowerBound,
              let departure = parseDate(e.departure), printed(departure, in: text)
        else { return nil }
        // An issue date decides which copy wins, so keep it only if it is printed in the text.
        let issued = parseDate(e.issued).flatMap { printed($0, in: text) ? $0 : nil }
        return Booking(pnr: e.pnr.uppercased(), carrier: e.carrier.nilIfEmpty, flightNumber: e.flightNumber,
                       origin: e.origin.uppercased(), destination: e.destination.uppercased(), departure: departure,
                       seat: e.seat.nilIfEmpty.flatMap { hasWord($0, in: text) ? $0 : nil },
                       terminal: e.terminal.nilIfEmpty, issuedAt: issued)
    }

    static func wordRange(_ word: String, in text: String) -> Range<String.Index>? {
        guard !word.isEmpty else { return nil }
        return text.range(of: #"\b\#(NSRegularExpression.escapedPattern(for: word))\b"#, options: [.regularExpression, .caseInsensitive])
    }

    static func hasWord(_ word: String, in text: String) -> Bool { wordRange(word, in: text) != nil }

    /// The day number and the clock time (24 h or 12 h) both appear in the text.
    static func printed(_ date: Date, in text: String) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let c = calendar.dateComponents([.day, .hour, .minute], from: date)
        guard let day = c.day, let hour = c.hour, let minute = c.minute else { return false }
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        let times = [String(format: "%02d:%02d", hour, minute), String(format: "%d:%02d", hour, minute),
                     String(format: "%d:%02d", h12, minute)]
        return hasWord(String(day), in: text) && times.contains { text.contains($0) }
    }

    static func parseDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Kolkata")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)
    }
}

extension String {
    nonisolated var nilIfEmpty: String? { isEmpty ? nil : self }
}
