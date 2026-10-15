import AlarmKit
import ActivityKit
import SwiftUI
import WidgetKit

/// Live Activity widget for Sloozly alarm countdown on Lock Screen and Dynamic Island.
struct SloozlyAlarmLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<SloozlyAlarmMetadata>.self) { context in
            // Lock Screen presentation
            lockScreenView(context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    expandedLeading(context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    expandedTrailing(context)
                }
                DynamicIslandExpandedRegion(.center) {
                    expandedCenter(context)
                }
            } compactLeading: {
                Image(systemName: "alarm.fill")
                    .foregroundColor(.orange)
            } compactTrailing: {
                countdownText(context)
            } minimal: {
                Image(systemName: "alarm.fill")
                    .foregroundColor(.orange)
            }
        }
    }

    // MARK: - Lock Screen

    @ViewBuilder
    private func lockScreenView(_ context: ActivityViewContext<AlarmAttributes<SloozlyAlarmMetadata>>) -> some View {
        switch context.state.mode {
        case .countdown:
            countdownLockScreen(context)
        case .paused:
            pausedLockScreen(context)
        case .alert:
            alertLockScreen(context)
        @unknown default:
            Text("Sloozly Alarm")
        }
    }

    private func countdownLockScreen(_ context: ActivityViewContext<AlarmAttributes<SloozlyAlarmMetadata>>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(alarmLabel(context))
                    .font(.headline)
                    .foregroundColor(.orange)

                Text("Snooze countdown")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "zzz")
                .font(.title2)
                .foregroundColor(.orange)
        }
        .padding()
    }

    private func pausedLockScreen(_ context: ActivityViewContext<AlarmAttributes<SloozlyAlarmMetadata>>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(alarmLabel(context))
                    .font(.headline)

                Text("Alarm paused")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "pause.circle.fill")
                .font(.title2)
                .foregroundColor(.gray)
        }
        .padding()
    }

    private func alertLockScreen(_ context: ActivityViewContext<AlarmAttributes<SloozlyAlarmMetadata>>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(alarmLabel(context))
                    .font(.headline)
                    .foregroundColor(.red)

                Text("Wake up!")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "alarm.waves.left.and.right.fill")
                .font(.title2)
                .foregroundColor(.red)
        }
        .padding()
    }

    // MARK: - Dynamic Island Expanded

    private func expandedLeading(_ context: ActivityViewContext<AlarmAttributes<SloozlyAlarmMetadata>>) -> some View {
        Image(systemName: "alarm.fill")
            .font(.title2)
            .foregroundColor(.orange)
    }

    private func expandedTrailing(_ context: ActivityViewContext<AlarmAttributes<SloozlyAlarmMetadata>>) -> some View {
        countdownText(context)
    }

    private func expandedCenter(_ context: ActivityViewContext<AlarmAttributes<SloozlyAlarmMetadata>>) -> some View {
        Text(alarmLabel(context))
            .font(.headline)
    }

    // MARK: - Helpers

    private func countdownText(_ context: ActivityViewContext<AlarmAttributes<SloozlyAlarmMetadata>>) -> some View {
        Image(systemName: "zzz")
            .font(.caption)
            .foregroundColor(.orange)
    }

    private func alarmLabel(_ context: ActivityViewContext<AlarmAttributes<SloozlyAlarmMetadata>>) -> String {
        context.attributes.metadata?.label ?? "Sloozly Alarm"
    }
}
