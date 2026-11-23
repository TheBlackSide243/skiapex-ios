import ActivityKit
import SwiftUI
import WidgetKit

/// The extension of Ski Apex: the day under way on the lock screen and in the Dynamic Island.
@main
struct SkiApexLiveBundle: WidgetBundle {
    var body: some Widget {
        SkiLiveActivity()
    }
}

private enum Ink {
    static let bg = Color(red: 0.043, green: 0.086, blue: 0.149)
    static let accent = Color(red: 0.361, green: 0.812, blue: 1.0)
    static let lift = Color(red: 0.769, green: 0.710, blue: 0.992)
    static let sub = Color(red: 0.596, green: 0.663, blue: 0.749)

    static func tint(_ phase: String) -> Color {
        switch phase {
        case "run": accent
        case "lift": lift
        default: sub
        }
    }
}

struct SkiLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SkiActivityAttributes.self) { context in
            LockScreenView(state: context.state, start: context.attributes.start)
                .activityBackgroundTint(Ink.bg)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.state.label)
                    } icon: {
                        Image(systemName: context.state.symbol)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Ink.tint(context.state.phase))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.start, style: .timer)
                        .font(.caption.monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Figure(value: "\(context.state.runs)", label: "Discese")
                        Figure(value: context.state.verticalText, label: "Dislivello")
                        Figure(value: context.state.maxSpeedText, label: "Velocità max")
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.symbol).foregroundStyle(Ink.tint(context.state.phase))
            } compactTrailing: {
                Text("\(context.state.runs)").font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(Ink.accent)
            } minimal: {
                Image(systemName: context.state.symbol).foregroundStyle(Ink.tint(context.state.phase))
            }
        }
    }
}

private struct LockScreenView: View {
    let state: SkiActivityAttributes.ContentState
    let start: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label {
                    Text(state.label)
                } icon: {
                    Image(systemName: state.symbol)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Ink.tint(state.phase))
                Spacer()
                Text(start, style: .timer)
                    .font(.subheadline.monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.white)
            }
            HStack {
                Figure(value: "\(state.runs)", label: "Discese")
                Figure(value: state.verticalText, label: "Dislivello")
                Figure(value: state.maxSpeedText, label: "Velocità max")
            }
        }
        .padding(16)
    }
}

private struct Figure: View {
    let value: String
    let label: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(Ink.sub).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
