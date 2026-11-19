import SwiftUI

struct BaselineCompleteView: View {
    @Environment(BaselineManager.self) private var baselineManager
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Baseline Complete!")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Your personal baseline has been recorded. StrokeSense can now detect changes in your face, arms, and speech.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Spacer()

            NavigationLink {
                HomeView()
                    .onAppear { saveBaseline() }
            } label: {
                Text("Continue to StrokeSense")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .navigationTitle("Done")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
    }

    private func saveBaseline() {
        let baseline = BaselineData(
            recordedAt: Date(),
            faceMetrics: baselineManager.stagedFaceMetrics,
            // No placeholders: a missing baseline must not look like a real one.
            armMetrics: baselineManager.stagedArmMetrics,
            speechMetrics: baselineManager.stagedSpeechMetrics
        )
        try? baselineManager.save(baseline)
        baselineManager.clearStaged()
    }
}

#Preview {
    NavigationStack {
        BaselineCompleteView()
            .environment(BaselineManager())
    }
}
