import Observation
import SwiftUI
import TrayceCore

struct PackedItem: Identifiable {
    let id = UUID()
    let image: UIImage
    var observation: ItemObservation
    var method: String
}

@Observable
final class BagCheckModel {
    var items: [PackedItem] = []
    var isWorking = false
    var message: String?
    let rules = RuleTable.india()

    func verdict(for item: PackedItem) -> Verdict { rules.verdict(for: item.observation) }

    /// Power banks go through in the second tray with liquids; everything else per its verdict.
    func tray(for item: PackedItem) -> Int? {
        switch verdict(for: item) {
        case .tray(let n): n
        case .cabinOnly: 2
        default: nil
        }
    }

    var trayCount: Int { Set(items.compactMap(tray(for:))).count }

    var trayLines: [String] {
        Dictionary(grouping: items.filter { tray(for: $0) != nil }, by: { tray(for: $0)! })
            .sorted { $0.key < $1.key }
            .map { "Tray \($0.key): " + $0.value.map(\.observation.kind.label).joined(separator: ", ") }
    }

    var flags: [String] {
        items.compactMap { item in
            switch verdict(for: item) {
            case .doNotCarry, .fix: item.observation.kind.label
            default: nil
            }
        }
    }

    func analyse(_ image: UIImage) async {
        guard let cg = image.uprightCGImage else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let crops = try await ItemVision.cutOutItems(from: cg)
            var found: [PackedItem] = []
            for crop in crops {
                let (observation, method) = await ItemVision.observe(crop)
                found.append(PackedItem(image: UIImage(cgImage: crop), observation: observation, method: method))
            }
            items = found
            message = found.isEmpty
                ? "No separate items found. Lay them flat with space between them."
                : "Found \(found.count) items you showed. Correct any label by tapping it."
        } catch {
            message = "Couldn't analyse the photo: \(error.localizedDescription)"
        }
    }
}
