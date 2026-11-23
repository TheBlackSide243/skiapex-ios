import ActivityKit
import Foundation

/// The day under way on the lock screen and in the Dynamic Island (a Live Activity): started with
/// the recording, brought up to date as the numbers are worked out, ended with the day.
enum LiveStatus {
    static func update(state: Recorder.State, analysis: Segmenter.Result, start: Date?) {
        guard !Demo.isOn else { return }
        guard state != .idle, let start else {
            end()
            return
        }
        let phase: String
        if state == .paused {
            phase = "paused"
        } else {
            switch analysis.current {
            case .run: phase = "run"
            case .lift: phase = "lift"
            case .idle: phase = "idle"
            }
        }
        let content = ActivityContent(
            state: SkiActivityAttributes.ContentState(phase: phase, runs: analysis.stats.runs, vertical: analysis.stats.vertical,
                                                      maxSpeed: analysis.stats.maxSpeed, metric: Units.current == .metric),
            staleDate: nil)
        if let activity = Activity<SkiActivityAttributes>.activities.first {
            Task { await activity.update(content) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            // Only from the foreground: started from a Siri command in the background, it comes
            // with the first look at the app.
            _ = try? Activity.request(attributes: SkiActivityAttributes(start: start), content: content, pushType: nil)
        }
    }

    static func end() {
        guard !Demo.isOn else { return }
        for activity in Activity<SkiActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
