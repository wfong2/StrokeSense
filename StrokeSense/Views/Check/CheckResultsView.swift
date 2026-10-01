import SwiftUI

private struct DismissCheckFlowKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: @Sendable () -> Void = {}
}

extension EnvironmentValues {
    var dismissCheckFlow: @Sendable () -> Void {
        get { self[DismissCheckFlowKey.self] }
        set { self[DismissCheckFlowKey.self] = newValue }
    }
}

struct CheckResultsView: View {
    @Environment(BaselineManager.self) private var baselineManager
    @Environment(\.dismissCheckFlow) private var dismissCheckFlow

    @State private var callCountdown: Int?
    @State private var countdownTimer: Timer?
    @State private var timerCancelled = false

    private var baseline: BaselineData? {
        baselineManager.load()
    }

    private var currentFace: FaceMetrics {
        baselineManager.stagedFaceMetrics ?? FaceMetrics(
            leftEyeOpenProbability: 0.93,
            rightEyeOpenProbability: 0.94,
            mouthSmileLeft: 0.78,
            mouthSmileRight: 0.79
        )
    }

    private var currentArms: ArmMetrics {
        baselineManager.stagedArmMetrics ?? ArmMetrics(
            leftArmRaiseAngle: 88.0,
            rightArmRaiseAngle: 89.0,
            steadinessScore: 0.93
        )
    }

    private func armRaiseScore(_ metrics: ArmMetrics) -> Double {
        let left = min(abs(metrics.leftArmRaiseAngle) / 90.0, 1.0)
        let right = min(abs(metrics.rightArmRaiseAngle) / 90.0, 1.0)
        return (left + right) / 2.0
    }

    private var currentSpeech: SpeechMetrics {
        baselineManager.stagedSpeechMetrics ?? SpeechMetrics(
            clarity: 0.90,
            wordsPerMinute: 125.0,
            samplePhrase: "The quick brown fox jumps over the lazy dog."
        )
    }

    // MARK: - Change percentages & severity

    private func changePct(baseline: Double?, current: Double) -> Double? {
        guard let baselineVal = baseline, baselineVal != 0 else { return nil }
        return abs((current - baselineVal) / baselineVal) * 100.0
    }

    private var faceChangePct: Double? {
        changePct(
            baseline: baseline?.faceMetrics.map { ($0.mouthSmileLeft + $0.mouthSmileRight) / 2.0 },
            current: (currentFace.mouthSmileLeft + currentFace.mouthSmileRight) / 2.0
        )
    }

    private var armRaiseChangePct: Double? {
        changePct(
            baseline: baseline?.armMetrics.map { armRaiseScore($0) },
            current: armRaiseScore(currentArms)
        )
    }

    private var armSteadinessChangePct: Double? {
        changePct(
            baseline: baseline?.armMetrics?.steadinessScore,
            current: currentArms.steadinessScore
        )
    }

    private var speechChangePct: Double? {
        changePct(
            baseline: baseline?.speechMetrics?.clarity,
            current: currentSpeech.clarity
        )
    }

    private var flaggedCount: Int {
        [faceChangePct, armRaiseChangePct, armSteadinessChangePct, speechChangePct]
            .compactMap { $0 }
            .filter { $0 >= 30 }
            .count
    }

    private var severityIcon: String {
        switch flaggedCount {
        case 0: return "checkmark.shield.fill"
        case 1: return "exclamationmark.triangle.fill"
        case 2: return "exclamationmark.octagon.fill"
        default: return "xmark.shield.fill"
        }
    }

    private var severityTitle: String {
        switch flaggedCount {
        case 0: return "Looking Good"
        case 1: return "Be Aware"
        case 2: return "Getting Serious"
        default: return "Seek Help Now"
        }
    }

    private var severityColor: Color {
        switch flaggedCount {
        case 0: return .green
        case 1: return .orange
        default: return .red
        }
    }

