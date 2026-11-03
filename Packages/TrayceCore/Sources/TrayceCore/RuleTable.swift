import Foundation

public enum ItemKind: String, Codable, Sendable, CaseIterable {
    case laptop, tablet, powerBank, cable, liquid, aerosol, lighter, blade, other

    public var label: String {
        switch self {
        case .laptop: "Laptop"
        case .tablet: "Tablet"
        case .powerBank: "Power bank"
        case .cable: "Cable"
        case .liquid: "Liquid"
        case .aerosol: "Aerosol"
        case .lighter: "Lighter"
        case .blade: "Blade or scissors"
        case .other: "Other"
        }
    }
}

/// What the camera and the label text said about one item.
public struct ItemObservation: Hashable, Sendable {
    public var kind: ItemKind
    public var mAh: Double?
    public var volts: Double?
    public var wattHours: Double?
    public var millilitres: Double?

    public init(kind: ItemKind, mAh: Double? = nil, volts: Double? = nil, wattHours: Double? = nil, millilitres: Double? = nil) {
        self.kind = kind
        self.mAh = mAh
        self.volts = volts
        self.wattHours = wattHours
        self.millilitres = millilitres
    }

    /// A printed Wh value beats one computed from mAh.
    public var resolvedWattHours: Double? {
        wattHours ?? mAh.map { TrayceCore.wattHours(mAh: $0, volts: volts ?? 3.7) }
    }
}

public enum Verdict: Hashable, Sendable {
    case tray(Int)
    case cabinOnly(String)
    case stayInBag
    case fix(String)
    case doNotCarry(String)
}

public func wattHours(mAh: Double, volts: Double = 3.7) -> Double { mAh * volts / 1000 }

/// Size over the limit per axis, in cm. Both lists are compared largest-first,
/// because a scanned bounding box has no fixed orientation.
public func cabinOverage(measuredCM: [Double], limitCM: [Double] = [55, 40, 20]) -> [Double] {
    zip(measuredCM.sorted(by: >), limitCM.sorted(by: >)).map { max(0, $0 - $1) }
}

/// A dated, sourced rule table. Decides legality in code, never with AI.
public struct RuleTable: Sendable {
    struct Limits: Decodable {
        let country: String
        let asOf: String
        let source: URL
        let powerBankCabinMaxWh: Double
        let powerBankApprovalMaxWh: Double
        let liquidMaxMl: Double
    }

    let limits: Limits
    public var asOf: String { limits.asOf }
    public var source: URL { limits.source }
    public var country: String { limits.country }

    public static func india() -> RuleTable {
        let url = Bundle.module.url(forResource: "rules-IN", withExtension: "json")!
        let limits = try! JSONDecoder().decode(Limits.self, from: Data(contentsOf: url))
        return RuleTable(limits: limits)
    }

    public func verdict(for item: ItemObservation) -> Verdict {
        switch item.kind {
        case .laptop, .tablet:
            return .tray(1)
        case .powerBank:
            guard let wh = item.resolvedWattHours else {
                return .cabinOnly("Capacity unknown. Cabin only; check the label for mAh or Wh.")
            }
            let shown = Int(wh.rounded())
            if wh <= limits.powerBankCabinMaxWh {
                return .cabinOnly("\(shown) Wh: cabin only, under \(Int(limits.powerBankCabinMaxWh)) Wh. Never in the checked bag or overhead bin.")
            }
            if wh <= limits.powerBankApprovalMaxWh {
                return .cabinOnly("\(shown) Wh: cabin only, and needs the airline's approval.")
            }
            return .doNotCarry("\(shown) Wh: over \(Int(limits.powerBankApprovalMaxWh)) Wh, not allowed on board.")
        case .liquid, .aerosol:
            if let ml = item.millilitres, ml > limits.liquidMaxMl {
                return .fix("\(Int(ml)) ml: move it to the checked bag, or use a bottle of \(Int(limits.liquidMaxMl)) ml or less.")
            }
            return .tray(2)
        case .lighter:
            return .doNotCarry("Lighters are not allowed in cabin or checked bags.")
        case .blade:
            return .doNotCarry("Blades and scissors are not allowed in the cabin.")
        case .cable, .other:
            return .stayInBag
        }
    }
}
