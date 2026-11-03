import ActivityKit
import Foundation

/// Shared between the app and the widget extension.
enum AppGroup {
    static let id = "group.com.alcor.trayce"
    static var defaults: UserDefaults { UserDefaults(suiteName: id) ?? .standard }
}

/// The small summary the home and Lock Screen widgets draw.
struct WidgetSnapshot: Codable, Hashable {
    var route: String
    var dayText: String
    var departureText: String
    var gate: String?
    var seat: String?
    var isCurrent: Bool
    var packFlags: [String]

    static let key = "widgetSnapshot"

    static func load() -> WidgetSnapshot? {
        AppGroup.defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(WidgetSnapshot.self, from: $0) }
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { AppGroup.defaults.set(data, forKey: Self.key) }
    }

    static let placeholder = WidgetSnapshot(route: "BLR → DEL", dayText: "Sun 16 Nov", departureText: "07:40",
                                            gate: "14", seat: "12C", isCurrent: true, packFlags: ["Lighter", "150 ml bottle"])
}

/// The flight-day Live Activity: boarding countdown and the tray order at security.
struct TrayceActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var step: String
        var trays: [String]
        var boardsAt: Date
    }

    var flight: String
    var gate: String
}
