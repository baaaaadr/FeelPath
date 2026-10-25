// Plays FeelPathCore `HapticPattern`s on the Taptic Engine. One cue loops at a time; switching
// cue cuts the old one immediately so "very close" never waits behind a long stairs buzz.

import CoreHaptics
import FeelPathCore
import Foundation

@MainActor
final class HapticRenderer {

    private(set) var isAvailable = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private(set) var lastError: String?

    private var engine: CHHapticEngine?
    private var currentAlert: Alert = .clear
    private var loopTask: Task<Void, Never>?
    private var activePlayer: CHHapticPatternPlayer?

    func start() {
        guard isAvailable, engine == nil else { return }
        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = false
            // Called on an internal queue: just restart, touching no main-actor state.
            engine.resetHandler = { [weak engine] in try? engine?.start() }
            engine.stoppedHandler = { _ in }
            try engine.start()
            self.engine = engine
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() {
        render(.clear)
        engine?.stop(completionHandler: nil)
        engine = nil
    }

    /// Loop the pattern for `alert` until a different alert is rendered.
    func render(_ alert: Alert) {
        guard alert != currentAlert else { return }
        currentAlert = alert
        loopTask?.cancel()
        try? activePlayer?.stop(atTime: CHHapticTimeImmediate)
        activePlayer = nil

        guard let pattern = alert.pattern else { return }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.playOnce(pattern)
                try? await Task.sleep(nanoseconds: UInt64(pattern.period * 1_000_000_000))
            }
        }
    }

    /// One-shot preview used by the test buttons.
    func preview(_ alert: Alert) {
        guard let pattern = alert.pattern else { return }
        render(.clear)
        playOnce(pattern)
    }

    private func playOnce(_ pattern: HapticPattern) {
        guard let engine else { return }
        do {
            let player = try engine.makePlayer(with: Self.chPattern(pattern))
            try player.start(atTime: CHHapticTimeImmediate)
            activePlayer = player
        } catch {
            lastError = error.localizedDescription
            try? engine.start()   // engine may have been stopped by the system
        }
    }

    private static func chPattern(_ pattern: HapticPattern) throws -> CHHapticPattern {
        let events = pattern.pulses.map { pulse in
            CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: pulse.intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: pulse.sharpness),
                ],
                relativeTime: pulse.time,
                duration: pulse.duration
            )
        }
        return try CHHapticPattern(events: events, parameters: [])
    }
}
