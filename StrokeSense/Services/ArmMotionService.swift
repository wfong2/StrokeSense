import CoreMotion
import Foundation

/// Records the phone's motion sensors while the user holds it in an
/// outstretched hand. The phone's tilt follows the arm, so a sinking arm
/// shows up directly as a falling elevation angle.
@Observable
final class ArmMotionService {
    /// Phone not turned onto its side right now, so the arm can be measured.
    private(set) var isGripUsable = false

    private let manager = CMMotionManager()
    private var isRecording = false
    private var startTime: TimeInterval?
    private var samples: [ArmSample] = []

    #if targetEnvironment(simulator)
    private let isSimulator = true
    #else
    private let isSimulator = false
    #endif

    func start() {
        guard !isSimulator, manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else {
            if isSimulator { isGripUsable = true }
            return
        }
        manager.deviceMotionUpdateInterval = 1.0 / 50.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.isGripUsable = abs(Self.sample(from: motion, t: 0).turn) < 30

            guard self.isRecording else { return }
            let start = self.startTime ?? motion.timestamp
            self.startTime = start
            self.samples.append(Self.sample(from: motion, t: motion.timestamp - start))
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        isRecording = false
    }

    func startRecording() {
        samples.removeAll()
        startTime = nil
        isRecording = true
    }

    func finishRecording() -> ArmRecording {
        isRecording = false
        defer { samples.removeAll() }
        if isSimulator { return Self.stubRecording }
        return ArmRecording(samples: samples)
    }

    private static func sample(from motion: CMDeviceMotion, t: Double) -> ArmSample {
        let g = motion.gravity
        let r = motion.rotationRate
        let a = motion.userAcceleration
        return ArmSample(
            t: t,
            gravity: [g.x, g.y, g.z],
            rotationRate: [r.x, r.y, r.z],
            userAcceleration: [a.x, a.y, a.z]
        )
    }

    /// A steady upright hold for the simulator, which has no sensors.
    private static var stubRecording: ArmRecording {
        let samples = stride(from: 0.0, through: 8.0, by: 1.0 / 50.0).map { t in
            ArmSample(t: t, gravity: [0, -0.99, -0.1],
                      rotationRate: [0, 0, 0], userAcceleration: [0, 0, 0])
        }
        return ArmRecording(samples: samples)
    }
}
