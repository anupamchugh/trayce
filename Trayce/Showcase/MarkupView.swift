import PaperKit
import PencilKit
import SwiftUI

/// PaperKit markup over a photo of a tray. Strokes carry no identity: "who drew it"
/// is whoever is holding the phone and picked their name here, nothing more.
struct MarkupView: View {
    @State private var author = "You"

    var body: some View {
        VStack(spacing: 0) {
            Picker("Drawing as", selection: $author) {
                Text("You").tag("You")
                Text("Security officer").tag("Security officer")
            }
            .pickerStyle(.segmented)
            .padding()
            ZStack {
                Image(uiImage: SampleFlatLay.render()).resizable().scaledToFit()
                PaperMarkupRepresentable()
            }
            Text("Drawing as \(author). Trayce never reads anyone's Apple Account; a shared session would label marks by the participant who joined.")
                .font(.footnote).foregroundStyle(.secondary).padding()
        }
        .navigationTitle("Tray markup")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PaperMarkupRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> MarkupHostController { MarkupHostController() }
    func updateUIViewController(_ controller: MarkupHostController, context: Context) {}
}

final class MarkupHostController: UIViewController {
    private var paper: PaperMarkupViewController?
    private let toolPicker = PKToolPicker()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let paper = PaperMarkupViewController(markup: PaperMarkup(bounds: view.bounds), supportedFeatureSet: .latest)
        paper.view.backgroundColor = .clear
        addChild(paper)
        paper.view.frame = view.bounds
        paper.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(paper.view)
        paper.didMove(toParent: self)
        toolPicker.addObserver(paper)
        pencilKitResponderState.activeToolPicker = toolPicker
        pencilKitResponderState.toolPickerVisibility = .visible
        self.paper = paper
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override var canBecomeFirstResponder: Bool { true }
}
