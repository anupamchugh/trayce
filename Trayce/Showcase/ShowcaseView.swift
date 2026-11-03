import SwiftUI

struct ShowcaseView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Talk to it") {
                    link("Ask Trayce", "Foundation Models with tools", "bubble.left.and.text.bubble.right") { AskView() }
                }
                Section("See it") {
                    link("Your plane, in miniature", "RealityKit RealityView", "airplane") { PlaneView() }
                    link("Live traffic near BLR", "adsb.lol open data, MapKit", "dot.radiowaves.left.and.right") { TrafficView() }
                }
                Section("Measure and mark") {
                    link("Cabin bag size check", "Object Capture, photogrammetry", "cube.transparent") { BagMeasureView() }
                    link("Tray markup", "PaperKit + PencilKit", "pencil.tip.crop.circle") { MarkupView() }
                }
            }
            .navigationTitle("Showcase")
        }
    }

    private func link<D: View>(_ title: String, _ subtitle: String, _ icon: String, @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink(destination: destination) {
            Label {
                VStack(alignment: .leading) {
                    Text(title)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            } icon: { Image(systemName: icon) }
        }
    }
}
