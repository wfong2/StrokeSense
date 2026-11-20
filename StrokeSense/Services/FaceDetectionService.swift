import AVFoundation
import Vision
import UIKit

@Observable
final class FaceDetectionService: NSObject, @unchecked Sendable {
    private(set) var isFaceDetected = false
    private(set) var isSessionRunning = false
    private(set) var latestMetrics: FaceMetrics?

    let captureSession = AVCaptureSession()

    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(label: "com.strokesense.facedetection", qos: .userInitiated)
    private var metricsBuffer: [FaceMetrics] = []
    private let bufferSize = 10
    private var latestPixelBuffer: CVPixelBuffer?
    private var latestFaceBoundingBox: CGRect?

    #if targetEnvironment(simulator)
    private let isSimulator = true
    #else
    private let isSimulator = false
    #endif

    func startSession() {
        guard !isSimulator else {
            isSessionRunning = true
            isFaceDetected = true
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
            isFaceDetected = false
            return
        }

        processingQueue.async { [weak self] in
            self?.captureSession.stopRunning()
            DispatchQueue.main.async {
                self?.isSessionRunning = false
                self?.isFaceDetected = false
                self?.metricsBuffer.removeAll()
            }
        }
    }

    func captureSnapshot() -> FaceMetrics? {
        if isSimulator { return stubMetrics }

        guard !metricsBuffer.isEmpty else { return latestMetrics }

        let count = Double(metricsBuffer.count)
        let tilts = metricsBuffer.compactMap(\.mouthCornerTilt)
        let averaged = FaceMetrics(
            leftEyeOpenProbability: metricsBuffer.map(\.leftEyeOpenProbability).reduce(0, +) / count,
            rightEyeOpenProbability: metricsBuffer.map(\.rightEyeOpenProbability).reduce(0, +) / count,
            mouthSmileLeft: metricsBuffer.map(\.mouthSmileLeft).reduce(0, +) / count,
            mouthSmileRight: metricsBuffer.map(\.mouthSmileRight).reduce(0, +) / count,
            mouthCornerTilt: tilts.isEmpty ? nil : tilts.reduce(0, +) / Double(tilts.count)
        )
        return averaged
    }

    /// Capture a snapshot with ML probability from the face classifier.
    func captureSnapshotWithML() async -> FaceMetrics? {
        guard let base = captureSnapshot() else { return nil }

        // Try ML classification on the latest face crop
        if let pixelBuffer = latestPixelBuffer, let bbox = latestFaceBoundingBox {
            let faceCrop = cropFace(from: pixelBuffer, boundingBox: bbox)
            if let cgImage = faceCrop {
                let mlProb = await FaceClassifierService.shared.classify(faceImage: cgImage)
                return FaceMetrics(
                    leftEyeOpenProbability: base.leftEyeOpenProbability,
                    rightEyeOpenProbability: base.rightEyeOpenProbability,
                    mouthSmileLeft: base.mouthSmileLeft,
                    mouthSmileRight: base.mouthSmileRight,
                    mouthCornerTilt: base.mouthCornerTilt,
                    mlProbability: mlProb
                )
            }
        }

        return base
    }

    /// Crop the face region from a pixel buffer using the Vision bounding box.
    private func cropFace(from pixelBuffer: CVPixelBuffer, boundingBox: CGRect) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let width = ciImage.extent.width
        let height = ciImage.extent.height

        // Vision bounding box is normalized with origin at bottom-left
        let faceRect = CGRect(
            x: boundingBox.origin.x * width,
            y: boundingBox.origin.y * height,
            width: boundingBox.width * width,
            height: boundingBox.height * height
        )

        // Add 10% margin
        let margin = max(faceRect.width, faceRect.height) * 0.1
        let expanded = faceRect.insetBy(dx: -margin, dy: -margin)
            .intersection(ciImage.extent)

        guard !expanded.isEmpty else { return nil }

        let cropped = ciImage.cropped(to: expanded)
        let context = CIContext()
        return context.createCGImage(cropped, from: cropped.extent)
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

