import Foundation

struct FaceMetrics: Codable {
    let leftEyeOpenProbability: Double
    let rightEyeOpenProbability: Double
    let mouthSmileLeft: Double
    let mouthSmileRight: Double
    /// Vertical offset between the two mouth corners divided by mouth width,
    /// after correcting for head tilt. 0 = level corners. Nil for baselines
    /// recorded before this was measured.
    let mouthCornerTilt: Double?
    let mlProbability: Double?

    init(
        leftEyeOpenProbability: Double,
        rightEyeOpenProbability: Double,
        mouthSmileLeft: Double,
        mouthSmileRight: Double,
        mouthCornerTilt: Double? = nil,
        mlProbability: Double? = nil
    ) {
        self.leftEyeOpenProbability = leftEyeOpenProbability
        self.rightEyeOpenProbability = rightEyeOpenProbability
        self.mouthSmileLeft = mouthSmileLeft
        self.mouthSmileRight = mouthSmileRight
        self.mouthCornerTilt = mouthCornerTilt
        self.mlProbability = mlProbability
    }

    /// Left/right symmetry from face landmarks, 0–1, higher = more symmetric.
    /// 75% mouth-corner level, 25% matching eye openness.
    var geometrySymmetry: Double {
        let eyeSymmetry = 1.0 - min(abs(leftEyeOpenProbability - rightEyeOpenProbability) / 0.5, 1.0)
        // Legacy baselines without corner tilt fall back to the old smile score.
        guard let tilt = mouthCornerTilt else { return (mouthSmileLeft + mouthSmileRight) / 2.0 }
        // A corner offset of 12% of mouth width or more counts as fully asymmetric.
        // Calibrated on-device: relaxed face ~1%, strong deliberate droop ~7%.
        let mouthSymmetry = 1.0 - min(tilt / 0.12, 1.0)
        return 0.75 * mouthSymmetry + 0.25 * eyeSymmetry
    }
}

struct ArmMetrics: Codable {
    let leftArmRaiseAngle: Double
    let rightArmRaiseAngle: Double
    let steadinessScore: Double
}

struct SpeechMetrics: Codable {
    let clarity: Double
    let wordsPerMinute: Double
    let samplePhrase: String
}

struct BaselineData: Codable {
    let recordedAt: Date
    let faceMetrics: FaceMetrics?
    let armMetrics: ArmMetrics?
    let speechMetrics: SpeechMetrics?
}
