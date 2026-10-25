// Runs an ARKit session with LiDAR scene depth, turns each depth map into gravity-aligned
// points relative to the phone, and hands a `SceneReading` to the main actor ~15 times a second.
//
// Why world coordinates instead of raw pixels (as in a simple "centre of the image" approach):
// on a cane the phone tilts constantly. Projecting every depth pixel through the camera pose
// lets us measure "forward distance" and "height above the floor" no matter how the phone is
// held, which is what makes the stairs-down check possible at all.
//
// Threading: ARKit calls the delegate on `queue`. All analysis happens there; only the final
// reading crosses to the main actor.

import ARKit
import FeelPathCore
import simd

final class DepthSensor: NSObject, ARSessionDelegate {

    static var isSupported: Bool {
        ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }

    /// Called on the main actor with each analysed frame.
    var onReading: (@MainActor (SceneReading) -> Void)?
    /// Called on the main actor with a human-readable status.
    var onStatus: (@MainActor (String) -> Void)?

    var analyzerConfig = AnalyzerConfig()

    private let session = ARSession()
    private let queue = DispatchQueue(label: "feelpath.depth", qos: .userInteractive)
    private let maxRate: Double = 15
    private let pixelStep = 4
    private var lastProcessed: TimeInterval = 0
    private var points: [DepthPoint] = []

    override init() {
        super.init()
        session.delegate = self
        session.delegateQueue = queue
        points.reserveCapacity(4096)
    }

    func start() {
        guard Self.isSupported else {
            report(status: "This device has no LiDAR depth")
            return
        }
        let config = ARWorldTrackingConfiguration()
        // Smoothed depth: temporally filtered, far less speckle for one frame of latency.
        config.frameSemantics = [.smoothedSceneDepth]
        config.worldAlignment = .gravity
        config.planeDetection = []
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        report(status: "Starting…")
    }

    func stop() {
        session.pause()
        report(status: "Stopped")
    }

    // MARK: ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard frame.timestamp - lastProcessed >= 1 / maxRate else { return }
        lastProcessed = frame.timestamp

        guard let depth = frame.smoothedSceneDepth ?? frame.sceneDepth else { return }
        collectPoints(depth: depth, camera: frame.camera)
        let reading = SceneAnalyzer.analyze(points, config: analyzerConfig)
        if let onReading {
            Task { @MainActor in onReading(reading) }
        }
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        switch camera.trackingState {
        case .normal: report(status: "Sensing")
        case .notAvailable: report(status: "Tracking unavailable")
        case .limited(let reason):
            switch reason {
            case .initializing: report(status: "Initialising — move the phone slightly")
            case .excessiveMotion: report(status: "Moving too fast")
            case .insufficientFeatures: report(status: "Low detail / too dark")
            default: report(status: "Tracking limited")
            }
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        report(status: "AR error: \(error.localizedDescription)")
    }

    func sessionWasInterrupted(_ session: ARSession) {
        report(status: "Interrupted")
    }

    // MARK: Depth → points

    private func collectPoints(depth: ARDepthData, camera: ARCamera) {
        points.removeAll(keepingCapacity: true)

        let depthMap = depth.depthMap
        let confMap = depth.confidenceMap
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        if let confMap { CVPixelBufferLockBaseAddress(confMap, .readOnly) }
        defer { if let confMap { CVPixelBufferUnlockBaseAddress(confMap, .readOnly) } }

        guard let depthBase = CVPixelBufferGetBaseAddress(depthMap) else { return }
        let width = CVPixelBufferGetWidth(depthMap)       // 256 on LiDAR iPhones
        let height = CVPixelBufferGetHeight(depthMap)     // 192
        let depthRowBytes = CVPixelBufferGetBytesPerRow(depthMap)
        let confBase = confMap.flatMap { CVPixelBufferGetBaseAddress($0) }
        let confRowBytes = confMap.map { CVPixelBufferGetBytesPerRow($0) } ?? 0
        let minConfidence = UInt8(ARConfidenceLevel.medium.rawValue)

        // Intrinsics are given for the full camera image; rescale them to the depth map.
        let sx = Float(width) / Float(camera.imageResolution.width)
        let sy = Float(height) / Float(camera.imageResolution.height)
        let k = camera.intrinsics
        let fx = k[0][0] * sx, fy = k[1][1] * sy
        let cx = k[2][0] * sx, cy = k[2][1] * sy

        // Gravity-aligned walking frame from the camera pose.
        let t = camera.transform
        let origin = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        let look = -SIMD3<Float>(t.columns.2.x, t.columns.2.y, t.columns.2.z)
        var forward = SIMD3<Float>(look.x, 0, look.z)
        guard simd_length(forward) > 0.15 else { return }   // pointing straight up/down
        forward = simd_normalize(forward)
        let right = simd_cross(forward, SIMD3<Float>(0, 1, 0))

        var v = 0
        while v < height {
            var u = 0
            while u < width {
                defer { u += pixelStep }
                if let confBase {
                    let c = confBase.load(fromByteOffset: v * confRowBytes + u, as: UInt8.self)
                    if c < minConfidence { continue }
                }
                let d = depthBase.load(
                    fromByteOffset: v * depthRowBytes + u * MemoryLayout<Float32>.stride,
                    as: Float32.self
                )
                guard d.isFinite, d > 0.1, d < 5 else { continue }

                // Pixel → camera space (ARKit camera looks down -Z, +Y up, image Y down).
                let xc = (Float(u) - cx) * d / fx
                let yc = -(Float(v) - cy) * d / fy
                let world = t * SIMD4<Float>(xc, yc, -d, 1)
                let rel = SIMD3<Float>(world.x, world.y, world.z) - origin

                points.append(DepthPoint(
                    forward: simd_dot(rel, forward),
                    lateral: simd_dot(rel, right),
                    height: rel.y
                ))
            }
            v += pixelStep
        }
    }

    private func report(status: String) {
        guard let onStatus else { return }
        Task { @MainActor in onStatus(status) }
    }
}
