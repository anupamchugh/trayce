import RealityKit
import SwiftUI
import TrayceCore

/// Photogrammetry: scan the outside of a cabin bag, rebuild it on the device, and
/// compare its real-world size (from LiDAR depth) with the airline's limit.
struct BagMeasureView: View {
    @State private var capture: ObjectCaptureSession?
    @State private var status = "Walk slowly around the bag. Needs an iPhone with LiDAR."
    @State private var dimensionsCM: [Double] = [54, 38, 23]
    @State private var measured = false

    private let limit: [Double] = [55, 40, 20]
    private var folder: URL { URL.temporaryDirectory.appending(path: "BagCapture", directoryHint: .isDirectory) }

    var body: some View {
        VStack(spacing: 0) {
            if let capture {
                ObjectCaptureView(session: capture)
                    .overlay(alignment: .bottom) { controls(capture) }
            } else {
                ContentUnavailableView {
                    Label("3D scan", systemImage: "cube.transparent")
                } description: {
                    Text(ObjectCaptureSession.isSupported
                         ? "Place the bag in open floor space with light all round."
                         : "This device can't run Object Capture (it needs LiDAR). The size check below uses example numbers; enter yours to try it.")
                } actions: {
                    if ObjectCaptureSession.isSupported { Button("Start scan") { start() }.buttonStyle(.borderedProminent) }
                }
            }
            SizeCheck(dimensionsCM: $dimensionsCM, limit: limit, measured: measured)
        }
        .navigationTitle("Cabin bag size")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func controls(_ session: ObjectCaptureSession) -> some View {
        VStack(spacing: 8) {
            Text(status).font(.footnote).padding(8).background(.regularMaterial, in: .capsule)
            HStack {
                switch session.state {
                case .ready: Button("Detect bag") { _ = session.startDetecting() }
                case .detecting: Button("Start capturing") { session.startCapturing() }
                case .capturing: Button("Finish") { session.finish() }
                case .completed: Button("Measure") { Task { await reconstruct() } }
                default: EmptyView()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.bottom, 24)
    }

    private func start() {
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let session = ObjectCaptureSession()
        session.start(imagesDirectory: folder)
        capture = session
    }

    /// Rebuilds the bag on the device and reads its bounds in metres.
    private func reconstruct() async {
        status = "Rebuilding on this iPhone. This takes a few minutes."
        let model = URL.temporaryDirectory.appending(path: "bag.usdz")
        do {
            let session = try PhotogrammetrySession(input: folder)
            try session.process(requests: [.modelFile(url: model, detail: .reduced)])
            for try await output in session.outputs {
                if case .processingComplete = output { break }
            }
            let entity = try await Entity(contentsOf: model)
            let size = entity.visualBounds(relativeTo: nil).extents
            dimensionsCM = [size.x, size.y, size.z].map { (Double($0) * 1000).rounded() / 10 }
            measured = true
            capture = nil
            status = "Measured."
        } catch {
            status = "Couldn't rebuild the bag: \(error.localizedDescription)"
        }
    }
}

private struct SizeCheck: View {
    @Binding var dimensionsCM: [Double]
    let limit: [Double]
    let measured: Bool

    var body: some View {
        let sorted = dimensionsCM.sorted(by: >)
        let over = cabinOverage(measuredCM: dimensionsCM, limitCM: limit)
        Form {
            Section(measured ? "Measured (approx. ±2 cm)" : "Example measurement") {
                ForEach(0..<3, id: \.self) { i in
                    Stepper(value: $dimensionsCM[i], in: 5...120, step: 1) {
                        LabeledContent(["Length", "Width", "Depth"][i]) {
                            Text("\(Int(sorted[i])) of \(Int(limit[i])) cm" + (over[i] > 0 ? " · \(Int(over[i])) over" : ""))
                                .foregroundStyle(over[i] > 0 ? .orange : .primary)
                        }
                    }
                }
            }
            Section {
                Label(over.allSatisfy { $0 == 0 } ? "Fits 55 × 40 × 20 cm" : "Too big for 55 × 40 × 20 cm",
                      systemImage: over.allSatisfy { $0 == 0 } ? "checkmark.circle" : "exclamationmark.triangle")
                Text("Soft bags squash; check your airline's limit and weight too.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxHeight: 360)
    }
}
