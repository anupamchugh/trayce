import Foundation

/// The mandatory fields of an IATA Bar Coded Boarding Pass (BCBP), format "M".
public struct BoardingPassData: Hashable, Sendable {
    public let passengerName: String
    public let pnr: String
    public let origin: String
    public let destination: String
    public let carrier: String
    public let flightNumber: String
    /// Day of the year the flight departs (1–366).
    public let dayOfYear: Int
    public let seat: String
    public let sequence: String
}

public enum BCBPParser {
    /// Parses the first leg of a BCBP string (fixed-width, 58 characters minimum).
    public static func parse(_ payload: String) -> BoardingPassData? {
        let chars = Array(payload)
        guard chars.count >= 58, chars[0] == "M" else { return nil }
        func field(_ start: Int, _ length: Int) -> String {
            String(chars[start..<start + length]).trimmingCharacters(in: .whitespaces)
        }
        guard let day = Int(field(44, 3)) else { return nil }
        let rawSeat = field(48, 4)
        let seat = String(rawSeat.drop { $0 == "0" })
        return BoardingPassData(
            passengerName: field(2, 20), pnr: field(23, 7), origin: field(30, 3), destination: field(33, 3),
            carrier: field(36, 3), flightNumber: String(field(39, 5).drop { $0 == "0" }), dayOfYear: day,
            seat: seat, sequence: field(52, 5))
    }
}
