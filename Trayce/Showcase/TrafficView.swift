import MapKit
import SwiftUI

/// Live aircraft around Bengaluru from adsb.lol: open data (ODbL), no key.
/// Position and type only; it never says gate, terminal or delay.
struct TrafficView: View {
    @State private var aircraft: [ADSBClient.Aircraft] = []
    @State private var error: String?
    private let blr = CLLocationCoordinate2D(latitude: 12.95, longitude: 77.67)

    var body: some View {
        VStack(spacing: 0) {
            Map(initialPosition: .region(MKCoordinateRegion(center: blr, latitudinalMeters: 90_000, longitudinalMeters: 90_000))) {
                Marker("BLR", systemImage: "airplane.departure", coordinate: blr)
                ForEach(aircraft) { plane in
                    if let c = plane.coordinate {
                        Annotation(plane.callsign, coordinate: c) {
                            Image(systemName: "airplane").rotationEffect(.degrees((plane.track ?? 0) - 90))
                                .foregroundStyle(.white).padding(4).background(.blue, in: .circle)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(error ?? "\(aircraft.count) aircraft within 25 nm of BLR").font(.subheadline)
                Text("Data: adsb.lol, ODbL v1.0. Positions only, no gates or delays.").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Live traffic")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private func refresh() async {
        do {
            aircraft = try await ADSBClient.aircraft(latitude: blr.latitude, longitude: blr.longitude, radiusNM: 25)
            error = nil
        } catch {
            self.error = "Couldn't reach adsb.lol: \(error.localizedDescription)"
        }
    }
}

nonisolated enum ADSBClient {
    struct Response: Decodable { let ac: [Aircraft]? }

    struct Aircraft: Decodable, Identifiable {
        let hex: String
        let flight: String?
        let t: String?
        let lat: Double?
        let lon: Double?
        let track: Double?

        var id: String { hex }
        var callsign: String { flight?.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? hex.uppercased() }
        var coordinate: CLLocationCoordinate2D? {
            guard let lat, let lon else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
    }

    static func aircraft(latitude: Double, longitude: Double, radiusNM: Int) async throws -> [Aircraft] {
        let url = URL(string: "https://api.adsb.lol/v2/point/\(latitude)/\(longitude)/\(radiusNM)")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(Response.self, from: data).ac ?? []
    }
}
