// Glue: depth readings → AlertDecider → haptics, plus the state the UI shows.

import FeelPathCore
import Observation
import UIKit

@MainActor
@Observable
final class AppModel {

    private(set) var isRunning = false
    private(set) var alert: Alert = .clear
    private(set) var reading = SceneReading.empty
    private(set) var status = "Ready"
    private(set) var readingsPerSecond = 0

    var hapticsMuted = false {
        didSet { haptics.render(hapticsMuted ? .clear : alert) }
    }
    var announceChanges = true

    var obstacleRange: Float = 2.0 { didSet { decider.config.obstacleRange = obstacleRange } }
    var veryCloseRange: Float = 0.8 { didSet { decider.config.veryCloseRange = veryCloseRange } }
    var stairsEnabled = true { didSet { decider.config.stairsEnabled = stairsEnabled } }

    let lidarSupported = DepthSensor.isSupported
    var hapticsSupported: Bool { haptics.isAvailable }

    @ObservationIgnored private let sensor = DepthSensor()
    @ObservationIgnored private let haptics = HapticRenderer()
    @ObservationIgnored private var decider = AlertDecider()
    @ObservationIgnored private var readingCount = 0
    @ObservationIgnored private var rateTimer: Timer?

    init() {
        sensor.onReading = { [weak self] in self?.handle($0) }
        sensor.onStatus = { [weak self] in self?.status = $0 }
    }

    func toggle() {
        isRunning ? stop() : start()
    }

    func start() {
        guard !isRunning else { return }
        decider.reset()
        haptics.start()
        sensor.start()
        isRunning = true
        UIApplication.shared.isIdleTimerDisabled = true
        rateTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.readingsPerSecond = self.readingCount
                self.readingCount = 0
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        sensor.stop()
        haptics.stop()
        rateTimer?.invalidate()
        rateTimer = nil
        isRunning = false
        alert = .clear
        reading = .empty
        readingsPerSecond = 0
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func preview(_ alert: Alert) {
        haptics.start()
        haptics.preview(alert)
    }

    private func handle(_ reading: SceneReading) {
        guard isRunning else { return }
        self.reading = reading
        readingCount += 1
        let next = decider.update(reading)
        if next != alert {
            alert = next
            if announceChanges, UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .announcement, argument: next.title)
            }
        }
        haptics.render(hapticsMuted ? .clear : next)
    }
}
