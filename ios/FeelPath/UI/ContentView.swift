import FeelPathCore
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if !model.lidarSupported {
                        Label("This iPhone has no LiDAR scanner. FeelPath needs a Pro model.",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    statusCard
                    startButton
                    tuning
                    patternTests
                    debug
                }
                .padding()
            }
            .navigationTitle("FeelPath")
        }
    }

    // MARK: Sections

    private var statusCard: some View {
        VStack(spacing: 8) {
            Image(systemName: icon(for: model.alert))
                .font(.system(size: 56, weight: .semibold))
            Text(model.isRunning ? model.alert.title : "Not running")
                .font(.largeTitle.bold())
            Text(distanceText)
                .font(.title2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .foregroundStyle(model.isRunning ? color(for: model.alert) : .secondary)
        .background(RoundedRectangle(cornerRadius: 24).fill(.background.secondary))
        .accessibilityElement(children: .combine)
    }

    private var startButton: some View {
        Button(action: model.toggle) {
            Label(model.isRunning ? "Stop" : "Start sensing",
                  systemImage: model.isRunning ? "stop.fill" : "play.fill")
                .font(.title2.bold())
                .frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(.borderedProminent)
        .tint(model.isRunning ? .red : .accentColor)
        .disabled(!model.lidarSupported)
    }

    private var tuning: some View {
        GroupBox("Settings") {
            VStack(alignment: .leading, spacing: 12) {
                slider("Obstacle alert within", value: $model.obstacleRange, range: 1...4)
                slider("Very close within", value: $model.veryCloseRange, range: 0.3...1.5)
                Toggle("Detect stairs down", isOn: $model.stairsEnabled)
                Toggle("Mute haptics", isOn: $model.hapticsMuted)
                Toggle("Announce changes (VoiceOver)", isOn: $model.announceChanges)
            }
        }
    }

    private var patternTests: some View {
        GroupBox("Feel the patterns") {
            HStack {
                ForEach([FeelPathCore.Alert.obstacle, .veryClose, .stairsDown], id: \.self) { alert in
                    Button(alert.title) { model.preview(alert) }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                }
            }
            .font(.footnote)
            if !model.hapticsSupported {
                Text("Haptics are not available on this device.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var debug: some View {
        GroupBox("Debug") {
            VStack(alignment: .leading, spacing: 4) {
                row("Status", model.status)
                row("Readings / s", "\(model.readingsPerSecond)")
                row("Points in corridor", "\(model.reading.pointCount)")
                row("Floor below phone", model.reading.floorHeight.map { String(format: "%.2f m", -$0) } ?? "—")
                row("Floor drop", model.reading.floorDrop ? "yes" : "no")
            }
            .font(.footnote.monospacedDigit())
        }
    }

    // MARK: Helpers

    private var distanceText: String {
        guard model.isRunning else { return "Tap Start, hold the phone pointing ahead" }
        guard let d = model.reading.obstacleDistance else { return "Nothing ahead" }
        return String(format: "%.1f m", d)
    }

    private func slider(_ label: String, value: Binding<Float>, range: ClosedRange<Float>) -> some View {
        VStack(alignment: .leading) {
            Text("\(label): \(String(format: "%.1f", value.wrappedValue)) m")
            Slider(value: value, in: range, step: 0.1)
        }
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
    }

    private func icon(for alert: FeelPathCore.Alert) -> String {
        switch alert {
        case .clear: return "figure.walk"
        case .obstacle: return "exclamationmark.triangle.fill"
        case .veryClose: return "hand.raised.fill"
        case .stairsDown: return "figure.stairs"
        }
    }

    private func color(for alert: FeelPathCore.Alert) -> Color {
        switch alert {
        case .clear: return .green
        case .obstacle: return .orange
        case .veryClose: return .red
        case .stairsDown: return .purple
        }
    }
}
