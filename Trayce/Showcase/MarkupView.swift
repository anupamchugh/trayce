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
            PaperMarkupRepresentable()
                .aspectRatio(4 / 3, contentMode: .fit)
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
        // The tray photo is an element of the markup itself, so marks sit on it and travel with it.
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        var markup = PaperMarkup(bounds: bounds)
        if let photo = ImageMarkup(image: SampleFlatLay.render(), frame: bounds) {
            markup.subelements.append(photo)
        }
        let paper = PaperMarkupViewController(markup: markup, supportedFeatureSet: .latest)
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
