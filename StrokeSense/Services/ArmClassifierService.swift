import CoreML

/// Runs the Core ML arm-drift classifier (training/arm_classifier) on one
/// arm hold. Returns a drift probability (0.0–1.0), or nil if the model is
/// unavailable or the hold is too short.
///
/// Info only for now: the model is trained on synthetic and team-simulated
/// holds, not stroke patients, so it doesn't count toward the score.
final class ArmClassifierService: @unchecked Sendable {
    static let shared = ArmClassifierService()

    private let model: ArmDriftClassifier?

    private init() {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine
            model = try ArmDriftClassifier(configuration: config)
        } catch {
            print("[ArmClassifierService] Failed to load model: \(error)")
            model = nil
        }
    }

    func driftProbability(_ recording: ArmRecording) -> Double? {
        guard let model, let input = recording.modelInput,
              let array = try? MLMultiArray(
                shape: [1, NSNumber(value: ArmRecording.modelChannels), NSNumber(value: ArmRecording.modelSteps)],
                dataType: .float32
              ) else { return nil }

        for (i, value) in input.enumerated() {
            array[i] = NSNumber(value: value)
        }
        guard let output = try? model.prediction(motion: array) else { return nil }
        let logit = output.driftLogit[0].doubleValue
        return 1.0 / (1.0 + exp(-logit))
    }
}
