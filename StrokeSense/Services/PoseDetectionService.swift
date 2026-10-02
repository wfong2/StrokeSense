import AVFoundation
import Vision
import UIKit

enum ArmSide {
    case left, right
}

@Observable
final class PoseDetectionService: NSObject, @unchecked Sendable {
    private(set) var isBodyDetected = false
    private(set) var isSessionRunning = false
    private(set) var latestMetrics: ArmMetrics?

    let captureSession = AVCaptureSession()

    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(label: "com.strokesense.posedetection", qos: .userInitiated)
    private var metricsBuffer: [ArmMetrics] = []
    private let bufferSize = 10
    var uncappedBuffer = false

    #if targetEnvironment(simulator)
    private let isSimulator = true
    #else
    private let isSimulator = false
    #endif

    func startSession() {
        guard !isSimulator else {
            isSessionRunning = true
            isBodyDetected = true
            latestMetrics = stubMetrics
            return
        }

        guard !captureSession.isRunning else { return }

        processingQueue.async { [weak self] in
            self?.configureCaptureSession()
            self?.captureSession.startRunning()
            DispatchQueue.main.async {
                self?.isSessionRunning = self?.captureSession.isRunning ?? false
            }
        }
    }

    func stopSession() {
        guard !isSimulator else {
            isSessionRunning = false
            isBodyDetected = false
            return
        }

        processingQueue.async { [weak self] in
            self?.captureSession.stopRunning()
            DispatchQueue.main.async {
                self?.isSessionRunning = false
                self?.isBodyDetected = false
                self?.metricsBuffer.removeAll()
            }
        }
    }

    func clearBuffer() {
        metricsBuffer.removeAll()
    }

    func captureSnapshot() -> ArmMetrics? {
        if isSimulator { return stubMetrics }

        guard !metricsBuffer.isEmpty else { return latestMetrics }

        let count = Double(metricsBuffer.count)
        let avgLeft = metricsBuffer.map(\.leftArmRaiseAngle).reduce(0, +) / count
        let avgRight = metricsBuffer.map(\.rightArmRaiseAngle).reduce(0, +) / count

        // Compute steadiness from variance of angles across the buffer
        let leftMean = avgLeft
        let rightMean = avgRight
        let leftVariance = metricsBuffer.map { ($0.leftArmRaiseAngle - leftMean) * ($0.leftArmRaiseAngle - leftMean) }.reduce(0, +) / count
        let rightVariance = metricsBuffer.map { ($0.rightArmRaiseAngle - rightMean) * ($0.rightArmRaiseAngle - rightMean) }.reduce(0, +) / count
        let combinedVariance = leftVariance + rightVariance
        let steadiness = min(max(1.0 - (combinedVariance / 100.0), 0.0), 1.0)

        return ArmMetrics(
            leftArmRaiseAngle: avgLeft,
            rightArmRaiseAngle: avgRight,
            steadinessScore: steadiness
        )
    }

    /// Capture averaged angle and steadiness for a single arm from the buffer.
    func captureSnapshotForArm(_ side: ArmSide) -> (angle: Double, steadiness: Double)? {
        if isSimulator { return (88.0, 0.95) }

        guard !metricsBuffer.isEmpty else { return nil }

        let count = Double(metricsBuffer.count)
        let angles: [Double]
        switch side {
        case .left: angles = metricsBuffer.map(\.leftArmRaiseAngle)
        case .right: angles = metricsBuffer.map(\.rightArmRaiseAngle)
        }

        let avg = angles.reduce(0, +) / count
        let variance = angles.map { ($0 - avg) * ($0 - avg) }.reduce(0, +) / count
        let steadiness = min(max(1.0 - (variance / 100.0), 0.0), 1.0)

        return (avg, steadiness)
    }

    // MARK: - Private

    private func configureCaptureSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .medium

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: camera),
              captureSession.canAddInput(input) else {
            captureSession.commitConfiguration()
            return
        }

        captureSession.addInput(input)

        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true

        guard captureSession.canAddOutput(videoOutput) else {
            captureSession.commitConfiguration()
            return
        }

        captureSession.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video) {
            connection.videoRotationAngle = 90
        }

        captureSession.commitConfiguration()
    }

    private var stubMetrics: ArmMetrics {
        ArmMetrics(
            leftArmRaiseAngle: 88.0,
            rightArmRaiseAngle: 89.0,
            steadinessScore: 0.95
        )
    }

    private func angleDegrees(shoulder: CGPoint, wrist: CGPoint) -> Double {
        let dx = wrist.x - shoulder.x
        let dy = wrist.y - shoulder.y
        let radians = atan2(dy, dx)
        return radians * 180.0 / .pi
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension PoseDetectionService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectHumanBodyPoseRequest { [weak self] request, _ in
            guard let self else { return }
            guard let results = request.results as? [VNHumanBodyPoseObservation],
                  let body = results.first else {
                DispatchQueue.main.async { self.isBodyDetected = false }
                return
            }

            guard let metrics = self.extractMetrics(from: body) else {
                DispatchQueue.main.async { self.isBodyDetected = false }
                return
            }

            DispatchQueue.main.async {
                self.isBodyDetected = true
                self.latestMetrics = metrics
                self.metricsBuffer.append(metrics)
                if !self.uncappedBuffer && self.metricsBuffer.count > self.bufferSize {
                    self.metricsBuffer.removeFirst()
                }
            }
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        try? handler.perform([request])
    }

    private func extractMetrics(from body: VNHumanBodyPoseObservation) -> ArmMetrics? {
        let leftShoulder = try? body.recognizedPoint(.leftShoulder)
        let leftWrist = try? body.recognizedPoint(.leftWrist)
        let rightShoulder = try? body.recognizedPoint(.rightShoulder)
        let rightWrist = try? body.recognizedPoint(.rightWrist)

        let confidenceThreshold: Float = 0.3

        let hasLeft = (leftShoulder?.confidence ?? 0) > confidenceThreshold
            && (leftWrist?.confidence ?? 0) > confidenceThreshold
        let hasRight = (rightShoulder?.confidence ?? 0) > confidenceThreshold
            && (rightWrist?.confidence ?? 0) > confidenceThreshold

        guard hasLeft || hasRight else { return nil }

        let leftAngle = hasLeft
            ? angleDegrees(shoulder: leftShoulder!.location, wrist: leftWrist!.location)
            : 0.0
        let rightAngle = hasRight
            ? angleDegrees(shoulder: rightShoulder!.location, wrist: rightWrist!.location)
            : 0.0

        return ArmMetrics(
            leftArmRaiseAngle: leftAngle,
            rightArmRaiseAngle: rightAngle,
            steadinessScore: 0.0 // Placeholder; real steadiness computed at captureSnapshot() time
        )
    }
}
