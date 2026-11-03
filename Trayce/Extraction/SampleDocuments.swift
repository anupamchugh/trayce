import CoreImage
import CoreImage.CIFilterBuiltins
import TrayceCore
import UIKit

/// Two synthetic e-tickets for the demo: the original, and a re-issue that moves the flight.
/// Every value is made up; the barcode is a synthetic BCBP string.
enum SampleDocuments {
    struct Sample {
        let url: URL
        let source: DocumentSource
        let receivedAt: Date
    }

    static func make() -> [Sample] {
        let old = """
            E-TICKET / ITINERARY  (sample, not a real booking)
            Booking ID: SAMPLE-0001
            PNR: X7K2LM
            Passenger: Test Traveller
            Flight 6E 2134  BLR → DEL
            Departure: 14 Nov 2026 18:15  Terminal T1
            Seat 12C
            Issued: 28 Oct 2026 10:05
            """
        let new = """
            E-TICKET / ITINERARY  (sample, not a real booking)
            Booking ID: SAMPLE-0001  ·  DATE CHANGE
            PNR: X7K2LM
            Passenger: Test Traveller
            Flight 6E 2134  BLR → DEL
            Departure: 16 Nov 2026 07:40  Terminal T1
            Seat 12C   Gate 14
            Issued: 02 Nov 2026 18:40
            """
        let bcbp = "M1TRAVELLER/TEST       EX7K2LM BLRDEL6E 2134 320Y012C0041 100"
        return [
            Sample(url: write(old, name: "E-Ticket_X7K2LM.pdf", barcode: nil), source: .whatsapp,
                   receivedAt: .now.addingTimeInterval(-6 * 86_400)),
            Sample(url: write(new, name: "E-Ticket_X7K2LM_reissued.pdf", barcode: bcbp), source: .mail,
                   receivedAt: .now),
        ]
    }

    private static func write(_ text: String, name: String, barcode: String?) -> URL {
        let url = URL.temporaryDirectory.appending(path: name)
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let data = UIGraphicsPDFRenderer(bounds: page).pdfData { context in
            context.beginPage()
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)]
            (text as NSString).draw(in: page.insetBy(dx: 48, dy: 56), withAttributes: attributes)
            if let barcode, let image = pdf417(barcode) {
                image.draw(in: CGRect(x: 48, y: 420, width: 420, height: 130))
            }
        }
        try? data.write(to: url)
        return url
    }

    private static func pdf417(_ message: String) -> UIImage? {
        let filter = CIFilter.pdf417BarcodeGenerator()
        filter.message = Data(message.utf8)
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 4, y: 4)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