    private var stubMetrics: FaceMetrics {
        FaceMetrics(
            leftEyeOpenProbability: 0.95,
            rightEyeOpenProbability: 0.95,
            mouthSmileLeft: 0.80,
            mouthSmileRight: 0.80,
            mouthCornerTilt: 0.02
        )
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension FaceDetectionService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectFaceLandmarksRequest { [weak self] request, _ in
            guard let self else { return }
            guard let results = request.results as? [VNFaceObservation],
                  let face = results.first else {
                DispatchQueue.main.async { self.isFaceDetected = false }
                return
            }

            let imageSize = CGSize(
                width: CVPixelBufferGetWidth(pixelBuffer),
                height: CVPixelBufferGetHeight(pixelBuffer)
            )
            let metrics = self.extractMetrics(from: face, imageSize: imageSize)
            let boundingBox = face.boundingBox
            // Handed to the main thread and only read from then on (for the
            // AI face crop); the camera never writes to a delivered frame.
            nonisolated(unsafe) let frame = pixelBuffer

            DispatchQueue.main.async {
                self.isFaceDetected = true
                self.latestMetrics = metrics
                self.latestPixelBuffer = frame
                self.latestFaceBoundingBox = boundingBox
                self.metricsBuffer.append(metrics)
                if self.metricsBuffer.count > self.bufferSize {
                    self.metricsBuffer.removeFirst()
                }
            }
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        try? handler.perform([request])
    }

    private func extractMetrics(from face: VNFaceObservation, imageSize: CGSize) -> FaceMetrics {
        var leftEyeOpen = 0.9
        var rightEyeOpen = 0.9
        var smileLeft = 0.5
        var smileRight = 0.5
        var cornerTilt: Double?

        if let landmarks = face.landmarks {
            if let leftEye = landmarks.leftEye {
                leftEyeOpen = eyeOpenness(leftEye)
            }
            if let rightEye = landmarks.rightEye {
                rightEyeOpen = eyeOpenness(rightEye)
            }
            if let outerLips = landmarks.outerLips {
                let smileScore = mouthSmile(outerLips)
                smileLeft = smileScore.left
                smileRight = smileScore.right
                if let leftEye = landmarks.leftEye, let rightEye = landmarks.rightEye {
                    cornerTilt = mouthCornerTilt(
                        lips: outerLips, leftEye: leftEye, rightEye: rightEye, imageSize: imageSize
                    )
                }
            }
        }

        return FaceMetrics(
            leftEyeOpenProbability: leftEyeOpen,
            rightEyeOpenProbability: rightEyeOpen,
            mouthSmileLeft: smileLeft,
            mouthSmileRight: smileRight,
            mouthCornerTilt: cornerTilt
        )
    }

    /// How uneven the mouth corners are: vertical offset between them divided by
    /// mouth width, measured along the eye line so a tilted head doesn't count.
    private func mouthCornerTilt(
        lips: VNFaceLandmarkRegion2D,
        leftEye: VNFaceLandmarkRegion2D,
        rightEye: VNFaceLandmarkRegion2D,
        imageSize: CGSize
    ) -> Double? {
        let lipPoints = lips.pointsInImage(imageSize: imageSize)
        guard lipPoints.count >= 6 else { return nil }

        func center(_ points: [CGPoint]) -> CGPoint? {
            guard !points.isEmpty else { return nil }
            let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
            return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
        }
        guard let eyeA = center(leftEye.pointsInImage(imageSize: imageSize)),
              let eyeB = center(rightEye.pointsInImage(imageSize: imageSize)) else { return nil }

        // Rotate into the eye-line frame to remove head roll.
        let roll = atan2(eyeB.y - eyeA.y, eyeB.x - eyeA.x)
        let cosR = cos(-roll), sinR = sin(-roll)
        func rotate(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x * cosR - p.y * sinR, y: p.x * sinR + p.y * cosR)
        }
        // Pick corners after rotating, so they're the ends of the mouth along
        // the eye line regardless of how the frame or head is oriented.
        let rotated = lipPoints.map(rotate)
        guard let a = rotated.min(by: { $0.x < $1.x }),
              let b = rotated.max(by: { $0.x < $1.x }) else { return nil }

        let width = abs(b.x - a.x)
        guard width > 0 else { return nil }
        return Double(abs(b.y - a.y) / width)
    }

    private func eyeOpenness(_ region: VNFaceLandmarkRegion2D) -> Double {
        let points = region.normalizedPoints
        guard points.count >= 6 else { return 0.9 }

        // Approximate eye aspect ratio from landmark points
        let topY = points.dropFirst(1).prefix(2).map(\.y).max() ?? 0
        let bottomY = points.dropFirst(4).prefix(2).map(\.y).min() ?? 0
        let leftX = points.first?.x ?? 0
        let rightX = points[3].x

        let height = abs(topY - bottomY)
        let width = abs(rightX - leftX)

        guard width > 0 else { return 0.9 }
        let aspectRatio = height / width

        // Normalize: closed eye ~0.05, open eye ~0.3
        return min(max(aspectRatio / 0.35, 0.0), 1.0)
    }

    private func mouthSmile(_ region: VNFaceLandmarkRegion2D) -> (left: Double, right: Double) {
        let points = region.normalizedPoints
        guard points.count >= 6 else { return (0.5, 0.5) }

        // Use mouth corner positions relative to center to estimate smile
        let leftCorner = points.first!
        let rightCorner = points[points.count / 2]

        let centerX = (leftCorner.x + rightCorner.x) / 2.0
        let centerY = (leftCorner.y + rightCorner.y) / 2.0

        // Top lip center point
        let topPoints = Array(points.prefix(points.count / 2))
        let topCenterY = topPoints.map(\.y).max() ?? centerY

        // Smile score based on how much corners are raised relative to center
        let leftRaise = Double(leftCorner.y - centerY)
        let rightRaise = Double(rightCorner.y - centerY)

        // Width ratio as smile indicator
        let width = Double(abs(rightCorner.x - leftCorner.x))
        let height = Double(abs(topCenterY - centerY))
        guard width > 0 else { return (0.5, 0.5) }

        let ratio = height / width
        let baseScore = min(max(ratio * 2.0, 0.0), 1.0)

        // Adjust per-side based on corner raise asymmetry
        let leftScore = min(max(baseScore + leftRaise * 0.5, 0.0), 1.0)
        let rightScore = min(max(baseScore + rightRaise * 0.5, 0.0), 1.0)

        return (left: leftScore, right: rightScore)
    }
}
