import XCTest
@testable import FeelPathCore

/// Synthetic scenes: phone held 1 m above a flat floor, looking forward.
private enum Scene {
    static func floor(from: Float = 0.3, to: Float = 4.0, height: Float = -1.0) -> [DepthPoint] {
        var pts: [DepthPoint] = []
        var f = from
        while f <= to {
            var l: Float = -0.5
            while l <= 0.5 {
                pts.append(DepthPoint(forward: f, lateral: l, height: height))
                l += 0.1
            }
            f += 0.05
        }
        return pts
    }

    static func wall(at forward: Float, lateral: ClosedRange<Float> = -0.5...0.5) -> [DepthPoint] {
        var pts: [DepthPoint] = []
        var h: Float = -1.0
        while h <= 0.6 {
            var l = lateral.lowerBound
            while l <= lateral.upperBound {
                pts.append(DepthPoint(forward: forward, lateral: l, height: h))
                l += 0.1
            }
            h += 0.05
        }
        return pts
    }
}

final class SceneAnalyzerTests: XCTestCase {

    func testFlatFloorIsClear() {
        let r = SceneAnalyzer.analyze(Scene.floor())
        XCTAssertNil(r.obstacleDistance)
        XCTAssertFalse(r.floorDrop)
        XCTAssertEqual(r.floorHeight ?? 0, -1.0, accuracy: 0.01)
    }

    func testWallInCorridorIsReported() {
        let r = SceneAnalyzer.analyze(Scene.floor(to: 1.5) + Scene.wall(at: 1.5))
        XCTAssertEqual(r.obstacleDistance ?? 0, 1.5, accuracy: 0.05)
    }

    func testObstacleOutsideCorridorIsIgnored() {
        let r = SceneAnalyzer.analyze(Scene.floor() + Scene.wall(at: 1.0, lateral: 0.8...1.2))
        XCTAssertNil(r.obstacleDistance)
    }

    func testStepDownIsDetected() {
        let pts = Scene.floor(to: 1.4) + Scene.floor(from: 1.45, to: 3.0, height: -1.3)
        let r = SceneAnalyzer.analyze(pts)
        XCTAssertTrue(r.floorDrop)
        XCTAssertNil(r.obstacleDistance)
    }

    func testSmallDipIsNotADrop() {
        let pts = Scene.floor(to: 1.4) + Scene.floor(from: 1.45, to: 3.0, height: -1.05)
        XCTAssertFalse(SceneAnalyzer.analyze(pts).floorDrop)
    }

    func testNoFloorMeansNoDropClaim() {
        // Phone pointed too high: only a far wall, no floor near the user.
        let r = SceneAnalyzer.analyze(Scene.wall(at: 3.0))
        XCTAssertNil(r.floorHeight)
        XCTAssertFalse(r.floorDrop)
    }
}

final class AlertDeciderTests: XCTestCase {

    func testDistanceBands() {
        var d = AlertDecider()
        XCTAssertEqual(d.update(SceneReading(obstacleDistance: 3.0)), .clear)
        XCTAssertEqual(d.update(SceneReading(obstacleDistance: 1.5)), .obstacle)
        XCTAssertEqual(d.update(SceneReading(obstacleDistance: 0.5)), .veryClose)
        XCTAssertEqual(d.update(SceneReading()), .clear)
    }

    func testHysteresisPreventsFlicker() {
        var d = AlertDecider()
        d.update(SceneReading(obstacleDistance: 1.9))
        XCTAssertEqual(d.update(SceneReading(obstacleDistance: 2.1)), .obstacle, "within hysteresis")
        XCTAssertEqual(d.update(SceneReading(obstacleDistance: 2.3)), .clear)
    }

    func testStairsNeedConfirmationAndRelease() {
        var d = AlertDecider()
        let drop = SceneReading(floorDrop: true)
        XCTAssertEqual(d.update(drop), .clear)
        XCTAssertEqual(d.update(drop), .clear)
        XCTAssertEqual(d.update(drop), .stairsDown)
        for _ in 0..<4 { XCTAssertEqual(d.update(SceneReading()), .stairsDown) }
        XCTAssertEqual(d.update(SceneReading()), .clear)
    }

    func testVeryCloseBeatsStairs() {
        var d = AlertDecider()
        for _ in 0..<3 { d.update(SceneReading(floorDrop: true)) }
        XCTAssertEqual(d.update(SceneReading(obstacleDistance: 0.4, floorDrop: true)), .veryClose)
    }

    func testStairsCanBeDisabled() {
        var config = DeciderConfig()
        config.stairsEnabled = false
        var d = AlertDecider(config: config)
        for _ in 0..<5 { XCTAssertEqual(d.update(SceneReading(floorDrop: true)), .clear) }
    }
}

final class HapticPatternTests: XCTestCase {

    func testPatternsMatchTheSketch() {
        XCTAssertEqual(HapticPattern.obstacleAhead.pulses.count, 2)
        XCTAssertEqual(HapticPattern.stairsDown.pulses.count, 1)
        XCTAssertGreaterThan(HapticPattern.veryClose.pulses.count, 4)
        // Long pulse is clearly longer than the "medium" ones, which are longer than the short ones.
        XCTAssertGreaterThan(HapticPattern.stairsDown.pulses[0].duration, 3 * HapticPattern.obstacleAhead.pulses[0].duration)
        XCTAssertGreaterThan(HapticPattern.obstacleAhead.pulses[0].duration, HapticPattern.veryClose.pulses[0].duration)
    }

    func testEveryPatternFitsInItsPeriod() {
        for alert in Alert.allCases {
            guard let p = alert.pattern else { continue }
            XCTAssertLessThanOrEqual(p.length, p.period, "\(alert)")
        }
    }
}
