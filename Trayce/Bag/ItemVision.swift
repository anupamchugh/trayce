import CoreImage
import FoundationModels
import TrayceCore
import Vision

/// The categories the on-device model may answer with; rules are decided later, in code.
@Generable
enum ItemGuess: String {
    case laptop, tablet, powerBank, cable, liquid, aerosol, lighter, blade, other
}

nonisolated enum ItemVision {
    /// Vision cuts every foreground object out of a flat-lay photo, one image per item.
    static func cutOutItems(from image: CGImage) async throws -> [CGImage] {
        guard let observation = try await GenerateForegroundInstanceMaskRequest().perform(on: image) else { return [] }
        let handler = ImageRequestHandler(image)
        let context = CIContext()
        return try observation.allInstances.compactMap { instance in
            let buffer = try observation.generateMaskedImage(for: IndexSet(integer: instance), imageFrom: handler,
                                                             croppedToInstancesExtent: true)
            let ci = CIImage(cvPixelBuffer: buffer)
            return context.createCGImage(ci, from: ci.extent)
        }
    }

    /// Labels one item: Apple Intelligence looks at the image; OCR reads mAh, Wh, V and ml off the label.
    static func observe(_ crop: CGImage) async -> (ItemObservation, method: String) {
        let text = (try? await readLabel(crop)) ?? ""
        let numbers = LabelNumbers(text)
        var kind: ItemKind = .other
        var method = "picked by you"
        if SystemLanguageModel.default.availability == .available,
           let guess = try? await guessWithModel(crop) {
            kind = ItemKind(rawValue: guess.rawValue) ?? .other
            method = "Apple Intelligence"
        } else if let guess = try? await guessWithClassifier(crop) {
            kind = guess
            method = "Vision classifier"
        }
        if kind == .other, numbers.mAh != nil || numbers.wattHours != nil { kind = .powerBank }
        return (ItemObservation(kind: kind, mAh: numbers.mAh, volts: numbers.volts,
                                wattHours: numbers.wattHours, millilitres: numbers.millilitres), method)
    }

    static func readLabel(_ image: CGImage) async throws -> String {
        let observations = try await RecognizeTextRequest().perform(on: image)
        return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }

    static func guessWithModel(_ image: CGImage) async throws -> ItemGuess {
        let session = LanguageModelSession(instructions: """
            You sort items a traveller packed into airport-security categories. \
            Pick the single best category for the object in the photo.
            """)
        let response = try await session.respond(generating: ItemGuess.self,
                                                 options: GenerationOptions(sampling: .greedy)) {
            "Which category is this item?"
            Attachment(image)
        }
        return response.content
    }

    /// Fallback without Apple Intelligence: Vision's generic image labels, mapped by keyword.
    static func guessWithClassifier(_ image: CGImage) async throws -> ItemKind? {
        let labels = try await ClassifyImageRequest().perform(on: image)
            .filter { $0.confidence > 0.3 }.map(\.identifier)
        let map: [(String, ItemKind)] = [("laptop", .laptop), ("computer", .laptop), ("tablet", .tablet),
                                         ("bottle", .liquid), ("cosmetic", .liquid), ("spray", .aerosol),
                                         ("cable", .cable), ("wire", .cable), ("lighter", .lighter),
                                         ("scissors", .blade), ("knife", .blade), ("battery", .powerBank)]
        return labels.lazy.compactMap { label in map.first { label.contains($0.0) }?.1 }.first
    }
}

/// Numbers printed on a label, such as "20000mAh 3.7V 74Wh" or "150 ml".
nonisolated struct LabelNumbers {
    var mAh: Double?
    var volts: Double?
    var wattHours: Double?
    var millilitres: Double?

    init(_ text: String) {
        func value(_ unit: String) -> Double? {
            BookingTextParserBridge.first(#"(\d[\d,\.]*)\s*"# + unit, in: text)
                .flatMap { Double($0.replacingOccurrences(of: ",", with: "")) }
        }
        mAh = value("mAh")
        volts = value("V\\b")
        wattHours = value("Wh")
        millilitres = value("ml")
    }
}

nonisolated enum BookingTextParserBridge {
    static func first(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}
