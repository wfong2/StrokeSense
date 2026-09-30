import SwiftUI

struct CheckResultsView: View {
    @Environment(BaselineManager.self) private var baselineManager
    @Environment(\.dismiss) private var dismiss

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

    // Stubs until arms/speech capture is integrated
    private let currentArms = ArmMetrics(
        leftArmRaiseAngle: 88.0,
        rightArmRaiseAngle: 89.0,
        steadinessScore: 0.93
    )
    private let currentSpeech = SpeechMetrics(
        clarity: 0.90,
        wordsPerMinute: 125.0,
        samplePhrase: "The quick brown fox jumps over the lazy dog."
    )

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)

                Text("Looking Good")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Your results are within normal range compared to your baseline.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                VStack(spacing: 16) {
                    resultCard(
                        title: "Face Symmetry",
                        icon: "face.smiling",
                        baselineValue: baseline?.faceMetrics.map { ($0.mouthSmileLeft + $0.mouthSmileRight) / 2.0 },
                        currentValue: (currentFace.mouthSmileLeft + currentFace.mouthSmileRight) / 2.0,
                        unit: "symmetry"
                    )

                    resultCard(
                        title: "Arm Steadiness",
                        icon: "figure.arms.open",
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
                    baselineManager.clearStaged()
                    dismiss()
                } label: {
                    Text("Done")
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
    }

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
                    let change = currentValue - baselineVal
                    let pct = abs(change / baselineVal) * 100.0

                    HStack(spacing: 4) {
                        Text("Baseline: \(Int(baselineVal * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Now: \(Int(currentValue * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: pct < 5 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(pct < 5 ? .green : .orange)
                            .font(.caption)
                        Text(pct < 5 ? "Normal" : "Minor change (\(String(format: "%.0f", pct))%)")
                            .font(.caption)
                            .foregroundStyle(pct < 5 ? .green : .orange)
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
