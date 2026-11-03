import Foundation
import Testing
@testable import TrayceCore

private func date(_ s: String) -> Date {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "Asia/Kolkata")
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.date(from: s)!
}

private func doc(pnr: String = "X7K2LM", departs: String, issued: String?, received: String, seat: String = "12C") -> TripDocument {
    TripDocument(
        id: UUID(), fileName: "E-Ticket_\(pnr).pdf", source: .whatsapp, receivedAt: date(received),
        booking: Booking(pnr: pnr, carrier: "6E", flightNumber: "2134", origin: "BLR", destination: "DEL",
                         departure: date(departs), seat: seat, gate: nil, terminal: "T1", passenger: "Test Traveller",
                         issuedAt: issued.map(date)),
        barcodePayload: nil)
}

@Suite struct SupersedeResolverTests {
    @Test func newerIssueDateWins() {
        let old = doc(departs: "2026-11-14 18:15", issued: "2026-10-28 10:00", received: "2026-11-03 09:00")
        let new = doc(departs: "2026-11-16 07:40", issued: "2026-11-02 18:40", received: "2026-11-01 09:00")
        let trips = SupersedeResolver.trips(from: [old, new])
        #expect(trips.count == 1)
        #expect(trips[0].current.id == new.id)
        #expect(trips[0].stale.map(\.id) == [old.id])
        #expect(trips[0].changes.contains { $0.field == "Date" })
        #expect(trips[0].changes.contains { $0.field == "Departure" && $0.old == "18:15" && $0.new == "07:40" })
    }

    @Test func resolverFallsBackToReceivedAt() {
        let old = doc(departs: "2026-11-14 18:15", issued: nil, received: "2026-10-28 10:00")
        let new = doc(departs: "2026-11-16 07:40", issued: nil, received: "2026-11-03 09:12")
        #expect(SupersedeResolver.trips(from: [new, old])[0].current.id == new.id)
    }

    @Test func differentPNRsStaySeparate() {
        let a = doc(pnr: "AAA111", departs: "2026-11-16 07:40", issued: nil, received: "2026-11-01 09:00")
        let b = doc(pnr: "BBB222", departs: "2026-11-16 07:40", issued: nil, received: "2026-11-02 09:00")
        let trips = SupersedeResolver.trips(from: [a, b])
        #expect(trips.count == 2)
        #expect(trips.allSatisfy { $0.stale.isEmpty })
    }

    @Test func identicalDocsProduceNoChanges() {
        let a = doc(departs: "2026-11-16 07:40", issued: "2026-11-02 18:40", received: "2026-11-02 19:00")
        let b = doc(departs: "2026-11-16 07:40", issued: "2026-11-02 18:40", received: "2026-11-03 09:00")
        let trip = SupersedeResolver.trips(from: [a, b])[0]
        #expect(trip.changes.isEmpty)
        #expect(trip.stale.count == 1)
    }
}

@Suite struct ParserTests {
    static let ticket = """
    E-TICKET / ITINERARY
    Booking ID: MMT-SAMPLE-0001
    PNR: X7K2LM
    Passenger: Test Traveller
    Flight 6E 2134  BLR → DEL
    Departure: 16 Nov 2026 07:40  Terminal T1
    Seat 12C
    Issued: 02 Nov 2026 18:40
    """

    @Test func parsesSampleETicket() throws {
        let b = try #require(BookingTextParser.parse(Self.ticket, issuedFallback: nil))
        #expect(b.pnr == "X7K2LM")
        #expect(b.carrier == "6E")
        #expect(b.flightNumber == "2134")
        #expect(b.origin == "BLR")
        #expect(b.destination == "DEL")
        #expect(b.departure == date("2026-11-16 07:40"))
        #expect(b.seat == "12C")
        #expect(b.terminal == "T1")
        #expect(b.issuedAt == date("2026-11-02 18:40"))
    }

    @Test func parserRejectsTextWithoutPNR() {
        #expect(BookingTextParser.parse("Flight 6E 2134 BLR DEL 16 Nov 2026 07:40", issuedFallback: nil) == nil)
    }

    @Test func parsesM1Payload() throws {
        let p = try #require(BCBPParser.parse("M1DOE/JANE            EX7K2LM BLRDEL6E 2134 320Y012C0041 100"))
        #expect(p.passengerName == "DOE/JANE")
        #expect(p.pnr == "X7K2LM")
        #expect(p.origin == "BLR")
        #expect(p.destination == "DEL")
        #expect(p.carrier == "6E")
        #expect(p.flightNumber == "2134")
        #expect(p.dayOfYear == 320)
        #expect(p.seat == "12C")
        #expect(p.sequence == "0041")
    }

    @Test func rejectsShortPayload() {
        #expect(BCBPParser.parse("M1DOE/JANE") == nil)
    }
}

@Suite struct RuleTests {
    let rules = RuleTable.india()

    @Test func twentyKmAhIs74Wh() {
        #expect(abs(wattHours(mAh: 20_000) - 74) < 0.01)
    }

    @Test func whLabelWins() {
        let o = ItemObservation(kind: .powerBank, mAh: 50_000, volts: nil, wattHours: 90, millilitres: nil)
        #expect(o.resolvedWattHours == 90)
    }

    @Test func powerBankUnder100WhCabinOnly() {
        guard case .cabinOnly = rules.verdict(for: ItemObservation(kind: .powerBank, mAh: 20_000)) else {
            Issue.record("expected cabinOnly"); return
        }
    }

    @Test func powerBankOver160WhDoNotCarry() {
        guard case .doNotCarry = rules.verdict(for: ItemObservation(kind: .powerBank, wattHours: 200)) else {
            Issue.record("expected doNotCarry"); return
        }
    }

    @Test func liquidOver100mlIsFix() {
        guard case .fix = rules.verdict(for: ItemObservation(kind: .liquid, millilitres: 150)) else {
            Issue.record("expected fix"); return
        }
        #expect(rules.verdict(for: ItemObservation(kind: .liquid, millilitres: 90)) == .tray(2))
    }

    @Test func lighterDoNotCarry() {
        guard case .doNotCarry = rules.verdict(for: ItemObservation(kind: .lighter)) else {
            Issue.record("expected doNotCarry"); return
        }
    }

    @Test func laptopGetsTray1() {
        #expect(rules.verdict(for: ItemObservation(kind: .laptop)) == .tray(1))
        #expect(rules.verdict(for: ItemObservation(kind: .cable)) == .stayInBag)
    }

    @Test func rulesCarrySourceAndDate() {
        #expect(rules.asOf == "2026-10")
        #expect(rules.source.host() != nil)
    }

    @Test func cabinFitReportsDepthOverage() {
        // Bag measured 54 × 38 × 23 cm against 55 × 40 × 20 cm, axes in any order.
        #expect(cabinOverage(measuredCM: [23, 54, 38]) == [0, 0, 3])
    }
}
