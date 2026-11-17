import Foundation

struct FaceMetrics: Codable {
    let leftEyeOpenProbability: Double
    let rightEyeOpenProbability: Double
    let mouthSmileLeft: Double
    let mouthSmileRight: Double
    let mlProbability: Double?

    init(
        leftEyeOpenProbability: Double,
        rightEyeOpenProbability: Double,
        mouthSmileLeft: Double,
        mouthSmileRight: Double,
        mlProbability: Double? = nil
    ) {
        self.leftEyeOpenProbability = leftEyeOpenProbability
        self.rightEyeOpenProbability = rightEyeOpenProbability
        self.mouthSmileLeft = mouthSmileLeft
        self.mouthSmileRight = mouthSmileRight
        self.mlProbability = mlProbability
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
