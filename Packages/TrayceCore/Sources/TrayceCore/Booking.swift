import Foundation

/// The facts of one flight booking, as read from one document.
public struct Booking: Codable, Hashable, Sendable {
    public var pnr: String
    public var carrier: String?
    public var flightNumber: String
    public var origin: String
    public var destination: String
    public var departure: Date
    public var seat: String?
    public var gate: String?
    public var terminal: String?
    public var passenger: String?
    public var issuedAt: Date?

    public init(pnr: String, carrier: String?, flightNumber: String, origin: String, destination: String,
                departure: Date, seat: String? = nil, gate: String? = nil, terminal: String? = nil,
                passenger: String? = nil, issuedAt: Date? = nil) {
        self.pnr = pnr
        self.carrier = carrier
        self.flightNumber = flightNumber
        self.origin = origin
        self.destination = destination
        self.departure = departure
        self.seat = seat
        self.gate = gate
        self.terminal = terminal
        self.passenger = passenger
        self.issuedAt = issuedAt
    }

    public var flightLabel: String { [carrier, flightNumber].compactMap { $0 }.joined(separator: " ") }
}

public enum DocumentSource: String, Codable, Sendable, CaseIterable {
    case whatsapp, mail, files, camera, sample

    public var label: String {
        switch self {
        case .whatsapp: "WhatsApp"
        case .mail: "Mail"
        case .files: "Files"
        case .camera: "Camera"
        case .sample: "Sample"
        }
    }
}

/// One shared file and what was read from it.
public struct TripDocument: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var fileName: String
    public var source: DocumentSource
    public var receivedAt: Date
    public var booking: Booking
    public var barcodePayload: String?

    public init(id: UUID = UUID(), fileName: String, source: DocumentSource, receivedAt: Date,
                booking: Booking, barcodePayload: String? = nil) {
        self.id = id
        self.fileName = fileName
        self.source = source
        self.receivedAt = receivedAt
        self.booking = booking
        self.barcodePayload = barcodePayload
    }

    /// Which copy is newer: the issue date printed on it, else when it arrived.
    public var recency: Date { booking.issuedAt ?? receivedAt }
}
