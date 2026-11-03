import PhotosUI
import SwiftUI
import TrayceCore

struct BagCheckView: View {
    @Environment(BagCheckModel.self) private var bag
    @State private var pick: PhotosPickerItem?
    @State private var showingCamera = false

    var body: some View {
        @Bindable var bag = bag
        NavigationStack {
            List {
                Section {
                    Text("Lay what you're packing flat, in one layer, with space between items. Trayce can only judge what it sees; it can't see inside a closed bag.")
                        .font(.subheadline)
                    HStack {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button("Take photo", systemImage: "camera") { showingCamera = true }
                        }
                        PhotosPicker("Choose photo", selection: $pick, matching: .images)
                        Button("Sample", systemImage: "wand.and.stars") {
                            Task { await bag.analyse(SampleFlatLay.render()) }
                        }
                    }
                    .buttonStyle(.bordered)
                }
                if bag.isWorking { ProgressView("Looking at your items on this iPhone…") }
                if let message = bag.message { Text(message).font(.footnote).foregroundStyle(.secondary) }

                if !bag.items.isEmpty {
                    Section("Items you showed") {
                        ForEach($bag.items) { $item in
                            ItemRow(item: $item, verdict: bag.verdict(for: item))
                        }
                    }
                    Section {
                        NavigationLink("Tray plan") { TrayPlanView() }.bold()
                    }
                }
            }
            .navigationTitle("Pack check")
            .onChange(of: pick) {
                Task {
                    if let data = try? await pick?.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        await bag.analyse(image)
                    }
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { image in Task { await bag.analyse(image) } }.ignoresSafeArea()
            }
        }
    }
}

private struct ItemRow: View {
    @Binding var item: PackedItem
    let verdict: Verdict

    var body: some View {
        HStack(spacing: 12) {
            Image(uiImage: item.image).resizable().scaledToFit().frame(width: 56, height: 56)
                .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Picker("Item", selection: $item.observation.kind) {
                    ForEach(ItemKind.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .onChange(of: item.observation.kind) { item.method = "picked by you" }
                Text(VerdictText(verdict).line).font(.caption).foregroundStyle(VerdictText(verdict).color)
                Text("Labelled by \(item.method)").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct VerdictText {
    let line: String
    let color: Color

    init(_ verdict: Verdict) {
        switch verdict {
        case .tray(let n): (line, color) = ("Tray \(n) at the X-ray", .blue)
        case .cabinOnly(let why): (line, color) = (why, .blue)
        case .stayInBag: (line, color) = ("Stays in your bag", .secondary)
        case .fix(let why): (line, color) = (why, .orange)
        case .doNotCarry(let why): (line, color) = (why, .red)
        }
    }
}

/// A drawn flat lay for the simulator, where there's no camera: real Vision runs on it.
enum SampleFlatLay {
    static func render() -> UIImage {
        let size = CGSize(width: 1200, height: 900)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(red: 0.54, green: 0.48, blue: 0.42, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            func box(_ r: CGRect, _ color: UIColor, _ label: String? = nil, radius: CGFloat = 18) {
                color.setFill()
                UIBezierPath(roundedRect: r, cornerRadius: radius).fill()
                if let label {
                    (label as NSString).draw(at: CGPoint(x: r.minX + 20, y: r.midY - 20),
                                             withAttributes: [.font: UIFont.boldSystemFont(ofSize: 34), .foregroundColor: UIColor.white])
                }
            }
            box(CGRect(x: 80, y: 90, width: 520, height: 340), .darkGray, radius: 22)
            box(CGRect(x: 700, y: 110, width: 200, height: 330), .black, "20000mAh")
            box(CGRect(x: 980, y: 140, width: 120, height: 330), UIColor(red: 0.85, green: 0.93, blue: 0.95, alpha: 1), radius: 30)
            ("150 ml" as NSString).draw(at: CGPoint(x: 985, y: 290), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 30)])
            box(CGRect(x: 560, y: 600, width: 60, height: 150), .systemRed, radius: 12)
        }
    }
}

private struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
