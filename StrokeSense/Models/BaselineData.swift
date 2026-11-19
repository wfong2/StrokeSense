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

/// One motion-sensor reading during an arm hold. The phone is held in the
/// outstretched hand, so its tilt follows the arm. Raw sensor values are
/// saved so recordings can later train an arm-drift classifier; the ML plan's
/// stroke datasets are also motion-sensor (IMU) data.
struct ArmSample: Codable {
    /// Seconds since the recording started.
    let t: Double
    /// Gravity direction in the phone's frame, in g (x, y, z).
    let gravity: [Double]
    /// Rotation rate in rad/s (x, y, z).
    let rotationRate: [Double]
    /// Acceleration from the user's movement, gravity removed, in g (x, y, z).
    let userAcceleration: [Double]

    private var gx: Double { gravity.count == 3 ? gravity[0] : 0 }
    private var gy: Double { gravity.count == 3 ? gravity[1] : 0 }
    private var gz: Double { gravity.count == 3 ? gravity[2] : 0 }

    /// Tilt around the phone's side-to-side axis, in degrees. The arm sinking
    /// rotates the hand around this axis, and this angle grows by the same
    /// amount whether the phone is held upright (screen facing the user, 0°)
    /// or flat (screen up, 90°).
    var pitch: Double { atan2(-gz, -gy) * 180 / .pi }

    /// How far the phone's side edge dips out of level, in degrees. The forearm
    /// turning (pronation) shows up here in either grip.
    var turn: Double { asin(min(max(gx, -1), 1)) * 180 / .pi }
}

/// A single-arm hold recording and the measurements derived from it.
struct ArmRecording: Codable {
    let samples: [ArmSample]

    /// The first second is skipped while the user settles their arm.
    fileprivate static let settleSeconds = 1.0
    fileprivate static let windowSeconds = 1.0
    fileprivate static let minSamples = 20

    private var held: [ArmSample] { samples.filter { $0.t >= Self.settleSeconds } }

    /// Enough readings across the hold, held in a grip the tilt can be read from.
    var isComplete: Bool {
        let h = held
        guard h.count >= Self.minSamples, let first = h.first, let last = h.last,
              last.t - first.t >= 2.0 else { return false }
        return isGripUsable
    }

    private func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private var startWindow: [ArmSample] {
        let h = held
        guard let first = h.first?.t else { return [] }
        return h.filter { $0.t < first + Self.windowSeconds }
    }

    /// Phone not turned onto its side at the start of the hold. On its side,
    /// the side-to-side axis points up and can't track the arm sinking.
    var isGripUsable: Bool {
        guard let turn = mean(startWindow.map(\.turn)) else { return false }
        return abs(turn) < 30
    }

    /// Pitch of the phone when the arm is level: 0° held upright (screen facing
    /// the user), 90° held flat (screen up). Picked from the start of the hold,
    /// when the arm is raised.
    var gripPitch: Double? {
        mean(startWindow.map(\.pitch)).map { $0 < 45 ? 0 : 90 }
    }

    var gripName: String? {
        gripPitch.map { $0 == 0 ? "upright" : "flat" }
    }

    /// Arm angle above horizontal, in degrees: 0 = straight out, −90 = hanging down.
    private func elevation(_ sample: ArmSample) -> Double? {
        gripPitch.map { $0 - sample.pitch }
    }

    /// Mean of `value` over the first and last second of the hold.
    private func startAndEnd(_ value: (ArmSample) -> Double) -> (start: Double, end: Double)? {
        let h = held
        guard let first = h.first?.t, let last = h.last?.t,
              let start = mean(h.filter { $0.t < first + Self.windowSeconds }.map(value)),
              let end = mean(h.filter { $0.t > last - Self.windowSeconds }.map(value)) else { return nil }
        return (start, end)
    }

    /// How far the forearm turned during the hold, in degrees, either direction.
    var pronation: Double? {
        startAndEnd(\.turn).map { abs($0.end - $0.start) }
    }

    /// Average arm elevation over the hold, in degrees.
    var meanElevation: Double? { mean(held.compactMap(elevation)) }

    /// How far the arm sank from the start of the hold to the end, in degrees.
    /// Only downward movement counts; raising the arm is not drift.
    var drift: Double? {
        startAndEnd(\.pitch).map { max($0.end - $0.start, 0) }
    }

