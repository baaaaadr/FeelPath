// Turns a cloud of LiDAR points (already expressed relative to the phone, gravity-aligned)
// into two facts: how far the nearest obstacle in the walking corridor is, and whether the
// floor drops away ahead (stairs / kerb down).
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
    /// Ignore things above head height (ceilings, signs high above).
    public var maxObstacleHeight: Float = 2.0
    /// Fewer obstacle points than this in the corridor is treated as noise.
    public var minObstaclePoints = 12
    /// Percentile of obstacle forward distances reported (low = conservative, robust to outliers).
    public var obstaclePercentile: Float = 0.1

    /// Zone right in front of the user where we measure the floor height.
    public var floorZone: ClosedRange<Float> = 0.3...1.2
    public var minFloorPoints = 15
    /// Used when the floor zone has no usable points (e.g. phone pointing too high).
    public var fallbackFloorHeight: Float = -1.0

    /// Zone ahead where a drop is looked for.
    public var dropZone: ClosedRange<Float> = 0.8...2.5
    /// How far below the floor a point must be to count as "dropped".
    public var dropThreshold: Float = 0.14
    public var minDropPoints = 20
    /// Fraction of ground-level points in the drop zone that must be dropped.
    public var minDropFraction: Float = 0.3

    public init() {}
}

public struct SceneReading: Sendable, Equatable {
    /// Forward distance to the nearest obstacle in the corridor, nil when clear.
    public var obstacleDistance: Float?
    /// True when the floor ahead falls away (stairs or kerb down).
    public var floorDrop: Bool
    /// Estimated floor height relative to the phone (negative), nil if the fallback was used.
    public var floorHeight: Float?
    /// Number of points analysed (for the debug panel).
    public var pointCount: Int

    public init(obstacleDistance: Float? = nil, floorDrop: Bool = false, floorHeight: Float? = nil, pointCount: Int = 0) {
        self.obstacleDistance = obstacleDistance
        self.floorDrop = floorDrop
        self.floorHeight = floorHeight
        self.pointCount = pointCount
    }

    public static let empty = SceneReading()
}

public enum SceneAnalyzer {

    public static func analyze(_ points: [DepthPoint], config: AnalyzerConfig = AnalyzerConfig()) -> SceneReading {
        let corridor = points.filter {
            abs($0.lateral) <= config.corridorHalfWidth && $0.forward > 0.05 && $0.forward <= config.maxRange
        }

        let floor = estimateFloor(corridor, config: config)
        let floorHeight = floor ?? config.fallbackFloorHeight

        // Obstacles: anything standing up out of the floor, below head height.
        var obstacleForwards: [Float] = []
        var dropped = 0
        var groundInDropZone = 0
        for p in corridor {
            let above = p.height - floorHeight
            if above >= config.minObstacleHeight && above <= config.maxObstacleHeight {
                obstacleForwards.append(p.forward)
            }
            if config.dropZone.contains(p.forward) && above < config.minObstacleHeight {
                groundInDropZone += 1
                if above < -config.dropThreshold { dropped += 1 }
            }
        }

        var obstacleDistance: Float?
        if obstacleForwards.count >= config.minObstaclePoints {
            obstacleDistance = percentile(&obstacleForwards, config.obstaclePercentile)
        }

        // Only trust a drop when we actually know where the floor is.
        let floorDrop = floor != nil
            && dropped >= config.minDropPoints
            && Float(dropped) / Float(max(groundInDropZone, 1)) >= config.minDropFraction

        return SceneReading(
            obstacleDistance: obstacleDistance,
            floorDrop: floorDrop,
            floorHeight: floor,
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
