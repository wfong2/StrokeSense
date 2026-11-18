import SwiftUI

struct CheckArmsView: View {
    @Environment(BaselineManager.self) private var baselineManager

    var body: some View {
        ArmHoldView(context: .check, tint: .red) { metrics in
            baselineManager.stagedArmMetrics = metrics
        } next: {
            if DevFlags.skipSpeech {
                CheckResultsView()
            } else {
                CheckSpeechView()
            }
        }
        .navigationTitle("Step 2 of 3")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        CheckArmsView()
            .environment(BaselineManager())
    }
}
