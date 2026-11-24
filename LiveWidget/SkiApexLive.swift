import ActivityKit
import SwiftUI
import WidgetKit

/// The extension of Ski Apex: the day under way on the lock screen and in the Dynamic Island, and
/// the widgets for the Home Screen and the Lock Screen (see HomeWidgets.swift).
@main
struct SkiApexLiveBundle: WidgetBundle {
    var body: some Widget {
        SkiLiveActivity()
        RecordWidget()
        SnowWidget()
    }
}

enum Ink {
    static let bg = Color(red: 0.102, green: 0.106, blue: 0.129)
    static let panel = Color(red: 0.165, green: 0.169, blue: 0.188)
    static let text = Color.white
    /// The ice blue of the icon, what is written on it, and the petrol the sheets of the app
    /// begin with at the top.
    static let accent = Color(red: 0.361, green: 0.812, blue: 1.0)
    static let onAccent = Color(red: 0.024, green: 0.125, blue: 0.180)
    static let sky = Color(red: 0.137, green: 0.271, blue: 0.361)
    /// The dot of the button that records.
    static let record = Color(red: 0.949, green: 0.333, blue: 0.353)
    /// The ground of a widget: as the sheets of the app, petrol fading into the dark.
    static var ground: LinearGradient {
        LinearGradient(stops: [.init(color: sky, location: 0), .init(color: bg, location: 0.6)], startPoint: .top, endPoint: .bottom)
    }
    static let lift = Color(red: 0.769, green: 0.710, blue: 0.992)
    static let sub = Color(red: 0.635, green: 0.647, blue: 0.694)

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
                    PhasePill(label: context.state.label, symbol: context.state.symbol, phase: context.state.phase)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.start, style: .timer)
                        .font(.system(.caption, design: .rounded, weight: .semibold).monospacedDigit())
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
                Text("\(context.state.runs)").font(.system(.caption, design: .rounded, weight: .bold).monospacedDigit()).foregroundStyle(Ink.accent)
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
                PhasePill(label: state.label, symbol: state.symbol, phase: state.phase)
                Spacer()
                Text(start, style: .timer)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold).monospacedDigit())
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

/// What is happening now, in a pill of its color: skiing, on a lift, standing.
private struct PhasePill: View {
    let label: String
    let symbol: String
    let phase: String

    var body: some View {
        Label {
            Text(label)
        } icon: {
            Image(systemName: symbol)
        }
        .font(.system(.caption, design: .rounded, weight: .bold))
        .foregroundStyle(Ink.tint(phase))
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Ink.tint(phase).opacity(0.2), in: Capsule())
    }
}

/// One number, bold, with its unit small beside it and what it counts under it.
private struct Figure: View {
    let value: String
    let label: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(UnitText.styled(value, big: .system(.title3, design: .rounded, weight: .bold),
                                 small: .system(.caption2, design: .rounded, weight: .bold)))
                .monospacedDigit().foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(.caption2, design: .rounded)).foregroundStyle(Ink.sub).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
