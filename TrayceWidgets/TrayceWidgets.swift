import ActivityKit
import SwiftUI
import WidgetKit

@main
struct TrayceWidgets: WidgetBundle {
    var body: some Widget {
        TripWidget()
        TripLiveActivity()
    }
}

struct TripEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct TripProvider: TimelineProvider {
    func placeholder(in context: Context) -> TripEntry { TripEntry(date: .now, snapshot: .placeholder) }
    func getSnapshot(in context: Context, completion: @escaping (TripEntry) -> Void) {
        completion(TripEntry(date: .now, snapshot: WidgetSnapshot.load() ?? .placeholder))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TripEntry>) -> Void) {
        completion(Timeline(entries: [TripEntry(date: .now, snapshot: WidgetSnapshot.load())], policy: .never))
    }
}

struct TripWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TripWidget", provider: TripProvider()) { entry in
            TripWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Trip")
        .description("Your current flight and what to fix before you pack.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct TripWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TripEntry

    var body: some View {
        if let s = entry.snapshot {
            switch family {
            case .accessoryRectangular:
                VStack(alignment: .leading) {
                    Text(s.route).font(.headline)
                    Text("\(s.departureText) · Gate \(s.gate ?? "—")")
                }
            default:
                VStack(alignment: .leading, spacing: 6) {
                    Text("CURRENT · \(s.dayText.uppercased())").font(.caption2.bold()).foregroundStyle(.green)
                    Text(s.route).font(.title3.bold())
                    Text("Departs \(s.departureText)").font(.caption)
                    Text("Gate \(s.gate ?? "—") · \(s.seat ?? "—")").font(.caption).foregroundStyle(.secondary)
                    if !s.packFlags.isEmpty {
                        Text("\(s.packFlags.count) to fix: \(s.packFlags.joined(separator: ", "))").font(.caption2).foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("Share a booking into Trayce").font(.caption)
        }
    }
}

struct TripLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrayceActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(context.attributes.flight) · Gate \(context.attributes.gate)").font(.headline)
                    Spacer()
                    Text(timerInterval: Date.now...max(.now, context.state.boardsAt), countsDown: true)
                        .monospacedDigit().font(.headline).foregroundStyle(.blue)
                        .frame(width: 80, alignment: .trailing)
                }
                ForEach(context.state.trays, id: \.self) { Text($0).font(.subheadline) }
                if context.isStale { Text("Departure has passed; this may be out of date.").font(.caption).foregroundStyle(.orange) }
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text(context.attributes.flight).font(.headline) }
                DynamicIslandExpandedRegion(.trailing) { Text("Gate \(context.attributes.gate)") }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading) { ForEach(context.state.trays, id: \.self) { Text($0).font(.caption) } }
                }
            } compactLeading: {
                Image(systemName: "suitcase")
            } compactTrailing: {
                Text("\(context.state.trays.count) trays")
            } minimal: {
                Image(systemName: "airplane")
            }
        }
    }
}