    /// Wobble around the arm's overall trend line: standard deviation of the
    /// tilt after removing a straight-line fit, in degrees.
    var shake: Double? {
        let h = held
        guard h.count >= 3 else { return nil }
        let n = Double(h.count)
        let meanT = h.map(\.t).reduce(0, +) / n
        let meanP = h.map(\.pitch).reduce(0, +) / n
        let covariance = h.map { ($0.t - meanT) * ($0.pitch - meanP) }.reduce(0, +)
        let varianceT = h.map { ($0.t - meanT) * ($0.t - meanT) }.reduce(0, +)
        let slope = varianceT > 0 ? covariance / varianceT : 0
        let residuals = h.map { $0.pitch - (meanP + slope * ($0.t - meanT)) }
        return (residuals.map { $0 * $0 }.reduce(0, +) / n).squareRoot()
    }

    /// 0–1, higher = arm held higher. Horizontal or above = 1, hanging down = 0.
    var positionScore: Double? {
        guard isComplete, let elevation = meanElevation else { return nil }
        return min(max((elevation + 90.0) / 90.0, 0.0), 1.0)
    }

    /// 0–1, higher = arm stayed put. Starting weights, to be calibrated on device:
    /// 60% downward drift (20° or more = 0), 25% forearm turning (30° or more = 0),
    /// 15% shake (3° or more = 0).
    var holdScore: Double? {
        guard isComplete, let drift, let pronation, let shake else { return nil }
        let driftScore = 1.0 - min(drift / 20.0, 1.0)
        let pronationScore = 1.0 - min(pronation / 30.0, 1.0)
        let shakeScore = 1.0 - min(shake / 3.0, 1.0)
        return 0.6 * driftScore + 0.25 * pronationScore + 0.15 * shakeScore
    }
}

extension ArmRecording {
    static let modelSteps = 140
    static let modelChannels = 5

    /// Input for ArmDriftClassifier: 5 channels × 140 steps (20 Hz over the
    /// 7 s hold), channel-major. Must match training/arm_classifier/features.py.
    /// Channels: d_pitch, d_turn (deg, relative to the first second),
    /// pitch_rate, rot_mag (deg/s), acc_mag (g).
    var modelInput: [Float]? {
        let h = samples.filter { $0.t >= Self.settleSeconds }
        guard h.count >= Self.minSamples, let t0 = h.first?.t, let tLast = h.last?.t,
              tLast - t0 >= 2.0 else { return nil }

        let times = h.map(\.t)
        let start = h.filter { $0.t < t0 + Self.windowSeconds }
        let pitch0 = start.map(\.pitch).reduce(0, +) / Double(start.count)
        let turn0 = start.map(\.turn).reduce(0, +) / Double(start.count)
        let toDeg = 180.0 / Double.pi
        func norm(_ v: [Double]) -> Double { v.map { $0 * $0 }.reduce(0, +).squareRoot() }

        let channels: [[Double]] = [
            h.map { $0.pitch - pitch0 },
            h.map { $0.turn - turn0 },
            h.map { ($0.rotationRate.first ?? 0) * toDeg },
            h.map { norm($0.rotationRate) * toDeg },
            h.map { norm($0.userAcceleration) },
        ]

        // Linear resample onto a fixed grid, holding the end values (numpy.interp).
        let step = 7.0 / Double(Self.modelSteps)
        var out: [Float] = []
        out.reserveCapacity(Self.modelChannels * Self.modelSteps)
        for values in channels {
            var j = 0
            for k in 0..<Self.modelSteps {
                let g = t0 + Double(k) * step
                if g <= times[0] { out.append(Float(values[0])); continue }
                if g >= times[times.count - 1] { out.append(Float(values[values.count - 1])); continue }
                while times[j + 1] <= g { j += 1 }
                let f = (g - times[j]) / (times[j + 1] - times[j])
                out.append(Float(values[j] + f * (values[j + 1] - values[j])))
            }
        }
        return out
    }
}

struct ArmMetrics: Codable {
    let left: ArmRecording?
    let right: ArmRecording?

    /// Weaker arm decides: one-sided weakness is the warning sign, and
    /// averaging both arms would halve it. Nil if either arm is incomplete.
    var positionScore: Double? {
        guard let l = left?.positionScore, let r = right?.positionScore else { return nil }
        return min(l, r)
    }

    var holdScore: Double? {
        guard let l = left?.holdScore, let r = right?.holdScore else { return nil }
        return min(l, r)
    }
}

