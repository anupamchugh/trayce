import CoreGraphics
import Foundation
import PDFKit
import UIKit
import Vision

/// Turns a PDF or screenshot into text plus the boarding barcode, entirely on the device.
nonisolated enum DocumentReader {
    struct Result: Sendable {
        var text: String
        var barcodePayload: String?
        var barcodeImage: CGImage?
    }

    enum ReadError: LocalizedError {
        case unreadable
        var errorDescription: String? { "The file isn't a PDF or image this iPhone can read." }
    }

    static func read(_ url: URL) async throws -> Result {
        let image: CGImage?
        var text = ""
        if url.pathExtension.lowercased() == "pdf", let pdf = PDFDocument(url: url) {
            // PDFKit: the text layer, when the PDF has one.
            text = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
            image = pdf.page(at: 0).flatMap(render)
        } else {
            image = UIImage(contentsOfFile: url.path)?.cgImage
        }
        guard let image else { throw ReadError.unreadable }

        // Vision: scanned PDFs and WhatsApp screenshots have no text layer.
        if text.trimmingCharacters(in: .whitespacesAndNewlines).count < 20 {
            text = try await recognizeDocument(image)
        }
        let barcode = try await detectBarcode(image)
        return Result(text: text, barcodePayload: barcode?.payload, barcodeImage: barcode?.crop)
    }

    static func render(_ page: PDFPage) -> CGImage? {
        let box = page.bounds(for: .mediaBox)
        let scale = 2000 / max(box.width, box.height)
        return page.thumbnail(of: CGSize(width: box.width * scale, height: box.height * scale), for: .mediaBox).cgImage
    }

    static func recognizeDocument(_ image: CGImage) async throws -> String {
        let observations = try await RecognizeDocumentsRequest().perform(on: image)
        return observations.map { $0.document.text.transcript }.joined(separator: "\n")
    }

    /// Finds the airline's boarding barcode and crops it out of the page as it is; Trayce never makes one.
    static func detectBarcode(_ image: CGImage) async throws -> (payload: String?, crop: CGImage?)? {
        var request = DetectBarcodesRequest()
        request.symbologies = [.pdf417, .aztec, .qr]
        guard let observation = try await request.perform(on: image).first else { return nil }
        let size = CGSize(width: image.width, height: image.height)
        let rect = observation.boundingBox.toImageCoordinates(size, origin: .upperLeft).insetBy(dx: -16, dy: -16)
        return (observation.payloadString, image.cropping(to: rect))
    }
}
