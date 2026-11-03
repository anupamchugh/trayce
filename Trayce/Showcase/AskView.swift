import FoundationModels
import SwiftUI
import TrayceCore

/// The on-device model phrases answers; the tools hold the facts (your trip, the rule table).
struct AskView: View {
    @Environment(TripStore.self) private var store
    @State private var question = ""
    @State private var turns: [(q: String, a: String)] = []
    @State private var session: LanguageModelSession?
    @State private var thinking = false

    private var availability: SystemLanguageModel.Availability { SystemLanguageModel.default.availability }

    var body: some View {
        List {
            if availability != .available {
                Section {
                    Label("Apple Intelligence isn't available on this device (\(String(describing: availability))). The tools below still run in the Pack check and Trip tabs.",
                          systemImage: "exclamationmark.circle")
                        .font(.footnote)
                }
            }
            ForEach(turns.indices, id: \.self) { i in
                Section {
                    Text(turns[i].q).bold()
                    Text(turns[i].a)
                }
            }
            if thinking { ProgressView() }
            Section {
                ForEach(["Can I take my 20,000 mAh power bank?", "When should I leave home?", "Is a 150 ml shampoo okay?"], id: \.self) { s in
                    Button(s) { question = s; ask() }
                }
            } header: { Text("Try") }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                TextField("Ask about your trip or bag", text: $question).textFieldStyle(.roundedBorder).onSubmit(ask)
                Button("Send", systemImage: "arrow.up.circle.fill", action: ask).labelStyle(.iconOnly).font(.title2)
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle("Ask Trayce")
        .onAppear {
            guard availability == .available else { return }
            currentSession().prewarm()
            // Screenshot/demo hook: ask the first suggestion on launch.
            if ProcessInfo.processInfo.arguments.contains("-demoAsk"), turns.isEmpty {
                question = "Can I take my 20,000 mAh power bank?"
                ask()
            }
        }
    }

    /// One session for the whole conversation, so follow-up questions keep their context.
    private func currentSession() -> LanguageModelSession {
        if let session { return session }
        let new = LanguageModelSession(
            tools: [GetTripTool(summary: tripSummary), CheckItemTool()],
            instructions: """
                You are Trayce, an airport companion. Use getTrip for anything about the traveller's flight \
                and checkItemRule for whether an item may be carried. Never state a rule, time or number \
                the tools didn't return. Answer in two or three short sentences.
                """)
        session = new
        return new
    }

    private func ask() {
        let q = question.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, !thinking, availability == .available else { return }
        question = ""
        thinking = true
        let session = currentSession()
        Task {
            let answer: String
            do {
                answer = try await session.respond(to: q).content
            } catch LanguageModelError.contextSizeExceeded {
                self.session = nil
                answer = "That conversation got too long, so I started a fresh one. Please ask again."
            } catch {
                answer = "Sorry, I couldn't answer that on this iPhone right now."
            }
            turns.append((q, answer))
            thinking = false
        }
    }

    private var tripSummary: String {
        guard let trip = store.nextTrip else { return "No trip saved yet." }
        let b = trip.current.booking
        return """
            Flight \(b.flightLabel) \(b.origin) to \(b.destination), departs \(b.departure.formatted(date: .complete, time: .shortened)). \
            Terminal \(b.terminal ?? "unknown"), gate \(b.gate ?? "not in documents"), seat \(b.seat ?? "unknown"). \
            Leave home by \(b.departure.addingTimeInterval(-150 * 60).formatted(date: .omitted, time: .shortened)). \
            Built from \(trip.all.count) documents; \(trip.stale.count) stale.
            """
    }
}

nonisolated struct GetTripTool: Tool {
    let name = "getTrip"
    let description = "Returns the traveller's current flight: route, departure time, terminal, gate, seat, and when to leave home."
    let summary: String

    @Generable struct Arguments {}

    func call(arguments: Arguments) async throws -> String { summary }
}

nonisolated struct CheckItemTool: Tool {
    let name = "checkItemRule"
    let description = "Checks Indian airport security rules for one item. Returns where it may go and why."

    @Generable struct Arguments {
        @Guide(description: "One of: laptop, tablet, powerBank, cable, liquid, aerosol, lighter, blade, other")
        var kind: String
        @Guide(description: "Battery capacity in mAh, or 0 if not given")
        var mAh: Double
        @Guide(description: "Battery energy in Wh, or 0 if not given")
        var wattHours: Double
        @Guide(description: "Liquid volume in ml, or 0 if not given")
        var millilitres: Double
    }

    func call(arguments: Arguments) async throws -> String {
        let rules = RuleTable.india()
        let item = ItemObservation(kind: ItemKind(rawValue: arguments.kind) ?? .other,
                                   mAh: arguments.mAh > 0 ? arguments.mAh : nil,
                                   wattHours: arguments.wattHours > 0 ? arguments.wattHours : nil,
                                   millilitres: arguments.millilitres > 0 ? arguments.millilitres : nil)
        let verdict: String = switch rules.verdict(for: item) {
        case .tray(let n): "Allowed in the cabin; put it in tray \(n) at the X-ray."
        case .cabinOnly(let why), .fix(let why), .doNotCarry(let why): why
        case .stayInBag: "Allowed; it can stay in the bag."
        }
        return "\(verdict) Source: \(rules.source.absoluteString), rules as of \(rules.asOf)."
    }
}
