import SwiftUI
import WidgetKit

// Ski Apex on the face of the Apple Watch: a complication that opens the app, ready to record.
// It shows no numbers: it reads nothing of the app.

struct FaceEntry: TimelineEntry {
    let date: Date
}

/// Nothing changes over time: one entry, for ever.
struct FaceProvider: TimelineProvider {
    func placeholder(in context: Context) -> FaceEntry { FaceEntry(date: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (FaceEntry) -> Void) {
        completion(FaceEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FaceEntry>) -> Void) {
        completion(Timeline(entries: [FaceEntry(date: Date())], policy: .never))
    }
}

struct FaceView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content.containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryInline:
            Label("Ski Apex", systemImage: "figure.skiing.downhill")
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "figure.skiing.downhill").font(.title2.weight(.semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ski Apex").font(.system(.headline, design: .rounded))
                    Text("Tocca per registrare").font(.system(.caption2, design: .rounded))
                }
                Spacer(minLength: 0)
            }
        case .accessoryCorner:
            Image(systemName: "figure.skiing.downhill")
                .font(.title3.weight(.semibold))
                .widgetLabel("Ski Apex")
        default:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "figure.skiing.downhill").font(.title3.weight(.semibold))
            }
        }
    }
}

@main
struct SkiApexFace: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "skiapex.face", provider: FaceProvider()) { _ in
            FaceView()
        }
        .configurationDisplayName("Ski Apex")
        .description("Apre Ski Apex, pronto a registrare la giornata.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}
