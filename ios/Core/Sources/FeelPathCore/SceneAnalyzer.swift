// Turns a cloud of LiDAR points (already expressed relative to the phone, gravity-aligned)
// into three facts: how far the nearest obstacle in the walking corridor is, whether part of it
// is an overhang at head / upper-body height with free space beneath (which a cane sweeping the
// ground will not touch), and whether the floor drops away ahead (stairs / kerb down).
//
// Coordinate frame of `DepthPoint` (metres):
//   forward  horizontal distance in the direction the phone faces (gravity removed)
//   lateral  horizontal offset, + = right
//   height   vertical offset from the phone, + = up (so the floor is negative)

public struct DepthPoint: Sendable, Equatable {
    public var forward: Float
    public var lateral: Float
    public var height: Float

    public init(forward: Float, lateral: Float, height: Float) {
        self.forward = forward
        self.lateral = lateral
        self.height = height
    }
}

public struct AnalyzerConfig: Sendable, Equatable {
    /// Half-width of the walking corridor in front of the user.
    public var corridorHalfWidth: Float = 0.35
    /// Ignore anything farther than this (LiDAR is reliable to ~5 m).
    public var maxRange: Float = 4.0
    /// Anything this far above the floor counts as an obstacle (filters floor noise / small bumps).
    public var minObstacleHeight: Float = 0.12
    /// The user's height. Obstacles up to `userHeight + headroom` above the floor are reported;
    /// anything higher is something the user can walk under.
    public var userHeight: Float = 1.75
    public var headroom: Float = 0.10
    /// Fewer obstacle points than this in the corridor is treated as noise.
    public var minObstaclePoints = 12
    /// Percentile of obstacle forward distances reported (low = conservative, robust to outliers).
    public var obstaclePercentile: Float = 0.1

    /// Zone right in front of the user where we measure the floor height.
    public var floorZone: ClosedRange<Float> = 0.3...1.2
    public var minFloorPoints = 15
    /// Used when the floor is neither measured nor remembered (e.g. phone pointing too high).
    public var fallbackFloorHeight: Float = -1.0

    /// Zone ahead where a drop is looked for.
    public var dropZone: ClosedRange<Float> = 0.8...2.5
    /// How far below the floor a point must be to count as "dropped".
    public var dropThreshold: Float = 0.14
    public var minDropPoints = 20
    /// Fraction of ground-level points in the drop zone that must be dropped.
    public var minDropFraction: Float = 0.3

    /// Overhang: obstacle points at least this high above the floor…
    public var overhangMinHeight: Float = 1.0
    /// …with (almost) nothing between `minObstacleHeight` and this height beneath them.
    public var overhangGapMaxHeight: Float = 0.6
    public var minOverhangPoints = 8
    /// More points than this in the gap means the object reaches down: not an overhang.
    public var maxGapPoints = 3
    /// The floor must be seen at or beyond the overhang to prove the gap is really empty
    /// (rather than just out of the sensor's view).
    public var minGroundBeyondOverhang = 10
    /// Forward bin size used to line up overhang points with what is beneath them.
    public var binSize: Float = 0.1

    public init() {}

    /// Highest point above the floor that still counts as an obstacle.
    public var maxObstacleHeight: Float { userHeight + headroom }
}

/// Where the floor height in a reading came from.
public enum FloorSource: String, Sendable {
    /// Measured from depth points just ahead of the user in this frame.
    case measured
    /// Not visible in this frame; taken from the floor plane ARKit tracked earlier.
    case remembered
    /// Unknown; `AnalyzerConfig.fallbackFloorHeight` was used.
    case assumed
}

public struct SceneReading: Sendable, Equatable {
    /// Forward distance to the nearest obstacle in the corridor, nil when clear.
    public var obstacleDistance: Float?
    /// Forward distance to the nearest overhang (upper body / head height, free space beneath).
    public var overhangDistance: Float?
    /// True when the floor ahead falls away (stairs or kerb down).
    public var floorDrop: Bool
    /// Floor height relative to the phone (negative), nil when `floorSource == .assumed`.
    public var floorHeight: Float?
    public var floorSource: FloorSource
    /// Number of points analysed (for the debug panel).
    public var pointCount: Int

    public init(
        obstacleDistance: Float? = nil,
        overhangDistance: Float? = nil,
        floorDrop: Bool = false,
        floorHeight: Float? = nil,
        floorSource: FloorSource = .assumed,
        pointCount: Int = 0
    ) {
        self.obstacleDistance = obstacleDistance
        self.overhangDistance = overhangDistance
        self.floorDrop = floorDrop
        self.floorHeight = floorHeight
        self.floorSource = floorSource
        self.pointCount = pointCount
    }

