import RealityKit
import SwiftUI
import TrayceCore

/// A tabletop airliner built from RealityKit primitives (no third-party model to license),
/// with the traveller's seat row marked.
struct PlaneView: View {
    @Environment(TripStore.self) private var store

    private var seatRow: Int {
        Int(store.nextTrip?.current.booking.seat?.filter(\.isNumber) ?? "") ?? 12
    }

    var body: some View {
        VStack(spacing: 0) {
            RealityView { content in
                content.add(Self.airliner(seatRow: seatRow))
                let light = DirectionalLight()
                light.light.intensity = 3000
                light.look(at: .zero, from: [0.4, 0.6, 0.5], relativeTo: nil)
                content.add(light)
            }
            .realityViewCameraControls(.orbit)
            .background(Color(white: 0.12))

            VStack(alignment: .leading, spacing: 6) {
                Text("Seat \(store.nextTrip?.current.booking.seat ?? "12C") · row \(seatRow) of 30").font(.headline)
                Text("A generic single-aisle airliner, not your exact aircraft. Drag to orbit.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Your plane")
        .navigationBarTitleDisplayMode(.inline)
    }

    static func airliner(seatRow: Int) -> Entity {
        let root = Entity()
        let white = SimpleMaterial(color: .init(white: 0.95, alpha: 1), roughness: 0.4, isMetallic: false)
        let grey = SimpleMaterial(color: .init(white: 0.75, alpha: 1), roughness: 0.5, isMetallic: true)
        let blue = SimpleMaterial(color: .systemBlue, roughness: 0.4, isMetallic: false)

        let length: Float = 0.6
        let fuselage = ModelEntity(mesh: .generateCylinder(height: length, radius: 0.035), materials: [white])
        fuselage.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        root.addChild(fuselage)

        let nose = ModelEntity(mesh: .generateSphere(radius: 0.035), materials: [white])
        nose.position = [0, 0, -length / 2]
        root.addChild(nose)

        let wings = ModelEntity(mesh: .generateBox(width: 0.62, height: 0.008, depth: 0.09, cornerRadius: 0.004), materials: [grey])
        wings.position = [0, -0.012, -0.02]
        root.addChild(wings)

        let tailplane = ModelEntity(mesh: .generateBox(width: 0.2, height: 0.006, depth: 0.05, cornerRadius: 0.003), materials: [grey])
        tailplane.position = [0, 0.01, length / 2 - 0.03]
        root.addChild(tailplane)

        let fin = ModelEntity(mesh: .generateBox(width: 0.008, height: 0.1, depth: 0.07, cornerRadius: 0.003), materials: [blue])
        fin.position = [0, 0.06, length / 2 - 0.03]
        root.addChild(fin)

        // Rows run nose (1) to tail (30).
        let row = Float(min(max(seatRow, 1), 30))
        let seat = ModelEntity(mesh: .generateSphere(radius: 0.012),
                               materials: [UnlitMaterial(color: .systemOrange)])
        seat.position = [0.02, 0.04, -length / 2 + 0.06 + (row - 1) / 29 * (length - 0.12)]
        root.addChild(seat)
        return root
    }
}
