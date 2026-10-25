// The haptic vocabulary, as plain data. The app turns these into Core Haptics events; keeping
// them here means the patterns are documented, testable and easy to tweak in one place.
//
//   Obstacle ahead   ▇ ▇           2 medium pulses, repeated every second
//   Very close       ▌▌▌▌▌▌        fast short pulses, continuous
//   Stairs down      ▇▇▇▇▇▇        1 long pulse, repeated every 1.6 s
//   Head height      ▌▌▌           3 sharp knocks, repeated every 0.9 s

public struct HapticPulse: Sendable, Equatable {
    /// Start, relative to the pattern start (seconds).
    public var time: Double
    /// Length of the buzz (seconds).
    public var duration: Double
    /// 0...1
    public var intensity: Float
    /// 0...1 — low feels round / dull, high feels crisp.
    public var sharpness: Float

    public init(time: Double, duration: Double, intensity: Float, sharpness: Float) {
        self.time = time
        self.duration = duration
        self.intensity = intensity
        self.sharpness = sharpness
    }
}

public struct HapticPattern: Sendable, Equatable {
    public var pulses: [HapticPulse]
    /// Time between the starts of two repetitions (seconds).
    public var period: Double

    public init(pulses: [HapticPulse], period: Double) {
        self.pulses = pulses
        self.period = period
    }

    /// End of the last pulse.
    public var length: Double {
        pulses.map { $0.time + $0.duration }.max() ?? 0
    }

    public static let obstacleAhead = HapticPattern(
        pulses: [
            HapticPulse(time: 0.00, duration: 0.12, intensity: 0.75, sharpness: 0.5),
            HapticPulse(time: 0.25, duration: 0.12, intensity: 0.75, sharpness: 0.5),
        ],
        period: 1.0
    )

    public static let veryClose = HapticPattern(
        pulses: (0..<6).map { i in
            HapticPulse(time: Double(i) * 0.1, duration: 0.05, intensity: 1.0, sharpness: 0.9)
        },
        period: 0.6
    )

    public static let stairsDown = HapticPattern(
        pulses: [HapticPulse(time: 0, duration: 0.7, intensity: 0.9, sharpness: 0.2)],
        period: 1.6
    )

    /// Three hard, crisp knocks then a pause: rhythmically distinct from the continuous
    /// "very close" rattle and from the softer two-pulse "obstacle ahead".
    public static let headHeight = HapticPattern(
        pulses: (0..<3).map { i in
            HapticPulse(time: Double(i) * 0.12, duration: 0.04, intensity: 1.0, sharpness: 1.0)
        },
        period: 0.9
    )
}

public extension Alert {
    var pattern: HapticPattern? {
        switch self {
        case .clear: return nil
        case .obstacle: return .obstacleAhead
        case .veryClose: return .veryClose
        case .stairsDown: return .stairsDown
        case .headHeight: return .headHeight
        }
    }

    var title: String {
        switch self {
        case .clear: return "Path clear"
        case .obstacle: return "Obstacle ahead"
        case .veryClose: return "Very close"
        case .stairsDown: return "Stairs down"
        case .headHeight: return "Head height"
        }
    }
}