    public static let empty = SceneReading()
}

public enum SceneAnalyzer {

    /// - Parameter floorHint: floor height relative to the phone from an earlier, still-tracked
    ///   floor plane. Used only when the floor cannot be measured in this frame.
    public static func analyze(
        _ points: [DepthPoint],
        floorHint: Float? = nil,
        config: AnalyzerConfig = AnalyzerConfig()
    ) -> SceneReading {
        let corridor = points.filter {
            abs($0.lateral) <= config.corridorHalfWidth && $0.forward > 0.05 && $0.forward <= config.maxRange
        }

        let floor: Float?
        let source: FloorSource
        if let measured = estimateFloor(corridor, config: config) {
            (floor, source) = (measured, .measured)
        } else if let floorHint {
            (floor, source) = (floorHint, .remembered)
        } else {
            (floor, source) = (nil, .assumed)
        }
        let floorHeight = floor ?? config.fallbackFloorHeight

        let binCount = Int((config.maxRange / config.binSize).rounded(.up)) + 1
        var gapBins = [Int](repeating: 0, count: binCount)
        var groundBins = [Int](repeating: 0, count: binCount)
        var overhangBins = [Float?](repeating: nil, count: binCount)   // nearest forward per bin
        var overhangCounts = [Int](repeating: 0, count: binCount)

        var obstacleForwards: [Float] = []
        var dropped = 0
        var groundInDropZone = 0
        for p in corridor {
            let above = p.height - floorHeight
            let bin = min(binCount - 1, Int(p.forward / config.binSize))

            if above >= config.minObstacleHeight && above <= config.maxObstacleHeight {
                obstacleForwards.append(p.forward)
                if above <= config.overhangGapMaxHeight {
                    gapBins[bin] += 1
                } else if above >= config.overhangMinHeight {
                    overhangCounts[bin] += 1
                    overhangBins[bin] = min(overhangBins[bin] ?? .infinity, p.forward)
                }
            } else if above < config.minObstacleHeight {
                groundBins[bin] += 1
                if config.dropZone.contains(p.forward) {
                    groundInDropZone += 1
                    if above < -config.dropThreshold { dropped += 1 }
                }
            }
        }

        var obstacleDistance: Float?
        if obstacleForwards.count >= config.minObstaclePoints {
            obstacleDistance = percentile(&obstacleForwards, config.obstaclePercentile)
        }

        // An overhang is only claimed when we know where the floor is: otherwise "nothing in the
        // gap" may just mean "gap measured against the wrong floor".
        var overhangDistance: Float?
        if floor != nil {
            for bin in 0..<binCount where overhangCounts[bin] >= config.minOverhangPoints {
                let near = max(0, bin - 1)...min(binCount - 1, bin + 1)
                let gap = near.reduce(0) { $0 + gapBins[$1] }
                let beyond = max(0, bin - 2)...min(binCount - 1, bin + 10)
                let ground = beyond.reduce(0) { $0 + groundBins[$1] }
                if gap <= config.maxGapPoints && ground >= config.minGroundBeyondOverhang {
                    overhangDistance = overhangBins[bin]
                    break   // bins are in forward order: the first match is the nearest
                }
            }
        }

        // Only trust a drop when we actually know where the floor is.
        let floorDrop = floor != nil
            && dropped >= config.minDropPoints
            && Float(dropped) / Float(max(groundInDropZone, 1)) >= config.minDropFraction

        return SceneReading(
            obstacleDistance: obstacleDistance,
            overhangDistance: overhangDistance,
            floorDrop: floorDrop,
            floorHeight: floor,
            floorSource: source,
            pointCount: corridor.count
        )
    }

    /// Floor = median height of the lower half of points just ahead of the user. Using the lower
    /// half keeps a nearby obstacle (a box, a leg) from lifting the estimate.
    static func estimateFloor(_ corridor: [DepthPoint], config: AnalyzerConfig) -> Float? {
        var heights = corridor
            .filter { config.floorZone.contains($0.forward) && $0.height < -0.2 }
            .map(\.height)
        guard heights.count >= config.minFloorPoints else { return nil }
        heights.sort()
        let lowerHalf = heights[0..<max(1, heights.count / 2)]
        return lowerHalf[lowerHalf.count / 2]
    }

    static func percentile(_ values: inout [Float], _ p: Float) -> Float {
        values.sort()
        let index = min(values.count - 1, max(0, Int(Float(values.count - 1) * p)))
        return values[index]
    }
}
