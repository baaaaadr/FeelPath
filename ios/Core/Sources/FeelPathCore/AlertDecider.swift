// Decides which cue the user should feel, from a stream of `SceneReading`s.
// Adds hysteresis on distances and a few frames of confirmation for stairs and overhangs so the
// cane does not flicker between patterns when a reading jitters around a threshold.

public enum Alert: String, Sendable, CaseIterable {
    case clear
    case obstacle     // "Obstacle ahead" — 2 medium pulses
    case veryClose    // "Very close" — fast short pulses
    case stairsDown   // "Stairs down" — 1 long pulse
    case headHeight   // "Head height" — 3 sharp knocks
}

public struct DeciderConfig: Sendable, Equatable {
    public var obstacleRange: Float = 2.0
    public var veryCloseRange: Float = 0.8
    /// A cue that is already on stays on until the distance exceeds its threshold by this much.
    public var hysteresis: Float = 0.15
    /// Consecutive drop readings needed before "stairs down" fires.
    public var dropConfirmFrames = 3
    /// Consecutive non-drop readings needed before "stairs down" is released.
    public var dropReleaseFrames = 5
    public var stairsEnabled = true
    /// Overhangs within this distance trigger "head height".
    public var headRange: Float = 2.0
    /// Consecutive overhang readings needed before "head height" fires.
    public var headConfirmFrames = 2
    public var headEnabled = true

    public init() {}
}

public struct AlertDecider: Sendable {
    public var config: DeciderConfig
    public private(set) var current: Alert = .clear
    private var dropStreak = 0
    private var noDropStreak = 0
    private var stairsLatched = false
    private var headStreak = 0

    public init(config: DeciderConfig = DeciderConfig()) {
        self.config = config
    }

    public mutating func reset() {
        current = .clear
        dropStreak = 0
        noDropStreak = 0
        stairsLatched = false
        headStreak = 0
    }

    @discardableResult
    public mutating func update(_ reading: SceneReading) -> Alert {
        if reading.floorDrop {
            dropStreak += 1
            noDropStreak = 0
        } else {
            noDropStreak += 1
            dropStreak = 0
        }
        if dropStreak >= config.dropConfirmFrames { stairsLatched = true }
        if noDropStreak >= config.dropReleaseFrames { stairsLatched = false }

        let d = reading.obstacleDistance ?? .infinity
        let veryCloseLimit = config.veryCloseRange + (current == .veryClose ? config.hysteresis : 0)
        let obstacleLimit = config.obstacleRange
            + ((current == .obstacle || current == .veryClose) ? config.hysteresis : 0)

        let h = reading.overhangDistance ?? .infinity
        let headLimit = config.headRange + (current == .headHeight ? config.hysteresis : 0)
        headStreak = h < headLimit ? headStreak + 1 : 0
        // Once on, the head cue survives the confirmation reset as long as the overhang is in range.
        let headActive = config.headEnabled
            && (headStreak >= config.headConfirmFrames || (current == .headHeight && headStreak > 0))

        // Priority: imminent collision > overhang the cane cannot feel > drop > obstacle.
        let next: Alert
        if d < veryCloseLimit {
            next = .veryClose
        } else if headActive {
            next = .headHeight
        } else if config.stairsEnabled && stairsLatched {
            next = .stairsDown
        } else if d < obstacleLimit {
            next = .obstacle
        } else {
            next = .clear
        }
        current = next
        return next
    }
}