/// Measurements from one spoken phrase. Timing comes from the recognizer's
/// per-word timestamps, so it doesn't depend on when Record/Stop were tapped.
struct SpeechMetrics: Codable {
    let samplePhrase: String
    let transcript: String?
    /// Fraction of the phrase's words that were recognized (0–1).
    let wordAccuracy: Double?
    /// Words per second, from the start of the first word to the end of the last.
    let speechRate: Double?
    /// Fraction of that span spent in gaps between words (0–1).
    let pauseRatio: Double?
    /// Apple voice analytics, averaged over voiced frames. Shown for
    /// calibration, not scored yet.
    let jitter: Double?
    let shimmer: Double?
    let pitchVariation: Double?
    /// Saved recording in Documents/SpeechRecordings, for analysis and training.
    let audioFileName: String?

    // Pre-November 2026 baselines only.
    let clarity: Double?
    let wordsPerMinute: Double?

    init(samplePhrase: String, transcript: String?, wordAccuracy: Double?, speechRate: Double?,
         pauseRatio: Double?, jitter: Double? = nil, shimmer: Double? = nil,
         pitchVariation: Double? = nil, audioFileName: String? = nil) {
        self.samplePhrase = samplePhrase
        self.transcript = transcript
        self.wordAccuracy = wordAccuracy
        self.speechRate = speechRate
        self.pauseRatio = pauseRatio
        self.jitter = jitter
        self.shimmer = shimmer
        self.pitchVariation = pitchVariation
        self.audioFileName = audioFileName
        self.clarity = nil
        self.wordsPerMinute = nil
    }

    /// The user couldn't get the phrase recognized during a check and chose to
    /// continue. Scored as the worst case: being unable to say it is a warning sign.
    static let unrecognized = SpeechMetrics(
        samplePhrase: SpeechRecognitionService.samplePhrase, transcript: nil,
        wordAccuracy: 0, speechRate: 0, pauseRatio: 1
    )

    var isUnrecognized: Bool { wordAccuracy == 0 && speechRate == 0 }

    /// Enough was recognized to measure accuracy and timing.
    var isComplete: Bool {
        wordAccuracy != nil && speechRate != nil && pauseRatio != nil
    }

    // MARK: - Scoring

    /// Slowing down less than this, relative to baseline, is normal variation.
    static let rateAllowance = 0.15
    /// Slowing at which the rate score reaches 0 (allowance + range).
    static let rateRange = 0.35
    /// Extra pause share (absolute) that's normal variation.
    static let pauseAllowance = 0.05
    static let pauseRange = 0.30
    /// Words lost vs baseline that are normal recognizer variation: one word
    /// of the 8-word phrase (on device, normal speech lost 1–2 words).
    static let wordAllowance = 0.15
    static let wordRange = 0.50

    /// How many fewer of the phrase's words were recognized than at baseline.
    func wordsLost(vs base: SpeechMetrics?) -> Double? {
        guard let now = wordAccuracy, let then = base?.wordAccuracy, base?.isComplete == true else { return nil }
        return then - now
    }

    /// How much slower than baseline, as a fraction (0.2 = 20% slower).
    func slowing(vs base: SpeechMetrics?) -> Double? {
        guard let now = speechRate, let then = base?.speechRate, then > 0 else { return nil }
        return 1.0 - now / then
    }

    /// Extra share of time spent pausing compared with baseline.
    func extraPauses(vs base: SpeechMetrics?) -> Double? {
        guard let now = pauseRatio, let then = base?.pauseRatio else { return nil }
        return now - then
    }

    /// 0–1, higher = clearer. 40% words + 35% speaking rate + 25% pauses, each
    /// compared with the user's own baseline, so a word the phone always
    /// mishears in *their* voice doesn't count against them. Scoring the
    /// baseline against itself gives 1.0. With no baseline, words count as-is.
    func rulesScore(vs base: SpeechMetrics? = nil) -> Double? {
        guard isComplete, let accuracy = wordAccuracy else { return nil }
        let wordScore = wordsLost(vs: base).map {
            1.0 - min(max($0 - Self.wordAllowance, 0) / Self.wordRange, 1.0)
        } ?? accuracy
        let rateScore = slowing(vs: base).map {
            1.0 - min(max($0 - Self.rateAllowance, 0) / Self.rateRange, 1.0)
        } ?? 1.0
        let pauseScore = extraPauses(vs: base).map {
            1.0 - min(max($0 - Self.pauseAllowance, 0) / Self.pauseRange, 1.0)
        } ?? 1.0
        return 0.40 * wordScore + 0.35 * rateScore + 0.25 * pauseScore
    }
}

struct BaselineData: Codable {
    let recordedAt: Date
    let faceMetrics: FaceMetrics?
    let armMetrics: ArmMetrics?
    let speechMetrics: SpeechMetrics?
}
