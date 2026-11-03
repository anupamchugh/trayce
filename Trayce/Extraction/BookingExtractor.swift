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

    static func extract(from text: String) async -> Extraction? {
        if modelIsAvailable, let booking = try? await extractWithModel(text) {
            return Extraction(booking: booking, method: "with Apple Intelligence on this iPhone")
        }
        return BookingTextParser.parse(text, issuedFallback: nil)
            .map { Extraction(booking: $0, method: "with pattern rules on this iPhone") }
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
        guard e.pnr.count == 6, text.contains(e.pnr), text.contains(e.flightNumber),
              text.contains(e.origin), text.contains(e.destination),
              let departure = parseDate(e.departure) else { return nil }
        return Booking(pnr: e.pnr.uppercased(), carrier: e.carrier.nilIfEmpty, flightNumber: e.flightNumber,
                       origin: e.origin.uppercased(), destination: e.destination.uppercased(), departure: departure,
                       seat: e.seat.nilIfEmpty, terminal: e.terminal.nilIfEmpty, issuedAt: parseDate(e.issued))
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
