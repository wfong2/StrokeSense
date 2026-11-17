import CoreML
import UIKit
import Vision

/// Runs the CoreML face asymmetry classifier on a cropped face image.
/// Returns a stroke probability (0.0–1.0) or nil if the model is unavailable.
final class FaceClassifierService: @unchecked Sendable {
    static let shared = FaceClassifierService()

    private let model: VNCoreMLModel?

    private init() {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine
            let coremlModel = try FaceAsymmetryClassifier(configuration: config).model
            model = try VNCoreMLModel(for: coremlModel)
        } catch {
            print("[FaceClassifierService] Failed to load model: \(error). Falling back to heuristics.")
            model = nil
        }
    }

    var isAvailable: Bool { model != nil }

    /// Classify a face crop and return stroke probability (0.0–1.0).
    func classify(faceImage: CGImage) async -> Double? {
        guard let model else { return nil }

        return await withCheckedContinuation { continuation in
            let request = VNCoreMLRequest(model: model) { request, error in
                guard error == nil,
                      let results = request.results as? [VNCoreMLFeatureValueObservation],
                      let multiArray = results.first?.featureValue.multiArrayValue else {
                    continuation.resume(returning: nil)
                    return
                }

                // Model outputs raw logit; apply sigmoid for probability
                let logit = multiArray[0].doubleValue
                let probability = 1.0 / (1.0 + exp(-logit))
                continuation.resume(returning: probability)
            }

            request.imageCropAndScaleOption = .scaleFill

            let handler = VNImageRequestHandler(cgImage: faceImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}
