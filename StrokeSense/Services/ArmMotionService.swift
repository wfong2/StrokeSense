import CoreMotion
import Foundation

/// Records the phone's motion sensors while the user holds it in an
/// outstretched hand. The phone's tilt follows the arm, so a sinking arm
/// shows up directly as a falling elevation angle.
@Observable
final class ArmMotionService {
    /// Phone not turned onto its side right now, so the arm can be measured.
    private(set) var isGripUsable = false

    /// Apple recommends one CMMotionManager per app; separate instances can
    /// starve each other of updates. SwiftUI may create this service more than
    /// once while navigating, so all instances share one manager and the most
    /// recent `start()` owns its updates.
    ///
    /// `nonisolated(unsafe)`: both are only touched from the main thread (the
    /// views call in on the main actor and updates are delivered to `.main`),
    /// which Swift 6 can't verify for a static.
    nonisolated(unsafe) private static let manager = CMMotionManager()
    nonisolated(unsafe) private static var owner: ObjectIdentifier?
    private var manager: CMMotionManager { Self.manager }

    private var isRecording = false
    private var startTime: TimeInterval?
    private var samples: [ArmSample] = []

    #if targetEnvironment(simulator)
    private let isSimulator = true
    #else
    private let isSimulator = false
    #endif

    func start() {
        guard !isSimulator, manager.isDeviceMotionAvailable else {
            if isSimulator { isGripUsable = true }
            return
        }
        // Take over updates, even if another instance had them.
        if manager.isDeviceMotionActive { manager.stopDeviceMotionUpdates() }
        Self.owner = ObjectIdentifier(self)
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
        isRecording = false
        // Don't cut off another instance that has since taken over.
        guard Self.owner == ObjectIdentifier(self) else { return }
        manager.stopDeviceMotionUpdates()
        Self.owner = nil
    }

    func startRecording() {
        samples.removeAll()
        startTime = nil
        isRecording = true
        // Make sure this instance is the one receiving updates.
        if Self.owner != ObjectIdentifier(self) || !manager.isDeviceMotionActive { start() }
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
