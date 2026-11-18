import SwiftUI

struct BaselineArmsView: View {
    @Environment(BaselineManager.self) private var baselineManager

    var body: some View {
        ArmHoldView(context: .baseline, tint: .accentColor) { metrics in
            baselineManager.stagedArmMetrics = metrics
        } next: {
            if DevFlags.skipSpeech {
                BaselineCompleteView()
            } else {
                BaselineSpeechView()
            }
        }
        .navigationTitle("Step 2 of 3")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        BaselineArmsView()
            .environment(BaselineManager())
    }
}