    private var severitySubtitle: String {
        switch flaggedCount {
        case 0: return "Your results are within normal range compared to your baseline."
        case 1: return "One area shows a significant change from your baseline."
        case 2: return "Multiple areas show significant changes from your baseline."
        default: return "Several areas show significant changes. Consider seeking medical attention."
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Dynamic severity header
                Image(systemName: severityIcon)
                    .font(.system(size: 64))
                    .foregroundStyle(severityColor)

                Text(severityTitle)
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text(severitySubtitle)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                // 911 countdown UI
                if let countdown = callCountdown, !timerCancelled {
                    VStack(spacing: 12) {
                        Text("\(countdown)")
                            .font(.system(size: 72, weight: .bold, design: .rounded))
                            .foregroundStyle(.red)
                            .contentTransition(.numericText())

                        Text("Calling 911 in \(countdown) seconds...")
                            .font(.title3)
                            .foregroundStyle(.secondary)

                        Button {
                            cancelTimer()
                        } label: {
                            Text("Cancel")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .padding(.horizontal)
                    }
                    .padding()
                    .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                }

                VStack(spacing: 16) {
                    resultCard(
                        title: "Face Symmetry",
                        icon: "face.smiling",
                        baselineValue: baseline?.faceMetrics.map { ($0.mouthSmileLeft + $0.mouthSmileRight) / 2.0 },
                        currentValue: (currentFace.mouthSmileLeft + currentFace.mouthSmileRight) / 2.0,
                        unit: "symmetry"
                    )

                    resultCard(
                        title: "Arm Raise",
                        icon: "figure.arms.open",
                        baselineValue: baseline?.armMetrics.map { armRaiseScore($0) },
                        currentValue: armRaiseScore(currentArms),
                        unit: "raise"
                    )

                    resultCard(
                        title: "Arm Steadiness",
                        icon: "hand.raised.slash",
                        baselineValue: baseline?.armMetrics?.steadinessScore,
                        currentValue: currentArms.steadinessScore,
                        unit: "score"
                    )

                    resultCard(
                        title: "Speech Clarity",
                        icon: "waveform",
                        baselineValue: baseline?.speechMetrics?.clarity,
                        currentValue: currentSpeech.clarity,
                        unit: "clarity"
                    )
                }
                .padding(.horizontal)

                Button {
                    cancelTimer()
                    baselineManager.clearStaged()
                    dismissCheckFlow()
                } label: {
                    Text(flaggedCount >= 1 && !timerCancelled ? "I'm OK — Dismiss" : "Done")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .padding(.vertical)
        }
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .onAppear {
            if flaggedCount >= 1 {
                startCountdown()
            }
        }
        .onDisappear {
            cancelTimer()
        }
    }

    // MARK: - Timer

    private func startCountdown() {
        callCountdown = 10
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            guard let current = callCountdown, current > 1 else {
                cancelTimer()
                // TODO: Replace with tel://911 for production
                print("[DEV] 911 call would be placed now")
                return
            }
            callCountdown = current - 1
        }
    }

    private func cancelTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        if callCountdown != nil {
            timerCancelled = true
            callCountdown = nil
        }
    }

    // MARK: - Result card

    private func resultCard(title: String, icon: String, baselineValue: Double?, currentValue: Double, unit: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.red)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                if let baselineVal = baselineValue {
                    let pct = abs((currentValue - baselineVal) / baselineVal) * 100.0

                    HStack(spacing: 4) {
                        Text("Baseline: \(Int(baselineVal * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Now: \(Int(currentValue * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 4) {
                        if pct >= 30 {
                            Image(systemName: "exclamationmark.octagon.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                            Text("Significant change (\(String(format: "%.0f", pct))%)")
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else if pct >= 5 {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                            Text("Minor change (\(String(format: "%.0f", pct))%)")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                            Text("Normal")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                } else {
                    Text("No baseline to compare")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    NavigationStack {
        CheckResultsView()
            .environment(BaselineManager())
    }
}
